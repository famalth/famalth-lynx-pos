import 'package:flutter/material.dart';
import '../../controllers/inventory/stock_transfer_controller.dart';
import '../inventory/stock_dispatch_screen.dart';
import '../reports/transfer_progress_dashboard_screen.dart';

class OutletHierarchyLinkingScreen extends StatefulWidget {
  const OutletHierarchyLinkingScreen({super.key});

  @override
  State<OutletHierarchyLinkingScreen> createState() => _OutletHierarchyLinkingScreenState();
}

class _OutletHierarchyLinkingScreenState extends State<OutletHierarchyLinkingScreen> {
  final StockTransferController _transferCtrl = StockTransferController();

  bool _isLoading = true;
  Map<String, dynamic>? _currentOutlet;
  Map<String, dynamic>? _masterOutlet;
  List<dynamic> _childOutlets = [];
  bool _shareContactInfo = true;

  @override
  void initState() {
    super.initState();
    _loadHierarchy();
  }

  Future<void> _loadHierarchy() async {
    setState(() => _isLoading = true);
    final data = await _transferCtrl.fetchHierarchy();
    if (mounted) {
      setState(() {
        _isLoading = false;
        if (data != null) {
          _currentOutlet = data['current_outlet'];
          _masterOutlet = data['master_outlet'];
          _childOutlets = data['child_outlets'] ?? data['linked_child_outlets'] ?? [];
          if (data['share_contact_info'] != null) {
            _shareContactInfo = Boolean(data['share_contact_info']);
          }
        }
      });
    }
  }

  bool Boolean(dynamic val) {
    if (val is bool) return val;
    if (val is int) return val == 1;
    return val.toString().toLowerCase() == 'true';
  }

