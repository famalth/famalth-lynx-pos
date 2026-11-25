import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/config/app_config.dart';
import '../dashboard/server_config_screen.dart';
import 'driver_app_splash_screen.dart';

class DriverPortalScreen extends StatefulWidget {
  const DriverPortalScreen({super.key});

  @override
  State<DriverPortalScreen> createState() => _DriverPortalScreenState();
}

class _DriverPortalScreenState extends State<DriverPortalScreen> {
  bool _isLoading = true;
  String? _driverToken;
  Map<String, dynamic>? _driverProfile;

  // Login Form Controllers
  final TextEditingController _loginIdCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoggingIn = false;

  // Driver Dashboard State
  int _selectedNavTab = 0; // 0: Active Trips & Consignments, 1: Profile & History
  List<dynamic> _activeChallans = [];
  List<dynamic> _deliveredRecent = [];
  int _totalCompleted = 0;
  bool _isLoadingTrips = false;

  // Live Location & Periodic Timer
  Timer? _hourlyLocationTimer;
  String _lastLocationMsg = 'Location not updated yet';
  bool _isUpdatingGps = false;

  @override
  void initState() {
    super.initState();
    _checkPersistedSession();
  }

  @override
  void dispose() {
    _hourlyLocationTimer?.cancel();
    _loginIdCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // =========================================================================
  // AUTHENTICATION & PERSISTENT SESSION
  // =========================================================================

  Future<void> _checkPersistedSession() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('transport_driver_token');

    if (token != null && token.isNotEmpty) {
      _driverToken = token;
      try {
        final res = await ApiClient.get('/api/transport/driver/me', token: token, silent: true);
        if (res['success'] == true && res['driver'] != null) {
          _driverProfile = res['driver'];
          _startHourlyLocationTracking();
          await _fetchDriverTrips();
          setState(() => _isLoading = false);
          return;
        } else if (res['auto_logout'] == true) {
          await _logoutDriver(reason: res['message'] ?? 'Account terminated or deactivated by admin.');
          return;
        }
      } catch (_) {
        // If offline, continue with cached profile
        final cachedName = prefs.getString('transport_driver_name');
        if (cachedName != null) {
          _driverProfile = {
            'driver_name': cachedName,
            'phone': prefs.getString('transport_driver_phone') ?? '',
            'total_consignments_completed': prefs.getInt('transport_driver_completed') ?? 0,
          };
          _startHourlyLocationTracking();
          await _fetchDriverTrips();
          setState(() => _isLoading = false);
          return;
        }
      }
    }

    setState(() {
      _driverToken = null;
      _driverProfile = null;
      _isLoading = false;
    });
  }

  Future<void> _handleLogin() async {
    final loginId = _loginIdCtrl.text.trim();
    final pass = _passwordCtrl.text.trim();

    if (loginId.isEmpty || pass.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Phone/Email and Password')),
      );
      return;
    }

    setState(() => _isLoggingIn = true);
    try {
      final res = await ApiClient.post('/api/transport/driver/login', {
        'login_id': loginId,
        'password': pass,
      });

      if (res['success'] == true && res['token'] != null) {
        final token = res['token'].toString();
        final driver = res['driver'] as Map<String, dynamic>;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('transport_driver_token', token);
        await prefs.setString('transport_driver_name', driver['driver_name'] ?? '');
        await prefs.setString('transport_driver_phone', driver['phone'] ?? '');
        await prefs.setInt('transport_driver_completed', driver['total_consignments_completed'] ?? 0);

        setState(() {
          _driverToken = token;
          _driverProfile = driver;
        });

        _startHourlyLocationTracking();
        await _fetchDriverTrips();
        await _sendGpsLocationPing(); // Send immediate location on login
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Login failed. Please check credentials.'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Login Error: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Configure Server',
              textColor: Colors.amberAccent,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ServerConfigScreen(
                      nextScreen: DriverAppSplashScreen(),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoggingIn = false);
    }
  }

