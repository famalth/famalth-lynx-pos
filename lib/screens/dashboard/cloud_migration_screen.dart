import 'dart:async';
import '../../core/config/app_config.dart';
import '../../core/settings/local_preferences.dart';
import 'package:flutter/material.dart';
import '../../core/auth/token_storage.dart';
import '../../core/services/cloud_migration_service.dart';
import '../splash_screen.dart';

enum MigrationDirection {
  offlineToCloud,
  cloudToOffline
}

enum MigrationStep {
  configure,
  connecting,
  exporting,
  uploading,
  switching,
  completed,
  failed
}

class CloudMigrationScreen extends StatefulWidget {
  final MigrationDirection initialDirection;
  const CloudMigrationScreen({super.key, this.initialDirection = MigrationDirection.offlineToCloud});

  @override
  State<CloudMigrationScreen> createState() => _CloudMigrationScreenState();
}

class _CloudMigrationScreenState extends State<CloudMigrationScreen> {
  late MigrationDirection _direction;
  final _cloudUrlCtrl = TextEditingController(text: "https://");
  final _outletCodeCtrl = TextEditingController();
  final _adminPassCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _isRequestingOtp = false;
  bool _otpSent = false;
  String _maskedEmail = "";
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  MigrationStep _currentStep = MigrationStep.configure;
  String _statusMessage = "";
  String _errorMessage = "";
  Map<String, dynamic> _migratedStats = {};
  String _migratedOutletCode = "";
  final String _migrationScope = 'OUTLET'; // Locked to single outlet (one-by-one)

  @override
  void initState() {
    super.initState();
    _direction = widget.initialDirection;
    _loadCurrentOutlet();
  }

  Future<void> _loadCurrentOutlet() async {
    final currentOutlet = await TokenStorage.getOutletCode();
    if (currentOutlet != null && currentOutlet.isNotEmpty) {
      setState(() {
        _outletCodeCtrl.text = currentOutlet;
      });
    }
  }

  @override
  void dispose() {
    _cloudUrlCtrl.dispose();
    _outletCodeCtrl.dispose();
    _adminPassCtrl.dispose();
    _otpCtrl.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestSecurityOtp() async {
    final cloudUrl = _cloudUrlCtrl.text.trim();
    final outletCode = _outletCodeCtrl.text.trim();
    final isOfflineMode = _direction == MigrationDirection.offlineToCloud;

    if (!isOfflineMode && (cloudUrl.isEmpty || cloudUrl == 'https://')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Cloud Server URL to verify outlet.')),
      );
      return;
    }

    if (outletCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your specific Outlet Code.')),
      );
      return;
    }

    setState(() => _isRequestingOtp = true);

    // Target server to request OTP:
    // If downloading from cloud (Online -> Offline), request OTP from Cloud Server
    // If uploading to cloud (Offline -> Online), request OTP from local backend
    final targetServer = isOfflineMode ? (AppConfig.baseUrl) : cloudUrl;

    final res = await CloudMigrationService.requestMigrationOtp(
      serverUrl: targetServer,
      outletCode: outletCode,
      scope: 'OUTLET',
    );

    if (!mounted) return;
    setState(() => _isRequestingOtp = false);

