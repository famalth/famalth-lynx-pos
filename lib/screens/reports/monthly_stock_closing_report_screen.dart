import 'dart:io';

import 'package:excel/excel.dart' as exc;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../core/currency/currency_service.dart';

class MonthlyStockClosingReportScreen extends StatefulWidget {
  const MonthlyStockClosingReportScreen({super.key});

  @override
  State<MonthlyStockClosingReportScreen> createState() =>
      _MonthlyStockClosingReportScreenState();
}

class _MonthlyStockClosingReportScreenState
    extends State<MonthlyStockClosingReportScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _verticalCtrl = ScrollController();
  final ScrollController _horizontalCtrl = ScrollController();

  bool _loading = true;
  bool _runningClose = false;
  List<Map<String, dynamic>> _rows = [];
  List<String> _months = [];
  String _selectedMonth = 'ALL';
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _verticalCtrl.dispose();
    _horizontalCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final params = <String>[];
      if (_selectedMonth != 'ALL') {
        params.add('month_key=${Uri.encodeComponent(_selectedMonth)}');
      }
      final query = params.isEmpty ? '' : '?${params.join('&')}';
      final res = await ApiClient.get('${ApiEndpoints.monthlyStockClosingReport}$query');
      if (mounted && res != null && res['success'] == true) {
        final rawList = (res['data'] as List?) ?? [];
        final rawMonths = (res['months'] as List?) ?? [];
        setState(() {
          _rows = rawList.map((e) => Map<String, dynamic>.from(e)).toList();
          _months = rawMonths.map((e) => e.toString()).toList();
          if (_selectedMonth != 'ALL' && !_months.contains(_selectedMonth)) {
            _selectedMonth = 'ALL';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load report: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _runClosingNow() async {
    setState(() => _runningClose = true);
    try {
      final res = await ApiClient.post(ApiEndpoints.monthlyStockClosingRun, {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res?['message'] ?? 'Monthly closing check completed.'),
            backgroundColor: res?['success'] == true ? const Color(0xFF008060) : Colors.red,
          ),
        );
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error running closing: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _runningClose = false);
    }
  }

  List<Map<String, dynamic>> get _filteredRows {
    final q = _search.trim().toLowerCase();
    return _rows.where((row) {
      if (_selectedMonth != 'ALL' && '${row['month_key'] ?? ''}' != _selectedMonth) {
        return false;
      }
      if (q.isEmpty) return true;
      final hay = '${row['item_code'] ?? ''} ${row['item_name'] ?? ''} ${row['brand'] ?? ''} ${row['month_key'] ?? ''}'.toLowerCase();
      return hay.contains(q);
    }).toList();
  }

  String _fmt(dynamic value) {
    final n = double.tryParse('${value ?? 0}') ?? 0;
    return n.toStringAsFixed(2);
  }

  Future<void> _exportToExcel() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel file save is available on Windows/Mobile desktop builds.')),
      );
      return;
    }
    try {
      final excel = exc.Excel.createExcel();
      final sheet = excel['Monthly Stock Closing'];
      final rows = _filteredRows;
      final headers = [
        'Month',
        'Item Code',
        'Item Name',
        'Brand',
        'Unit',
        'Opening Qty',
        'Total In',
        'Total Out',
        'Closing Qty',
        'Closing Value',
        'Closed At',
      ];
      for (var c = 0; c < headers.length; c++) {
        sheet.cell(exc.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          ..value = exc.TextCellValue(headers[c])
          ..cellStyle = exc.CellStyle(bold: true);
      }
      for (var i = 0; i < rows.length; i++) {
        final r = rows[i];
        final closedRaw = DateTime.tryParse('${r['closed_at'] ?? ''}')?.toLocal();
        final closedStr = closedRaw == null ? '' : DateFormat('dd-MMM-yyyy HH:mm').format(closedRaw);
        final vals = [
          '${r['month_key'] ?? ''}',
          '${r['item_code'] ?? ''}',
          '${r['item_name'] ?? ''}',
          '${r['brand'] ?? ''}',
          '${r['unit'] ?? ''}',
          _fmt(r['opening_qty']),
          _fmt(r['total_in']),
          _fmt(r['total_out']),
          _fmt(r['closing_qty']),
          _fmt(r['closing_value']),
          closedStr,
        ];
        for (var c = 0; c < vals.length; c++) {
          sheet
              .cell(exc.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: i + 1))
              .value = exc.TextCellValue(vals[c]);
        }
      }
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/monthly_stock_closing_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final bytes = excel.encode();
      if (bytes != null) {
        await File(filePath).writeAsBytes(bytes);
        await OpenFile.open(filePath);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows;
    double sumOpening = 0;
    double sumIn = 0;
    double sumOut = 0;
    double sumClosing = 0;
    double sumValue = 0;
    for (final r in rows) {
      sumOpening += double.tryParse('${r['opening_qty'] ?? 0}') ?? 0;
      sumIn += double.tryParse('${r['total_in'] ?? 0}') ?? 0;
      sumOut += double.tryParse('${r['total_out'] ?? 0}') ?? 0;
      sumClosing += double.tryParse('${r['closing_qty'] ?? 0}') ?? 0;
      sumValue += double.tryParse('${r['closing_value'] ?? 0}') ?? 0;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Month-on-Month Stock Closing Report'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
          if (!kIsWeb)
            IconButton(
              tooltip: 'Export Excel',
              onPressed: _exportToExcel,
              icon: const Icon(Icons.table_view_outlined),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF008060),
                foregroundColor: Colors.white,
              ),
              onPressed: _runningClose ? null : _runClosingNow,
              icon: _runningClose
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.lock_clock_outlined, size: 18),
              label: const Text('Close Pending Months'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter Card
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: _selectedMonth,
                    decoration: const InputDecoration(
                      labelText: 'Month (YYYY-MM)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(value: 'ALL', child: Text('All Closed Months')),
                      ..._months.map((m) => DropdownMenuItem(value: m, child: Text(m))),
                    ],
                    onChanged: (val) {
                      setState(() => _selectedMonth = val ?? 'ALL');
                      _loadData();
                    },
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Search item code, name, brand',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => _search = val),
                  ),
                ),
                _summaryChip('Opening', _fmt(sumOpening), Colors.blueGrey),
                _summaryChip('Total In', _fmt(sumIn), const Color(0xFF008060)),
                _summaryChip('Total Out', _fmt(sumOut), Colors.orange.shade800),
                _summaryChip('Closing Qty', _fmt(sumClosing), Colors.indigo),
                _summaryChip('Closing Value', CurrencyService.format(sumValue), const Color(0xFF0F172A)),
              ],
            ),
          ),

          // DataTable Card
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : Container(
                    margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: rows.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32),
                              child: Text(
                                'No monthly stock closing records found yet.\nCompleted months are auto-closed at month end or via "Close Pending Months".',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF64748B)),
                              ),
                            ),
                          )
                        : Scrollbar(
                            controller: _verticalCtrl,
                            thumbVisibility: true,
                            child: SingleChildScrollView(
                              controller: _verticalCtrl,
                              child: Scrollbar(
                                controller: _horizontalCtrl,
                                thumbVisibility: true,
                                notificationPredicate: (n) => n.depth == 1,
                                child: SingleChildScrollView(
                                  controller: _horizontalCtrl,
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                                    columns: const [
                                      DataColumn(label: Text('Month', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Item Code', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Item Name', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Brand', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Unit', style: TextStyle(fontWeight: FontWeight.bold))),
                                      DataColumn(label: Text('Opening Qty', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                      DataColumn(label: Text('Total In', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                      DataColumn(label: Text('Total Out', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                      DataColumn(label: Text('Closing Qty', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                      DataColumn(label: Text('Closing Value', style: TextStyle(fontWeight: FontWeight.bold)), numeric: true),
                                      DataColumn(label: Text('Closed At', style: TextStyle(fontWeight: FontWeight.bold))),
                                    ],
                                    rows: rows.map((r) {
                                      final closedDt = DateTime.tryParse('${r['closed_at'] ?? ''}')?.toLocal();
                                      final closedStr = closedDt == null
                                          ? '--'
                                          : DateFormat('dd-MMM-yyyy HH:mm').format(closedDt);
                                      return DataRow(
                                        cells: [
                                          DataCell(
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: Colors.indigo.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                '${r['month_key'] ?? ''}',
                                                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
                                              ),
                                            ),
                                          ),
                                          DataCell(Text('${r['item_code'] ?? ''}')),
                                          DataCell(Text('${r['item_name'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w600))),
                                          DataCell(Text('${r['brand'] ?? ''}')),
                                          DataCell(Text('${r['unit'] ?? ''}')),
                                          DataCell(Text(_fmt(r['opening_qty']))),
                                          DataCell(Text(_fmt(r['total_in']), style: const TextStyle(color: Color(0xFF008060)))),
                                          DataCell(Text(_fmt(r['total_out']), style: TextStyle(color: Colors.orange.shade800))),
                                          DataCell(Text(_fmt(r['closing_qty']), style: const TextStyle(fontWeight: FontWeight.bold))),
                                          DataCell(Text(CurrencyService.format(double.tryParse('${r['closing_value'] ?? 0}') ?? 0))),
                                          DataCell(Text(closedStr, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)))),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }
}
