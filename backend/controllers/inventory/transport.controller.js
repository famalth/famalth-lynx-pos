"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.TransportController = void 0;
const sequelize_1 = require("sequelize");
async function reverseGeocodeCoords(lat, lng) {
    try {
        const url = `https://api.bigdatacloud.net/data/reverse-geocode-client?latitude=${lat}&longitude=${lng}&localityLanguage=en`;
        const res = await fetch(url, { signal: AbortSignal.timeout(3000) });
        if (res.ok) {
            const data = await res.json();
            const parts = new Set();
            if (data.locality)
                parts.add(data.locality);
            if (data.city && data.city !== data.locality)
                parts.add(data.city);
            if (data.principalSubdivision)
                parts.add(data.principalSubdivision);
            if (parts.size === 0 && data.countryName)
                parts.add(data.countryName);
            if (parts.size > 0)
                return Array.from(parts).join(', ');
        }
    }
    catch (_) { }
    try {
        const res = await fetch(`https://nominatim.openstreetmap.org/reverse?format=json&lat=${lat}&lon=${lng}`, {
            headers: { 'User-Agent': 'FamalthLynx/1.0 (pos@famalth.com)' },
            signal: AbortSignal.timeout(3000)
        });
        if (res.ok) {
            const data = await res.json();
            if (data.display_name) {
                return data.display_name.split(',').slice(0, 3).map((s) => s.trim()).join(', ');
            }
        }
    }
    catch (_) { }
    return null;
}
class TransportController {
    // =========================================================================
    // VEHICLE MANAGEMENT
    // =========================================================================
    static async listVehicles(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const { status, search } = req.query;
            const where = { outlet_id, is_active: true };
            if (status && status !== 'ALL') {
                where.status = status;
            }
            if (search) {
                where[sequelize_1.Op.or] = [
                    { vehicle_number: { [sequelize_1.Op.iLike]: `%${search}%` } },
                    { vehicle_type: { [sequelize_1.Op.iLike]: `%${search}%` } },
                    { model: { [sequelize_1.Op.iLike]: `%${search}%` } }
                ];
            }
            const vehicles = await req.propertyDb.models.transport_vehicles.findAll({
                where,
                include: [
                    {
                        model: req.propertyDb.models.transport_drivers,
                        as: 'current_driver',
                        required: false,
                        attributes: ['id', 'driver_name', 'phone', 'license_number', 'last_latitude', 'last_longitude', 'last_location_address', 'last_location_updated']
                    }
                ],
                order: [['vehicle_number', 'ASC']]
            });
            return res.json({ success: true, data: vehicles });
        }
        catch (err) {
            console.error('listVehicles error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async createVehicle(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const { vehicle_number, vehicle_type, capacity_tonnage, capacity_unit, model, notes } = req.body;
            if (!vehicle_number || !vehicle_number.trim()) {
                return res.status(400).json({ success: false, message: 'Vehicle number is required' });
            }
            const formattedNumber = vehicle_number.trim().toUpperCase();
            // Check duplicate
            const existing = await req.propertyDb.models.transport_vehicles.findOne({
                where: { outlet_id, vehicle_number: formattedNumber, is_active: true }
            });
            if (existing) {
                return res.status(400).json({ success: false, message: `Vehicle ${formattedNumber} already exists.` });
            }
            const vehicle = await req.propertyDb.models.transport_vehicles.create({
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
        }
        catch (err) {
            console.error('createVehicle error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async updateVehicle(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const { id } = req.params;
            const { vehicle_number, vehicle_type, capacity_tonnage, capacity_unit, model, status, notes } = req.body;
            const vehicle = await req.propertyDb.models.transport_vehicles.findOne({
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
        }
        catch (err) {
            console.error('updateVehicle error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async deleteVehicle(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const { id } = req.params;
            const vehicle = await req.propertyDb.models.transport_vehicles.findOne({
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
        }
        catch (err) {
            console.error('deleteVehicle error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    // =========================================================================
    // DRIVER MANAGEMENT
    // =========================================================================
    static async listDrivers(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const { status, search } = req.query;
            const where = { outlet_id, is_active: true };
            if (status && status !== 'ALL') {
                where.status = status;
            }
            if (search) {
                where[sequelize_1.Op.or] = [
                    { driver_name: { [sequelize_1.Op.iLike]: `%${search}%` } },
                    { phone: { [sequelize_1.Op.iLike]: `%${search}%` } },
                    { license_number: { [sequelize_1.Op.iLike]: `%${search}%` } }
                ];
            }
            const drivers = await req.propertyDb.models.transport_drivers.findAll({
                where,
                include: [
                    {
                        model: req.propertyDb.models.transport_vehicles,
                        as: 'current_vehicle',
                        required: false,
                        attributes: ['id', 'vehicle_number', 'vehicle_type', 'model']
                    }
                ],
                order: [['driver_name', 'ASC']]
            });
            return res.json({ success: true, data: drivers });
        }
        catch (err) {
            console.error('listDrivers error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async createDriver(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
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
            const existing = await req.propertyDb.models.transport_drivers.findOne({
                where: {
                    outlet_id,
                    is_active: true,
                    [sequelize_1.Op.or]: [
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
            }
            else {
                const bcrypt = require('bcryptjs');
                password_hash = await bcrypt.hash('123456', 10);
            }
            const driver = await req.propertyDb.models.transport_drivers.create({
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
        }
        catch (err) {
            console.error('createDriver error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async updateDriver(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const { id } = req.params;
            const { driver_name, phone, email, password, license_number, address, status } = req.body;
            const driver = await req.propertyDb.models.transport_drivers.findOne({
                where: { id, outlet_id }
            });
            if (!driver) {
                return res.status(404).json({ success: false, message: 'Driver not found' });
            }
            const updatePayload = {};
            if (driver_name !== undefined)
                updatePayload.driver_name = driver_name ? driver_name.trim() : driver.driver_name;
            if (phone !== undefined)
                updatePayload.phone = phone ? phone.trim() : driver.phone;
            if (email !== undefined)
                updatePayload.email = email && String(email).trim() ? String(email).trim().toLowerCase() : null;
            if (license_number !== undefined)
                updatePayload.license_number = license_number ? license_number.trim().toUpperCase() : null;
            if (address !== undefined)
                updatePayload.address = address ? address.trim() : null;
            if (status !== undefined) {
                updatePayload.status = status;
                if (status === 'TERMINATED' || status === 'INACTIVE') {
                    updatePayload.is_active = false;
                }
                else {
                    updatePayload.is_active = true;
                }
            }
            if (password && password.toString().trim()) {
                const bcrypt = require('bcryptjs');
                updatePayload.password_hash = await bcrypt.hash(password.toString().trim(), 10);
            }
            await driver.update(updatePayload);
            return res.json({ success: true, data: driver, message: 'Driver profile updated successfully' });
        }
        catch (err) {
            console.error('updateDriver error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async deleteDriver(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const { id } = req.params;
            const driver = await req.propertyDb.models.transport_drivers.findOne({
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
        }
        catch (err) {
            console.error('deleteDriver error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    // =========================================================================
    // TRIP ASSIGNMENT & MULTI-CHALLAN GROUPING PER TRUCK
    // =========================================================================
    static async assignTrip(req, res) {
        const t = await req.propertyDb.transaction();
        try {
            const outlet_id = req.user.outlet_id;
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
            const vehicle = await req.propertyDb.models.transport_vehicles.findOne({
                where: { id: vehicle_id, outlet_id },
                transaction: t
            });
            if (!vehicle) {
                await t.rollback();
                return res.status(404).json({ success: false, message: 'Selected vehicle not found.' });
            }
            // Check driver
            const driver = await req.propertyDb.models.transport_drivers.findOne({
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
            const assignedChallans = [];
            for (const challanId of challan_ids) {
                const challan = await req.propertyDb.models.delivery_challan_headers.findOne({
                    where: { id: challanId, outlet_id },
                    transaction: t
                });
                if (!challan)
                    continue;
                // Generate 6-digit OTP for secure customer delivery
                const delivery_otp = String(Math.floor(100000 + Math.random() * 900000));
                await challan.update({
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
                }, { transaction: t });
                assignedChallans.push({
                    id: challan.id,
                    challan_no: challan.challan_no,
                    customer_name: challan.customer_name,
                    delivery_otp
                });
            }
            // Set vehicle status to BOOKED
            await vehicle.update({
                status: 'BOOKED',
                current_trip_id: trip_id,
                current_driver_id: driver.id
            }, { transaction: t });
            // Set driver status to BOOKED
            await driver.update({
                status: 'BOOKED',
                current_vehicle_id: vehicle.id
            }, { transaction: t });
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
        }
        catch (err) {
            await t.rollback();
            console.error('assignTrip error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    // =========================================================================
    // VERIFY DELIVERY (OTP OR DRIVER SUBMIT CONFIRMATION)
    // =========================================================================
    static async verifyDelivery(req, res) {
        const t = await req.propertyDb.transaction();
        try {
            const outlet_id = req.user.outlet_id;
            const { challan_id, otp, remark, receiver_name } = req.body;
            if (!challan_id) {
                await t.rollback();
                return res.status(400).json({ success: false, message: 'Challan ID is required.' });
            }
            const challan = await req.propertyDb.models.delivery_challan_headers.findOne({
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
            await challan.update({
                delivery_status: 'DELIVERED',
                status: 'Delivered',
                delivered_at: new Date(),
                delivered_by_remark: deliveryNote
            }, { transaction: t });
            // Increment driver's completed consignments
            if (challan.driver_id && req.propertyDb.models.transport_drivers) {
                await req.propertyDb.models.transport_drivers.increment('total_consignments_completed', {
                    by: 1,
                    where: { id: challan.driver_id, outlet_id },
                    transaction: t
                }).catch(() => null);
            }
            // Check if all other challans in this trip/vehicle are also delivered
            let tripCompleted = false;
            if (challan.trip_id) {
                const remainingInTrip = await req.propertyDb.models.delivery_challan_headers.count({
                    where: {
                        outlet_id,
                        trip_id: challan.trip_id,
                        delivery_status: { [sequelize_1.Op.ne]: 'DELIVERED' }
                    },
                    transaction: t
                });
                if (remainingInTrip === 0) {
                    tripCompleted = true;
                    // Free the vehicle
                    if (challan.vehicle_id) {
                        await req.propertyDb.models.transport_vehicles.update({
                            status: 'AVAILABLE',
                            current_trip_id: null,
                            current_driver_id: null
                        }, { where: { id: challan.vehicle_id, outlet_id }, transaction: t });
                    }
                    // Free the driver
                    if (challan.driver_id) {
                        await req.propertyDb.models.transport_drivers.update({
                            status: 'AVAILABLE',
                            current_vehicle_id: null
                        }, { where: { id: challan.driver_id, outlet_id }, transaction: t });
                    }
                }
            }
            else if (challan.vehicle_id) {
                // Single challan without trip_id: check if any other pending challan on this vehicle
                const remainingOnVehicle = await req.propertyDb.models.delivery_challan_headers.count({
                    where: {
                        outlet_id,
                        vehicle_id: challan.vehicle_id,
                        delivery_status: { [sequelize_1.Op.ne]: 'DELIVERED' }
                    },
                    transaction: t
                });
                if (remainingOnVehicle === 0) {
                    tripCompleted = true;
                    await req.propertyDb.models.transport_vehicles.update({ status: 'AVAILABLE', current_trip_id: null, current_driver_id: null }, { where: { id: challan.vehicle_id, outlet_id }, transaction: t });
                    if (challan.driver_id) {
                        await req.propertyDb.models.transport_drivers.update({ status: 'AVAILABLE', current_vehicle_id: null }, { where: { id: challan.driver_id, outlet_id }, transaction: t });
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
        }
        catch (err) {
            await t.rollback();
            console.error('verifyDelivery error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    // =========================================================================
    // RELEASE VEHICLE & DRIVER TRIP MANUALLY
    // =========================================================================
    static async releaseTrip(req, res) {
        const t = await req.propertyDb.transaction();
        try {
            const outlet_id = req.user.outlet_id;
            const { vehicle_id, driver_id, trip_id } = req.body;
            if (vehicle_id) {
                await req.propertyDb.models.transport_vehicles.update({ status: 'AVAILABLE', current_trip_id: null, current_driver_id: null }, { where: { id: vehicle_id, outlet_id }, transaction: t });
            }
            if (driver_id) {
                await req.propertyDb.models.transport_drivers.update({ status: 'AVAILABLE', current_vehicle_id: null }, { where: { id: driver_id, outlet_id }, transaction: t });
            }
            if (trip_id) {
                // Also release any vehicle/driver linked to this trip_id
                await req.propertyDb.models.transport_vehicles.update({ status: 'AVAILABLE', current_trip_id: null, current_driver_id: null }, { where: { current_trip_id: trip_id, outlet_id }, transaction: t });
            }
            await t.commit();
            return res.json({ success: true, message: 'Vehicle and Driver have been marked AVAILABLE.' });
        }
        catch (err) {
            await t.rollback();
            console.error('releaseTrip error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    // =========================================================================
    // ACTIVE TRIPS & DISPATCH MANIFEST
    // =========================================================================
    static async getActiveTrips(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const bookedVehicles = await req.propertyDb.models.transport_vehicles.findAll({
                where: {
                    outlet_id,
                    status: { [sequelize_1.Op.in]: ['BOOKED', 'IN_TRANSIT'] },
                    is_active: true
                },
                include: [
                    {
                        model: req.propertyDb.models.transport_drivers,
                        as: 'current_driver',
                        required: false
                    }
                ]
            });
            const activeTrips = [];
            for (const vehicle of bookedVehicles) {
                const plainVehicle = vehicle.toJSON();
                const tripWhere = {
                    outlet_id,
                    vehicle_id: plainVehicle.id,
                    delivery_status: { [sequelize_1.Op.ne]: 'DELIVERED' }
                };
                const challans = await req.propertyDb.models.delivery_challan_headers.findAll({
                    where: tripWhere,
                    include: [
                        {
                            model: req.propertyDb.models.delivery_challan_items,
                            as: 'items'
                        }
                    ]
                });
                let driverData = plainVehicle.current_driver;
                if (driverData && (driverData.last_latitude == null || driverData.last_longitude == null) && req.propertyDb.models.transport_driver_locations) {
                    const latestLoc = await req.propertyDb.models.transport_driver_locations.findOne({
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
        }
        catch (err) {
            console.error('getActiveTrips error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    // =========================================================================
    // TRUCK DRIVER PORTAL & SELF-SERVICE AUTH / TRACKING
    // =========================================================================
    static async driverLogin(req, res) {
        try {
            const { login_id, password } = req.body;
            if (!login_id || !password) {
                return res.status(400).json({ success: false, message: 'Phone/Email and Password are required.' });
            }
            const cleanLogin = login_id.toString().trim();
            const driver = await req.propertyDb.models.transport_drivers.findOne({
                where: {
                    is_active: true,
                    [sequelize_1.Op.or]: [
                        { phone: cleanLogin },
                        { email: { [sequelize_1.Op.iLike]: cleanLogin } }
                    ]
                },
                include: [
                    {
                        model: req.propertyDb.models.transport_vehicles,
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
            }
            else {
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
        }
        catch (err) {
            console.error('driverLogin error:', err);
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async getDriverMe(req, res) {
        try {
            const driverId = req.user?.driver_id || req.user?.id;
            const driver = await req.propertyDb.models.transport_drivers.findByPk(driverId, {
                include: [
                    {
                        model: req.propertyDb.models.transport_vehicles,
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
        }
        catch (err) {
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async driverForgotPassword(req, res) {
        try {
            const { login_id } = req.body;
            if (!login_id)
                return res.status(400).json({ success: false, message: 'Please provide registered Phone or Email.' });
            const clean = login_id.toString().trim();
            const driver = await req.propertyDb.models.transport_drivers.findOne({
                where: {
                    is_active: true,
                    [sequelize_1.Op.or]: [
                        { phone: clean },
                        { email: { [sequelize_1.Op.iLike]: clean } }
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
            }
            catch (mailErr) {
                console.warn('Driver reset email send warning:', mailErr.message);
            }
            return res.json({
                success: true,
                message: `OTP sent to ${driver.email ? driver.email : 'registered mobile ' + driver.phone}. (OTP: ${otp})`,
                demo_otp: otp
            });
        }
        catch (err) {
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async driverResetPassword(req, res) {
        try {
            const { login_id, otp, new_password } = req.body;
            if (!login_id || !otp || !new_password) {
                return res.status(400).json({ success: false, message: 'Phone/Email, OTP, and New Password are required.' });
            }
            const clean = login_id.toString().trim();
            const driver = await req.propertyDb.models.transport_drivers.findOne({
                where: {
                    is_active: true,
                    [sequelize_1.Op.or]: [
                        { phone: clean },
                        { email: { [sequelize_1.Op.iLike]: clean } }
                    ]
                }
            });
            if (!driver)
                return res.status(404).json({ success: false, message: 'Driver not found.' });
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
        }
        catch (err) {
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async getDriverAssignedTrips(req, res) {
        try {
            const driverId = req.user?.driver_id || req.user?.id;
            const driver = await req.propertyDb.models.transport_drivers.findByPk(driverId);
            if (!driver || driver.status === 'TERMINATED' || driver.status === 'INACTIVE' || !driver.is_active) {
                return res.status(403).json({ success: false, auto_logout: true, message: 'Account terminated or deactivated.' });
            }
            const challans = await req.propertyDb.models.delivery_challan_headers.findAll({
                where: {
                    driver_id: driverId,
                    delivery_status: { [sequelize_1.Op.in]: ['IN_TRANSIT', 'PENDING'] }
                },
                include: [
                    {
                        model: req.propertyDb.models.delivery_challan_items,
                        as: 'items'
                    }
                ],
                order: [['id', 'DESC']]
            });
            const deliveredRecent = await req.propertyDb.models.delivery_challan_headers.findAll({
                where: {
                    driver_id: driverId,
                    delivery_status: 'DELIVERED'
                },
                include: [
                    {
                        model: req.propertyDb.models.delivery_challan_items,
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
        }
        catch (err) {
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async driverUpdateLocation(req, res) {
        try {
            const driverId = req.user?.driver_id || req.user?.id;
            const { latitude, longitude, address, battery_level, trip_id } = req.body;
            if (!latitude || !longitude) {
                return res.status(400).json({ success: false, message: 'Latitude and Longitude are required.' });
            }
            const driver = await req.propertyDb.models.transport_drivers.findByPk(driverId);
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
                }
                catch (_) { }
            }
            const now = new Date();
            await driver.update({
                last_latitude: latitude,
                last_longitude: longitude,
                last_location_address: resolvedAddress || driver.last_location_address,
                last_location_updated: now
            });
            if (req.propertyDb.models.transport_driver_locations) {
                await req.propertyDb.models.transport_driver_locations.create({
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
        }
        catch (err) {
            return res.status(500).json({ success: false, error: err.message });
        }
    }
    static async getFleetLiveTracking(req, res) {
        try {
            const outlet_id = req.user.outlet_id;
            const drivers = await req.propertyDb.models.transport_drivers.findAll({
                where: { outlet_id, is_active: true },
                attributes: [
                    'id', 'driver_name', 'phone', 'email', 'license_number', 'status',
                    'last_latitude', 'last_longitude', 'last_location_address', 'last_location_updated',
                    'total_consignments_completed'
                ],
                include: [
                    {
                        model: req.propertyDb.models.transport_vehicles,
                        as: 'current_vehicle',
                        required: false,
                        attributes: ['id', 'vehicle_number', 'vehicle_type', 'status', 'current_trip_id']
                    }
                ],
                order: [['driver_name', 'ASC']]
            });
            return res.json({ success: true, data: drivers });
        }
        catch (err) {
            return res.status(500).json({ success: false, error: err.message });
        }
    }
}
exports.TransportController = TransportController;
exports.default = TransportController;