    if (res['success'] == true) {
      setState(() {
        _otpSent = true;
        _maskedEmail = res['masked_email'] ?? '';
        _resendCooldown = 60;
      });
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (_resendCooldown > 0) {
          if (mounted) setState(() => _resendCooldown--);
        } else {
          timer.cancel();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'OTP sent to registered email!'),
          backgroundColor: const Color(0xFF059669),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['message'] ?? 'Failed to send OTP.'),
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    }
  }

  Future<void> _startMigration() async {
    final cloudUrl = _cloudUrlCtrl.text.trim();
    final outletCode = _outletCodeCtrl.text.trim();
    final adminPass = _adminPassCtrl.text.trim();

    if (cloudUrl.isEmpty || cloudUrl == 'https://') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid Cloud Server URL')),
      );
      return;
    }

    if (outletCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outlet Code is required to migrate store data')),
      );
      return;
    }

    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty || otp.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔒 Security Verification: Please request and enter the 6-digit Email OTP before migrating.'),
          backgroundColor: Color(0xFFEA580C),
        ),
      );
      return;
    }

    setState(() {
      _currentStep = MigrationStep.connecting;
      _statusMessage = "Testing connection to Cloud Server ($cloudUrl)...";
      _errorMessage = "";
    });

    try {
      // Step 1: Verify Cloud Server
      final pingRes = await CloudMigrationService.testCloudConnection(cloudUrl);
      if (pingRes['success'] != true) {
        setState(() {
          _currentStep = MigrationStep.failed;
          _errorMessage = pingRes['message'] ?? 'Could not reach target Cloud Server.';
        });
        return;
      }

      if (_direction == MigrationDirection.offlineToCloud) {
        // --- PATH A: OFFLINE TO CLOUD (RELATIONAL ID TRANSLATION) ---
        setState(() {
          _currentStep = MigrationStep.exporting;
          _statusMessage = "Packaging local products, customers, transactions and settings for outlet $outletCode...";
        });

        final exportRes = await CloudMigrationService.exportLocalStoreBundle(
          outletCode: outletCode,
          scope: _migrationScope,
          otp: otp,
        );
        if (exportRes['success'] != true || exportRes['bundle'] == null) {
          setState(() {
            _currentStep = MigrationStep.failed;
            _errorMessage = exportRes['message'] ?? 'Failed to export local store data.';
          });
          return;
        }

        final bundle = Map<String, dynamic>.from(exportRes['bundle']);

        setState(() {
          _currentStep = MigrationStep.uploading;
          _statusMessage = "Transmitting to cloud with Relational ID Translation & Sequence mapping...";
        });

        final importRes = await CloudMigrationService.uploadAndMigrateToCloud(
          cloudUrl: cloudUrl,
          bundle: bundle,
          targetOutletCode: outletCode.isNotEmpty ? outletCode : null,
          adminPassword: adminPass.isNotEmpty ? adminPass : null,
          mode: "MERGE_OUTLET",
          otp: otp,
        );

        if (importRes['success'] != true) {
          setState(() {
            _currentStep = MigrationStep.failed;
            _errorMessage = importRes['message'] ?? 'Cloud server failed to ingest store data.';
          });
          return;
        }

        setState(() {
          _currentStep = MigrationStep.switching;
          _statusMessage = "Finalizing outlet cloud synchronization...";
        });

        final finalOutlet = importRes['outlet_code'] ?? outletCode;
        final token = importRes['token'];

        await CloudMigrationService.completeCloudMigrationSwitch(
          cloudUrl: cloudUrl,
          outletCode: finalOutlet,
          token: token,
          user: importRes['user'],
        );
        await LocalPreferences.setLastOutletCode(finalOutlet);

        setState(() {
          _currentStep = MigrationStep.completed;
          _statusMessage = "Store successfully migrated to Cloud Server!";
          _migratedStats = Map<String, dynamic>.from(importRes['stats'] ?? exportRes['stats'] ?? {});
          _migratedOutletCode = finalOutlet;
        });

      } else {
        // --- PATH B: CLOUD TO OFFLINE (CLEAN LOCAL PURGE & RESTORE) ---
        setState(() {
          _currentStep = MigrationStep.uploading;
          _statusMessage = "Purging local database tables and restoring cloud store dataset...";
        });

        final pullRes = await CloudMigrationService.pullOnlineToOffline(
          cloudUrl: cloudUrl,
          outletCode: outletCode,
          adminPassword: adminPass.isNotEmpty ? adminPass : null,
          scope: 'OUTLET',
          otp: otp,
        );

        if (pullRes['success'] != true) {
          setState(() {
            _currentStep = MigrationStep.failed;
            _errorMessage = pullRes['message'] ?? 'Failed to download and restore cloud store locally.';
          });
          return;
        }

        setState(() {
          _currentStep = MigrationStep.switching;
          _statusMessage = "Finalizing local offline outlet restore...";
        });

        await CloudMigrationService.completeCloudMigrationSwitch(
          cloudUrl: "http://127.0.0.1:3000",
          outletCode: outletCode,
          token: pullRes['token'],
          user: pullRes['user'],
        );
        await LocalPreferences.setLastOutletCode(outletCode);

        setState(() {
          _currentStep = MigrationStep.completed;
          _statusMessage = "Cloud store downloaded and restored to local offline station!";
          _migratedStats = Map<String, dynamic>.from(pullRes['stats'] ?? {});
          _migratedOutletCode = outletCode;
        });
      }

    } catch (e) {
      setState(() {
        _currentStep = MigrationStep.failed;
        _errorMessage = "Migration encountered an unexpected error: $e";
      });
    }
  }

  void _finishAndLaunch() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const SplashScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Store Migration Wizard'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 680),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _buildBody(theme, isDark),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark) {
    switch (_currentStep) {
      case MigrationStep.configure:
        return _buildConfigureView(theme, isDark);
      case MigrationStep.connecting:
      case MigrationStep.exporting:
      case MigrationStep.uploading:
      case MigrationStep.switching:
        return _buildProgressView(theme, isDark);
      case MigrationStep.completed:
        return _buildCompletedView(theme, isDark);
      case MigrationStep.failed:
        return _buildFailedView(theme, isDark);
    }
  }

  Widget _buildConfigureView(ThemeData theme, bool isDark) {
    final isOfflineMode = _direction == MigrationDirection.offlineToCloud;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Direction Toggle Segmented Controls
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _direction = MigrationDirection.offlineToCloud),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isOfflineMode ? (isDark ? const Color(0xFF1E293B) : Colors.white) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: isOfflineMode
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_upload_rounded,
                          size: 18,
                          color: isOfflineMode ? const Color(0xFF0284C7) : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Offline ➔ Online Cloud',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isOfflineMode ? FontWeight.bold : FontWeight.normal,
                            color: isOfflineMode ? (isDark ? Colors.white : const Color(0xFF0F172A)) : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => setState(() => _direction = MigrationDirection.cloudToOffline),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: !isOfflineMode ? (isDark ? const Color(0xFF1E293B) : Colors.white) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: !isOfflineMode
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_download_rounded,
                          size: 18,
                          color: !isOfflineMode ? const Color(0xFF10B981) : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Online Cloud ➔ Offline',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: !isOfflineMode ? FontWeight.bold : FontWeight.normal,
                            color: !isOfflineMode ? (isDark ? Colors.white : const Color(0xFF0F172A)) : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Migration Scope Badge (Strictly single outlet: one-by-one)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F9FF),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isDark ? const Color(0xFF1E3A5F) : const Color(0xFFBAE6FD)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.storefront_rounded, size: 20, color: Color(0xFF0284C7)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Migration Scope: Single Outlet (One-by-One)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Each store outlet must be migrated individually. Offline licenses do not work on Cloud and will require activation via the Console.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Header Description
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (isOfflineMode ? const Color(0xFF0284C7) : const Color(0xFF10B981)).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isOfflineMode ? Icons.cloud_upload_rounded : Icons.cloud_download_rounded,
                color: isOfflineMode ? const Color(0xFF0284C7) : const Color(0xFF10B981),
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOfflineMode ? 'Migrate to Shared Cloud Server' : 'Download Cloud Store to Offline Station',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isOfflineMode
                        ? 'Translates local row IDs dynamically into new cloud IDs to prevent conflicts with existing cloud merchants.'
                        : 'Purges old local database tables and restores a clean offline mirror of your cloud store data.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 16),

        // Cloud Server URL Field
        TextField(
          controller: _cloudUrlCtrl,
          decoration: const InputDecoration(
            labelText: 'Cloud Server URL',
            hintText: 'https://your-cloud-domain.com or https://pos.famalth.com',
            prefixIcon: Icon(Icons.dns_rounded),
            border: OutlineInputBorder(),
            helperText: 'Base URL of the hosted cloud backend',
          ),
        ),
        const SizedBox(height: 16),

        // Outlet Code
        TextField(
          controller: _outletCodeCtrl,
          decoration: InputDecoration(
            labelText: isOfflineMode
                ? 'Outlet Code to Migrate (Offline ➔ Cloud)'
                : 'Outlet Code to Migrate (Cloud ➔ Offline)',
            hintText: 'e.g. OUTLET202611102255',
            prefixIcon: const Icon(Icons.storefront_rounded),
            border: const OutlineInputBorder(),
            helperText: 'Each outlet is migrated separately. Other linked outlets will remain safe and untouched.',
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (AppConfig.outlets.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Linked Outlets:',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.grey[400] : Colors.grey[700],
                ),
              ),
              ...AppConfig.outlets.map((code) {
                final isSelected = _outletCodeCtrl.text.trim() == code;
                return ChoiceChip(
                  label: Text(
                    code,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _outletCodeCtrl.text = code;
                      });
                    }
                  },
                );
              }),
            ],
          ),
        ],
        const SizedBox(height: 16),

        // Admin Password
        TextField(
          controller: _adminPassCtrl,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Admin Password (Optional)',
            hintText: 'Leave empty to preserve existing password',
            prefixIcon: Icon(Icons.lock_outline_rounded),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 18),

        // Security Authorization Section (Email OTP)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _otpSent
                  ? const Color(0xFF10B981)
                  : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
              width: _otpSent ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.security_rounded,
                    color: _otpSent ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Email Security Authorization (Required)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'To prevent unauthorized data access or restore, an OTP verification code must be sent to the outlet owner\'s registered email address.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 14),
              if (_otpSent) ...[
                if (_maskedEmail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Verification code sent to $_maskedEmail (Valid for 10 min)',
                            style: const TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: const InputDecoration(
                          counterText: '',
                          labelText: '6-Digit Email OTP *',
                          hintText: 'Enter 6-digit code',
                          prefixIcon: Icon(Icons.password_rounded),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                      onPressed: (_resendCooldown > 0 || _isRequestingOtp) ? null : _requestSecurityOtp,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(_resendCooldown > 0 ? '${_resendCooldown}s' : 'Resend OTP'),
                    ),
                  ],
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                        color: isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7),
                      ),
                    ),
                    onPressed: _isRequestingOtp ? null : _requestSecurityOtp,
                    icon: _isRequestingOtp
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mark_email_read_outlined, size: 18),
                    label: Text(_isRequestingOtp ? 'Sending OTP to Registered Email...' : 'Send Security OTP to Registered Email'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 24),

        // Safety Architecture Callout
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isOfflineMode ? Icons.auto_awesome_rounded : Icons.cleaning_services_rounded,
                    color: isOfflineMode ? const Color(0xFF0284C7) : const Color(0xFF10B981),
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isOfflineMode ? 'Zero ID Conflict Engine:' : 'Clean Local Restore Process:',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isOfflineMode
                    ? '• Products, Customers, Sales and Purchases are mapped to new cloud IDs.\n• Foreign keys (sale_id, item_id, customer_id, po_id) are translated automatically.\n• Sequence numbering continues from highest ID without colliding with other merchants.'
                    : '• Cleanly wipes existing local tables to prevent duplicate/orphan rows.\n• Pulls full catalog, customer balances, invoices, and sequence settings from cloud.\n• Switches terminal into offline standalone mode.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),

        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: isOfflineMode ? const Color(0xFF0284C7) : const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _startMigration,
          icon: Icon(isOfflineMode ? Icons.rocket_launch_rounded : Icons.download_rounded),
          label: Text(
            isOfflineMode ? 'Start 1-Click Migration to Cloud' : 'Download Cloud Store Offline',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressView(ThemeData theme, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 16),
        const SizedBox(
          width: 56,
          height: 56,
          child: CircularProgressIndicator(strokeWidth: 4, color: Color(0xFF0284C7)),
        ),
        const SizedBox(height: 24),
        Text(
          _direction == MigrationDirection.offlineToCloud ? 'Migrating Store to Cloud...' : 'Downloading Cloud Store Data...',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        Text(
          _statusMessage,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 28),
        _buildStepTimeline(isDark),
      ],
    );
  }

  Widget _buildStepTimeline(bool isDark) {
    return Column(
      children: [
        _stepRow("1. Connect to Cloud Server", _currentStep.index >= MigrationStep.connecting.index, _currentStep == MigrationStep.connecting),
        _stepRow("2. Package Store Master & Sales Data", _currentStep.index >= MigrationStep.exporting.index, _currentStep == MigrationStep.exporting),
        _stepRow("3. Relational ID Translation & Ingestion", _currentStep.index >= MigrationStep.uploading.index, _currentStep == MigrationStep.uploading),
        _stepRow("4. Terminal Configuration Switch", _currentStep.index >= MigrationStep.switching.index, _currentStep == MigrationStep.switching),
      ],
    );
  }

  Widget _stepRow(String title, bool isDone, bool isActive) {
    Color color = Colors.grey;
    IconData icon = Icons.radio_button_unchecked_rounded;

    if (isDone && !isActive) {
      color = const Color(0xFF10B981);
      icon = Icons.check_circle_rounded;
    } else if (isActive) {
      color = const Color(0xFF0284C7);
      icon = Icons.sync_rounded;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontSize: 13.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletedView(ThemeData theme, bool isDark) {
    final isOfflineMode = _direction == MigrationDirection.offlineToCloud;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 56),
        ),
        const SizedBox(height: 20),
        Text(
          'Migration Completed Successfully! 🎉',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          isOfflineMode
              ? 'Your store data has been safely transferred to the online cloud server with relational ID translation.'
              : 'Your cloud store has been restored locally in standalone offline mode.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13.5,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 24),

        // Statistics Grid
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _statItem('Products', '${_migratedStats['products'] ?? 0}', Icons.inventory_2_outlined),
                  _statItem('Customers', '${_migratedStats['customers'] ?? 0}', Icons.people_outline_rounded),
                  _statItem('Sales', '${_migratedStats['sales'] ?? 0}', Icons.receipt_long_outlined),
                ],
              ),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 6),
              Text(
                'Active Outlet: $_migratedOutletCode',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0284C7)),
              ),
            ],
          ),
        ),
        if (isOfflineMode) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF451A03).withValues(alpha: 0.3) : const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Cloud License Activation Required',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13.5,
                          color: Color(0xFFD97706),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Store data migrated successfully! Note: Offline licenses do not work on online cloud servers. The cloud license is EXPIRED and must be activated via the Management Console before terminal operations can proceed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 24),

        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: isOfflineMode ? const Color(0xFF0284C7) : const Color(0xFF10B981),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: _finishAndLaunch,
          icon: Icon(isOfflineMode ? Icons.login_rounded : Icons.rocket_launch_rounded),
          label: Text(
            isOfflineMode ? 'Proceed to Login / Console Activation' : 'Open Local Offline POS Now',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  Widget _buildFailedView(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 56),
        ),
        const SizedBox(height: 20),
        Text(
          'Migration Incomplete',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.red),
        ),
        const SizedBox(height: 10),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13.5, color: Colors.redAccent),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () {
            setState(() {
              _currentStep = MigrationStep.configure;
            });
          },
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Try Again'),
        ),
      ],
    );
  }

  Widget _statItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 22, color: const Color(0xFF0284C7)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
      ],
    );
  }
}
