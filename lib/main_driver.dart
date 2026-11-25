import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'controllers/security/recovery_controller.dart';
import 'controllers/security/user_controller.dart';
import 'controllers/settings/app_branding_controller.dart';
import 'controllers/settings/notification_services.dart';
import 'controllers/settings/property_info_controller.dart';
import 'controllers/settings/system_settings_controller.dart';
import 'controllers/settings/theme_controller.dart';
import 'controllers/settings/ui_preferences_controller.dart';
import 'controllers/transport/transport_controller.dart';
import 'core/config/app_config.dart';
import 'core/config/date_time_service.dart';
import 'main.dart'; // Reuses MyApp and global navigation/snackbar keys
import 'screens/transport/driver_portal_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await NotificationService.init();
  await AppConfig.init();
  await DateTimeService.instance.init();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SystemSettingsController()..load()),
        ChangeNotifierProvider(create: (_) => ThemeController()..load()),
        ChangeNotifierProvider(create: (_) => UiPreferencesController()..load()),
        ChangeNotifierProvider(create: (_) => AppBrandingController()..loadLocal()),
        ChangeNotifierProvider(create: (_) => UserController()),
        ChangeNotifierProvider(create: (_) => RecoveryController()),
        ChangeNotifierProvider(create: (_) => PropertyInfoController()..load()),
        ChangeNotifierProvider(create: (_) => TransportController()),
      ],
      child: const MyApp(homeWidget: DriverPortalScreen()),
    ),
  );
}
