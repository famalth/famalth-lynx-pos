import 'package:shared_preferences/shared_preferences.dart';
import 'control_plane_storage.dart';
import 'token_storage.dart';

/// Centralized check to determine if any app in the suite currently has an
/// active authenticated user session. Used to restrict server endpoint changes
/// to pre-login screens only.
class SessionGuard {
  static Future<bool> hasActiveLoginSession() async {
    try {
      // 1. Standard POS, Mobile Billing, Waiter, Supplier, Employee HRMS
      final token = await TokenStorage.read();
      if (token != null && token.isNotEmpty) {
        return true;
      }

      // 2. Master Control Plane
      if (await ControlPlaneStorage.isAuthenticated()) {
        return true;
      }

      final prefs = await SharedPreferences.getInstance();

      // 3. Customer App
      final customerSession = prefs.getString('delivery_logged_in_customer');
      if (customerSession != null && customerSession.trim().isNotEmpty) {
        return true;
      }

      // 4. Rider App
      final riderSession = prefs.getString('delivery_logged_in_rider');
      if (riderSession != null && riderSession.trim().isNotEmpty) {
        return true;
      }

      // 5. Driver Portal App
      final driverToken = prefs.getString('transport_driver_token');
      if (driverToken != null && driverToken.trim().isNotEmpty) {
        return true;
      }

      // 6. Clinic Booking App
      final clinicProfile = prefs.getString('clinic_patient_profile');
      if (clinicProfile != null && clinicProfile.trim().isNotEmpty) {
        return true;
      }

      // 7. Table Dining App (outlet-scoped or global token/profile)
      for (final key in prefs.getKeys()) {
        if (key == 'dining_auth_token' ||
            key.startsWith('dining_auth_token_') ||
            key == 'dining_customer_profile' ||
            key.startsWith('dining_customer_profile_')) {
          final val = prefs.getString(key);
          if (val != null && val.trim().isNotEmpty) {
            return true;
          }
        }
      }
    } catch (_) {
      // Fail open only if SharedPreferences cannot be read; normal path handles all keys.
    }
    return false;
  }
}
