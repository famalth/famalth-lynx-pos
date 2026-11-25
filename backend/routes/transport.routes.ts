import { Router } from 'express';
import { TransportController } from '../controllers/inventory/transport.controller';
const auth = require('../middlewares/auth.middleware');

const router = Router();

// Public Driver Auth & Password Reset (no token required)
router.post('/driver/login', TransportController.driverLogin);
router.post('/driver/forgot-password', TransportController.driverForgotPassword);
router.post('/driver/reset-password', TransportController.driverResetPassword);

router.use(auth);

// Driver Authenticated Self-Service Endpoints
router.get('/driver/me', TransportController.getDriverMe);
router.get('/driver/assigned-trips', TransportController.getDriverAssignedTrips);
router.post('/driver/verify-delivery', TransportController.verifyDelivery);
router.post('/driver/update-location', TransportController.driverUpdateLocation);

// Admin Live Fleet Tracking
router.get('/fleet-tracking', TransportController.getFleetLiveTracking);

// Vehicle endpoints
router.get('/vehicles', TransportController.listVehicles);
router.post('/vehicles', TransportController.createVehicle);
router.put('/vehicles/:id', TransportController.updateVehicle);
router.delete('/vehicles/:id', TransportController.deleteVehicle);

// Driver management endpoints (Admin)
router.get('/drivers', TransportController.listDrivers);
router.post('/drivers', TransportController.createDriver);
router.put('/drivers/:id', TransportController.updateDriver);
router.delete('/drivers/:id', TransportController.deleteDriver);

// Trip & Delivery Challan Logistics endpoints
router.post('/assign-trip', TransportController.assignTrip);
router.post('/verify-delivery', TransportController.verifyDelivery);
router.post('/release-trip', TransportController.releaseTrip);
router.get('/active-trips', TransportController.getActiveTrips);

module.exports = router;
export default router;