  Future<void> _logoutDriver({String? reason}) async {
    _hourlyLocationTimer?.cancel();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('transport_driver_token');
    await prefs.remove('transport_driver_name');
    await prefs.remove('transport_driver_phone');
    await prefs.remove('transport_driver_completed');

    setState(() {
      _driverToken = null;
      _driverProfile = null;
      _activeChallans.clear();
      _deliveredRecent.clear();
      _isLoading = false;
    });

    if (reason != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(reason), backgroundColor: Colors.orange.shade800),
      );
    }
  }

  // =========================================================================
  // PASSWORD RESET VIA EMAIL OTP
  // =========================================================================

  void _openForgotPasswordDialog() {
    final forgotLoginCtrl = TextEditingController(text: _loginIdCtrl.text.trim());
    final otpCtrl = TextEditingController();
    final newPassCtrl = TextEditingController();
    bool otpSent = false;
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  const Icon(Icons.lock_reset, color: Color(0xFF008060)),
                  const SizedBox(width: 8),
                  Text(otpSent ? 'Enter OTP & New Password' : 'Reset Driver Password', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!otpSent) ...[
                      const Text(
                        'Enter your registered Phone Number or Email ID. We will send a 6-digit OTP to reset your password.',
                        style: TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: forgotLoginCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Phone or Email *',
                          prefixIcon: Icon(Icons.account_circle_outlined),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ] else ...[
                      Text(
                        'OTP sent to ${forgotLoginCtrl.text.trim()}. Please enter OTP and your new password.',
                        style: const TextStyle(fontSize: 13, color: Colors.indigo),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: otpCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          labelText: '6-Digit OTP *',
                          prefixIcon: Icon(Icons.pin),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: newPassCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New Password *',
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (!otpSent) {
                            if (forgotLoginCtrl.text.trim().isEmpty) return;
                            setDialogState(() => isSubmitting = true);
                            try {
                              final res = await ApiClient.post('/api/transport/driver/forgot-password', {
                                'login_id': forgotLoginCtrl.text.trim(),
                              });
                              if (res['success'] == true) {
                                setDialogState(() {
                                  otpSent = true;
                                  isSubmitting = false;
                                });
                              } else {
                                setDialogState(() => isSubmitting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res['message'] ?? 'Could not send OTP')),
                                );
                              }
                            } catch (e) {
                              setDialogState(() => isSubmitting = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                            }
                          } else {
                            if (otpCtrl.text.trim().length < 6 || newPassCtrl.text.trim().isEmpty) return;
                            setDialogState(() => isSubmitting = true);
                            try {
                              final res = await ApiClient.post('/api/transport/driver/reset-password', {
                                'login_id': forgotLoginCtrl.text.trim(),
                                'otp': otpCtrl.text.trim(),
                                'new_password': newPassCtrl.text.trim(),
                              });
                              if (res['success'] == true) {
                                Navigator.pop(dCtx);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Password reset successfully! Please login.'),
                                    backgroundColor: Color(0xFF008060),
                                  ),
                                );
                              } else {
                                setDialogState(() => isSubmitting = false);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(res['message'] ?? 'Failed to reset password')),
                                );
                              }
                            } catch (e) {
                              setDialogState(() => isSubmitting = false);
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                            }
                          }
                        },
                  child: Text(otpSent ? 'Update Password' : 'Send OTP'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // LIVE GPS LOCATION TRACKING (EVERY 1 HOUR & MANUAL PING)
  // =========================================================================

  void _startHourlyLocationTracking() {
    _hourlyLocationTimer?.cancel();
    // Run live GPS ping every 1 hour (3600 seconds)
    _hourlyLocationTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _sendGpsLocationPing(silent: true);
    });
  }

  Future<void> _sendGpsLocationPing({bool silent = false}) async {
    if (_driverToken == null) return;
    if (!silent) setState(() => _isUpdatingGps = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      double lat = 30.3165; // Fallback Dehradun coordinates
      double lng = 78.0322;

      if (serviceEnabled && permission != LocationPermission.denied && permission != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          timeLimit: const Duration(seconds: 10),
        );
        lat = pos.latitude;
        lng = pos.longitude;
      }

      final res = await ApiClient.post(
        '/api/transport/driver/update-location',
        {
          'latitude': lat,
          'longitude': lng,
          'address': 'GPS Location (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})',
        },
        token: _driverToken,
      );

      if (res['success'] == true && mounted) {
        setState(() {
          _lastLocationMsg = 'Live GPS synced at ${TimeOfDay.now().format(context)} (${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)})';
        });
        if (!silent) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Live location sent to Owner Dashboard!'), backgroundColor: Color(0xFF008060)),
          );
        }
      } else if (res['auto_logout'] == true) {
        await _logoutDriver(reason: 'Account terminated or deactivated.');
      }
    } catch (e) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('GPS ping notice: $e')));
      }
    } finally {
      if (!silent && mounted) setState(() => _isUpdatingGps = false);
    }
  }

  // =========================================================================
  // ASSIGNED CHALLANS & OTP DELIVERY VERIFICATION
  // =========================================================================

  Future<void> _fetchDriverTrips() async {
    if (_driverToken == null) return;
    setState(() => _isLoadingTrips = true);
    try {
      final res = await ApiClient.get('/api/transport/driver/assigned-trips', token: _driverToken, silent: true);
      if (res['success'] == true && res['data'] != null) {
        final data = res['data'];
        setState(() {
          _activeChallans = data['active_challans'] ?? [];
          _deliveredRecent = data['delivered_recent'] ?? [];
          _totalCompleted = data['total_completed'] ?? _deliveredRecent.length;
        });
      } else if (res['auto_logout'] == true) {
        await _logoutDriver(reason: res['message'] ?? 'Account terminated or deactivated.');
      }
    } catch (e) {
      debugPrint('Error fetching driver trips: $e');
    } finally {
      if (mounted) setState(() => _isLoadingTrips = false);
    }
  }

  void _openOtpVerificationDialog(Map<String, dynamic> challan) {
    final otpCtrl = TextEditingController();
    final receiverCtrl = TextEditingController(text: challan['customer_name'] ?? '');
    final remarkCtrl = TextEditingController();
    bool isSubmitting = false;

    showDialog(
      context: context,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  const Icon(Icons.verified_user, color: Color(0xFF008060)),
                  const SizedBox(width: 8),
                  Text('Verify Delivery OTP #${challan['challan_no']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Recipient: ${challan['customer_name']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            const SizedBox(height: 2),
                            Text('Phone: ${challan['customer_phone'] ?? 'N/A'} | Qty: ${challan['total_qty']} Units', style: const TextStyle(fontSize: 12)),
                            if (challan['destination_address'] != null)
                              Text('Site: ${challan['destination_address']}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Ask the recipient for their 6-Digit Delivery OTP to confirm goods handover:',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: otpCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        autofocus: true,
                        style: const TextStyle(fontSize: 20, letterSpacing: 6, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          hintText: '123456',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: receiverCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Received By (Person Name)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: remarkCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Delivery Remarks (Optional)',
                          hintText: 'e.g. Unloaded at warehouse gate #2',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final otp = otpCtrl.text.trim();
                          if (otp.length < 6) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter the complete 6-digit OTP')),
                            );
                            return;
                          }

                          setDialogState(() => isSubmitting = true);
                          try {
                            final res = await ApiClient.post(
                              '/api/transport/verify-delivery',
                              {
                                'challan_id': challan['id'],
                                'otp': otp,
                                'receiver_name': receiverCtrl.text.trim(),
                                'remark': remarkCtrl.text.trim(),
                              },
                              token: _driverToken,
                            );

                            if (res['success'] == true) {
                              Navigator.pop(dCtx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Challan #${challan['challan_no']} marked DELIVERED successfully!'),
                                  backgroundColor: const Color(0xFF008060),
                                ),
                              );
                              await _fetchDriverTrips();
                              await _sendGpsLocationPing(silent: true);
                            } else {
                              setDialogState(() => isSubmitting = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(res['message'] ?? 'Invalid OTP entered. Please check with recipient.'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isSubmitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Verification error: $e'), backgroundColor: Colors.red),
                            );
                          }
                        },
                  icon: const Icon(Icons.check_circle, size: 18),
                  label: const Text('Verify OTP & Complete Delivery'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // UI BUILDERS: LOGIN SCREEN & DRIVER DASHBOARD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFF008060)),
              SizedBox(height: 12),
              Text('Checking Driver Session...', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    if (_driverToken == null) {
      return _buildLoginView();
    }

    return _buildDashboardView();
  }

  Widget _buildLoginView() {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.dns_outlined, size: 18, color: Color(0xFF008060)),
            label: Text(
              AppConfig.baseUrl.replaceAll('https://', '').replaceAll('http://', ''),
              style: const TextStyle(fontSize: 12, color: Color(0xFF008060), fontWeight: FontWeight.bold),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ServerConfigScreen(
                    nextScreen: DriverAppSplashScreen(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: Color(0xFF008060)),
            tooltip: 'Configure / Scan Server QR',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ServerConfigScreen(
                    nextScreen: DriverAppSplashScreen(),
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            padding: const EdgeInsets.all(28.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Driver App Logo Header
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF008060).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_shipping, size: 48, color: Color(0xFF008060)),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Truck Driver Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sign in to view your assigned delivery challans, update live GPS, and verify delivery OTPs.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 24),

                // Login ID (Phone / Email)
                TextField(
                  controller: _loginIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Driver Login ID (Phone or Email) *',
                    hintText: 'e.g. 9876543210 or driver@mail.com',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 14),

                // Password
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password *',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 8),

                // Forgot Password link
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _openForgotPasswordDialog,
                    child: const Text('Forgot Password? (Reset via Email OTP)', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(height: 14),

                // Login Button
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF008060),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isLoggingIn ? null : _handleLogin,
                  child: _isLoggingIn
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text('Sign In as Driver', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 14),

                // Connected Server Display & Shortcut
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ServerConfigScreen(
                          nextScreen: DriverAppSplashScreen(),
                        ),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Connected to: ${AppConfig.baseUrl} (Tap to change)',
                            style: const TextStyle(fontSize: 11, color: Colors.grey, decoration: TextDecoration.underline),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Persistent Session: You will stay logged in on this device until you explicitly log out or the admin deactivates your account.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardView() {
    final driverName = _driverProfile?['driver_name'] ?? 'Truck Driver';
    final vehicle = _driverProfile?['current_vehicle'];
    final vehiclePlate = vehicle != null ? '${vehicle['vehicle_number']} (${vehicle['vehicle_type']})' : 'Assigned Truck';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, size: 20, color: Color(0xFF008060)),
                const SizedBox(width: 8),
                Text(driverName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            Text(vehiclePlate, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.dns_outlined),
            tooltip: 'Server Settings',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ServerConfigScreen(
                    nextScreen: DriverAppSplashScreen(),
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Trips',
            onPressed: _fetchDriverTrips,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log Out',
            onPressed: () => _logoutDriver(reason: 'Logged out successfully.'),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavTab,
        onDestinationSelected: (idx) => setState(() => _selectedNavTab = idx),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _activeChallans.isNotEmpty,
              label: Text('${_activeChallans.length}'),
              child: const Icon(Icons.alt_route),
            ),
            label: 'Active Consignments',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_circle),
            label: 'Driver Profile & Stats',
          ),
        ],
      ),
      body: _selectedNavTab == 0 ? _buildActiveTripsTab() : _buildProfileTab(),
    );
  }

  Widget _buildActiveTripsTab() {
    return RefreshIndicator(
      onRefresh: () async {
        await _fetchDriverTrips();
        await _sendGpsLocationPing(silent: true);
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Live GPS Tracking Banner Card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF008060).withValues(alpha: 0.2)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF008060).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.gps_fixed, color: Color(0xFF008060), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Text('Live Fleet GPS Tracking', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                            SizedBox(width: 6),
                            Text('• Syncs Hourly', style: TextStyle(color: Color(0xFF008060), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(_lastLocationMsg, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF008060),
                      side: const BorderSide(color: Color(0xFF008060)),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _isUpdatingGps ? null : () => _sendGpsLocationPing(silent: false),
                    icon: _isUpdatingGps
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location, size: 14),
                    label: const Text('Update GPS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Active Challans Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Assigned Challans (${_activeChallans.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF0F172A)),
                ),
                Text(
                  'Ask OTP on handover',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 10),

            if (_activeChallans.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade400),
                    const SizedBox(height: 12),
                    const Text('No Pending Deliveries!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text('You have completed all assigned consignments.', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _activeChallans.length,
                itemBuilder: (context, idx) {
                  final challan = _activeChallans[idx];
                  final items = (challan['items'] as List?) ?? [];

                  return Card(
                    elevation: 1,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header: Challan # and Status
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.indigo.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.indigo.shade200),
                                ),
                                child: Text(
                                  'Challan #${challan['challan_no']}',
                                  style: TextStyle(color: Colors.indigo.shade900, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  (challan['delivery_status'] ?? 'IN_TRANSIT').toString().toUpperCase(),
                                  style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Customer Name & Phone
                          Text(
                            challan['customer_name'] ?? 'Customer',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.phone, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(challan['customer_phone'] ?? 'No Phone', style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
                              const SizedBox(width: 12),
                              if (challan['customer_phone'] != null && challan['customer_phone'].toString().isNotEmpty)
                                InkWell(
                                  onTap: () async {
                                    final uri = Uri.parse('tel:${challan['customer_phone']}');
                                    if (await canLaunchUrl(uri)) await launchUrl(uri);
                                  },
                                  child: const Text('Call', style: TextStyle(color: Color(0xFF008060), fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                            ],
                          ),

                          // Destination Site
                          if (challan['destination_address'] != null && challan['destination_address'].toString().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.location_on_outlined, size: 15, color: Colors.red.shade400),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    challan['destination_address'],
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          const Divider(),
                          const SizedBox(height: 6),

                          // Items List
                          Text('Consignment Items (${items.length}):', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          const SizedBox(height: 4),
                          ...items.map((it) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text('• ${it['item_name']}', style: const TextStyle(fontSize: 12)),
                                  ),
                                  Text(
                                    '${it['qty']} ${it['unit'] ?? ''}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 14),

                          // Verify OTP & Deliver Button
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF008060),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () => _openOtpVerificationDialog(challan),
                              icon: const Icon(Icons.verified, size: 18),
                              label: const Text('Verify OTP & Mark Delivered', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileTab() {
    final driverName = _driverProfile?['driver_name'] ?? 'Truck Driver';
    final phone = _driverProfile?['phone'] ?? 'N/A';
    final email = _driverProfile?['email'] ?? 'Not registered';
    final license = _driverProfile?['license_number'] ?? 'N/A';
    final vehicle = _driverProfile?['current_vehicle'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Consignments Completed Badge Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF008060), Color(0xFF005E46)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(color: const Color(0xFF008060).withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                const Icon(Icons.military_tech, size: 48, color: Colors.amberAccent),
                const SizedBox(height: 8),
                Text(
                  '$_totalCompleted',
                  style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const Text(
                  'Consignments Successfully Delivered',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Driver Details Card
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Driver Details', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  _buildProfileRow('Driver Name', driverName, Icons.person),
                  const Divider(height: 16),
                  _buildProfileRow('Phone Number', phone, Icons.phone),
                  const Divider(height: 16),
                  _buildProfileRow('Email ID', email, Icons.email),
                  const Divider(height: 16),
                  _buildProfileRow('Driving License #', license, Icons.badge),
                  if (vehicle != null) ...[
                    const Divider(height: 16),
                    _buildProfileRow('Assigned Vehicle', '${vehicle['vehicle_number']} (${vehicle['vehicle_type']})', Icons.rv_hookup),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Recent Deliveries History
          Card(
            elevation: 0.5,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Recent Completed Consignments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 10),
                  if (_deliveredRecent.isEmpty)
                    const Text('No recent deliveries completed yet.', style: TextStyle(color: Colors.grey, fontSize: 13))
                  else
                    ..._deliveredRecent.map((c) {
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.check_circle, color: Color(0xFF008060)),
                        title: Text('Challan #${c['challan_no']} - ${c['customer_name']}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        subtitle: Text('Delivered ${c['delivered_at'] != null ? c['delivered_at'].toString().substring(0, 10) : 'Recently'}', style: const TextStyle(fontSize: 11)),
                      );
                    }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Logout Button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: () => _logoutDriver(reason: 'Logged out successfully.'),
              icon: const Icon(Icons.logout, size: 18),
              label: const Text('Log Out from Driver App', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 10),
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        const Spacer(),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