  void _showLinkExistingOutletDialog() {
    final formKey = GlobalKey<FormState>();
    final codeCtrl = TextEditingController();
    final pinCtrl = TextEditingController();
    final otpCtrl = TextEditingController();

    String linkMethod = 'PIN'; // 'PIN' or 'OTP'
    bool isRequestingOtp = false;
    bool isOtpSent = false;
    String? otpHintMessage;
    bool isLinking = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.link, color: Colors.blue),
                const SizedBox(width: 10),
                Text('Link Existing Outlet (${linkMethod == 'PIN' ? 'PIN' : 'OTP'})'),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(
                            value: 'PIN',
                            label: Text('Recovery PIN'),
                            icon: Icon(Icons.pin),
                          ),
                          ButtonSegment(
                            value: 'OTP',
                            label: Text('OTP Code'),
                            icon: Icon(Icons.sms),
                          ),
                        ],
                        selected: {linkMethod},
                        onSelectionChanged: (Set<String> newSelection) {
                          setDialogState(() {
                            linkMethod = newSelection.first;
                            otpHintMessage = null;
                            isOtpSent = false;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      Text(
                        linkMethod == 'PIN'
                            ? 'Enter target outlet code and its 4-digit Recovery PIN setup during registration to link under this Master Outlet.'
                            : 'Enter target outlet code to send a 6-digit verification OTP to its registered mobile/email.',
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: codeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Target Outlet Code (e.g. OUTLET202604212159)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.store),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Target Outlet Code is required' : null,
                      ),
                      const SizedBox(height: 14),
                      if (linkMethod == 'PIN') ...[
                        TextFormField(
                          controller: pinCtrl,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Recovery PIN / Supervisor PIN',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'PIN is required' : null,
                        ),
                      ] else ...[
                        if (!isOtpSent) ...[
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: isRequestingOtp
                                  ? null
                                  : () async {
                                      if (codeCtrl.text.trim().isEmpty) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text('Please enter Target Outlet Code first')),
                                        );
                                        return;
                                      }
                                      setDialogState(() => isRequestingOtp = true);

                                      final res = await _transferCtrl.requestLinkOtp(
                                        targetOutletCode: codeCtrl.text.trim(),
                                      );

                                      if (mounted) {
                                        setDialogState(() {
                                          isRequestingOtp = false;
                                          if (res['success'] == true) {
                                            isOtpSent = true;
                                            otpHintMessage = res['message'] ?? 'OTP sent to registered phone/email. Please enter the 6-digit code received.';
                                            otpCtrl.clear();
                                          } else {
                                            otpHintMessage = res['message'] ?? 'Failed to send OTP.';
                                          }
                                        });
                                      }
                                    },
                              icon: isRequestingOtp
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.send),
                              label: const Text('Send Verification OTP'),
                            ),
                          ),
                        ],
                        if (otpHintMessage != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isOtpSent ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isOtpSent ? Colors.green.shade200 : Colors.red.shade200),
                            ),
                            child: Text(
                              otpHintMessage!,
                              style: TextStyle(
                                fontSize: 12,
                                color: isOtpSent ? Colors.green.shade900 : Colors.red.shade900,
                              ),
                            ),
                          ),
                        ],
                        if (isOtpSent) ...[
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: otpCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '6-Digit Verification OTP',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.security),
                            ),
                            validator: (v) => (v == null || v.trim().length < 4) ? 'Enter valid OTP' : null,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton.icon(
                onPressed: isLinking
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        if (linkMethod == 'OTP' && !isOtpSent) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please request OTP first')),
                          );
                          return;
                        }

                        setDialogState(() => isLinking = true);

                        Map<String, dynamic> res;
                        if (linkMethod == 'PIN') {
                          res = await _transferCtrl.linkOutletByPin(
                            targetOutletCode: codeCtrl.text.trim(),
                            pin: pinCtrl.text.trim(),
                            masterOutletId: _currentOutlet?['id'],
                          );
                        } else {
                          res = await _transferCtrl.verifyLinkOtp(
                            targetOutletCode: codeCtrl.text.trim(),
                            otp: otpCtrl.text.trim(),
                            masterOutletId: _currentOutlet?['id'],
                          );
                        }

                        if (mounted) {
                          Navigator.pop(ctx);
                          if (res['success'] == true) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(res['message'] ?? 'Outlet linked successfully!')),
                            );
                            _loadHierarchy();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(res['message'] ?? 'Verification or linking failed.')),
                            );
                          }
                        }
                      },
                icon: isLinking
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.link),
                label: Text(linkMethod == 'PIN' ? 'Verify PIN & Link' : 'Verify OTP & Link'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)), overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isChild = _currentOutlet?['parent_outlet_id'] != null;
    final storeName = (_currentOutlet?['outlet_name'] ?? 'Current Store').toString();
    final storeCode = (_currentOutlet?['outlet_code'] ?? '').toString();
    final roleLabel = isChild ? 'BRANCH' : 'MASTER';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Master & Child Outlet Linking',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Hierarchy',
            onPressed: _loadHierarchy,
          ),
          const SizedBox(width: 4),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF008060),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _showLinkExistingOutletDialog,
              icon: const Icon(Icons.add_link, size: 18),
              label: const Text('Link Outlet', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadHierarchy,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Standard KPI Summary Row (Store / Payroll style)
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth >= 720;
                            final cards = [
                              _buildStatCard(
                                title: 'Current Store Role',
                                value: roleLabel,
                                subtitle: '$storeName${storeCode.isNotEmpty ? ' ($storeCode)' : ''}',
                                icon: Icons.storefront_outlined,
                                color: isChild ? Colors.indigo : const Color(0xFF008060),
                              ),
                              _buildStatCard(
                                title: 'Linked Child Outlets',
                                value: '${_childOutlets.length}',
                                subtitle: _childOutlets.isEmpty ? 'No branches linked yet' : 'Active branch connections',
                                icon: Icons.account_tree_outlined,
                                color: Colors.blue,
                              ),
                              _buildStatCard(
                                title: 'Directory Sharing',
                                value: _shareContactInfo ? 'Enabled' : 'Paused',
                                subtitle: 'Cross-outlet contact visibility',
                                icon: Icons.verified_user_outlined,
                                color: _shareContactInfo ? const Color(0xFF008060) : Colors.orange,
                              ),
                            ];
                            if (isWide) {
                              return Row(
                                children: [
                                  Expanded(child: cards[0]),
                                  const SizedBox(width: 12),
                                  Expanded(child: cards[1]),
                                  const SizedBox(width: 12),
                                  Expanded(child: cards[2]),
                                ],
                              );
                            }
                            return Column(
                              children: [
                                cards[0],
                                const SizedBox(height: 10),
                                cards[1],
                                const SizedBox(height: 10),
                                cards[2],
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // 2. Inter-Outlet Stock Dispatch & Progress Card
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEEF2FF),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.swap_horiz, color: Colors.indigo, size: 22),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Inter-Outlet Stock Dispatch & Progress',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'Transfer inventory between linked outlets and monitor live dispatch status.',
                                          style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      backgroundColor: const Color(0xFF008060),
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const StockDispatchScreen()),
                                    ),
                                    icon: const Icon(Icons.local_shipping_outlined, size: 18),
                                    label: const Text('Dispatch Stock to Child Outlet', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF0F172A),
                                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (_) => const TransferProgressDashboardScreen()),
                                    ),
                                    icon: const Icon(Icons.analytics_outlined, size: 18),
                                    label: const Text('Transfer Progress Dashboard', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // 3. Contact Info Sharing Privacy Toggle Card
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: SwitchListTile(
                            value: _shareContactInfo,
                            activeTrackColor: const Color(0xFF008060),
                            onChanged: (val) async {
                              setState(() => _shareContactInfo = val);
                              final success = await _transferCtrl.toggleContactSharing(val);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      success
                                          ? 'Contact info sharing ${val ? 'enabled' : 'disabled'}!'
                                          : 'Failed to update contact sharing setting',
                                    ),
                                    backgroundColor: success ? const Color(0xFF008060) : Colors.red,
                                  ),
                                );
                              }
                            },
                            secondary: Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: _shareContactInfo ? const Color(0xFFDCFCE7) : const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.contacts_outlined,
                                color: _shareContactInfo ? const Color(0xFF008060) : const Color(0xFF64748B),
                              ),
                            ),
                            title: const Text(
                              'Share Contact Info Across Linked Outlets',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                            ),
                            subtitle: const Text(
                              'Allows linked master and branch outlets to view each other\'s contact phone, email, and store details in dashboard directory.',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 4. Linked Child Outlets Section Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Linked Child Outlets',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    isChild
                                        ? 'Store: $storeName ($storeCode) | Linked under: ${_masterOutlet?['outlet_name'] ?? 'Parent Store'}'
                                        : 'Master Store: $storeName ($storeCode)',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF008060),
                                side: const BorderSide(color: Color(0xFF008060)),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _showLinkExistingOutletDialog,
                              icon: const Icon(Icons.link, size: 18),
                              label: const Text('Link Existing Outlet (PIN / OTP)', style: TextStyle(fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 5. Linked Child Outlets List Card
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: _childOutlets.isEmpty
                              ? Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                                  child: Column(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFF1F5F9),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(Icons.link_off, size: 36, color: Color(0xFF64748B)),
                                      ),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'No Child Outlets Currently Linked',
                                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Click "Link Existing Outlet (PIN / OTP)" to connect branch stores under $storeName.',
                                        style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 16),
                                      FilledButton.icon(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: const Color(0xFF008060),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                        onPressed: _showLinkExistingOutletDialog,
                                        icon: const Icon(Icons.link, size: 18),
                                        label: const Text('Link Outlet (PIN / OTP)', style: TextStyle(fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: _childOutlets.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                                  itemBuilder: (context, index) {
                                    final outlet = _childOutlets[index];
                                    final phone = outlet['contact_phone'] ?? '';
                                    final email = outlet['contact_email'] ?? '';

                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      leading: Container(
                                        padding: const EdgeInsets.all(10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFE0F2FE),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Icon(Icons.store_outlined, color: Color(0xFF0284C7), size: 22),
                                      ),
                                      title: Text(
                                        '${outlet['outlet_name']} (${outlet['outlet_code']})',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 2),
                                          Text(
                                            'Role: CHILD BRANCH OUTLET | Module: ${outlet['business_module'] ?? "ALL"}',
                                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                          ),
                                          if (phone.toString().isNotEmpty || email.toString().isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              'Contact: ${phone.toString().isNotEmpty ? phone : "N/A"} | Email: ${email.toString().isNotEmpty ? email : "N/A"}',
                                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                            ),
                                          ],
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(color: const Color(0xFF86EFAC)),
                                            ),
                                            child: const Text(
                                              'LINKED',
                                              style: TextStyle(color: Color(0xFF15803D), fontWeight: FontWeight.bold, fontSize: 11),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          IconButton(
                                            icon: const Icon(Icons.link_off, color: Colors.red, size: 20),
                                            tooltip: 'Unlink Outlet',
                                            onPressed: () async {
                                              final confirm = await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: const Text('Unlink Outlet'),
                                                  content: Text('Are you sure you want to unlink ${outlet['outlet_name']} (${outlet['outlet_code']})?'),
                                                  actions: [
                                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                                    FilledButton(
                                                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                      onPressed: () => Navigator.pop(ctx, true),
                                                      child: const Text('Unlink'),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirm == true) {
                                                final res = await _transferCtrl.unlinkOutlet(targetOutletId: outlet['id']);
                                                if (mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(content: Text(res['message'] ?? 'Unlinked outlet')),
                                                  );
                                                  _loadHierarchy();
                                                }
                                              }
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
