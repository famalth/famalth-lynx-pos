import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/currency/currency_service.dart';
import '../../core/printing/pos_invoice_printer.dart';
import 'pay_schedule_screen.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({Key? key}) : super(key: key);

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  DateTime _currentMonth = DateTime.now();
  bool _isLoading = false;
  bool _showPreview = false;
  String _runStatus = 'Draft';
  List<Map<String, dynamic>> _previewData = [];
  int? _activeRunId;
  String _selectedOfficeId = 'all';
  String _selectedScheduleOfficeId = 'all';
  String _selectedApprovalsOfficeId = 'all';
  List<Map<String, dynamic>> _offices = [];
  
  // Tab Lists data
  List<Map<String, dynamic>> _revisions = [];
  List<Map<String, dynamic>> _bonuses = [];
  List<Map<String, dynamic>> _payStructures = [];
  List<Map<String, dynamic>> _leaveApprovals = [];
  List<Map<String, dynamic>> _loanApprovals = [];
  List<Map<String, dynamic>> _revisionApprovals = [];
  List<Map<String, dynamic>> _bonusApprovals = [];
  List<Map<String, dynamic>> _payrollHistory = [];
  List<Map<String, dynamic>> _chartData = [];
  Map<String, dynamic> _dashboardKpis = {};
  bool _loadingTab = false;

  // Penalties State
  List<Map<String, dynamic>> _penaltiesList = [];
  List<Map<String, dynamic>> _arrearsList = [];
  List<Map<String, dynamic>> _employeesList = [];

  // Reports Tab State
  int _selectedReportIndex = 0; // 0: Salary Revision, 1: Advances & Loans, 2: Salary Payroll, 3: Leaves, 4: Bonuses & Arrears
  DateTime _reportFromDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _reportToDate = DateTime.now();
  String _reportStatusFilter = 'All'; // All, Pending, Approved, Rejected, Paid
  String _reportSearchQuery = '';
  List<Map<String, dynamic>> _reportData = [];
  bool _loadingReport = false;
  final _tableScrollController = ScrollController();
  List<int> _selectedRowIds = [];
  Map<int, String> _rowPayModes = {};
  String _searchQuery = '';
  String _statusFilter = 'All';

  // Pay Schedule Inline State
  String _calcMethod = 'Actual Days';
  final _fixedDaysCtrl = TextEditingController(text: '26');
  final _workingHoursCtrl = TextEditingController(text: '8.0');
  String _payDateType = 'Last Day';
  int _payDateDay = 1;
  String _firstMonth = '';
  DateTime? _firstPayDate;
  final List<String> _monthsList = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _generateMonthsList();
    _loadTabContent();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _fixedDaysCtrl.dispose();
    _workingHoursCtrl.dispose();
    _tableScrollController.dispose();
    super.dispose();
  }

  void _generateMonthsList() {
    final now = DateTime.now();
    final df = DateFormat('MMMM-yyyy');
    for (int i = -3; i <= 6; i++) {
      final date = DateTime(now.year, now.month + i);
      _monthsList.add(df.format(date));
    }
    _firstMonth = df.format(now);
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      _loadTabContent();
    }
  }

  Future<void> _checkPayrollStatus() async {
    final period = DateFormat('yyyy-MM').format(_currentMonth);
    try {
      final res = await ApiClient.get('/api/hrms/payroll/history?pay_period=$period');
      if (res['success'] == true && res['data'] != null) {
        final List list = res['data'];
        if (list.isNotEmpty) {
          final first = list[0];
          final run = first['payrollRun'] ?? {};
          
          final Map<int, String> modes = {};
          for (final item in list) {
            final id = item['id'];
            if (id != null) {
              final breakdown = item['components_breakdown'] as Map<String, dynamic>?;
              modes[id as int] = breakdown?['payment_method']?.toString() ?? 'Cash';
            }
          }

          setState(() {
            _activeRunId = run['id'];
            _runStatus = run['status'] ?? 'Draft';
            _previewData = List<Map<String, dynamic>>.from(list);
            _rowPayModes = modes;
            _selectedRowIds = [];
            _showPreview = true;
          });
          return;
        }
      }
      setState(() {
        _activeRunId = null;
        _runStatus = 'Draft';
        _showPreview = false;
        _previewData = [];
        _rowPayModes = {};
        _selectedRowIds = [];
      });
    } catch (_) {}
  }

  Future<void> _paySingleEmployee(int detailId, String method) async {
    try {
      final res = await ApiClient.post('/api/hrms/payroll/details/pay', {
        'detail_ids': [detailId],
        'payment_methods': { detailId.toString(): method }
      });
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment processed successfully!'), backgroundColor: Color(0xFF059669)),
        );
        setState(() {
          _selectedRowIds.remove(detailId);
        });
        _checkPayrollStatus();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Payment failed: $e')));
    }
  }

  Future<void> _toggleHoldStatus(int detailId) async {
    try {
      final res = await ApiClient.post('/api/hrms/payroll/details/$detailId/toggle-hold', {});
      if (res['success'] == true) {
        setState(() {
          _selectedRowIds.remove(detailId);
        });
        _checkPayrollStatus();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
    }
  }

  Future<void> _payAllSelected(String method) async {
    if (_selectedRowIds.isEmpty) return;
    try {
      final Map<String, String> methods = {};
      for (final id in _selectedRowIds) {
        methods[id.toString()] = method;
      }
      final res = await ApiClient.post('/api/hrms/payroll/details/pay', {
        'detail_ids': _selectedRowIds,
        'payment_methods': methods
      });
      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selected payments processed!'), backgroundColor: Color(0xFF059669)),
        );
        setState(() {
          _selectedRowIds = [];
        });
        _checkPayrollStatus();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Bulk payment failed: $e')));
    }
  }

  void _showSingleEmployeePaymentDialog(int detailId, String name, String currentStatus, String? paidMethod) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Manage Salary: $name'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Current Status: ${currentStatus.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (paidMethod != null && currentStatus == 'Paid') ...[
                const SizedBox(height: 6),
                Text('Paid via: $paidMethod'),
              ],
              const SizedBox(height: 16),
              if (currentStatus == 'Paid')
                const Text('This salary has already been paid.')
              else if (currentStatus == 'On Hold' || currentStatus == 'Hold')
                const Text('This salary is currently on hold. Release the hold to pay.')
              else
                const Text('Choose a payment method to pay, or place on hold:'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            if (currentStatus == 'Paid') ...[
              // No options
            ] else if (currentStatus == 'On Hold' || currentStatus == 'Hold') ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _toggleHoldStatus(detailId);
                },
                child: const Text('Release Hold', style: TextStyle(color: Colors.white)),
              ),
            ] else ...[
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _toggleHoldStatus(detailId);
                },
                child: const Text('Hold', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _paySingleEmployee(detailId, 'Cash');
                },
                child: const Text('Cash', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _paySingleEmployee(detailId, 'Bank');
                },
                child: const Text('Bank', style: TextStyle(color: Colors.white)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6B21A8)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _paySingleEmployee(detailId, 'Cheque');
                },
                child: const Text('Cheque', style: TextStyle(color: Colors.white)),
              ),
            ]
          ],
        );
      },
    );
  }

  void _showBulkPaymentDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text('Pay Selected (${_selectedRowIds.length} Employees)'),
          content: const Text('Select a payment method to pay all selected employees. Note: Employees on hold will be skipped.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
              onPressed: () {
                Navigator.pop(ctx);
                _payAllSelected('Cash');
              },
              child: const Text('Cash', style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A5F)),
              onPressed: () {
                Navigator.pop(ctx);
                _payAllSelected('Bank');
              },
              child: const Text('Bank', style: TextStyle(color: Colors.white)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6B21A8)),
              onPressed: () {
                Navigator.pop(ctx);
                _payAllSelected('Cheque');
              },
              child: const Text('Cheque', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadTabContent() async {
    setState(() => _loadingTab = true);
    try {
      if (_offices.isEmpty) {
        try {
          final offRes = await ApiClient.get(ApiEndpoints.hrmsOffices);
          if (offRes['success'] == true && offRes['data'] is List) {
            _offices = List<Map<String, dynamic>>.from(offRes['data']);
          }
        } catch (_) {}
      }
      if (_tabController.index == 0) {
        await _checkPayrollStatus();
        final period = DateFormat('yyyy-MM').format(_currentMonth);
        final stats = await ApiClient.get('/api/hrms/payroll/dashboard-stats?pay_period=$period');
        if (stats['success'] == true) {
          setState(() {
            _chartData = List<Map<String, dynamic>>.from(stats['data'] ?? []);
            _dashboardKpis = Map<String, dynamic>.from(stats['kpis'] ?? {});
          });
        }
      } else if (_tabController.index == 1) {
        final res = await ApiClient.get('/api/hrms/payroll/revisions');
        setState(() {
          _revisions = List<Map<String, dynamic>>.from(res['data'] ?? []);
        });
      } else if (_tabController.index == 2) {
        final res = await ApiClient.get('/api/hrms/payroll/bonuses');
        setState(() {
          _bonuses = List<Map<String, dynamic>>.from(res['data'] ?? []);
        });
      } else if (_tabController.index == 3) {
        final res = await ApiClient.get(ApiEndpoints.hrmsPayStructures);
        setState(() {
          _payStructures = List<Map<String, dynamic>>.from(res['data'] ?? []);
        });
      } else if (_tabController.index == 4) {
        final res = await ApiClient.get(ApiEndpoints.hrmsPayrollSettings);
        if (res['success'] == true && res['data'] != null) {
          final data = res['data'] as Map<String, dynamic>;
          setState(() {
            _calcMethod = data['calculation_method'] ?? 'Actual Days';
            _fixedDaysCtrl.text = (data['fixed_working_days'] ?? 26).toString();
            _workingHoursCtrl.text = (data['working_hours_per_day'] ?? 8.0).toString();
            _payDateType = data['pay_date_type'] ?? 'Last Day';
            _payDateDay = data['pay_date_value'] ?? 1;
            final m = data['first_month']?.toString() ?? '';
            if (m.isNotEmpty && _monthsList.contains(m)) {
              _firstMonth = m;
            }
            if (data['first_date'] != null) {
              _firstPayDate = DateTime.tryParse(data['first_date'].toString());
            }
          });
        }
      } else if (_tabController.index == 5) {
        final res = await ApiClient.get('/api/hrms/payroll/approvals');
        final rawBonuses = List<Map<String, dynamic>>.from(res['data']?['bonuses'] ?? []);
        setState(() {
          _leaveApprovals = List<Map<String, dynamic>>.from(res['data']?['leaves'] ?? []);
          _loanApprovals = List<Map<String, dynamic>>.from(res['data']?['loans'] ?? []);
          _revisionApprovals = List<Map<String, dynamic>>.from(res['data']?['revisions'] ?? []);
          // Separate true bonuses from arrears so an arrear is never shown under both bonus and arrear approvals
          _bonusApprovals = rawBonuses.where((b) {
            final r = (b['reason'] ?? '').toString().toLowerCase();
            final t = (b['type'] ?? b['bonus_type'] ?? '').toString().toLowerCase();
            return !r.contains('arrear') && !t.contains('arrear');
          }).toList();
        });
        final pRes = await ApiClient.get('/api/hrms/penalties');
        if (pRes['success'] == true) {
          setState(() {
            _penaltiesList = List<Map<String, dynamic>>.from(pRes['data'] ?? []);
          });
        }
        final bRes = await ApiClient.get('/api/hrms/payroll/bonuses');
        if (bRes['success'] == true) {
          final allBon = List<Map<String, dynamic>>.from(bRes['data'] ?? []);
          setState(() {
            _arrearsList = allBon.where((b) {
              final r = (b['reason'] ?? '').toString().toLowerCase();
              final t = (b['type'] ?? b['bonus_type'] ?? '').toString().toLowerCase();
              return r.contains('arrear') || t.contains('arrear');
            }).toList();
          });
        }
      } else if (_tabController.index == 6) {
        await _fetchReportData();
      }
    } catch (_) {}
    finally {
      setState(() => _loadingTab = false);
    }
  }

  Future<void> _fetchPreviewData({bool showFeedback = false}) async {
    final period = DateFormat('yyyy-MM').format(_currentMonth);
    if (showFeedback && mounted) setState(() => _loadingTab = true);
    try {
      final payload = {
        'pay_period': period,
        if (_selectedOfficeId != 'all') 'office_id': int.tryParse(_selectedOfficeId),
      };
      final res = await ApiClient.post('/api/hrms/payroll/preview', payload);
      if (res['success'] == true && res['data'] != null) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
        if (mounted) {
          setState(() {
            _previewData = list;
            _showPreview = true;
          });
          if (showFeedback) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(list.isEmpty
                    ? 'No active employees found for $period.'
                    : 'Calculated payroll preview for ${list.length} employee(s).'),
                backgroundColor: list.isEmpty ? Colors.orange : const Color(0xFF059669),
              ),
            );
          }
        }
      } else if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Failed to calculate payroll preview.')),
        );
      }
    } catch (e) {
      if (showFeedback && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error calculating preview: $e')),
        );
      }
    } finally {
      if (showFeedback && mounted) setState(() => _loadingTab = false);
    }
  }

  void _previousMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
    });
    _loadTabContent();
  }

  void _nextMonth() {
    setState(() {
      _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
    });
    _loadTabContent();
  }

  Future<void> _printPayrollSummaryReport() async {
    final pdf = await PosInvoicePrinter.createDocument();
    final periodStr = DateFormat('MMMM yyyy').format(_currentMonth);

    final List<List<String>> tableData = [];
    for (final row in _previewData) {
      final emp = row['employee'] ?? {};
      final name = emp['full_name']?.toString() ?? '—';
      final code = emp['employee_code']?.toString() ?? '—';
      
      final days = double.tryParse(row['days_present']?.toString() ?? '0') ?? 0.0;
      final gross = double.tryParse(row['gross_pay']?.toString() ?? '0') ?? 0.0;
      final statutory = double.tryParse(row['statutory_deductions']?.toString() ?? '0') ?? 0.0;
      final totalDeducts = double.tryParse(row['total_deductions']?.toString() ?? '0') ?? 0.0;
      final net = double.tryParse(row['net_pay']?.toString() ?? '0') ?? 0.0;
      
      tableData.add([
        '$name ($code)',
        days.toStringAsFixed(1),
        CurrencyService.format(gross),
        CurrencyService.format(statutory),
        CurrencyService.format(totalDeducts),
        CurrencyService.format(net),
      ]);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (context) => [
          pw.Center(
            child: pw.Column(
              children: [
                pw.Text('PAYROLL SUMMARY & PPF REPORT', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16)),
                pw.SizedBox(height: 4),
                pw.Text('MONTH: ${periodStr.toUpperCase()}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Divider(),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          pw.Table.fromTextArray(
            headers: const ['Employee', 'Salary Days', 'Gross Pay', 'EPF / PF Deduct', 'Total Deductions', 'Net Salary'],
            data: tableData,
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {
              1: pw.Alignment.center,
              2: pw.Alignment.centerRight,
              3: pw.Alignment.centerRight,
              4: pw.Alignment.centerRight,
              5: pw.Alignment.centerRight,
            },
          ),
        ],
      ),
    );

    await Printing.layoutPdf(
      name: 'Payroll_Summary_Report_${DateFormat('yyyy_MM').format(_currentMonth)}',
      onLayout: (format) async => pdf.save(),
    );
  }

  String _monthYearString(DateTime date) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${months[date.month - 1]} ${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Payroll Dashboard', style: TextStyle(color: Color(0xFF1E3A5F), fontWeight: FontWeight.bold, fontSize: 18)),
        iconTheme: const IconThemeData(color: Color(0xFF1E3A5F)),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFE03E2D),
          unselectedLabelColor: const Color(0xFF6B7280),
          indicatorColor: const Color(0xFFE03E2D),
          indicatorWeight: 3,
          isScrollable: true,
          tabs: const [
            Tab(text: 'Pay Run'),
            Tab(text: 'Revisions'),
            Tab(text: 'Bonuses'),
            Tab(text: 'Grades (Pay Structures)'),
            Tab(text: 'Pay Schedule'),
            Tab(text: 'Approvals'),
            Tab(text: 'Reports'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPayRunTab(),
          _buildRevisionsTab(),
          _buildBonusesTab(),
          _buildGradesTab(),
          _buildPayScheduleTab(),
          _buildApprovalsTab(),
          _buildReportsTab(),
        ],
      ),
    );
  }

  Widget _buildPayRunTab() {
    if (_loadingTab) return const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D)));

    double totalGross = 0;
    double totalDeductions = 0;
    double totalNet = 0;
    
    double paidAmt = 0;
    int paidCount = 0;
    double unpaidAmt = 0;
    int unpaidCount = 0;
    double holdAmt = 0;
    int holdCount = 0;

    for (final row in _previewData) {
      totalGross += double.tryParse(row['gross_pay']?.toString() ?? '0') ?? 0;
      totalDeductions += double.tryParse(row['total_deductions']?.toString() ?? '0') ?? 0;
      final net = double.tryParse(row['net_pay']?.toString() ?? '0') ?? 0;
      totalNet += net;

      final breakdown = row['components_breakdown'] as Map<String, dynamic>?;
      final paymentStatus = breakdown?['payment_status']?.toString() ?? 'Unpaid';
      
      if (paymentStatus == 'Paid') {
        paidAmt += net;
        paidCount++;
      } else if (paymentStatus == 'On Hold' || paymentStatus == 'Hold') {
        holdAmt += net;
        holdCount++;
      } else {
        unpaidAmt += net;
        unpaidCount++;
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        _buildPayRunHeader(),
        const SizedBox(height: 16),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: _buildStatsGrid(totalGross, totalDeductions, totalNet, paidAmt, paidCount, unpaidAmt, unpaidCount, holdAmt, holdCount),
        ),
        const SizedBox(height: 16),
        _buildDashboardKpisGrid(),
        const SizedBox(height: 16),
        if (_previewData.isNotEmpty) _buildPreviewTable(),
        _buildPayrollChart(),
      ],
    );
  }

  Widget _buildPayRunHeader() {
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: _previousMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              Text(
                'Process Pay Run for ${_monthYearString(_currentMonth)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: _nextMonth,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              _buildStatusChip(_runStatus),
              const SizedBox(width: 10),
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_city, size: 14, color: Color(0xFF64748B)),
                    const SizedBox(width: 6),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedOfficeId,
                        isDense: true,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.w600),
                        items: [
                          const DropdownMenuItem(value: 'all', child: Text('🏢 All Offices & Branches')),
                          ..._offices.map((o) => DropdownMenuItem(
                                value: o['id'].toString(),
                                child: Text('${o['office_code']} - ${o['office_name']}'),
                              )),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedOfficeId = val;
                              _previewData.clear();
                              _showPreview = false;
                            });
                            _fetchPreviewData();
                            _loadTabContent();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF991B1B),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.gavel_rounded, color: Colors.white, size: 14),
                label: const Text('Apply Penalty / Fine', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _showApplyPenaltyDialog,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 14),
                label: const Text('Add Arrear / Bonus', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: _showAddArrearDialog,
              ),
              if (_runStatus == 'Draft') ...[
                OutlinedButton.icon(
                  icon: const Icon(Icons.analytics_outlined, size: 14),
                  label: const Text('Calculate Preview', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                  onPressed: () {
                    _fetchPreviewData(showFeedback: true);
                  },
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE03E2D),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                  label: const Text('Run Payroll', style: TextStyle(color: Colors.white, fontSize: 12)),
                  onPressed: _previewData.isNotEmpty ? () async {
                    try {
                      await ApiClient.post('/api/hrms/payroll/run', {
                        'pay_period': DateFormat('yyyy-MM').format(_currentMonth),
                        if (_selectedOfficeId != 'all') 'office_id': int.tryParse(_selectedOfficeId),
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payroll processed successfully!'), backgroundColor: Color(0xFF059669)),
                      );
                      await _checkPayrollStatus();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error running payroll: $e')),
                      );
                    }
                  } : null,
                ),
              ],
              if ((_runStatus == 'Draft' || _runStatus == 'Generated') && _activeRunId != null) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 14),
                  label: const Text('Approve & Lock', style: TextStyle(color: Colors.white, fontSize: 12)),
                  onPressed: () async {
                    try {
                      await ApiClient.post('/api/hrms/payroll/$_activeRunId/approve', {});
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Payroll approved and locked!'), backgroundColor: Color(0xFF059669)),
                      );
                      await _checkPayrollStatus();
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error approving payroll: $e')),
                      );
                    }
                  },
                ),
              ],
              if (_runStatus == 'Approved' && _previewData.isNotEmpty) ...[
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E3A5F),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 14),
                  label: const Text('Print Summary / PPF Report', style: TextStyle(color: Colors.white, fontSize: 12)),
                  onPressed: _printPayrollSummaryReport,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid(double gross, double deduct, double net, double paidAmt, int paidCount, double unpaidAmt, int unpaidCount, double holdAmt, int holdCount) {
    final card1 = _buildSummaryCard(
      label: 'GROSS PAY',
      value: CurrencyService.format(gross),
      icon: Icons.account_balance_wallet,
      color: const Color(0xFF1E3A5F),
      iconBgColor: const Color(0xFF1E3A5F),
      cardBgColor: const Color(0xFFEFF6FF),
    );
    final card2 = _buildSummaryCard(
      label: 'TOTAL DEDUCTIONS',
      value: CurrencyService.format(deduct),
      icon: Icons.money_off,
      color: const Color(0xFFDC2626),
      iconBgColor: const Color(0xFFDC2626),
      cardBgColor: const Color(0xFFFEF2F2),
    );
    final card3 = _buildSummaryCard(
      label: 'NET PAY',
      value: CurrencyService.format(net),
      icon: Icons.payments,
      color: const Color(0xFF059669),
      iconBgColor: const Color(0xFF059669),
      cardBgColor: const Color(0xFFECFDF5),
    );
    final card4 = _buildSummaryCard(
      label: 'PAID SALARY',
      value: '${CurrencyService.format(paidAmt)} ($paidCount)',
      icon: Icons.check_circle,
      color: const Color(0xFF047857),
      iconBgColor: const Color(0xFF059669),
      cardBgColor: const Color(0xFFD1FAE5),
    );
    final card5 = _buildSummaryCard(
      label: 'UNPAID SALARY',
      value: '${CurrencyService.format(unpaidAmt)} ($unpaidCount)',
      icon: Icons.pending_actions,
      color: const Color(0xFFB91C1C),
      iconBgColor: const Color(0xFFDC2626),
      cardBgColor: const Color(0xFFFEE2E2),
    );
    final card6 = _buildSummaryCard(
      label: 'ON HOLD SALARY',
      value: '${CurrencyService.format(holdAmt)} ($holdCount)',
      icon: Icons.pause_circle,
      color: const Color(0xFFB45309),
      iconBgColor: const Color(0xFFD97706),
      cardBgColor: const Color(0xFFFEF3C7),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 950) {
          // Large Screen: 6 cards in a single row
          return SizedBox(
            height: 60,
            child: Row(
              children: [
                Expanded(child: card1),
                const SizedBox(width: 8),
                Expanded(child: card2),
                const SizedBox(width: 8),
                Expanded(child: card3),
                const SizedBox(width: 8),
                Expanded(child: card4),
                const SizedBox(width: 8),
                Expanded(child: card5),
                const SizedBox(width: 8),
                Expanded(child: card6),
              ],
            ),
          );
        } else if (constraints.maxWidth >= 650) {
          // Medium Screen: 2 rows of 3 columns
          return Column(
            children: [
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Expanded(child: card1),
                    const SizedBox(width: 8),
                    Expanded(child: card2),
                    const SizedBox(width: 8),
                    Expanded(child: card3),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Expanded(child: card4),
                    const SizedBox(width: 8),
                    Expanded(child: card5),
                    const SizedBox(width: 8),
                    Expanded(child: card6),
                  ],
                ),
              ),
            ],
          );
        } else {
          // Small Screen: 3 rows of 2 columns
          return Column(
            children: [
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Expanded(child: card1),
                    const SizedBox(width: 8),
                    Expanded(child: card2),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Expanded(child: card3),
                    const SizedBox(width: 8),
                    Expanded(child: card4),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 60,
                child: Row(
                  children: [
                    Expanded(child: card5),
                    const SizedBox(width: 8),
                    Expanded(child: card6),
                  ],
                ),
              ),
            ],
          );
        }
      },
    );
  }

  Widget _buildSummaryCard({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required Color iconBgColor,
    required Color cardBgColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.012),
            blurRadius: 3,
            offset: const Offset(0, 1),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: iconBgColor,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w600, color: Color(0xFF6B7280), letterSpacing: 0.3),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  value,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  double _getBreakdownValue(Map<String, dynamic>? breakdown, List<String> synonyms) {
    if (breakdown == null) return 0.0;
    for (final key in breakdown.keys) {
      final lowerKey = key.toLowerCase();
      for (final syn in synonyms) {
        if (lowerKey == syn.toLowerCase() || lowerKey.contains(syn.toLowerCase())) {
          return double.tryParse(breakdown[key]?.toString() ?? '0') ?? 0.0;
        }
      }
    }
    return 0.0;
  }

  Widget _buildPreviewTable() {
    final filteredData = _previewData.where((row) {
      final name = (row['employee_name']?.toString() ?? row['employee']?['full_name']?.toString() ?? '').toLowerCase();
      final code = (row['employee_code']?.toString() ?? row['employee']?['employee_code']?.toString() ?? '').toLowerCase();
      final query = _searchQuery.toLowerCase();
      final matchesSearch = query.isEmpty || name.contains(query) || code.contains(query);
      
      final breakdown = row['components_breakdown'] as Map<String, dynamic>?;
      final paymentStatus = breakdown?['payment_status']?.toString() ?? 'Unpaid';
      
      final matchesFilter = _statusFilter == 'All' ||
          (_statusFilter == 'Paid' && paymentStatus == 'Paid') ||
          (_statusFilter == 'Unpaid' && paymentStatus == 'Unpaid') ||
          (_statusFilter == 'On Hold' && (paymentStatus == 'On Hold' || paymentStatus == 'Hold'));
          
      return matchesSearch && matchesFilter;
    }).toList();

    return _card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1E3A5F),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(8), topRight: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Text('Payroll Summary Ledger', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                const Spacer(),
                Row(
                  children: [
                    _legendDot(Colors.green),
                    const SizedBox(width: 4),
                    const Text('Paid', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 12),
                    _legendDot(Colors.red),
                    const SizedBox(width: 4),
                    const Text('Unpaid', style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 12),
                    _legendDot(Colors.amber),
                    const SizedBox(width: 4),
                    const Text('On Hold', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                )
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search employee name or code...',
                      prefixIcon: Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: ['All', 'Paid', 'Unpaid', 'On Hold'].map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _statusFilter = val;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_activeRunId != null) ...[
            Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  Checkbox(
                    value: _selectedRowIds.length == filteredData.length && filteredData.isNotEmpty,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedRowIds = filteredData.map<int>((r) => r['id'] as int).toList();
                        } else {
                          _selectedRowIds = [];
                        }
                      });
                    },
                  ),
                  Text(
                    '${_selectedRowIds.length} of ${filteredData.length} selected',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                    icon: const Icon(Icons.payment, color: Colors.white, size: 16),
                    label: const Text('Pay Selected', style: TextStyle(color: Colors.white)),
                    onPressed: _selectedRowIds.isEmpty ? null : _showBulkPaymentDialog,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Scrollbar(
            controller: _tableScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            child: SingleChildScrollView(
              controller: _tableScrollController,
              scrollDirection: Axis.horizontal,
              child: Builder(builder: (context) {
                // Dynamically extract earning & deduction component columns from components_breakdown
                final Set<String> dynamicEarningNames = {};
                final Set<String> dynamicDeductionNames = {};
                for (final r in filteredData) {
                  final bd = r['components_breakdown'] as Map<String, dynamic>?;
                  if (bd != null) {
                    bd.forEach((k, v) {
                      if (k == 'attendance_analytics' || k == 'payment_status' || k == 'payment_method') return;
                      final kLower = k.toLowerCase().trim();
                      // Exclude components that already have dedicated columns to prevent duplicate columns
                      if (kLower.contains('loan') ||
                          kLower.contains('penalt') ||
                          kLower.contains('shortage') ||
                          kLower.contains('fine') ||
                          kLower.contains('arrear') ||
                          kLower.contains('commission') ||
                          kLower.contains('bonus') ||
                          kLower.contains('basic')) {
                        return;
                      }
                      final isDeduct = kLower.contains('deduct') || kLower.contains('pf') || kLower.contains('esi') || 
                          kLower.contains('tds') || kLower.contains('tcs') || kLower.contains('tax') || 
                          kLower.contains('loss') || kLower.contains('provident');
                      if (isDeduct) {
                        dynamicDeductionNames.add(k);
                      } else {
                        dynamicEarningNames.add(k);
                      }
                    });
                  }
                }
                if (dynamicEarningNames.isEmpty) dynamicEarningNames.addAll(['HRA', 'DA']);
                final sortedEarnings = dynamicEarningNames.toList()..sort();
                final sortedDeductions = dynamicDeductionNames.toList()..sort();

                final tableCols = [
                  if (_activeRunId != null)
                    DataColumn(
                      label: Checkbox(
                        value: _selectedRowIds.length == filteredData.length && filteredData.isNotEmpty,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedRowIds = filteredData.map<int>((r) => r['id'] as int).toList();
                            } else {
                              _selectedRowIds = [];
                            }
                          });
                        },
                      ),
                    ),
                  const DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Basic Earning', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  ...sortedEarnings.map((c) => DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))))),
                  const DataColumn(label: Text('Arrears', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Commission', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Bonus', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Loan EMI', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Penalties/Shortage', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  ...sortedDeductions.map((c) => DataColumn(label: Text(c, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))))),
                  const DataColumn(label: Text('Total Deductions', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Paid Days', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Work Hours', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Overtime Hours', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Overtime Add.', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Less Hours', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Less Hours Ded.', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Late Mins', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Leaves', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Unpaid Leaves', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Unpaid Leave Ded.', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Absents', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Req. Hours', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Done Hours', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Absent Ded.', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Weekdays', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Holidays', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  const DataColumn(label: Text('Net Pay', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                  if (_activeRunId != null)
                    const DataColumn(label: Text('Action', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)))),
                ];

                return DataTable(
                  headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 52,
                  columns: tableCols,
                  rows: filteredData.map((row) {
                  final rowId = row['id'] as int? ?? 0;
                  final name = row['employee_name']?.toString() ?? row['employee']?['full_name']?.toString() ?? '—';
                  final code = row['employee_code']?.toString() ?? row['employee']?['employee_code']?.toString() ?? '—';
                  
                  final breakdown = row['components_breakdown'] as Map<String, dynamic>?;
                  final basicVal = double.tryParse(row['prorated_salary']?.toString() ?? '0') ?? 0.0;
                  final arrears = double.tryParse(row['arrears']?.toString() ?? breakdown?['Arrear']?.toString() ?? breakdown?['arrears']?.toString() ?? '0') ?? 0.0;
                  final commission = double.tryParse(row['commissions']?.toString() ?? row['sales_commission']?.toString() ?? breakdown?['Commission']?.toString() ?? breakdown?['sales_commission']?.toString() ?? '0') ?? 0.0;
                  
                  final loan = double.tryParse(row['loan_deduction']?.toString() ?? row['loan_emi']?.toString() ?? '0') ?? 0.0;
                  final penalties = double.tryParse(row['penalty_deduction']?.toString() ?? row['shortage_penalties']?.toString() ?? '0') ?? 0.0;
                  final emiPenalties = loan + penalties;
                  
                  final bonus = double.tryParse(row['bonuses']?.toString() ?? breakdown?['Bonus']?.toString() ?? breakdown?['bonuses']?.toString() ?? '0') ?? 0.0;
                  final statutoryDeductions = double.tryParse(row['statutory_deductions']?.toString() ?? '0') ?? 0.0;
                  final net = double.tryParse(row['net_pay']?.toString() ?? '0') ?? 0.0;
                  
                  final paidDays = double.tryParse(row['salary_days']?.toString() ?? '0') ?? 0.0;
                  final hra = _getBreakdownValue(breakdown, ['hra', 'house', 'rent', 'ha']);
                  final da = _getBreakdownValue(breakdown, ['da', 'dearness']);
                  final tcs = _getBreakdownValue(breakdown, ['tcs']);
                  final tds = _getBreakdownValue(breakdown, ['tds']);
                  final epf = _getBreakdownValue(breakdown, ['epf', 'pf', 'provident']);
                  final esi = _getBreakdownValue(breakdown, ['esi']);

                  final analytics = row['components_breakdown']?['attendance_analytics'] ?? row;
                  final workHours = double.tryParse(analytics['total_working_hours']?.toString() ?? '0') ?? 0.0;
                  final otHours = double.tryParse(analytics['total_overtime_hours']?.toString() ?? '0') ?? 0.0;
                  final lateMins = int.tryParse(analytics['total_late_mins']?.toString() ?? '0') ?? 0;
                  final leaves = double.tryParse(row['on_leave']?.toString() ?? row['days_on_leave']?.toString() ?? '0') ?? 0.0;
                  final absent = double.tryParse(row['absent']?.toString() ?? row['days_absent']?.toString() ?? '0') ?? 0.0;
                  
                  final reqHours = double.tryParse(analytics['required_hours']?.toString() ?? '0') ?? 0.0;
                  final doneHours = double.tryParse(analytics['completed_hours']?.toString() ?? '0') ?? 0.0;
                  final otAdd = double.tryParse(analytics['overtime_addition_amount']?.toString() ?? '0') ?? 0.0;
                  final absentDed = double.tryParse(analytics['absent_deduction_amount']?.toString() ?? '0') ?? 0.0;
                  
                  final weekdays = int.tryParse(analytics['weekdays_count']?.toString() ?? '0') ?? 0;
                  final holidays = int.tryParse(analytics['holidays_count']?.toString() ?? '0') ?? 0;

                  final lessHours = double.tryParse(analytics['total_less_hours']?.toString() ?? '0') ?? 0.0;
                  final lessHoursDed = double.tryParse(analytics['less_hours_debit_amount']?.toString() ?? '0') ?? 0.0;

                  final unpaidLeaves = double.tryParse(row['unpaid_leave']?.toString() ?? analytics['unpaid_leave_count']?.toString() ?? '0') ?? 0.0;
                  final unpaidLeaveDed = double.tryParse(row['unpaid_leave_deduction_amount']?.toString() ?? analytics['unpaid_leave_deduction_amount']?.toString() ?? '0') ?? 0.0;

                  final rawTotalDed = double.tryParse(row['total_deductions']?.toString() ?? '');
                  final totalDeductionsVal = (rawTotalDed != null && rawTotalDed > 0)
                      ? rawTotalDed
                      : (loan + penalties + statutoryDeductions + lessHoursDed + unpaidLeaveDed);

                  final paymentStatus = breakdown?['payment_status']?.toString() ?? 'Unpaid';
                  
                  Color dotColor = Colors.red;
                  if (paymentStatus == 'Paid') dotColor = Colors.green;
                  if (paymentStatus == 'On Hold' || paymentStatus == 'Hold') dotColor = Colors.amber;
  
                  final rowCells = <DataCell>[
                    if (_activeRunId != null)
                      DataCell(
                        Checkbox(
                          value: _selectedRowIds.contains(rowId),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                _selectedRowIds.add(rowId);
                              } else {
                                _selectedRowIds.remove(rowId);
                              }
                            });
                          },
                        ),
                      ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Text('$name ($code)', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    DataCell(Text(CurrencyService.format(basicVal))),
                    ...sortedEarnings.map((c) {
                      final val = double.tryParse(breakdown?[c]?.toString() ?? '0') ?? 0.0;
                      return DataCell(Text(CurrencyService.format(val)));
                    }),
                    DataCell(Text(CurrencyService.format(arrears), style: const TextStyle(color: Color(0xFF059669)))),
                    DataCell(Text(CurrencyService.format(commission), style: const TextStyle(color: Color(0xFF059669)))),
                    DataCell(Text(CurrencyService.format(bonus), style: const TextStyle(color: Color(0xFF059669)))),
                    DataCell(Text(CurrencyService.format(loan), style: const TextStyle(color: Color(0xFFDC2626)))),
                    DataCell(Text(CurrencyService.format(penalties), style: const TextStyle(color: Color(0xFFDC2626)))),
                    ...sortedDeductions.map((c) {
                      final val = double.tryParse(breakdown?[c]?.toString() ?? '0') ?? 0.0;
                      return DataCell(Text(CurrencyService.format(val), style: const TextStyle(color: Color(0xFFDC2626))));
                    }),
                    DataCell(Text(CurrencyService.format(totalDeductionsVal), style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold))),
                    DataCell(Text(paidDays.toStringAsFixed(1))),
                    DataCell(Text('${workHours.toStringAsFixed(1)} hrs')),
                    DataCell(Text('${otHours.toStringAsFixed(1)} hrs')),
                    DataCell(Text(CurrencyService.format(otAdd), style: const TextStyle(color: Color(0xFF059669)))),
                    DataCell(Text('${lessHours.toStringAsFixed(1)} hrs')),
                    DataCell(Text(CurrencyService.format(lessHoursDed), style: const TextStyle(color: Color(0xFFDC2626)))),
                    DataCell(Text('$lateMins mins')),
                    DataCell(Text(leaves.toStringAsFixed(1))),
                    DataCell(Text(unpaidLeaves.toStringAsFixed(1))),
                    DataCell(Text(CurrencyService.format(unpaidLeaveDed), style: const TextStyle(color: Color(0xFFDC2626)))),
                    DataCell(Text(absent.toStringAsFixed(1))),
                    DataCell(Text('${reqHours.toStringAsFixed(1)} hrs')),
                    DataCell(Text('${doneHours.toStringAsFixed(1)} hrs')),
                    DataCell(Text(CurrencyService.format(absentDed))),
                    DataCell(Text('$weekdays')),
                    DataCell(Text('$holidays')),
                    DataCell(Text(CurrencyService.format(net), style: TextStyle(fontWeight: FontWeight.bold, color: net < 0 ? const Color(0xFFDC2626) : const Color(0xFF059669)))),
                    if (_activeRunId != null)
                      DataCell(
                        ElevatedButton(
                          onPressed: () => _showSingleEmployeePaymentDialog(
                            rowId,
                            name,
                            paymentStatus,
                            breakdown?['payment_method']?.toString(),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: paymentStatus == 'Paid' ? Colors.grey : const Color(0xFF059669),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          child: Text(
                            paymentStatus == 'Paid' ? 'Details' : 'Pay',
                            style: const TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ),
                  ];

                  while (rowCells.length < tableCols.length) {
                    rowCells.add(const DataCell(Text('—')));
                  }
                  if (rowCells.length > tableCols.length) {
                    rowCells.removeRange(tableCols.length, rowCells.length);
                  }

                  return DataRow(cells: rowCells);
                }).toList(),
              );
            }),
          ),
        ),
      ],
    ),
  );
}

  Widget _legendDot(Color color) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }

  Widget _buildPayrollChart() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('COST TREND CHART', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Color(0xFF9CA3AF), fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          SizedBox(
            height: 220,
            width: double.infinity,
            child: _chartData.isEmpty
                ? const Center(
                    child: Text(
                      'No approved payroll data found for cost trend chart.',
                      style: TextStyle(color: Color(0xFF6B7280), fontSize: 12),
                    ),
                  )
                : SfCartesianChart(
                    legend: const Legend(isVisible: true, position: LegendPosition.bottom),
                    tooltipBehavior: TooltipBehavior(enable: true),
                    primaryXAxis: const CategoryAxis(
                      majorGridLines: MajorGridLines(width: 0),
                    ),
                    primaryYAxis: NumericAxis(
                      numberFormat: CurrencyService.compactCurrencyFormat,
                      majorGridLines: const MajorGridLines(width: 0.5, color: Color(0xFFE5E7EB)),
                    ),
                    series: <CartesianSeries>[
                      ColumnSeries<Map<String, dynamic>, String>(
                        name: 'Gross Pay',
                        dataSource: _chartData,
                        xValueMapper: (d, _) {
                          final periodStr = d['pay_period']?.toString() ?? '';
                          try {
                            final parsed = DateFormat('yyyy-MM').parse(periodStr);
                            return DateFormat('MMM yy').format(parsed);
                          } catch (_) {
                            return periodStr;
                          }
                        },
                        yValueMapper: (d, _) => double.tryParse(d['total_gross']?.toString() ?? '0') ?? 0.0,
                        color: const Color(0xFF1E3A5F),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                      ),
                      ColumnSeries<Map<String, dynamic>, String>(
                        name: 'Net Pay',
                        dataSource: _chartData,
                        xValueMapper: (d, _) {
                          final periodStr = d['pay_period']?.toString() ?? '';
                          try {
                            final parsed = DateFormat('yyyy-MM').parse(periodStr);
                            return DateFormat('MMM yy').format(parsed);
                          } catch (_) {
                            return periodStr;
                          }
                        },
                        yValueMapper: (d, _) => double.tryParse(d['total_net']?.toString() ?? '0') ?? 0.0,
                        color: const Color(0xFF059669),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                      ),
                      ColumnSeries<Map<String, dynamic>, String>(
                        name: 'Deductions',
                        dataSource: _chartData,
                        xValueMapper: (d, _) {
                          final periodStr = d['pay_period']?.toString() ?? '';
                          try {
                            final parsed = DateFormat('yyyy-MM').parse(periodStr);
                            return DateFormat('MMM yy').format(parsed);
                          } catch (_) {
                            return periodStr;
                          }
                        },
                        yValueMapper: (d, _) => double.tryParse(d['total_deductions']?.toString() ?? '0') ?? 0.0,
                        color: const Color(0xFFDC2626),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 2: REVISIONS =================
  Widget _buildRevisionsTab() {
    if (_loadingTab) return const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D)));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Salary Increment Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E3A5F))),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, color: Colors.white, size: 16),
                label: const Text('Bulk Revision', style: TextStyle(color: Colors.white)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE03E2D)),
                onPressed: _showBulkRevisionDialog,
              ),
            ],
          ),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
              columns: const [
                DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Previous Salary', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('New Salary', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Revision Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _revisions.map((rev) {
                final emp = rev['employee'] ?? {};
                final name = emp['full_name']?.toString() ?? '—';
                final prev = double.tryParse(rev['previous_salary']?.toString() ?? '0') ?? 0;
                final next = double.tryParse(rev['new_salary']?.toString() ?? '0') ?? 0;
                final date = rev['effective_date']?.toString() ?? '—';
                final status = rev['status']?.toString() ?? 'Approved';

                return DataRow(cells: [
                  DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(CurrencyService.format(prev))),
                  DataCell(Text(CurrencyService.format(next), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)))),
                  DataCell(Text(date)),
                  DataCell(_buildStatusChip(status)),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ================= TAB 3: BONUSES =================
  Widget _buildBonusesTab() {
    if (_loadingTab) return const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D)));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Company Bonuses & Rewards', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E3A5F))),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white, size: 16),
                    label: const Text('Add Arrear / Bonus', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                    onPressed: _showAddArrearDialog,
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.group_add_outlined, size: 16),
                    label: const Text('Bulk Bonus Payout'),
                    onPressed: _showBulkBonusDialog,
                  ),
                ],
              ),
            ],
          ),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
              columns: const [
                DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Type', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Payout Month', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _bonuses.map((bon) {
                final emp = bon['employee'] ?? {};
                final name = emp['full_name']?.toString() ?? '—';
                final itemType = bon['type']?.toString() ?? bon['bonus_type']?.toString() ?? 'Bonus';
                final amt = double.tryParse(bon['amount']?.toString() ?? '0') ?? 0;
                final reason = bon['reason']?.toString() ?? '—';
                final isInstant = reason.toLowerCase().contains('(instant)') || bon['payment_mode'] == 'Instant';
                final month = bon['payment_month']?.toString() ?? '—';
                final status = bon['status']?.toString() ?? 'Pending';

                return DataRow(cells: [
                  DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: itemType == 'Arrear' ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: itemType == 'Arrear' ? const Color(0xFF93C5FD) : const Color(0xFFA7F3D0)),
                    ),
                    child: Text(
                      itemType,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: itemType == 'Arrear' ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
                      ),
                    ),
                  )),
                  DataCell(Text(CurrencyService.format(amt), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)))),
                  DataCell(Text(reason)),
                  DataCell(Text(month)),
                  DataCell(_buildStatusChip(status, type: itemType.toLowerCase(), isInstant: isInstant)),
                ]);
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  // ================= TAB 4: GRADES (PAY STRUCTURES) =================
  Widget _buildGradesTab() {
    if (_loadingTab) return const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D)));

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Employee Grade Scales (Pay Structures)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E3A5F))),
            ],
          ),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: Column(
            children: _payStructures.map((structure) {
              final name = structure['name']?.toString() ?? '—';
              final desc = structure['description']?.toString() ?? 'Custom Scale';
              final active = structure['is_active'] == true;

              return ListTile(
                onTap: () => _showGradeSummaryDialog(structure),
                leading: CircleAvatar(
                  backgroundColor: active ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
                  child: Icon(Icons.layers_outlined, color: active ? const Color(0xFF059669) : const Color(0xFF6B7280)),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(desc),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: active ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(active ? 'ACTIVE' : 'INACTIVE', style: TextStyle(color: active ? const Color(0xFF059669) : const Color(0xFFDC2626), fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  void _showGradeSummaryDialog(Map<String, dynamic> structure) {
    final name = structure['name']?.toString() ?? '—';
    final desc = structure['description']?.toString() ?? 'Custom Scale';
    final components = List<Map<String, dynamic>>.from(structure['components'] ?? []);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.normal)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Linked Salary Components:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A5F))),
              const SizedBox(height: 8),
              if (components.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('No salary components linked to this grade.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: components.length,
                    separatorBuilder: (c, i) => const Divider(),
                    itemBuilder: (c, i) {
                      final comp = components[i];
                      final cName = comp['name']?.toString() ?? '—';
                      final cNature = comp['nature']?.toString() ?? 'Earning';
                      final cType = comp['type']?.toString() ?? 'Fixed';
                      final isEarning = cNature.toLowerCase() == 'earning';

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(cName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                Text('$cType Component', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isEarning ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                cNature.toUpperCase(),
                                style: TextStyle(
                                  color: isEarning ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Color(0xFFE03E2D), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ================= TAB 5: PAY SCHEDULE =================
  Widget _buildOfficeScheduleBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.location_city_rounded, color: Color(0xFF2563EB), size: 20),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Schedule Office Scope:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF6B7280))),
              Text('Branch-Wise or Company-Wide Schedule', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedScheduleOfficeId,
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('🏢 All Offices (Consolidated Default)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  ..._offices.map((o) => DropdownMenuItem(
                    value: o['id'].toString(),
                    child: Text('🏢 ${o['office_code']} - ${o['office_name']}', style: const TextStyle(fontSize: 12)),
                  )),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedScheduleOfficeId = v);
                    _loadTabContent();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayScheduleTab() {
    if (_loadingTab) return const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D)));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOfficeScheduleBar(),
        _payScheduleCard(
          title: 'Salary Calculation Method',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select how monthly salary should be calculated.*',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
              const SizedBox(height: 12),
              RadioListTile<String>(
                title: const Text('Actual days in a month', style: TextStyle(fontSize: 14)),
                value: 'Actual Days',
                groupValue: _calcMethod,
                activeColor: const Color(0xFFE03E2D),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _calcMethod = v!),
              ),
              RadioListTile<String>(
                title: const Text('Based on fixed working days per month', style: TextStyle(fontSize: 14)),
                value: 'Fixed Days',
                groupValue: _calcMethod,
                activeColor: const Color(0xFFE03E2D),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _calcMethod = v!),
              ),
              if (_calcMethod == 'Fixed Days') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _fixedDaysCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _inputDecor('Working Days in Month', Icons.calendar_today_outlined),
                ),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _workingHoursCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: _inputDecor('Required Working Hours per Day', Icons.access_time),
              ),
            ],
          ),
        ),
        _payScheduleCard(
          title: 'Pay Date',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Select when employees should be paid.*',
                  style: TextStyle(color: Color(0xFF6B7280), fontSize: 13)),
              const SizedBox(height: 12),
              RadioListTile<String>(
                title: const Text('On the last day of every month', style: TextStyle(fontSize: 14)),
                value: 'Last Day',
                groupValue: _payDateType,
                activeColor: const Color(0xFFE03E2D),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _payDateType = v!),
              ),
              RadioListTile<String>(
                title: Row(
                  children: [
                    const Text('On Day ', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    DropdownButton<int>(
                      value: _payDateDay,
                      onChanged: _payDateType == 'Day X'
                          ? (v) => setState(() => _payDateDay = v!)
                          : null,
                      items: List.generate(31, (i) => i + 1)
                          .map((d) => DropdownMenuItem<int>(
                                value: d,
                                child: Text(d.toString()),
                              ))
                          .toList(),
                    ),
                    const SizedBox(width: 6),
                    const Text(' of every month', style: TextStyle(fontSize: 14)),
                  ],
                ),
                value: 'Day X',
                groupValue: _payDateType,
                activeColor: const Color(0xFFE03E2D),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _payDateType = v!),
              ),
            ],
          ),
        ),
        _payScheduleCard(
          title: 'First Payroll Setup',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Start your first payroll from*', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                value: _firstMonth,
                items: _monthsList
                    .map((m) => DropdownMenuItem<String>(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) => setState(() => _firstMonth = v!),
                decoration: _dropdownDecor(),
              ),
              const SizedBox(height: 16),
              const Text('Select a pay date for your first payroll*', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
              const SizedBox(height: 6),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _firstPayDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) setState(() => _firstPayDate = picked);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _firstPayDate != null
                            ? DateFormat('dd/MM/yyyy').format(_firstPayDate!)
                            : 'Select Date',
                        style: TextStyle(
                          fontSize: 13,
                          color: _firstPayDate != null ? const Color(0xFF1F2937) : const Color(0xFF9CA3AF),
                        ),
                      ),
                      const Icon(Icons.calendar_today_outlined, size: 16, color: Color(0xFF9CA3AF)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.save_outlined, color: Colors.white, size: 16),
              label: const Text('Save Schedule Settings', style: TextStyle(color: Colors.white)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE03E2D),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: () async {
                try {
                  final payload = {
                    'calculation_method': _calcMethod,
                    'fixed_working_days': int.tryParse(_fixedDaysCtrl.text) ?? 26,
                    'working_hours_per_day': double.tryParse(_workingHoursCtrl.text) ?? 8.0,
                    'pay_date_type': _payDateType,
                    'pay_date_value': _payDateDay,
                    'first_month': _firstMonth,
                    'first_date': _firstPayDate != null ? DateFormat('yyyy-MM-dd').format(_firstPayDate!) : null,
                  };
                  await ApiClient.post(ApiEndpoints.hrmsPayrollSettings, payload);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pay schedule settings saved!'), backgroundColor: Color(0xFF059669)),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
            ),
          ],
        ),
      ],
    );
  }

  // ================= TAB 6: APPROVALS =================
  Widget _buildApprovalsOfficeFilterBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_outlined, color: Color(0xFF6B7280), size: 18),
          const SizedBox(width: 8),
          const Text('Filter Approvals by Office:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF374151))),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedApprovalsOfficeId,
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('🏢 All Offices & Branches', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  ..._offices.map((o) => DropdownMenuItem(
                    value: o['id'].toString(),
                    child: Text('🏢 ${o['office_code']} - ${o['office_name']}', style: const TextStyle(fontSize: 12)),
                  )),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedApprovalsOfficeId = v);
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApprovalsTab() {
    if (_loadingTab) return const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D)));

    final filteredLeaves = _leaveApprovals.where((a) {
      if (_selectedApprovalsOfficeId == 'all') return true;
      final emp = a['employee'];
      return emp != null && emp['office_id']?.toString() == _selectedApprovalsOfficeId;
    }).toList();

    final filteredLoans = _loanApprovals.where((a) {
      if (_selectedApprovalsOfficeId == 'all') return true;
      final emp = a['employee'];
      return emp != null && emp['office_id']?.toString() == _selectedApprovalsOfficeId;
    }).toList();

    final filteredRevisions = _revisionApprovals.where((a) {
      if (_selectedApprovalsOfficeId == 'all') return true;
      final emp = a['employee'];
      return emp != null && emp['office_id']?.toString() == _selectedApprovalsOfficeId;
    }).toList();

    final filteredBonuses = _bonusApprovals.where((a) {
      if (_selectedApprovalsOfficeId == 'all') return true;
      final emp = a['employee'];
      return emp != null && emp['office_id']?.toString() == _selectedApprovalsOfficeId;
    }).toList();

    final filteredArrears = _arrearsList.where((a) {
      if (_selectedApprovalsOfficeId == 'all') return true;
      final emp = a['employee'];
      return emp == null || emp['office_id']?.toString() == _selectedApprovalsOfficeId;
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        _buildApprovalsOfficeFilterBar(),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Leave Applications Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
              columns: const [
                DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Leave Type', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Duration', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: filteredLeaves.map((app) {
                final emp = app['employee'] ?? {};
                final name = emp['full_name']?.toString() ?? '—';
                final lt = app['leaveType'] ?? {};
                final type = lt['name']?.toString() ?? 'Leave';
                final days = app['total_days']?.toString() ?? '0';
                final status = app['status']?.toString() ?? 'Pending';
                final isPending = status.toLowerCase() == 'pending' || status.toLowerCase() == 'pending approval';

                return DataRow(cells: [
                  DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                  DataCell(Text(type)),
                  DataCell(Text('$days Day(s)')),
                  DataCell(_buildStatusChip(status)),
                  DataCell(
                    isPending
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 20),
                                onPressed: () => _approveLeave(app['id'] as int),
                                tooltip: 'Approve Leave',
                              ),
                              IconButton(
                                icon: const Icon(Icons.highlight_off, color: Color(0xFFDC2626), size: 20),
                                onPressed: () => _rejectLeave(app['id'] as int),
                                tooltip: 'Reject Leave',
                              ),
                            ],
                          )
                        : Text(
                            status.toLowerCase() == 'approved' ? 'Approved' : '—',
                            style: TextStyle(
                              fontSize: 12,
                              color: status.toLowerCase() == 'approved' ? const Color(0xFF059669) : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                  ),
                ]);
              }).toList(),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Advances & Loans Log', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: filteredLoans.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No advance or loan requests found.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                    columns: const [
                      DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Remaining Balance', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: filteredLoans.map((loan) {
                      final emp = loan['employee'] ?? {};
                      final name = emp['full_name']?.toString() ?? 'Employee #${loan['employee_id']}';
                      final amt = double.tryParse(loan['loan_amount']?.toString() ?? '0') ?? 0;
                      final bal = double.tryParse(loan['remaining_balance']?.toString() ?? '0') ?? 0;
                      final rawStatus = loan['status']?.toString() ?? 'Pending';
                      final isPending = rawStatus.toLowerCase() == 'pending' || rawStatus.toLowerCase() == 'pending approval' || rawStatus.toLowerCase() == 'pending_approval';

                      return DataRow(cells: [
                        DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(CurrencyService.format(amt))),
                        DataCell(Text(CurrencyService.format(bal))),
                        DataCell(_buildStatusChip(rawStatus)),
                        DataCell(
                          isPending
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 20),
                                      onPressed: () => _approveLoan(loan['id'] as int),
                                      tooltip: 'Approve & Mark Paid',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.highlight_off, color: Color(0xFFDC2626), size: 20),
                                      onPressed: () => _rejectLoan(loan['id'] as int),
                                      tooltip: 'Reject Loan',
                                    ),
                                  ],
                                )
                              : Text(
                                  rawStatus.toLowerCase() == 'approved' || rawStatus.toLowerCase() == 'paid' || rawStatus.toLowerCase() == 'active'
                                      ? 'Approved'
                                      : '—',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: rawStatus.toLowerCase() == 'approved' || rawStatus.toLowerCase() == 'paid' || rawStatus.toLowerCase() == 'active'
                                        ? const Color(0xFF059669)
                                        : Colors.grey,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Penalties & Fines Log (${_penaltiesList.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.add, color: Colors.white, size: 14),
                label: const Text('Add Penalty', style: TextStyle(color: Colors.white, fontSize: 11)),
                onPressed: _showApplyPenaltyDialog,
              ),
            ],
          ),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: _penaltiesList.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No disciplinary penalties recorded.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                    columns: const [
                      DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Date / Period', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: _penaltiesList.map((p) {
                      final emp = p['employee'] ?? {};
                      final name = emp['full_name']?.toString() ?? 'Employee #${p['employee_id']}';
                      final amt = double.tryParse(p['amount']?.toString() ?? '0') ?? 0;
                      final cat = p['category']?.toString() ?? 'Disciplinary';
                      final reason = p['reason']?.toString() ?? '—';
                      final date = p['penalty_date']?.toString() ?? p['pay_period']?.toString() ?? '—';
                      final pStatus = p['status']?.toString() ?? 'Pending';
                      final isPending = pStatus.toLowerCase() == 'pending';

                      return DataRow(cells: [
                        DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(cat)),
                        DataCell(Text(CurrencyService.format(amt), style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold))),
                        DataCell(Text(reason)),
                        DataCell(Text(date)),
                        DataCell(_buildStatusChip(pStatus)),
                        DataCell(
                          isPending
                              ? IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 18),
                                  onPressed: () => _deletePenalty(p['id'] as int),
                                  tooltip: 'Delete Penalty',
                                )
                              : const Text('Deducted', style: TextStyle(color: Color(0xFF059669), fontSize: 12)),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Arrears & Adjustments Log (${filteredArrears.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                ),
                icon: const Icon(Icons.add, color: Colors.white, size: 14),
                label: const Text('Add Arrear', style: TextStyle(color: Colors.white, fontSize: 11)),
                onPressed: _showAddArrearDialog,
              ),
            ],
          ),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: filteredArrears.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No arrears recorded.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic)),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                    columns: const [
                      DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Type / Reason', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Payment Month', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: filteredArrears.map((arr) {
                      final emp = arr['employee'] ?? {};
                      final name = emp['full_name']?.toString() ?? 'Employee #${arr['employee_id']}';
                      final amt = double.tryParse(arr['amount']?.toString() ?? '0') ?? 0;
                      final reason = arr['reason']?.toString() ?? 'Salary Arrear';
                      final month = arr['payment_month']?.toString() ?? '—';
                      final aStatus = arr['status']?.toString() ?? 'Pending Approval';
                      final isInstant = reason.toLowerCase().contains('(instant)') || arr['payment_mode'] == 'Instant';
                      final isPending = aStatus.toLowerCase().contains('pending');

                      return DataRow(cells: [
                        DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(reason)),
                        DataCell(Text(CurrencyService.format(amt), style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold))),
                        DataCell(Text(month)),
                        DataCell(_buildStatusChip(aStatus, type: 'arrear', isInstant: isInstant)),
                        DataCell(
                          isPending
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 20),
                                      onPressed: () => _approveArrear(arr['id'] as int),
                                      tooltip: 'Approve Arrear',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 18),
                                      onPressed: () => _rejectArrear(arr['id'] as int),
                                      tooltip: 'Delete / Reject Arrear',
                                    ),
                                  ],
                                )
                              : const Text('Approved', style: TextStyle(color: Color(0xFF059669), fontSize: 12)),
                        ),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Pending Salary Revisions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: _revisionApprovals.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No pending salary revisions.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                    columns: const [
                      DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Previous Salary', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('New Salary', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Effective Date', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: _revisionApprovals.map((rev) {
                      final emp = rev['employee'] ?? {};
                      final name = emp['full_name']?.toString() ?? '—';
                      final prev = double.tryParse(rev['previous_salary']?.toString() ?? '0') ?? 0;
                      final next = double.tryParse(rev['new_salary']?.toString() ?? '0') ?? 0;
                      final date = rev['effective_date']?.toString() ?? '—';

                      return DataRow(cells: [
                        DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(CurrencyService.format(prev))),
                        DataCell(Text(CurrencyService.format(next), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)))),
                        DataCell(Text(date)),
                        DataCell(Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 20),
                              onPressed: () => _approveRevision(rev['id'] as int),
                              tooltip: 'Approve',
                            ),
                            IconButton(
                              icon: const Icon(Icons.highlight_off, color: Color(0xFFDC2626), size: 20),
                              onPressed: () => _rejectRevision(rev['id'] as int),
                              tooltip: 'Reject',
                            ),
                          ],
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Pending Bonuses & Rewards', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
        ),
        _card(
          padding: EdgeInsets.zero,
          child: filteredBonuses.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No pending bonuses / rewards.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
                    columns: const [
                      DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Reason / Occasion', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Payout Month', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: filteredBonuses.map((bon) {
                      final emp = bon['employee'] ?? {};
                      final name = emp['full_name']?.toString() ?? '—';
                      final amt = double.tryParse(bon['amount']?.toString() ?? '0') ?? 0;
                      final reason = bon['reason']?.toString() ?? 'Bonus';
                      final month = bon['payment_month']?.toString() ?? '—';

                      return DataRow(cells: [
                        DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
                        DataCell(Text(CurrencyService.format(amt), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)))),
                        DataCell(Text(reason)),
                        DataCell(Text(month)),
                        DataCell(Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 20),
                              onPressed: () => _approveBonus(bon['id'] as int),
                              tooltip: 'Approve',
                            ),
                            IconButton(
                              icon: const Icon(Icons.highlight_off, color: Color(0xFFDC2626), size: 20),
                              onPressed: () => _rejectBonus(bon['id'] as int),
                              tooltip: 'Reject',
                            ),
                          ],
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  Future<void> _approveRevision(int id) async {
    try {
      await ApiClient.put('/api/hrms/payroll/revisions/$id/approve', {});
      _loadTabContent();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salary revision approved!'), backgroundColor: Color(0xFF059669)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _rejectRevision(int id) async {
    try {
      await ApiClient.put('/api/hrms/payroll/revisions/$id/reject', {});
      _loadTabContent();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Salary revision rejected!'), backgroundColor: Color(0xFFDC2626)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _approveArrear(int id) async {
    try {
      final res = await ApiClient.put('/api/hrms/payroll/bonuses/$id/approve', {});
      _loadTabContent();
      final msg = res['message']?.toString() ?? 'Arrear approved!';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: const Color(0xFF059669)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _rejectArrear(int id) async {
    try {
      final res = await ApiClient.put('/api/hrms/payroll/bonuses/$id/reject', {});
      _loadTabContent();
      final msg = res['message']?.toString() ?? 'Arrear rejected!';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: const Color(0xFFDC2626)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _approveBonus(int id) async {
    try {
      final res = await ApiClient.put('/api/hrms/payroll/bonuses/$id/approve', {});
      _loadTabContent();
      final msg = res['message']?.toString() ?? 'Bonus approved!';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: const Color(0xFF059669)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _rejectBonus(int id) async {
    try {
      final res = await ApiClient.put('/api/hrms/payroll/bonuses/$id/reject', {});
      _loadTabContent();
      final msg = res['message']?.toString() ?? 'Bonus rejected!';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: const Color(0xFFDC2626)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _approveLoan(int id) async {
    try {
      await ApiClient.put('/api/hrms/loans/$id/status', {'status': 'Approved'});
      _loadTabContent();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Advance/Loan approved! Marked as Paid.'), backgroundColor: Color(0xFF059669)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error approving advance/loan: $e')));
    }
  }

  Future<void> _rejectLoan(int id) async {
    try {
      await ApiClient.put('/api/hrms/loans/$id/status', {'status': 'Rejected'});
      _loadTabContent();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Advance/Loan rejected.'), backgroundColor: Color(0xFFDC2626)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error rejecting advance/loan: $e')));
    }
  }

  Future<void> _approveLeave(int id) async {
    try {
      await ApiClient.put('/api/hrms/leaves/$id/approve', {});
      _loadTabContent();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave application approved!'), backgroundColor: Color(0xFF059669)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error approving leave: $e')));
    }
  }

  Future<void> _rejectLeave(int id) async {
    try {
      await ApiClient.put('/api/hrms/leaves/$id/reject', {});
      _loadTabContent();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Leave application rejected.'), backgroundColor: Color(0xFFDC2626)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error rejecting leave: $e')));
    }
  }

  Future<void> _deletePenalty(int id) async {
    try {
      await ApiClient.delete('/api/hrms/penalties/$id');
      _loadTabContent();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Penalty removed successfully!'), backgroundColor: Color(0xFF059669)));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  void _showApplyPenaltyDialog() async {
    if (_employeesList.isEmpty) {
      try {
        final res = await ApiClient.get(ApiEndpoints.hrmsEmployees);
        if (res['success'] == true && res['data'] != null) {
          _employeesList = List<Map<String, dynamic>>.from(res['data'] ?? []);
        }
      } catch (_) {}
    }

    final activeEmps = (_employeesList.isNotEmpty
            ? _employeesList
            : _previewData.map((e) => Map<String, dynamic>.from(e)).toList())
        .where((e) {
      final st = (e['status'] ?? 'Active').toString().toLowerCase();
      final isActiveFlag = e['is_active'] != false;
      return isActiveFlag && st != 'terminated' && st != 'inactive';
    }).toList();

    int? selectedEmpId;
    if (activeEmps.isNotEmpty) {
      selectedEmpId = (activeEmps.first['id'] ?? activeEmps.first['employee_id']) as int?;
    }

    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String category = 'Disciplinary';
    final period = DateFormat('yyyy-MM').format(_currentMonth);

    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.gavel_rounded, color: Color(0xFFDC2626)),
              SizedBox(width: 8),
              Text('Apply Disciplinary Penalty / Fine', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Employee *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: selectedEmpId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      DropdownMenuItem<int>(
                        value: -1,
                        child: Text(
                          'All Active Employees (${activeEmps.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                        ),
                      ),
                      ...activeEmps.map((e) {
                        final id = (e['id'] ?? e['employee_id']) as int;
                        final name = e['full_name'] ?? e['employee_name'] ?? 'Employee';
                        final code = e['employee_code'] ?? '';
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text('$name ($code)', overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: (val) => setDState(() => selectedEmpId = val),
                  ),
                  const SizedBox(height: 12),
                  const Text('Penalty / Fine Amount (₹) *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '₹ ',
                      hintText: 'e.g. 500',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: category,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'Disciplinary', child: Text('Disciplinary / Misconduct')),
                      DropdownMenuItem(value: 'Cash Shortage', child: Text('Cash Counter Shortage')),
                      DropdownMenuItem(value: 'Damage / Loss', child: Text('Inventory Damage / Loss')),
                      DropdownMenuItem(value: 'Late Violation', child: Text('Habitual Late Arrival')),
                      DropdownMenuItem(value: 'Other', child: Text('Other Disciplinary Deduction')),
                    ],
                    onChanged: (v) => setDState(() => category = v ?? 'Disciplinary'),
                  ),
                  const SizedBox(height: 12),
                  const Text('Reason / Remarks', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: reasonCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Enter reason for deduction...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.all(10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFECACA))),
                    child: Text(
                      'Note: This penalty will be queued for Pay Period $period and will automatically be deducted from the employee\'s salary slip and net take-home pay.',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF991B1B)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
              onPressed: () async {
                final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
                if (selectedEmpId == null || amt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select employee and enter valid amount.')));
                  return;
                }
                Navigator.pop(dctx);
                try {
                  if (selectedEmpId == -1) {
                    int successCount = 0;
                    for (final e in activeEmps) {
                      final empId = (e['id'] ?? e['employee_id']) as int;
                      final body = {
                        'employee_id': empId,
                        'amount': amt,
                        'category': category,
                        'reason': reasonCtrl.text.trim().isEmpty ? 'Disciplinary fine' : reasonCtrl.text.trim(),
                        'penalty_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                        'pay_period': period,
                      };
                      final res = await ApiClient.post('/api/hrms/penalties', body);
                      if (res['success'] == true) successCount++;
                    }
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Penalty applied to $successCount of ${activeEmps.length} active employees.'),
                        backgroundColor: const Color(0xFF059669),
                      ));
                    }
                    _loadTabContent();
                  } else {
                    final body = {
                      'employee_id': selectedEmpId,
                      'amount': amt,
                      'category': category,
                      'reason': reasonCtrl.text.trim().isEmpty ? 'Disciplinary fine' : reasonCtrl.text.trim(),
                      'penalty_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                      'pay_period': period,
                    };
                    final res = await ApiClient.post('/api/hrms/penalties', body);
                    if (res['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(res['message'] ?? 'Penalty queued and adjusted into salary payroll.'),
                        backgroundColor: const Color(0xFF059669),
                      ));
                      _loadTabContent();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(res['message'] ?? 'Failed to apply penalty.'),
                        backgroundColor: const Color(0xFFDC2626),
                      ));
                    }
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Apply & Queue for Salary', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ================= TAB 7: REPORTS =================
  Future<void> _fetchReportData() async {
    setState(() => _loadingReport = true);
    try {
      List<Map<String, dynamic>> raw = [];
      if (_selectedReportIndex == 0) {
        // Salary Revision Report
        final res = await ApiClient.get('/api/hrms/payroll/revisions');
        raw = List<Map<String, dynamic>>.from(res['data'] ?? []);
      } else if (_selectedReportIndex == 1) {
        // Advance / Loan Report
        final res = await ApiClient.get('/api/hrms/loans');
        raw = List<Map<String, dynamic>>.from(res['data'] ?? []);
      } else if (_selectedReportIndex == 2) {
        // Salary Payroll Report
        final res = await ApiClient.get('/api/hrms/payroll/history');
        raw = List<Map<String, dynamic>>.from(res['data'] ?? []);
      } else if (_selectedReportIndex == 3) {
        // Leave Report
        final res = await ApiClient.get(ApiEndpoints.hrmsLeaves);
        raw = List<Map<String, dynamic>>.from(res['data'] ?? []);
      } else if (_selectedReportIndex == 4) {
        // Bonus & Arrears Report
        final res = await ApiClient.get('/api/hrms/payroll/bonuses');
        raw = List<Map<String, dynamic>>.from(res['data'] ?? []);
      }
      setState(() {
        _reportData = raw;
      });
    } catch (_) {}
    finally {
      setState(() => _loadingReport = false);
    }
  }

  Widget _buildReportsTab() {
    if (_loadingTab || _loadingReport) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D)));
    }

    final filtered = _reportData.where((item) {
      // Status filter
      if (_reportStatusFilter != 'All') {
        final st = (item['status'] ?? item['payrollRun']?['status'] ?? '').toString().toLowerCase();
        if (_reportStatusFilter == 'Approved' && (st != 'approved' && st != 'active')) return false;
        if (_reportStatusFilter == 'Pending' && (st != 'pending' && st != 'pending approval' && st != 'draft')) return false;
        if (_reportStatusFilter == 'Rejected' && st != 'rejected') return false;
        if (_reportStatusFilter == 'Paid' && (st != 'paid' && st != 'closed')) return false;
      }
      // Search filter
      if (_reportSearchQuery.trim().isNotEmpty) {
        final q = _reportSearchQuery.trim().toLowerCase();
        final emp = item['employee'] ?? {};
        final name = (emp['full_name'] ?? item['employee_name'] ?? '').toString().toLowerCase();
        final code = (emp['employee_code'] ?? item['employee_code'] ?? '').toString().toLowerCase();
        if (!name.contains(q) && !code.contains(q)) return false;
      }
      // Date filter
      final dateStr = (item['effective_date'] ?? item['start_date'] ?? item['penalty_date'] ?? item['run_date'] ?? item['created_at'] ?? item['payment_month'] ?? '').toString();
      if (dateStr.isNotEmpty && dateStr.length >= 7) {
        DateTime? dt;
        if (dateStr.length == 7) {
          dt = DateTime.tryParse('$dateStr-01');
        } else {
          dt = DateTime.tryParse(dateStr.substring(0, 10));
        }
        if (dt != null) {
          if (dt.isBefore(DateTime(_reportFromDate.year, _reportFromDate.month, _reportFromDate.day))) return false;
          if (dt.isAfter(DateTime(_reportToDate.year, _reportToDate.month, _reportToDate.day, 23, 59, 59))) return false;
        }
      }
      return true;
    }).toList();

    final reportTitles = [
      'Salary Revision Report',
      'Advance & Loan Report',
      'Salary Payroll Report',
      'Employee Leave Report',
      'Bonus & Arrears Report'
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        // Sub-reports Selector
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(reportTitles.length, (idx) {
                final isSelected = _selectedReportIndex == idx;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(reportTitles[idx], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isSelected ? Colors.white : const Color(0xFF374151))),
                    selected: isSelected,
                    selectedColor: const Color(0xFFE03E2D),
                    backgroundColor: const Color(0xFFF3F4F6),
                    onSelected: (val) {
                      if (val) {
                        setState(() => _selectedReportIndex = idx);
                        _fetchReportData();
                      }
                    },
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Filter Bar (Dates, Status, Search)
        _card(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                    icon: const Icon(Icons.date_range, size: 14),
                    label: Text('From: ${DateFormat('yyyy-MM-dd').format(_reportFromDate)}', style: const TextStyle(fontSize: 11)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _reportFromDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setState(() => _reportFromDate = picked);
                    },
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                    icon: const Icon(Icons.date_range, size: 14),
                    label: Text('To: ${DateFormat('yyyy-MM-dd').format(_reportToDate)}', style: const TextStyle(fontSize: 11)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _reportToDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (picked != null) setState(() => _reportToDate = picked);
                    },
                  ),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD1D5DB)), borderRadius: BorderRadius.circular(6)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _reportStatusFilter,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF374151), fontWeight: FontWeight.bold),
                        items: const [
                          DropdownMenuItem(value: 'All', child: Text('Status: All')),
                          DropdownMenuItem(value: 'Pending', child: Text('Pending')),
                          DropdownMenuItem(value: 'Approved', child: Text('Approved / Active')),
                          DropdownMenuItem(value: 'Paid', child: Text('Paid / Closed')),
                          DropdownMenuItem(value: 'Rejected', child: Text('Rejected')),
                        ],
                        onChanged: (v) => setState(() => _reportStatusFilter = v ?? 'All'),
                      ),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 180,
                    height: 32,
                    child: TextField(
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Search employee...',
                        prefixIcon: const Icon(Icons.search, size: 14),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      onChanged: (v) => setState(() => _reportSearchQuery = v),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                    icon: const Icon(Icons.download, size: 14, color: Colors.white),
                    label: const Text('Export CSV', style: TextStyle(color: Colors.white, fontSize: 11)),
                    onPressed: () => _exportReportCsv(filtered, reportTitles[_selectedReportIndex]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: _fetchReportData,
                    tooltip: 'Refresh Report',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Report Title & Count
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${reportTitles[_selectedReportIndex]} (${filtered.length} records)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E3A5F))),
              Text('Filtered Date: ${DateFormat('yyyy-MM-dd').format(_reportFromDate)} to ${DateFormat('yyyy-MM-dd').format(_reportToDate)}', style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280))),
            ],
          ),
        ),

        // Report DataTable
        _card(
          padding: EdgeInsets.zero,
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No records match the selected date range and filters.', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic))),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: _buildSpecificReportTable(filtered),
                ),
        ),
      ],
    );
  }

  Widget _buildSpecificReportTable(List<Map<String, dynamic>> data) {
    if (_selectedReportIndex == 0) {
      // Salary Revision Report
      return DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
        columns: const [
          DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Previous Salary', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('New / Requested Salary', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Increment (₹)', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Effective Date', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: data.map((rev) {
          final emp = rev['employee'] ?? {};
          final name = emp['full_name']?.toString() ?? 'Employee #${rev['employee_id']}';
          final oldSal = double.tryParse((rev['previous_salary'] ?? rev['old_salary'] ?? rev['current_salary'] ?? 0).toString()) ?? 0;
          final newSal = double.tryParse((rev['new_salary'] ?? rev['revised_salary'] ?? rev['requested_salary'] ?? 0).toString()) ?? 0;
          final inc = newSal - oldSal;
          final eff = rev['effective_date']?.toString() ?? '—';
          final reason = rev['reason']?.toString() ?? '—';
          final st = rev['status']?.toString() ?? 'Pending';

          return DataRow(cells: [
            DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text(CurrencyService.format(oldSal))),
            DataCell(Text(CurrencyService.format(newSal), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)))),
            DataCell(Text(inc >= 0 ? '+ ${CurrencyService.format(inc)}' : CurrencyService.format(inc), style: const TextStyle(color: Color(0xFF059669)))),
            DataCell(Text(eff)),
            DataCell(Text(reason)),
            DataCell(_buildStatusChip(st)),
          ]);
        }).toList(),
      );
    } else if (_selectedReportIndex == 1) {
      // Advance & Loan Report
      return DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
        columns: const [
          DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Loan Amount', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Monthly EMI', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Remaining Balance', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Payment Method', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Notes', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: data.map((loan) {
          final emp = loan['employee'] ?? {};
          final name = emp['full_name']?.toString() ?? 'Employee #${loan['employee_id']}';
          final amt = double.tryParse(loan['loan_amount']?.toString() ?? '0') ?? 0;
          final emi = double.tryParse(loan['monthly_emi']?.toString() ?? '0') ?? 0;
          final bal = double.tryParse(loan['remaining_balance']?.toString() ?? '0') ?? 0;
          final method = loan['payment_method']?.toString() ?? 'Cash';
          final st = loan['status']?.toString() ?? 'Pending';
          final notes = loan['notes']?.toString() ?? '—';

          return DataRow(cells: [
            DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text(CurrencyService.format(amt), style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(CurrencyService.format(emi))),
            DataCell(Text(CurrencyService.format(bal))),
            DataCell(Text(method)),
            DataCell(_buildStatusChip(st)),
            DataCell(Text(notes)),
          ]);
        }).toList(),
      );
    } else if (_selectedReportIndex == 2) {
      // Salary Payroll Report
      return DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
        columns: const [
          DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Pay Period', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Base Salary', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Paid Days', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Gross Pay', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Loan EMI', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Penalties/Shortage', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Statutory Deductions', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Total Deductions', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Net Salary', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: data.map((row) {
          final emp = row['employee'] ?? {};
          final name = emp['full_name']?.toString() ?? row['employee_name']?.toString() ?? 'Employee #${row['employee_id']}';
          final period = row['payrollRun']?['pay_period'] ?? row['pay_period'] ?? '—';
          final base = double.tryParse(row['base_salary']?.toString() ?? '0') ?? 0;
          final days = double.tryParse((row['days_present'] ?? row['salary_days'] ?? 0).toString()) ?? 0;
          final gross = double.tryParse(row['gross_pay']?.toString() ?? '0') ?? 0;
          final loan = double.tryParse((row['loan_emi'] ?? row['loan_deduction'] ?? 0).toString()) ?? 0;
          final pen = double.tryParse((row['shortage_penalties'] ?? row['penalty_deduction'] ?? 0).toString()) ?? 0;
          final stat = double.tryParse((row['statutory_deductions'] ?? 0).toString()) ?? 0;
          final totalDed = double.tryParse(row['total_deductions']?.toString() ?? '0') ?? 0;
          final net = double.tryParse(row['net_pay']?.toString() ?? '0') ?? 0;
          final st = row['payrollRun']?['status'] ?? 'Paid';

          return DataRow(cells: [
            DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text(period)),
            DataCell(Text(CurrencyService.format(base))),
            DataCell(Text(days.toStringAsFixed(1))),
            DataCell(Text(CurrencyService.format(gross))),
            DataCell(Text(CurrencyService.format(loan), style: const TextStyle(color: Color(0xFFDC2626)))),
            DataCell(Text(CurrencyService.format(pen), style: const TextStyle(color: Color(0xFFDC2626)))),
            DataCell(Text(CurrencyService.format(stat), style: const TextStyle(color: Color(0xFFDC2626)))),
            DataCell(Text(CurrencyService.format(totalDed), style: const TextStyle(color: Color(0xFFDC2626)))),
            DataCell(Text(CurrencyService.format(net), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)))),
            DataCell(_buildStatusChip(st)),
          ]);
        }).toList(),
      );
    } else if (_selectedReportIndex == 3) {
      // Leave Report
      return DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
        columns: const [
          DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Leave Type', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Start Date', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('End Date', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Total Days', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Reason', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: data.map((l) {
          final emp = l['employee'] ?? {};
          final name = emp['full_name']?.toString() ?? 'Employee #${l['employee_id']}';
          final lType = l['leaveType'] != null ? (l['leaveType']['name'] ?? 'Leave') : 'Leave';
          final start = l['start_date']?.toString() ?? '—';
          final end = l['end_date']?.toString() ?? '—';
          final days = l['total_days'] ?? 0;
          final reason = l['reason']?.toString() ?? '—';
          final st = l['status']?.toString() ?? 'Pending';

          return DataRow(cells: [
            DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text(lType)),
            DataCell(Text(start)),
            DataCell(Text(end)),
            DataCell(Text('$days')),
            DataCell(Text(reason)),
            DataCell(_buildStatusChip(st)),
          ]);
        }).toList(),
      );
    } else {
      // Bonus & Arrears Report
      return DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF9FAFB)),
        columns: const [
          DataColumn(label: Text('Employee', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Category', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Amount', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Payment Month', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Reason / Remarks', style: TextStyle(fontWeight: FontWeight.bold))),
          DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
        ],
        rows: data.map((b) {
          final emp = b['employee'] ?? {};
          final name = emp['full_name']?.toString() ?? 'Employee #${b['employee_id']}';
          final cat = b['type'] ?? b['category'] ?? 'Bonus';
          final amt = double.tryParse(b['amount']?.toString() ?? '0') ?? 0;
          final month = b['payment_month']?.toString() ?? '—';
          final reason = b['reason'] ?? b['notes'] ?? '—';
          final st = b['status']?.toString() ?? 'Pending';

          return DataRow(cells: [
            DataCell(Text(name, style: const TextStyle(fontWeight: FontWeight.w600))),
            DataCell(Text(cat)),
            DataCell(Text(CurrencyService.format(amt), style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF059669)))),
            DataCell(Text(month)),
            DataCell(Text(reason)),
            DataCell(_buildStatusChip(st)),
          ]);
        }).toList(),
      );
    }
  }

  void _exportReportCsv(List<Map<String, dynamic>> data, String title) {
    if (data.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No data to export.')));
      return;
    }
    final buffer = StringBuffer();
    buffer.writeln('Report: $title');
    buffer.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}');
    buffer.writeln('Date Filter: ${DateFormat('yyyy-MM-dd').format(_reportFromDate)} to ${DateFormat('yyyy-MM-dd').format(_reportToDate)}');
    buffer.writeln('');

    if (_selectedReportIndex == 0) {
      buffer.writeln('Employee,Previous Salary,New Salary,Increment,Effective Date,Reason,Status');
      for (final r in data) {
        final emp = r['employee'] ?? {};
        final name = '"${emp['full_name'] ?? 'Employee'}"';
        final oldSal = r['previous_salary'] ?? 0;
        final newSal = r['new_salary'] ?? 0;
        final inc = (double.tryParse('$newSal') ?? 0) - (double.tryParse('$oldSal') ?? 0);
        buffer.writeln('$name,$oldSal,$newSal,$inc,${r['effective_date']},"${r['reason'] ?? ''}",${r['status']}');
      }
    } else if (_selectedReportIndex == 1) {
      buffer.writeln('Employee,Loan Amount,Monthly EMI,Remaining Balance,Method,Status,Notes');
      for (final r in data) {
        final emp = r['employee'] ?? {};
        final name = '"${emp['full_name'] ?? 'Employee'}"';
        buffer.writeln('$name,${r['loan_amount']},${r['monthly_emi']},${r['remaining_balance']},${r['payment_method']},${r['status']},"${r['notes'] ?? ''}"');
      }
    } else if (_selectedReportIndex == 2) {
      buffer.writeln('Employee,Pay Period,Base Salary,Paid Days,Gross Pay,Loan EMI,Penalties,Statutory,Total Deductions,Net Salary,Status');
      for (final r in data) {
        final emp = r['employee'] ?? {};
        final name = '"${emp['full_name'] ?? r['employee_name'] ?? 'Employee'}"';
        final period = r['payrollRun']?['pay_period'] ?? r['pay_period'] ?? '';
        buffer.writeln('$name,$period,${r['base_salary']},${r['days_present'] ?? r['salary_days']},${r['gross_pay']},${r['loan_emi'] ?? r['loan_deduction'] ?? 0},${r['shortage_penalties'] ?? 0},${r['statutory_deductions'] ?? 0},${r['total_deductions']},${r['net_pay']},${r['payrollRun']?['status'] ?? 'Paid'}');
      }
    } else if (_selectedReportIndex == 3) {
      buffer.writeln('Employee,Leave Type,Start Date,End Date,Total Days,Reason,Status');
      for (final r in data) {
        final emp = r['employee'] ?? {};
        final name = '"${emp['full_name'] ?? 'Employee'}"';
        final lt = r['leaveType'] != null ? (r['leaveType']['name'] ?? 'Leave') : 'Leave';
        buffer.writeln('$name,$lt,${r['start_date']},${r['end_date']},${r['total_days']},"${r['reason'] ?? ''}",${r['status']}');
      }
    } else {
      buffer.writeln('Employee,Category,Amount,Payment Month,Reason,Status');
      for (final r in data) {
        final emp = r['employee'] ?? {};
        final name = '"${emp['full_name'] ?? 'Employee'}"';
        buffer.writeln('$name,${r['type'] ?? r['category'] ?? 'Bonus'},${r['amount']},${r['payment_month']},"${r['reason'] ?? ''}",${r['status']}');
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Exported ${data.length} records for $title successfully!'),
      backgroundColor: const Color(0xFF059669),
    ));
  }

  // ================= UTILS & HELPERS =================
  Widget _payScheduleCard({required String title, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F))),
          const Divider(height: 20, color: Color(0xFFE5E7EB)),
          child,
        ],
      ),
    );
  }

  InputDecoration _inputDecor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12),
      prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 16),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE03E2D), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
    );
  }

  InputDecoration _dropdownDecor() {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE03E2D), width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
    );
  }

  void _showBulkRevisionDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D))),
    );

    List<Map<String, dynamic>> payStructures = [];
    try {
      final res = await ApiClient.get(ApiEndpoints.hrmsPayStructures);
      payStructures = List<Map<String, dynamic>>.from(res['data'] ?? []);
      if (_employeesList.isEmpty) {
        final empRes = await ApiClient.get(ApiEndpoints.hrmsEmployees);
        if (empRes['success'] == true && empRes['data'] != null) {
          _employeesList = List<Map<String, dynamic>>.from(empRes['data'] ?? []);
        }
      }
    } catch (_) {}

    if (mounted) Navigator.pop(context);

    final activeRevisionEmps = _employeesList.where((e) {
      final st = (e['status'] ?? 'Active').toString().toLowerCase();
      final isActiveFlag = e['is_active'] != false;
      return isActiveFlag && st != 'terminated' && st != 'inactive';
    }).toList();

    String revisionType = 'Percentage';
    final valueCtrl = TextEditingController(text: '10');
    DateTime effectiveDate = DateTime.now();
    String target = 'All';
    dynamic selectedGradeId;
    dynamic selectedOfficeTargetId;
    int? selectedRevisionEmpId = activeRevisionEmps.isNotEmpty ? activeRevisionEmps.first['id'] as int? : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Bulk Salary Revision', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Revision Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('%', style: TextStyle(fontSize: 13)),
                        value: 'Percentage',
                        groupValue: revisionType,
                        activeColor: const Color(0xFFE03E2D),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDs(() => revisionType = v!),
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: Text(CurrencyService.symbol, style: const TextStyle(fontSize: 13)),
                        value: 'Amount',
                        groupValue: revisionType,
                        activeColor: const Color(0xFFE03E2D),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDs(() => revisionType = v!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valueCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: revisionType == 'Percentage' ? 'Percentage Value (%)' : 'Revision Amount (${CurrencyService.symbol})',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    prefixIcon: Icon(revisionType == 'Percentage' ? Icons.percent : Icons.attach_money, size: 20),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Target Employees', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
                Wrap(
                  spacing: 4,
                  children: [
                    SizedBox(
                      width: 90,
                      child: RadioListTile<String>(
                        title: const Text('All', style: TextStyle(fontSize: 12)),
                        value: 'All',
                        groupValue: target,
                        activeColor: const Color(0xFFE03E2D),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDs(() {
                          target = v!;
                          selectedGradeId = null;
                          selectedOfficeTargetId = null;
                        }),
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: RadioListTile<String>(
                        title: const Text('By Office', style: TextStyle(fontSize: 12)),
                        value: 'Office',
                        groupValue: target,
                        activeColor: const Color(0xFFE03E2D),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDs(() {
                          target = v!;
                          if (_offices.isNotEmpty) selectedOfficeTargetId = _offices[0]['id'];
                        }),
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: RadioListTile<String>(
                        title: const Text('By Grade', style: TextStyle(fontSize: 12)),
                        value: 'Designation',
                        groupValue: target,
                        activeColor: const Color(0xFFE03E2D),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDs(() {
                          target = v!;
                          if (payStructures.isNotEmpty) selectedGradeId = payStructures[0]['id'];
                        }),
                      ),
                    ),
                    SizedBox(
                      width: 135,
                      child: RadioListTile<String>(
                        title: const Text('By Employee', style: TextStyle(fontSize: 12)),
                        value: 'Employee',
                        groupValue: target,
                        activeColor: const Color(0xFFE03E2D),
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) => setDs(() {
                          target = v!;
                          if (activeRevisionEmps.isNotEmpty && selectedRevisionEmpId == null) {
                            selectedRevisionEmpId = activeRevisionEmps.first['id'] as int?;
                          }
                        }),
                      ),
                    ),
                  ],
                ),
                if (target == 'Employee') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    value: selectedRevisionEmpId,
                    isExpanded: true,
                    hint: const Text('Select Employee'),
                    items: activeRevisionEmps
                        .map((e) => DropdownMenuItem<int>(
                              value: e['id'] as int,
                              child: Text('${e['full_name'] ?? 'Employee'} (${e['employee_code'] ?? ''})', overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => setDs(() => selectedRevisionEmpId = v),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
                if (target == 'Office') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<dynamic>(
                    value: (_offices.any((o) => o['id'] == selectedOfficeTargetId)) ? selectedOfficeTargetId : null,
                    hint: const Text('Select Company Office / Branch'),
                    items: _offices
                        .map((o) => DropdownMenuItem<dynamic>(
                              value: o['id'],
                              child: Text('🏢 ${o['office_code']} - ${o['office_name']}'),
                            ))
                        .toList(),
                    onChanged: (v) => setDs(() => selectedOfficeTargetId = v),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
                if (target == 'Designation') ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<dynamic>(
                    value: (payStructures.any((d) => d['id'] == selectedGradeId)) ? selectedGradeId : null,
                    hint: const Text('Select Grade (Pay Structure)'),
                    items: payStructures
                        .map((d) => DropdownMenuItem<dynamic>(
                              value: d['id'],
                              child: Text(d['name']?.toString() ?? ''),
                            ))
                        .toList(),
                    onChanged: (v) => setDs(() => selectedGradeId = v),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                GestureDetector(
                  onTap: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: effectiveDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      builder: (c, child) => Theme(
                        data: Theme.of(c).copyWith(colorScheme: const ColorScheme.light(primary: Color(0xFFE03E2D))),
                        child: child!,
                      ),
                    );
                    if (d != null) setDs(() => effectiveDate = d);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.calendar_today, size: 16, color: Color(0xFF6B7280)),
                            const SizedBox(width: 8),
                            Text('Effective Date: ${DateFormat('dd-MM-yyyy').format(effectiveDate)}', style: const TextStyle(fontSize: 13)),
                          ],
                        ),
                        const Icon(Icons.arrow_drop_down, color: Color(0xFF6B7280)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE03E2D),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final val = double.tryParse(valueCtrl.text) ?? 0.0;
                if (val <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid revision value')),
                  );
                  return;
                }
                if (target == 'Designation' && selectedGradeId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select a grade scale')),
                  );
                  return;
                }
                if (target == 'Employee' && selectedRevisionEmpId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select an employee')),
                  );
                  return;
                }
                try {
                  final payload = {
                    'type': revisionType,
                    'value': val,
                    'designation_id': target == 'Designation' ? selectedGradeId : null,
                    'office_id': target == 'Office' ? selectedOfficeTargetId : null,
                    'employee_ids': target == 'Employee' && selectedRevisionEmpId != null ? [selectedRevisionEmpId] : null,
                    'effective_date': DateFormat('yyyy-MM-dd').format(effectiveDate),
                  };
                  final res = await ApiClient.post('/api/hrms/payroll/bulk-revise', payload);
                  Navigator.pop(ctx);
                  _loadTabContent();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res['message'] ?? 'Bulk salary revision created and sent for approval!'),
                      backgroundColor: const Color(0xFF059669),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              },
              child: const Text('Apply', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showBulkBonusDialog() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator(color: Color(0xFFE03E2D))),
    );

    List<Map<String, dynamic>> payStructures = [];
    List<Map<String, dynamic>> employees = [];
    try {
      final res = await ApiClient.get(ApiEndpoints.hrmsPayStructures);
      payStructures = List<Map<String, dynamic>>.from(res['data'] ?? []);
      final empRes = await ApiClient.get(ApiEndpoints.hrmsEmployees);
      employees = List<Map<String, dynamic>>.from(empRes['data'] ?? []);
    } catch (_) {}

    if (mounted) Navigator.pop(context);

    String bonusType = 'Amount';
    final valueCtrl = TextEditingController(text: '5000');
    final reasonCtrl = TextEditingController(text: 'Diwali Bonus');
    String target = 'All';
    dynamic selectedGradeId;
    dynamic selectedOfficeTargetId;
    String paymentMode = 'Payroll';
    String paymentMethod = 'Cash';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDs) {
          List<Map<String, dynamic>> getTargetEmployees() {
            final active = employees.where((e) => e['status']?.toString().toLowerCase() == 'active').toList();
            if (target == 'All') {
              return active;
            } else if (target == 'Office') {
              return active.where((e) => e['office_id'] == selectedOfficeTargetId).toList();
            } else {
              return active.where((e) => e['pay_structure_id'] == selectedGradeId).toList();
            }
          }

          double calculateEstimatedCost(List<Map<String, dynamic>> targetEmps) {
            final val = double.tryParse(valueCtrl.text) ?? 0.0;
            if (bonusType == 'Amount') {
              return targetEmps.length * val;
            } else {
              double total = 0.0;
              for (final emp in targetEmps) {
                final base = double.tryParse(emp['base_salary']?.toString() ?? '0') ?? 0.0;
                total += base * (val / 100.0);
              }
              return total;
            }
          }

          final targets = getTargetEmployees();
          final cost = calculateEstimatedCost(targets);

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Bulk Bonus Payout', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bonus Type', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: Text('Fixed (${CurrencyService.symbol})', style: const TextStyle(fontSize: 13)),
                          value: 'Amount',
                          groupValue: bonusType,
                          activeColor: const Color(0xFFE03E2D),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDs(() => bonusType = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('% of Salary', style: TextStyle(fontSize: 13)),
                          value: 'Percentage',
                          groupValue: bonusType,
                          activeColor: const Color(0xFFE03E2D),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDs(() => bonusType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: valueCtrl,
                    keyboardType: TextInputType.number,
                    onChanged: (v) => setDs(() {}),
                    decoration: InputDecoration(
                      labelText: bonusType == 'Percentage' ? 'Percentage Value (%)' : 'Bonus Amount (${CurrencyService.symbol})',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: Icon(bonusType == 'Percentage' ? Icons.percent : Icons.attach_money, size: 20),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      labelText: 'Reason / Occasion',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      prefixIcon: const Icon(Icons.star_border, size: 20),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text('Payment Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: paymentMode,
                    items: const [
                      DropdownMenuItem(value: 'Payroll', child: Text('Add to Next Payroll')),
                      DropdownMenuItem(value: 'Instant', child: Text('Pay Instantly')),
                    ],
                    onChanged: (v) => setDs(() => paymentMode = v!),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (paymentMode == 'Instant') ...[
                    const SizedBox(height: 12),
                    const Text('Pay By Method', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      items: const [
                        DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                        DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                      ],
                      onChanged: (v) => setDs(() => paymentMethod = v!),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('Target Employees', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF4B5563))),
                  Wrap(
                    spacing: 4,
                    children: [
                      SizedBox(
                        width: 90,
                        child: RadioListTile<String>(
                          title: const Text('All', style: TextStyle(fontSize: 12)),
                          value: 'All',
                          groupValue: target,
                          activeColor: const Color(0xFFE03E2D),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDs(() {
                            target = v!;
                            selectedGradeId = null;
                            selectedOfficeTargetId = null;
                          }),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: RadioListTile<String>(
                          title: const Text('By Office', style: TextStyle(fontSize: 12)),
                          value: 'Office',
                          groupValue: target,
                          activeColor: const Color(0xFFE03E2D),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDs(() {
                            target = v!;
                            if (_offices.isNotEmpty) selectedOfficeTargetId = _offices[0]['id'];
                          }),
                        ),
                      ),
                      SizedBox(
                        width: 110,
                        child: RadioListTile<String>(
                          title: const Text('By Grade', style: TextStyle(fontSize: 12)),
                          value: 'Designation',
                          groupValue: target,
                          activeColor: const Color(0xFFE03E2D),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDs(() {
                            target = v!;
                            if (payStructures.isNotEmpty) selectedGradeId = payStructures[0]['id'];
                          }),
                        ),
                      ),
                    ],
                  ),
                  if (target == 'Office') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<dynamic>(
                      value: (_offices.any((o) => o['id'] == selectedOfficeTargetId)) ? selectedOfficeTargetId : null,
                      hint: const Text('Select Company Office / Branch'),
                      items: _offices
                          .map((o) => DropdownMenuItem<dynamic>(
                                value: o['id'],
                                child: Text('🏢 ${o['office_code']} - ${o['office_name']}'),
                              ))
                          .toList(),
                      onChanged: (v) => setDs(() => selectedOfficeTargetId = v),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                  if (target == 'Designation') ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<dynamic>(
                      value: (payStructures.any((d) => d['id'] == selectedGradeId)) ? selectedGradeId : null,
                      hint: const Text('Select Grade (Pay Structure)'),
                      items: payStructures
                          .map((d) => DropdownMenuItem<dynamic>(
                                value: d['id'],
                                child: Text(d['name']?.toString() ?? ''),
                              ))
                          .toList(),
                      onChanged: (v) => setDs(() => selectedGradeId = v),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calculate, color: Color(0xFF2563EB), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Estimated Total Cost',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${CurrencyService.format(cost)} (${targets.length} Employees)',
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E3A5F)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE03E2D),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () async {
                  final val = double.tryParse(valueCtrl.text) ?? 0.0;
                  if (val <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter a valid bonus value')),
                    );
                    return;
                  }
                  if (target == 'Designation' && selectedGradeId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please select a grade scale')),
                    );
                    return;
                  }
                  try {
                    final payload = {
                      'type': bonusType,
                      'value': val,
                      'designation_id': target == 'Designation' ? selectedGradeId : null,
                      'payment_mode': paymentMode,
                      'payment_method': paymentMode == 'Instant' ? paymentMethod : null,
                      'reason': reasonCtrl.text,
                      'payment_month': DateFormat('yyyy-MM').format(DateTime.now()),
                    };
                    final res = await ApiClient.post('/api/hrms/payroll/bulk-bonus', payload);
                    Navigator.pop(ctx);
                    _loadTabContent();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(res['message'] ?? 'Bulk bonus created!'),
                        backgroundColor: const Color(0xFF059669),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  } catch (e) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                },
                child: const Text('Apply', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddArrearDialog() async {
    if (_employeesList.isEmpty) {
      try {
        final res = await ApiClient.get(ApiEndpoints.hrmsEmployees);
        if (res['success'] == true && res['data'] != null) {
          _employeesList = List<Map<String, dynamic>>.from(res['data'] ?? []);
        }
      } catch (_) {}
    }

    final activeEmps = (_employeesList.isNotEmpty
            ? _employeesList
            : _previewData.map((e) => Map<String, dynamic>.from(e)).toList())
        .where((e) {
      final st = (e['status'] ?? 'Active').toString().toLowerCase();
      final isActiveFlag = e['is_active'] != false;
      return isActiveFlag && st != 'terminated' && st != 'inactive';
    }).toList();

    int? selectedEmpId;
    if (activeEmps.isNotEmpty) {
      selectedEmpId = (activeEmps.first['id'] ?? activeEmps.first['employee_id']) as int?;
    }

    final amountCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String itemType = 'Arrear';
    String paymentMode = 'Payroll';
    String paymentMethod = 'Bank Transfer';
    final period = DateFormat('yyyy-MM').format(_currentMonth);

    showDialog(
      context: context,
      builder: (dctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.monetization_on_outlined, color: Color(0xFF059669)),
              SizedBox(width: 8),
              Text('Add Arrear / Bonus Payout', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Employee *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<int>(
                    value: selectedEmpId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      DropdownMenuItem<int>(
                        value: -1,
                        child: Text(
                          'All Active Employees (${activeEmps.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFDC2626)),
                        ),
                      ),
                      ...activeEmps.map((e) {
                        final id = (e['id'] ?? e['employee_id']) as int;
                        final name = e['full_name'] ?? e['employee_name'] ?? 'Employee';
                        final code = e['employee_code'] ?? '';
                        return DropdownMenuItem<int>(
                          value: id,
                          child: Text('$name ($code)', overflow: TextOverflow.ellipsis),
                        );
                      }),
                    ],
                    onChanged: (val) => setDState(() => selectedEmpId = val),
                  ),
                  const SizedBox(height: 12),
                  const Text('Adjustment Type *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Arrear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: 'Arrear',
                          groupValue: itemType,
                          activeColor: const Color(0xFF059669),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDState(() => itemType = v!),
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          title: const Text('Bonus', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          value: 'Bonus',
                          groupValue: itemType,
                          activeColor: const Color(0xFF059669),
                          contentPadding: EdgeInsets.zero,
                          onChanged: (v) => setDState(() => itemType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('$itemType Amount (${CurrencyService.symbol}) *', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      prefixText: '${CurrencyService.symbol} ',
                      hintText: 'e.g. 5000',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Reason / Remarks *', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: reasonCtrl,
                    decoration: InputDecoration(
                      hintText: itemType == 'Arrear' ? 'e.g. Revision difference arrears for prev month' : 'e.g. Performance incentive',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('Payout Option', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: paymentMode,
                    items: const [
                      DropdownMenuItem(value: 'Payroll', child: Text('Add to Payroll (Calculated into next Net Pay)')),
                      DropdownMenuItem(value: 'Instant', child: Text('Pay Instantly (Direct Payout)')),
                    ],
                    onChanged: (v) => setDState(() => paymentMode = v!),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  if (paymentMode == 'Instant') ...[
                    const SizedBox(height: 12),
                    const Text('Payment Method', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    const SizedBox(height: 4),
                    DropdownButtonFormField<String>(
                      value: paymentMethod,
                      items: const [
                        DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer')),
                        DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                        DropdownMenuItem(value: 'Cheque', child: Text('Cheque')),
                        DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                      ],
                      onChanged: (v) => setDState(() => paymentMethod = v!),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B7280))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF059669),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final val = double.tryParse(amountCtrl.text) ?? 0.0;
                if (selectedEmpId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please select an employee')),
                  );
                  return;
                }
                if (val <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Please enter a valid $itemType amount')),
                  );
                  return;
                }
                try {
                  if (selectedEmpId == -1) {
                    int successCount = 0;
                    for (final e in activeEmps) {
                      final empId = (e['id'] ?? e['employee_id']) as int;
                      final payload = {
                        'employee_id': empId,
                        'amount': val,
                        'type': itemType,
                        'bonus_type': itemType,
                        'payment_mode': paymentMode,
                        'payment_method': paymentMode == 'Instant' ? paymentMethod : null,
                        'reason': reasonCtrl.text.isEmpty ? '$itemType adjustment' : reasonCtrl.text,
                        'payment_month': period,
                      };
                      final res = await ApiClient.post('/api/hrms/payroll/bonuses', payload);
                      if (res['success'] == true) successCount++;
                    }
                    Navigator.pop(ctx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('$itemType applied to $successCount of ${activeEmps.length} active employees!'),
                          backgroundColor: const Color(0xFF059669),
                        ),
                      );
                    }
                    _loadTabContent();
                    if (_tabController.index == 0) {
                      _fetchPreviewData();
                    }
                  } else {
                    final payload = {
                      'employee_id': selectedEmpId,
                      'amount': val,
                      'type': itemType,
                      'bonus_type': itemType,
                      'payment_mode': paymentMode,
                      'payment_method': paymentMode == 'Instant' ? paymentMethod : null,
                      'reason': reasonCtrl.text.isEmpty ? '$itemType adjustment' : reasonCtrl.text,
                      'payment_month': period,
                    };
                    final res = await ApiClient.post('/api/hrms/payroll/bonuses', payload);
                    Navigator.pop(ctx);
                    if (res['success'] == true) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res['message'] ?? '$itemType added successfully!'),
                          backgroundColor: const Color(0xFF059669),
                        ),
                      );
                      _loadTabContent();
                      if (_tabController.index == 0) {
                        _fetchPreviewData();
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res['message'] ?? 'Failed to add $itemType'),
                          backgroundColor: const Color(0xFFDC2626),
                        ),
                      );
                    }
                  }
                } catch (e) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error: $e')),
                  );
                }
              },
              child: Text('Save $itemType', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, {String? type, bool? isInstant}) {
    Color bg, fg;
    final lower = status.toLowerCase().trim();
    String displayStatus = status.toUpperCase();

    if (lower == 'paid' || lower == 'completed' || lower == 'disbursed') {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF059669);
      displayStatus = 'PAID';
    } else if (lower == 'approved' || lower == 'active') {
      if (type == 'arrear' || type == 'bonus') {
        if (isInstant == true) {
          bg = const Color(0xFFECFDF5);
          fg = const Color(0xFF059669);
          displayStatus = 'PAID';
        } else {
          // Designated to be paid on salary, waiting for payroll run & payment
          bg = const Color(0xFFFFFBEB);
          fg = const Color(0xFFD97706);
          displayStatus = 'PENDING (ON SALARY)';
        }
      } else {
        bg = const Color(0xFFECFDF5);
        fg = const Color(0xFF059669);
        displayStatus = lower == 'active' ? 'ACTIVE' : 'APPROVED';
      }
    } else if (lower.contains('pending approval') || lower == 'pending_approval') {
      bg = const Color(0xFFFFF7ED);
      fg = const Color(0xFFEA580C);
      displayStatus = 'PENDING APPROVAL';
    } else if (lower == 'pending') {
      if (type == 'arrear' || type == 'bonus') {
        bg = const Color(0xFFFFFBEB);
        fg = const Color(0xFFD97706);
        displayStatus = 'PENDING (ON SALARY)';
      } else {
        bg = const Color(0xFFFFF7ED);
        fg = const Color(0xFFEA580C);
        displayStatus = 'PENDING';
      }
    } else if (lower == 'rejected') {
      bg = const Color(0xFFFEF2F2);
      fg = const Color(0xFFDC2626);
      displayStatus = 'REJECTED';
    } else if (lower == 'draft') {
      bg = const Color(0xFFF3F4F6);
      fg = const Color(0xFF6B7280);
      displayStatus = 'DRAFT';
    } else {
      bg = const Color(0xFFF3F4F6);
      fg = const Color(0xFF6B7280);
      displayStatus = status.toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(displayStatus, style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 4, offset: const Offset(0, 1))],
      ),
      child: child,
    );
  }

  Widget _buildDashboardKpisGrid() {
    final selectedPeriod = DateFormat('yyyy-MM').format(_currentMonth);
    if (_dashboardKpis.isEmpty || 
        _dashboardKpis['pay_period'] == 'None' || 
        _dashboardKpis['pay_period'] == null ||
        _dashboardKpis['has_data'] == false ||
        _dashboardKpis['pay_period'] != selectedPeriod) {
      return const SizedBox.shrink();
    }
    
    final period = _dashboardKpis['pay_period'] ?? '';
    final leaveDed = double.tryParse(_dashboardKpis['total_leave_deduction']?.toString() ?? '0') ?? 0.0;
    final absentDed = double.tryParse(_dashboardKpis['total_absent_deduction']?.toString() ?? '0') ?? 0.0;
    final lateDed = double.tryParse(_dashboardKpis['total_late_deduction']?.toString() ?? '0') ?? 0.0;
    final otPaid = double.tryParse(_dashboardKpis['total_overtime_paid']?.toString() ?? '0') ?? 0.0;
    final bonusPaid = double.tryParse(_dashboardKpis['total_bonuses_paid']?.toString() ?? '0') ?? 0.0;
    final netPaid = double.tryParse(_dashboardKpis['total_net_paid']?.toString() ?? '0') ?? 0.0;
    final totalDeduct = double.tryParse(_dashboardKpis['total_deductions']?.toString() ?? '0') ?? 0.0;
    final increment = double.tryParse(_dashboardKpis['increment_from_prev_month']?.toString() ?? '0') ?? 0.0;

    final card1 = _buildSummaryCard(
      label: 'LEAVE DEDUCTIONS',
      value: CurrencyService.format(leaveDed),
      icon: Icons.time_to_leave,
      color: Colors.red.shade700,
      iconBgColor: Colors.red.shade700,
      cardBgColor: Colors.red.shade50,
    );
    final card2 = _buildSummaryCard(
      label: 'ABSENT DEDUCTIONS',
      value: CurrencyService.format(absentDed),
      icon: Icons.cancel_presentation,
      color: Colors.red.shade800,
      iconBgColor: Colors.red.shade800,
      cardBgColor: Colors.red.shade50,
    );
    final card3 = _buildSummaryCard(
      label: 'LATE / SHORT HOURS',
      value: CurrencyService.format(lateDed),
      icon: Icons.more_time,
      color: Colors.orange.shade700,
      iconBgColor: Colors.orange.shade700,
      cardBgColor: Colors.orange.shade50,
    );
    final card4 = _buildSummaryCard(
      label: 'OVERTIME PAID',
      value: CurrencyService.format(otPaid),
      icon: Icons.add_alarm,
      color: Colors.green.shade700,
      iconBgColor: Colors.green.shade700,
      cardBgColor: Colors.green.shade50,
    );
    final card5 = _buildSummaryCard(
      label: 'BONUS PAID',
      value: CurrencyService.format(bonusPaid),
      icon: Icons.workspace_premium,
      color: Colors.indigo.shade700,
      iconBgColor: Colors.indigo.shade700,
      cardBgColor: Colors.indigo.shade50,
    );
    final card6 = _buildSummaryCard(
      label: 'NET PAID (SALARY)',
      value: CurrencyService.format(netPaid),
      icon: Icons.monetization_on,
      color: Colors.teal.shade700,
      iconBgColor: Colors.teal.shade700,
      cardBgColor: Colors.teal.shade50,
    );
    final card7 = _buildSummaryCard(
      label: 'TOTAL DEDUCTIONS',
      value: CurrencyService.format(totalDeduct),
      icon: Icons.remove_circle_outline,
      color: Colors.red.shade900,
      iconBgColor: Colors.red.shade900,
      cardBgColor: Colors.red.shade50,
    );
    final card8 = _buildSummaryCard(
      label: 'MONTHLY INCREMENT',
      value: '${increment >= 0 ? "+" : ""}${CurrencyService.format(increment)}',
      icon: increment >= 0 ? Icons.trending_up : Icons.trending_down,
      color: increment >= 0 ? Colors.green.shade800 : Colors.red.shade800,
      iconBgColor: increment >= 0 ? Colors.green.shade800 : Colors.red.shade800,
      cardBgColor: increment >= 0 ? Colors.green.shade50 : Colors.red.shade50,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.analytics, color: Color(0xFF1E3A5F), size: 20),
              const SizedBox(width: 8),
              Text(
                'Payroll Analytics Summary ($period)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A5F)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= 1000) {
                // Large Screen: 2 rows of 4 cards
                return Column(
                  children: [
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card1),
                          const SizedBox(width: 8),
                          Expanded(child: card2),
                          const SizedBox(width: 8),
                          Expanded(child: card3),
                          const SizedBox(width: 8),
                          Expanded(child: card4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card5),
                          const SizedBox(width: 8),
                          Expanded(child: card6),
                          const SizedBox(width: 8),
                          Expanded(child: card7),
                          const SizedBox(width: 8),
                          Expanded(child: card8),
                        ],
                      ),
                    ),
                  ],
                );
              } else if (constraints.maxWidth >= 700) {
                // Medium Screen: 3 rows (3, 3, 2)
                return Column(
                  children: [
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card1),
                          const SizedBox(width: 8),
                          Expanded(child: card2),
                          const SizedBox(width: 8),
                          Expanded(child: card3),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card4),
                          const SizedBox(width: 8),
                          Expanded(child: card5),
                          const SizedBox(width: 8),
                          Expanded(child: card6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card7),
                          const SizedBox(width: 8),
                          Expanded(child: card8),
                          const SizedBox(width: 8),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ],
                );
              } else {
                // Small Screen: 4 rows of 2 cards
                return Column(
                  children: [
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card1),
                          const SizedBox(width: 8),
                          Expanded(child: card2),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card3),
                          const SizedBox(width: 8),
                          Expanded(child: card4),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card5),
                          const SizedBox(width: 8),
                          Expanded(child: card6),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 60,
                      child: Row(
                        children: [
                          Expanded(child: card7),
                          const SizedBox(width: 8),
                          Expanded(child: card8),
                        ],
                      ),
                    ),
                  ],
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
