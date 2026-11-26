import { Request, Response } from 'express';
import { Op } from 'sequelize';

async function reverseGeocodeCoords(lat: number, lng: number): Promise<string | null> {
  try {
    const url = `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${lat}&longitude=${lng}&localityLanguage=en`;
    const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
    if (res.ok) {
      const data: any = await res.json();
      const parts = new Set<string>();
      if (data.locality) parts.add(data.locality);
      if (data.city && data.city !== data.locality) parts.add(data.city);
      if (data.principalSubdivision) parts.add(data.principalSubdivision);
      if (parts.size === 0 && data.countryName) parts.add(data.countryName);
      if (parts.size > 0) return Array.from(parts).join(', ');
    }
  } catch (_) {}
  try {
    const res = await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`, {
      headers: { 'User-Agent': 'FamalthLynx/1.0 (pos@famalth.com)' },
      signal: AbortSignal.timeout(3000)
    });
    if (res.ok) {
      const data: any = await res.json();
      if (data.display_name) {
        return data.display_name.split(',').slice(0, 3).map((s: string) => s.trim()).join(', ');
      }
    }
  } catch (_) {}
  return null;
}

export class TransportController {
  // =========================================================================
  // VEHICLE MANAGEMENT
  // =========================================================================

  public static async listVehicles(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { status, search } = req.query;

      const where: any = { outlet_id, is_active: true };
      if (status && status !== 'ALL') {
        where.status = status;
      }
      if (search) {
        where[Op.or] = [
          { vehicle_number: { [Op.iLike]: `%${search}%` } },
          { vehicle_type: { [Op.iLike]: `%${search}%` } },
          { model: { [Op.iLike]: `%${search}%` } }
        ];
      }

      const vehicles = await (req as any).propertyDb.models.transport_vehicles.findAll({
        where,
        include: [
          {
            model: (req as any).propertyDb.models.transport_drivers,
            as: 'current_driver',
            required: false,
            attributes: ['id', 'driver_name', 'phone', 'license_number', 'last_latitude', 'last_longitude', 'last_location_address', 'last_location_updated']
          }
        ],
        order: [['vehicle_number', 'ASC']]
      });

      return res.json({ success: true, data: vehicles });
    } catch (err: any) {
      console.error('listVehicles error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async createVehicle(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const {
        vehicle_number,
        vehicle_type,
        capacity_tonnage,
        capacity_unit,
        model,
        notes
      } = req.body;

      if (!vehicle_number || !vehicle_number.trim()) {
        return res.status(400).json({ success: false, message: 'Vehicle number is required' });
      }

      const formattedNumber = vehicle_number.trim().toUpperCase();

      // Check duplicate
      const existing = await (req as any).propertyDb.models.transport_vehicles.findOne({
        where: { outlet_id, vehicle_number: formattedNumber, is_active: true }
      });
      if (existing) {
        return res.status(400).json({ success: false, message: `Vehicle ${formattedNumber} already exists.` });
      }

      const vehicle = await (req as any).propertyDb.models.transport_vehicles.create({
        outlet_id,
        vehicle_number: formattedNumber,
        vehicle_type: vehicle_type || 'Truck',
        capacity_tonnage: parseFloat(capacity_tonnage) || 0.0,
        capacity_unit: capacity_unit || 'Tons',
        model: model ? model.trim() : null,
        status: 'AVAILABLE',
        notes: notes ? notes.trim() : null,
        is_active: true
      });

      return res.status(201).json({ success: true, data: vehicle, message: 'Vehicle added successfully' });
    } catch (err: any) {
      console.error('createVehicle error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async updateVehicle(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { id } = req.params;
      const {
        vehicle_number,
        vehicle_type,
        capacity_tonnage,
        capacity_unit,
        model,
        status,
        notes
      } = req.body;

      const vehicle = await (req as any).propertyDb.models.transport_vehicles.findOne({
        where: { id, outlet_id }
      });
      if (!vehicle) {
        return res.status(404).json({ success: false, message: 'Vehicle not found' });
      }

      await vehicle.update({
        vehicle_number: vehicle_number ? vehicle_number.trim().toUpperCase() : vehicle.vehicle_number,
        vehicle_type: vehicle_type || vehicle.vehicle_type,
        capacity_tonnage: capacity_tonnage !== undefined ? parseFloat(capacity_tonnage) : vehicle.capacity_tonnage,
        capacity_unit: capacity_unit || vehicle.capacity_unit,
        model: model !== undefined ? (model ? model.trim() : null) : vehicle.model,
        status: status || vehicle.status,
        notes: notes !== undefined ? (notes ? notes.trim() : null) : vehicle.notes
      });

      return res.json({ success: true, data: vehicle, message: 'Vehicle updated successfully' });
    } catch (err: any) {
      console.error('updateVehicle error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async deleteVehicle(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { id } = req.params;

      const vehicle = await (req as any).propertyDb.models.transport_vehicles.findOne({
        where: { id, outlet_id }
      });
      if (!vehicle) {
        return res.status(404).json({ success: false, message: 'Vehicle not found' });
      }

      if (vehicle.status === 'BOOKED' || vehicle.status === 'IN_TRANSIT') {
        return res.status(400).json({ success: false, message: 'Cannot delete vehicle while booked or on trip.' });
      }

      await vehicle.update({ is_active: false });
      return res.json({ success: true, message: 'Vehicle removed successfully' });
    } catch (err: any) {
      console.error('deleteVehicle error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  // =========================================================================
  // DRIVER MANAGEMENT
  // =========================================================================

  public static async listDrivers(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { status, search } = req.query;

      const where: any = { outlet_id, is_active: true };
      if (status && status !== 'ALL') {
        where.status = status;
      }
      if (search) {
        where[Op.or] = [
          { driver_name: { [Op.iLike]: `%${search}%` } },
          { phone: { [Op.iLike]: `%${search}%` } },
          { license_number: { [Op.iLike]: `%${search}%` } }
        ];
      }

      const drivers = await (req as any).propertyDb.models.transport_drivers.findAll({
        where,
        include: [
          {
            model: (req as any).propertyDb.models.transport_vehicles,
            as: 'current_vehicle',
            required: false,
            attributes: ['id', 'vehicle_number', 'vehicle_type', 'model']
          }
        ],
        order: [['driver_name', 'ASC']]
      });

      return res.json({ success: true, data: drivers });
    } catch (err: any) {
      console.error('listDrivers error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async createDriver(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { driver_name, phone, email, password, license_number, address, status } = req.body;

      if (!driver_name || !driver_name.trim()) {
        return res.status(400).json({ success: false, message: 'Driver name is required' });
      }
      if (!phone || !phone.trim()) {
        return res.status(400).json({ success: false, message: 'Driver phone number is required' });
      }

      const cleanPhone = phone.trim();
      const cleanEmail = email ? email.trim().toLowerCase() : null;

      // Unique check
      const existing = await (req as any).propertyDb.models.transport_drivers.findOne({
        where: {
          outlet_id,
          is_active: true,
          [Op.or]: [
            { phone: cleanPhone },
            ...(cleanEmail ? [{ email: cleanEmail }] : [])
          ]
        }
      });

      if (existing) {
        return res.status(400).json({
          success: false,
          message: `A driver with phone ${cleanPhone}${cleanEmail ? ' or email ' + cleanEmail : ''} already exists.`
        });
      }

      let password_hash = null;
      if (password && password.toString().trim().length > 0) {
        const bcrypt = require('bcryptjs');
        password_hash = await bcrypt.hash(password.toString().trim(), 10);
      } else {
        const bcrypt = require('bcryptjs');
        password_hash = await bcrypt.hash('123456', 10);
      }

      const driver = await (req as any).propertyDb.models.transport_drivers.create({
        outlet_id,
        driver_name: driver_name.trim(),
        phone: cleanPhone,
        email: cleanEmail,
        password_hash,
        license_number: license_number ? license_number.trim().toUpperCase() : null,
        address: address ? address.trim() : null,
        status: status || 'AVAILABLE',
        total_consignments_completed: 0,
        is_active: true
      });

      return res.status(201).json({ success: true, data: driver, message: 'Driver profile created successfully' });
    } catch (err: any) {
      console.error('createDriver error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async updateDriver(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { id } = req.params;
      const { driver_name, phone, email, password, license_number, address, status } = req.body;

      const driver = await (req as any).propertyDb.models.transport_drivers.findOne({
        where: { id, outlet_id }
      });
      if (!driver) {
        return res.status(404).json({ success: false, message: 'Driver not found' });
      }

      const updatePayload: any = {};
      if (driver_name !== undefined) updatePayload.driver_name = driver_name ? driver_name.trim() : driver.driver_name;
      if (phone !== undefined) updatePayload.phone = phone ? phone.trim() : driver.phone;
      if (email !== undefined) updatePayload.email = email ? email.trim().toLowerCase() : driver.email;
      if (license_number !== undefined) updatePayload.license_number = license_number ? license_number.trim().toUpperCase() : null;
      if (address !== undefined) updatePayload.address = address ? address.trim() : null;
      if (status !== undefined) {
        updatePayload.status = status;
        if (status === 'TERMINATED' || status === 'INACTIVE') {
          updatePayload.is_active = false;
        } else {
          updatePayload.is_active = true;
        }
      }

      if (password && password.toString().trim()) {
        const bcrypt = require('bcryptjs');
        updatePayload.password_hash = await bcrypt.hash(password.toString().trim(), 10);
      }

      await driver.update(updatePayload);

      return res.json({ success: true, data: driver, message: 'Driver profile updated successfully' });
    } catch (err: any) {
      console.error('updateDriver error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async deleteDriver(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { id } = req.params;

      const driver = await (req as any).propertyDb.models.transport_drivers.findOne({
        where: { id, outlet_id }
      });
      if (!driver) {
        return res.status(404).json({ success: false, message: 'Driver not found' });
      }

      if (driver.status === 'BOOKED' || driver.status === 'ON_TRIP') {
        return res.status(400).json({ success: false, message: 'Cannot delete driver while booked on an active trip.' });
      }

      await driver.update({ is_active: false });
      return res.json({ success: true, message: 'Driver profile removed successfully' });
    } catch (err: any) {
      console.error('deleteDriver error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  // =========================================================================
  // TRIP ASSIGNMENT & MULTI-CHALLAN GROUPING PER TRUCK
  // =========================================================================

  public static async assignTrip(req: Request, res: Response): Promise<any> {
    const t = await (req as any).propertyDb.transaction();
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { vehicle_id, driver_id, challan_ids, e_way_bill_no, destination_address } = req.body;

      if (!vehicle_id) {
        await t.rollback();
        return res.status(400).json({ success: false, message: 'Please select a vehicle/truck.' });
      }
      if (!driver_id) {
        await t.rollback();
        return res.status(400).json({ success: false, message: 'Please select a driver.' });
      }
      if (!challan_ids || !Array.isArray(challan_ids) || challan_ids.length === 0) {
        await t.rollback();
        return res.status(400).json({ success: false, message: 'Please select at least one delivery challan.' });
      }

      // Check vehicle
      const vehicle = await (req as any).propertyDb.models.transport_vehicles.findOne({
        where: { id: vehicle_id, outlet_id },
        transaction: t
      });
      if (!vehicle) {
        await t.rollback();
        return res.status(404).json({ success: false, message: 'Selected vehicle not found.' });
      }

      // Check driver
      const driver = await (req as any).propertyDb.models.transport_drivers.findOne({
        where: { id: driver_id, outlet_id },
        transaction: t
      });
      if (!driver) {
        await t.rollback();
        return res.status(404).json({ success: false, message: 'Selected driver not found.' });
      }

      // Generate or reuse trip ID for multi-challan trip
      let trip_id = vehicle.current_trip_id;
      if (!trip_id) {
        const today = new Date();
        const dateStr = `${today.getFullYear()}${String(today.getMonth() + 1).padStart(2, '0')}${String(today.getDate()).padStart(2, '0')}`;
        const tripRandom = Math.random().toString(36).substring(2, 6).toUpperCase();
        trip_id = `TRIP-${dateStr}-${tripRandom}`;
      }

      const assignedChallans: any[] = [];

      for (const challanId of challan_ids) {
        const challan = await (req as any).propertyDb.models.delivery_challan_headers.findOne({
          where: { id: challanId, outlet_id },
          transaction: t
        });
        if (!challan) continue;

        // Generate 6-digit OTP for secure customer delivery
        const delivery_otp = String(Math.floor(100000 + Math.random() * 900000));

        await challan.update(
          {
            vehicle_id: vehicle.id,
            vehicle_number: vehicle.vehicle_number,
            vehicle_type: vehicle.vehicle_type,
            driver_id: driver.id,
            driver_name: driver.driver_name,
            driver_phone: driver.phone,
            trip_id,
            delivery_status: 'IN_TRANSIT',
            delivery_otp,
            e_way_bill_no: e_way_bill_no || challan.e_way_bill_no,
            destination_address: destination_address || challan.destination_address,
            status: 'In-Transit'
          },
          { transaction: t }
        );

        assignedChallans.push({
          id: challan.id,
          challan_no: challan.challan_no,
          customer_name: challan.customer_name,
          delivery_otp
        });
      }

      // Set vehicle status to BOOKED
      await vehicle.update(
        {
          status: 'BOOKED',
          current_trip_id: trip_id,
          current_driver_id: driver.id
        },
        { transaction: t }
      );

      // Set driver status to BOOKED
      await driver.update(
        {
          status: 'BOOKED',
          current_vehicle_id: vehicle.id
        },
        { transaction: t }
      );

      await t.commit();

      return res.json({
        success: true,
        message: `Successfully booked Truck ${vehicle.vehicle_number} with Driver ${driver.driver_name} for ${assignedChallans.length} delivery challan(s).`,
        data: {
          trip_id,
          vehicle_number: vehicle.vehicle_number,
          driver_name: driver.driver_name,
          driver_phone: driver.phone,
          challans: assignedChallans
        }
      });
    } catch (err: any) {
      await t.rollback();
      console.error('assignTrip error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  // =========================================================================
  // VERIFY DELIVERY (OTP OR DRIVER SUBMIT CONFIRMATION)
  // =========================================================================

  public static async verifyDelivery(req: Request, res: Response): Promise<any> {
    const t = await (req as any).propertyDb.transaction();
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { challan_id, otp, remark, receiver_name } = req.body;

      if (!challan_id) {
        await t.rollback();
        return res.status(400).json({ success: false, message: 'Challan ID is required.' });
      }

      const challan = await (req as any).propertyDb.models.delivery_challan_headers.findOne({
        where: { id: challan_id, outlet_id },
        transaction: t
      });
      if (!challan) {
        await t.rollback();
        return res.status(404).json({ success: false, message: 'Delivery challan not found.' });
      }

      if (challan.delivery_status === 'DELIVERED') {
        await t.rollback();
        return res.json({ success: true, message: 'This challan is already marked as DELIVERED.', data: challan });
      }

      // If OTP provided, verify it matches
      if (otp && otp.trim() !== '') {
        const cleanInput = otp.toString().trim();
        const storedOtp = (challan.delivery_otp || '').toString().trim();
        if (storedOtp && cleanInput !== storedOtp) {
          await t.rollback();
          return res.status(400).json({ success: false, message: 'Invalid Delivery OTP entered. Please verify with recipient.' });
        }
      }

      const deliveryNote = remark
        ? `${remark}${receiver_name ? ` (Received by: ${receiver_name})` : ''}`
        : (receiver_name ? `Received by: ${receiver_name}` : 'Goods delivered and verified by driver');

      // Update Challan to DELIVERED
      await challan.update(
        {
          delivery_status: 'DELIVERED',
          status: 'Delivered',
          delivered_at: new Date(),
          delivered_by_remark: deliveryNote
        },
        { transaction: t }
      );

      // Increment driver's completed consignments
      if (challan.driver_id && (req as any).propertyDb.models.transport_drivers) {
        await (req as any).propertyDb.models.transport_drivers.increment('total_consignments_completed', {
          by: 1,
          where: { id: challan.driver_id, outlet_id },
          transaction: t
        }).catch(() => null);
      }

      // Check if all other challans in this trip/vehicle are also delivered
      let tripCompleted = false;
      if (challan.trip_id) {
        const remainingInTrip = await (req as any).propertyDb.models.delivery_challan_headers.count({
          where: {
            outlet_id,
            trip_id: challan.trip_id,
            delivery_status: { [Op.ne]: 'DELIVERED' }
          },
          transaction: t
        });

        if (remainingInTrip === 0) {
          tripCompleted = true;
          // Free the vehicle
          if (challan.vehicle_id) {
            await (req as any).propertyDb.models.transport_vehicles.update(
              {
                status: 'AVAILABLE',
                current_trip_id: null,
                current_driver_id: null
              },
              { where: { id: challan.vehicle_id, outlet_id }, transaction: t }
            );
          }
          // Free the driver
          if (challan.driver_id) {
            await (req as any).propertyDb.models.transport_drivers.update(
              {
                status: 'AVAILABLE',
                current_vehicle_id: null
              },
              { where: { id: challan.driver_id, outlet_id }, transaction: t }
            );
          }
        }
      } else if (challan.vehicle_id) {
        // Single challan without trip_id: check if any other pending challan on this vehicle
        const remainingOnVehicle = await (req as any).propertyDb.models.delivery_challan_headers.count({
          where: {
            outlet_id,
            vehicle_id: challan.vehicle_id,
            delivery_status: { [Op.ne]: 'DELIVERED' }
          },
          transaction: t
        });

        if (remainingOnVehicle === 0) {
          tripCompleted = true;
          await (req as any).propertyDb.models.transport_vehicles.update(
            { status: 'AVAILABLE', current_trip_id: null, current_driver_id: null },
            { where: { id: challan.vehicle_id, outlet_id }, transaction: t }
          );
          if (challan.driver_id) {
            await (req as any).propertyDb.models.transport_drivers.update(
              { status: 'AVAILABLE', current_vehicle_id: null },
              { where: { id: challan.driver_id, outlet_id }, transaction: t }
            );
          }
        }
      }

      await t.commit();

      return res.json({
        success: true,
        message: tripCompleted
          ? `Challan ${challan.challan_no} delivered! All deliveries complete; Truck & Driver are now AVAILABLE.`
          : `Challan ${challan.challan_no} marked as DELIVERED!`,
        data: {
          challan,
          tripCompleted
        }
      });
    } catch (err: any) {
      await t.rollback();
      console.error('verifyDelivery error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  // =========================================================================
  // RELEASE VEHICLE & DRIVER TRIP MANUALLY
  // =========================================================================

  public static async releaseTrip(req: Request, res: Response): Promise<any> {
    const t = await (req as any).propertyDb.transaction();
    try {
      const outlet_id = (req as any).user.outlet_id;
      const { vehicle_id, driver_id, trip_id } = req.body;

      if (vehicle_id) {
        await (req as any).propertyDb.models.transport_vehicles.update(
          { status: 'AVAILABLE', current_trip_id: null, current_driver_id: null },
          { where: { id: vehicle_id, outlet_id }, transaction: t }
        );
      }

      if (driver_id) {
        await (req as any).propertyDb.models.transport_drivers.update(
          { status: 'AVAILABLE', current_vehicle_id: null },
          { where: { id: driver_id, outlet_id }, transaction: t }
        );
      }

      if (trip_id) {
        // Also release any vehicle/driver linked to this trip_id
        await (req as any).propertyDb.models.transport_vehicles.update(
          { status: 'AVAILABLE', current_trip_id: null, current_driver_id: null },
          { where: { current_trip_id: trip_id, outlet_id }, transaction: t }
        );
      }

      await t.commit();
      return res.json({ success: true, message: 'Vehicle and Driver have been marked AVAILABLE.' });
    } catch (err: any) {
      await t.rollback();
      console.error('releaseTrip error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  // =========================================================================
  // ACTIVE TRIPS & DISPATCH MANIFEST
  // =========================================================================

  public static async getActiveTrips(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;

      const bookedVehicles = await (req as any).propertyDb.models.transport_vehicles.findAll({
        where: {
          outlet_id,
          status: { [Op.in]: ['BOOKED', 'IN_TRANSIT'] },
          is_active: true
        },
        include: [
          {
            model: (req as any).propertyDb.models.transport_drivers,
            as: 'current_driver',
            required: false
          }
        ]
      });

      const activeTrips: any[] = [];

      for (const vehicle of bookedVehicles) {
        const plainVehicle = vehicle.toJSON();
        const tripWhere: any = {
          outlet_id,
          vehicle_id: plainVehicle.id,
          delivery_status: { [Op.ne]: 'DELIVERED' }
        };

        const challans = await (req as any).propertyDb.models.delivery_challan_headers.findAll({
          where: tripWhere,
          include: [
            {
              model: (req as any).propertyDb.models.delivery_challan_items,
              as: 'items'
            }
          ]
        });

        let driverData = plainVehicle.current_driver;
        if (driverData && (driverData.last_latitude == null || driverData.last_longitude == null) && (req as any).propertyDb.models.transport_driver_locations) {
          const latestLoc = await (req as any).propertyDb.models.transport_driver_locations.findOne({
            where: { driver_id: driverData.id },
            order: [['created_at', 'DESC']]
          }).catch(() => null);
          if (latestLoc) {
            driverData = {
              ...driverData,
              last_latitude: latestLoc.latitude,
              last_longitude: latestLoc.longitude,
              last_location_address: latestLoc.address || driverData.last_location_address,
              last_location_updated: latestLoc.created_at
            };
          }
        }

        activeTrips.push({
          vehicle: plainVehicle,
          driver: driverData,
          trip_id: plainVehicle.current_trip_id,
          challan_count: challans.length,
          challans
        });
      }

      return res.json({ success: true, data: activeTrips });
    } catch (err: any) {
      console.error('getActiveTrips error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  // =========================================================================
  // TRUCK DRIVER PORTAL & SELF-SERVICE AUTH / TRACKING
  // =========================================================================

  public static async driverLogin(req: Request, res: Response): Promise<any> {
    try {
      const { login_id, password } = req.body;
      if (!login_id || !password) {
        return res.status(400).json({ success: false, message: 'Phone/Email and Password are required.' });
      }

      const cleanLogin = login_id.toString().trim();
      const driver = await (req as any).propertyDb.models.transport_drivers.findOne({
        where: {
          is_active: true,
          [Op.or]: [
            { phone: cleanLogin },
            { email: { [Op.iLike]: cleanLogin } }
          ]
        },
        include: [
          {
            model: (req as any).propertyDb.models.transport_vehicles,
            as: 'current_vehicle',
            required: false
          }
        ]
      });

      if (!driver) {
        return res.status(401).json({ success: false, message: 'Driver account not found with this Phone or Email.' });
      }

      if (driver.status === 'TERMINATED' || driver.status === 'INACTIVE' || driver.is_active === false) {
        return res.status(403).json({ success: false, message: 'This driver account has been terminated or deactivated by the admin.' });
      }

      const bcrypt = require('bcryptjs');
      let isMatch = false;
      if (driver.password_hash) {
        isMatch = await bcrypt.compare(password.toString().trim(), driver.password_hash);
      } else {
        isMatch = password.toString().trim() === '123456' || password.toString().trim() === driver.phone;
      }

      if (!isMatch) {
        return res.status(401).json({ success: false, message: 'Incorrect password entered.' });
      }

      const jwt = require('../../utils/jwt.util');
      const token = jwt.sign({
        driver_id: driver.id,
        id: driver.id,
        driver_name: driver.driver_name,
        phone: driver.phone,
        email: driver.email,
        outlet_id: driver.outlet_id,
        role: 'DRIVER'
      });

      return res.json({
        success: true,
        message: `Welcome, ${driver.driver_name}!`,
        token,
        driver: {
          id: driver.id,
          driver_name: driver.driver_name,
          phone: driver.phone,
          email: driver.email,
          license_number: driver.license_number,
          status: driver.status,
          total_consignments_completed: driver.total_consignments_completed || 0,
          outlet_id: driver.outlet_id,
          current_vehicle: driver.current_vehicle
        }
      });
    } catch (err: any) {
      console.error('driverLogin error:', err);
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async getDriverMe(req: Request, res: Response): Promise<any> {
    try {
      const driverId = (req as any).user?.driver_id || (req as any).user?.id;
      const driver = await (req as any).propertyDb.models.transport_drivers.findByPk(driverId, {
        include: [
          {
            model: (req as any).propertyDb.models.transport_vehicles,
            as: 'current_vehicle',
            required: false
          }
        ]
      });

      if (!driver || driver.is_active === false || driver.status === 'TERMINATED' || driver.status === 'INACTIVE') {
        return res.status(403).json({
          success: false,
          auto_logout: true,
          message: 'Driver profile has been terminated or deactivated by the admin.'
        });
      }

      return res.json({
        success: true,
        driver: {
          id: driver.id,
          driver_name: driver.driver_name,
          phone: driver.phone,
          email: driver.email,
          license_number: driver.license_number,
          status: driver.status,
          total_consignments_completed: driver.total_consignments_completed || 0,
          last_latitude: driver.last_latitude,
          last_longitude: driver.last_longitude,
          last_location_address: driver.last_location_address,
          last_location_updated: driver.last_location_updated,
          current_vehicle: driver.current_vehicle
        }
      });
    } catch (err: any) {
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async driverForgotPassword(req: Request, res: Response): Promise<any> {
    try {
      const { login_id } = req.body;
      if (!login_id) return res.status(400).json({ success: false, message: 'Please provide registered Phone or Email.' });

      const clean = login_id.toString().trim();
      const driver = await (req as any).propertyDb.models.transport_drivers.findOne({
        where: {
          is_active: true,
          [Op.or]: [
            { phone: clean },
            { email: { [Op.iLike]: clean } }
          ]
        }
      });

      if (!driver) {
        return res.status(404).json({ success: false, message: 'No driver found with this Phone or Email.' });
      }

      const otp = String(Math.floor(100000 + Math.random() * 900000));
      const expiresAt = new Date(Date.now() + 15 * 60 * 1000);

      await driver.update({
        reset_otp: otp,
        reset_otp_expires_at: expiresAt
      });

      try {
        const { sendEmail } = require('../../services/email.service');
        if (driver.email) {
          await sendEmail({
            to: driver.email,
            subject: 'Password Reset OTP - Truck Driver App',
            html: `<p>Dear ${driver.driver_name},</p><p>Your OTP for resetting your Truck Driver portal password is: <b>${otp}</b>.</p><p>This OTP will expire in 15 minutes.</p>`
          });
        }
      } catch (mailErr: any) {
        console.warn('Driver reset email send warning:', mailErr.message);
      }

      return res.json({
        success: true,
        message: `OTP sent to ${driver.email ? driver.email : 'registered mobile ' + driver.phone}. (OTP: ${otp})`,
        demo_otp: otp
      });
    } catch (err: any) {
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async driverResetPassword(req: Request, res: Response): Promise<any> {
    try {
      const { login_id, otp, new_password } = req.body;
      if (!login_id || !otp || !new_password) {
        return res.status(400).json({ success: false, message: 'Phone/Email, OTP, and New Password are required.' });
      }

      const clean = login_id.toString().trim();
      const driver = await (req as any).propertyDb.models.transport_drivers.findOne({
        where: {
          is_active: true,
          [Op.or]: [
            { phone: clean },
            { email: { [Op.iLike]: clean } }
          ]
        }
      });

      if (!driver) return res.status(404).json({ success: false, message: 'Driver not found.' });

      if (!driver.reset_otp || driver.reset_otp !== otp.toString().trim()) {
        return res.status(400).json({ success: false, message: 'Invalid OTP. Please check the OTP sent to your email.' });
      }

      if (driver.reset_otp_expires_at && new Date() > new Date(driver.reset_otp_expires_at)) {
        return res.status(400).json({ success: false, message: 'OTP has expired. Please request a new one.' });
      }

      const bcrypt = require('bcryptjs');
      const hash = await bcrypt.hash(new_password.toString().trim(), 10);
      await driver.update({
        password_hash: hash,
        reset_otp: null,
        reset_otp_expires_at: null
      });

      return res.json({ success: true, message: 'Password updated successfully! You can now log in.' });
    } catch (err: any) {
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async getDriverAssignedTrips(req: Request, res: Response): Promise<any> {
    try {
      const driverId = (req as any).user?.driver_id || (req as any).user?.id;
      const driver = await (req as any).propertyDb.models.transport_drivers.findByPk(driverId);
      if (!driver || driver.status === 'TERMINATED' || driver.status === 'INACTIVE' || !driver.is_active) {
        return res.status(403).json({ success: false, auto_logout: true, message: 'Account terminated or deactivated.' });
      }

      const challans = await (req as any).propertyDb.models.delivery_challan_headers.findAll({
        where: {
          driver_id: driverId,
          delivery_status: { [Op.in]: ['IN_TRANSIT', 'PENDING'] }
        },
        include: [
          {
            model: (req as any).propertyDb.models.delivery_challan_items,
            as: 'items'
          }
        ],
        order: [['id', 'DESC']]
      });

      const deliveredRecent = await (req as any).propertyDb.models.delivery_challan_headers.findAll({
        where: {
          driver_id: driverId,
          delivery_status: 'DELIVERED'
        },
        include: [
          {
            model: (req as any).propertyDb.models.delivery_challan_items,
            as: 'items'
          }
        ],
        order: [['delivered_at', 'DESC']],
        limit: 10
      });

      return res.json({
        success: true,
        data: {
          active_challans: challans,
          delivered_recent: deliveredRecent,
          total_completed: driver.total_consignments_completed || deliveredRecent.length
        }
      });
    } catch (err: any) {
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async driverUpdateLocation(req: Request, res: Response): Promise<any> {
    try {
      const driverId = (req as any).user?.driver_id || (req as any).user?.id;
      const { latitude, longitude, address, battery_level, trip_id } = req.body;

      if (!latitude || !longitude) {
        return res.status(400).json({ success: false, message: 'Latitude and Longitude are required.' });
      }

      const driver = await (req as any).propertyDb.models.transport_drivers.findByPk(driverId);
      if (!driver || driver.status === 'TERMINATED' || driver.status === 'INACTIVE' || !driver.is_active) {
        return res.status(403).json({ success: false, auto_logout: true, message: 'Account terminated or deactivated.' });
      }

      let resolvedAddress = (address || '').toString().trim();
      if (!resolvedAddress || resolvedAddress.startsWith('GPS Location (') || resolvedAddress.startsWith('(')) {
        try {
          const geoAddr = await reverseGeocodeCoords(Number(latitude), Number(longitude));
          if (geoAddr) {
            resolvedAddress = geoAddr;
          }
        } catch (_) {}
      }

      const now = new Date();
      await driver.update({
        last_latitude: latitude,
        last_longitude: longitude,
        last_location_address: resolvedAddress || driver.last_location_address,
        last_location_updated: now
      });

      if ((req as any).propertyDb.models.transport_driver_locations) {
        await (req as any).propertyDb.models.transport_driver_locations.create({
          outlet_id: driver.outlet_id,
          driver_id: driver.id,
          trip_id: trip_id || null,
          latitude,
          longitude,
          address: resolvedAddress || null,
          battery_level: battery_level || null,
          created_at: now
        }).catch(() => null);
      }

      return res.json({ success: true, message: 'Live GPS location updated successfully.' });
    } catch (err: any) {
      return res.status(500).json({ success: false, error: err.message });
    }
  }

  public static async getFleetLiveTracking(req: Request, res: Response): Promise<any> {
    try {
      const outlet_id = (req as any).user.outlet_id;
      const drivers = await (req as any).propertyDb.models.transport_drivers.findAll({
        where: { outlet_id, is_active: true },
        attributes: [
          'id', 'driver_name', 'phone', 'email', 'license_number', 'status',
          'last_latitude', 'last_longitude', 'last_location_address', 'last_location_updated',
          'total_consignments_completed'
        ],
        include: [
          {
            model: (req as any).propertyDb.models.transport_vehicles,
            as: 'current_vehicle',
            required: false,
            attributes: ['id', 'vehicle_number', 'vehicle_type', 'status', 'current_trip_id']
          }
        ],
        order: [['driver_name', 'ASC']]
      });

      return res.json({ success: true, data: drivers });
    } catch (err: any) {
      return res.status(500).json({ success: false, error: err.message });
    }
  }
}

export default TransportController;
