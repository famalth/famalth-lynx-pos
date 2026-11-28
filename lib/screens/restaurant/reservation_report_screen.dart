import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../controllers/restaurant/restaurant_controller.dart';
import '../../core/currency/currency_service.dart';
import '../../core/printing/pos_invoice_printer.dart';

class ReservationQuotationHelper {
  static String formatTables(Map<String, dynamic> r) {
    final tn = (r['table_names'] ?? '').toString().trim();
    if (tn.isNotEmpty) return tn;
    return (r['table']?['table_name'] ?? 'Table #${r['table_id'] ?? ''}').toString();
  }

  static String formatEvent(Map<String, dynamic> r) {
    final ev = (r['event_type'] ?? 'Dining').toString().trim();
    final custom = (r['custom_event_name'] ?? '').toString().trim();
    if (ev.toLowerCase() == 'custom' && custom.isNotEmpty) return custom;
    return custom.isNotEmpty ? '$ev ($custom)' : ev;
  }

  static String extractCancellationReason(Map<String, dynamic> r) {
    final direct = (r['cancellation_reason'] ?? '').toString().trim();
    if (direct.isNotEmpty) return direct;
    final rawRemarks = (r['remarks'] ?? '').toString();
    final cleaned = rawRemarks.replaceAll(RegExp(r'\[Slots:\s*[^\]]+\]'), '').trim();
    final match = RegExp(r'Cancelled:\s*(.+)$', caseSensitive: false).firstMatch(cleaned);
    if (match != null) return match.group(1)!.trim();
    final cleanNoSep = cleaned.replaceFirst(RegExp(r'^\|+\s*'), '').trim();
    return cleanNoSep;
  }

  static Future<Uint8List> buildQuotationPdf(Map<String, dynamic> r) async {
    final pdf = await PosInvoicePrinter.createDocument();
    final customer = (r['customer_name'] ?? 'Guest').toString();
    final phone = (r['customer_phone'] ?? '').toString();
    final tables = formatTables(r);
    final event = formatEvent(r);
    final pax = int.tryParse((r['guest_count'] ?? 1).toString()) ?? 1;
    final hallCharges = double.tryParse((r['hall_charges'] ?? 0).toString()) ?? 0;
    final itemsTotal = double.tryParse((r['items_total'] ?? 0).toString()) ?? 0;
    final bookingAmt = double.tryParse((r['booking_amount'] ?? 0).toString()) ?? 0;
    final advancePaid = double.tryParse((r['advance_paid'] ?? 0).toString()) ?? 0;
    final totalCost = double.tryParse((r['total_cost'] ?? (hallCharges + itemsTotal + bookingAmt)).toString()) ?? 0;
    final balanceDue = totalCost - advancePaid;
    final rawTime = (r['reservation_time'] ?? '').toString();
    final dt = DateTime.tryParse(rawTime)?.toLocal();
    final dateFmt = dt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(dt) : rawTime;
    final menuItems = (r['menu_items'] is List) ? (r['menu_items'] as List) : [];

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('RESERVATION & EVENT QUOTATION', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Divider(),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Guest: $customer', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    if (phone.isNotEmpty) pw.Text('Phone: $phone', style: const pw.TextStyle(fontSize: 11)),
                    if ((r['address'] ?? '').toString().trim().isNotEmpty)
                      pw.Text('Address: ${r['address']}', style: const pw.TextStyle(fontSize: 10)),
                    if ((r['gstin'] ?? '').toString().trim().isNotEmpty)
                      pw.Text('GSTIN: ${r['gstin']}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Event: $event', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
                    pw.Text('Date & Time: $dateFmt', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Tables: $tables  |  Pax: $pax', style: const pw.TextStyle(fontSize: 11)),
                    pw.Text('Status: ${r['status'] ?? 'Pending'}', style: const pw.TextStyle(fontSize: 10)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            if (menuItems.isNotEmpty) ...[
              pw.Text('Selected Menu Items', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
              pw.SizedBox(height: 6),
              pw.Table.fromTextArray(
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                cellStyle: const pw.TextStyle(fontSize: 10),
                headers: ['Item', 'Qty', 'Rate', 'Amount'],
                data: menuItems.map((m) {
                  final q = double.tryParse((m['qty'] ?? 1).toString()) ?? 1;
                  final rate = double.tryParse((m['rate'] ?? 0).toString()) ?? 0;
                  final amt = double.tryParse((m['amount'] ?? (q * rate)).toString()) ?? (q * rate);
                  return [
                    (m['item_name'] ?? 'Item').toString(),
                    q.toStringAsFixed(q % 1 == 0 ? 0 : 1),
                    rate.toStringAsFixed(2),
                    amt.toStringAsFixed(2),
                  ];
                }).toList(),
              ),
              pw.SizedBox(height: 14),
            ],
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(
                children: [
                  _pdfRow('Hall / Venue Charges', hallCharges),
                  _pdfRow('Menu Items Total', itemsTotal),
                  _pdfRow('Booking / Table Charges', bookingAmt),
                  pw.Divider(),
                  _pdfRow('Estimated Total Cost', totalCost, bold: true),
                  _pdfRow('Advance Paid', advancePaid),
                  _pdfRow('Balance Payable', balanceDue, bold: true),
                ],
              ),
            ),
            if ((r['remarks'] ?? '').toString().trim().isNotEmpty) ...[
              pw.SizedBox(height: 12),
              pw.Text('Remarks: ${r['remarks']}', style: const pw.TextStyle(fontSize: 10)),
            ],
          ],
        ),
      ),
    );
    return pdf.save();
  }

  static pw.Widget _pdfRow(String label, double val, {bool bold = false}) {
    final style = pw.TextStyle(fontSize: bold ? 12 : 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: style),
          pw.Text('Rs. ${val.toStringAsFixed(2)}', style: style),
        ],
      ),
    );
  }

  static Future<void> printQuotation(BuildContext context, Map<String, dynamic> r) async {
    final bytes = await buildQuotationPdf(r);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static Future<void> shareQuotation(BuildContext context, Map<String, dynamic> r) async {
    final bytes = await buildQuotationPdf(r);
    final name = (r['customer_name'] ?? 'Guest').toString().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    await Printing.sharePdf(bytes: bytes, filename: 'Quotation_$name.pdf');
  }

  static void showQuotationDialog(BuildContext context, Map<String, dynamic> r) {
    final customer = (r['customer_name'] ?? 'Guest').toString();
    final phone = (r['customer_phone'] ?? '').toString();
    final tables = formatTables(r);
    final event = formatEvent(r);
    final pax = int.tryParse((r['guest_count'] ?? 1).toString()) ?? 1;
    final hallCharges = double.tryParse((r['hall_charges'] ?? 0).toString()) ?? 0;
    final itemsTotal = double.tryParse((r['items_total'] ?? 0).toString()) ?? 0;
    final totalCost = double.tryParse((r['total_cost'] ?? (hallCharges + itemsTotal)).toString()) ?? 0;
    final advancePaid = double.tryParse((r['advance_paid'] ?? 0).toString()) ?? 0;
    final balanceDue = totalCost - advancePaid;
    final rawTime = (r['reservation_time'] ?? '').toString();
    final dt = DateTime.tryParse(rawTime)?.toLocal();
    final dateFmt = dt != null ? DateFormat('dd MMM yyyy, hh:mm a').format(dt) : rawTime;
    final menuItems = (r['menu_items'] is List) ? (r['menu_items'] as List) : [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, color: Color(0xFF0B5CAD)),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Reservation & Event Quotation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                (r['status'] ?? 'Confirmed').toString(),
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0B5CAD)),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$customer  •  $pax Pax', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Event: $event  •  Tables: $tables', style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155))),
                      Text('Date & Time: $dateFmt', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                      if (phone.isNotEmpty) Text('Phone: $phone', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                      if ((r['address'] ?? '').toString().trim().isNotEmpty)
                        Text('Address: ${r['address']}', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                      if ((r['gstin'] ?? '').toString().trim().isNotEmpty)
                        Text('GSTIN: ${r['gstin']}', style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
                    ],
                  ),
                ),
                if (menuItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Items & Charges Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  ...menuItems.map((m) {
                    final q = double.tryParse((m['qty'] ?? 1).toString()) ?? 1;
                    final rate = double.tryParse((m['rate'] ?? 0).toString()) ?? 0;
                    final amt = double.tryParse((m['amount'] ?? (q * rate)).toString()) ?? (q * rate);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Expanded(child: Text('${m['item_name'] ?? 'Item'} (${q.toStringAsFixed(q % 1 == 0 ? 0 : 1)} × ₹${rate.toStringAsFixed(2)})', style: const TextStyle(fontSize: 12.5))),
                          Text('₹${amt.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                        ],
                      ),
                    );
                  }),
                ],
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    children: [
                      _previewRow('Hall / Venue Charges', hallCharges),
                      _previewRow('Food / Menu / Extra Charges', itemsTotal),
                      const Divider(height: 14),
                      _previewRow('Total Booking Cost', totalCost, bold: true, color: const Color(0xFF0B5CAD)),
                      _previewRow('Advance Paid', advancePaid, color: Colors.green.shade700),
                      _previewRow('Balance Payable', balanceDue, bold: true, color: Colors.deepOrange),
                    ],
                  ),
                ),
                if ((r['remarks'] ?? '').toString().trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('Remarks: ${r['remarks']}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          OutlinedButton.icon(
            icon: const Icon(Icons.share_outlined, size: 16, color: Colors.green),
            label: const Text('Share'),
            onPressed: () => shareQuotation(context, r),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.print_outlined, size: 16),
            label: const Text('Print'),
            onPressed: () => printQuotation(context, r),
          ),
        ],
      ),
    );
  }

  static Widget _previewRow(String label, double val, {bool bold = false, Color? color}) {
    final st = TextStyle(fontSize: bold ? 13 : 12, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color ?? const Color(0xFF0F172A));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: st),
          Text('₹${val.toStringAsFixed(2)}', style: st),
        ],
      ),
    );
  }
}

class ReservationReportScreen extends StatefulWidget {
  const ReservationReportScreen({super.key});

  @override
  State<ReservationReportScreen> createState() => _ReservationReportScreenState();
}

class _ReservationReportScreenState extends State<ReservationReportScreen> {
  String _viewMode = 'Month'; // Day, Week, Month, Range
  DateTime _anchorDate = DateTime.now();
  DateTimeRange _dateRange = DateTimeRange(
    start: DateTime.now().subtract(const Duration(days: 30)),
    end: DateTime.now().add(const Duration(days: 30)),
  );
  String _statusFilter = 'All';
  String _eventFilter = 'All';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RestaurantController>().loadReservations();
    });
  }

  List<Map<String, dynamic>> _filterReservations(List<dynamic> raw) {
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).where((r) {
      final dt = DateTime.tryParse((r['reservation_time'] ?? '').toString())?.toLocal();
      if (dt != null) {
        if (_viewMode == 'Day') {
          if (dt.year != _anchorDate.year || dt.month != _anchorDate.month || dt.day != _anchorDate.day) return false;
        } else if (_viewMode == 'Week') {
          final start = DateTime(_anchorDate.year, _anchorDate.month, _anchorDate.day).subtract(Duration(days: _anchorDate.weekday - 1));
          final end = start.add(const Duration(days: 7));
          if (dt.isBefore(start) || !dt.isBefore(end)) return false;
        } else if (_viewMode == 'Month') {
          if (dt.year != _anchorDate.year || dt.month != _anchorDate.month) return false;
        } else if (_viewMode == 'Range') {
          final s = DateTime(_dateRange.start.year, _dateRange.start.month, _dateRange.start.day);
          final e = DateTime(_dateRange.end.year, _dateRange.end.month, _dateRange.end.day, 23, 59, 59);
          if (dt.isBefore(s) || dt.isAfter(e)) return false;
        }
      }
      if (_statusFilter != 'All' && (r['status'] ?? 'Pending').toString().toLowerCase() != _statusFilter.toLowerCase()) {
        return false;
      }
      if (_eventFilter != 'All' && (r['event_type'] ?? 'Dining').toString().toLowerCase() != _eventFilter.toLowerCase()) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        final hay = '${r['customer_name'] ?? ''} ${r['customer_phone'] ?? ''} ${ReservationQuotationHelper.formatTables(r)} ${ReservationQuotationHelper.formatEvent(r)}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RestaurantController>();
    final rows = _filterReservations(ctrl.reservations);

    final totalPax = rows.fold<int>(0, (s, r) => s + (int.tryParse((r['guest_count'] ?? 0).toString()) ?? 0));
    final totalCost = rows.fold<double>(0, (s, r) => s + (double.tryParse((r['total_cost'] ?? 0).toString()) ?? 0));
    final totalAdv = rows.fold<double>(0, (s, r) => s + (double.tryParse((r['advance_paid'] ?? 0).toString()) ?? 0));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('Reservation & Event Quotation Report', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A))),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE2E8F0)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ctrl.loadReservations(),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Filter bar
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Day', label: Text('Day')),
                      ButtonSegment(value: 'Week', label: Text('Week')),
                      ButtonSegment(value: 'Month', label: Text('Month')),
                      ButtonSegment(value: 'Range', label: Text('Date Range')),
                    ],
                    selected: {_viewMode},
                    onSelectionChanged: (s) => setState(() => _viewMode = s.first),
                  ),
                  if (_viewMode != 'Range')
                    OutlinedButton.icon(
                      icon: const Icon(Icons.calendar_today, size: 15),
                      label: Text(_viewMode == 'Month' ? DateFormat('MMMM yyyy').format(_anchorDate) : DateFormat('dd MMM yyyy').format(_anchorDate)),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _anchorDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) setState(() => _anchorDate = picked);
                      },
                    )
                  else
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range, size: 15),
                      label: Text('${DateFormat('dd MMM').format(_dateRange.start)} - ${DateFormat('dd MMM yyyy').format(_dateRange.end)}'),
                      onPressed: () async {
                        final picked = await showDateRangePicker(
                          context: context,
                          initialDateRange: _dateRange,
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now().add(const Duration(days: 730)),
                        );
                        if (picked != null) setState(() => _dateRange = picked);
                      },
                    ),
                  DropdownButton<String>(
                    value: _statusFilter,
                    items: ['All', 'Pending', 'Confirmed', 'Seated', 'Cancelled']
                        .map((s) => DropdownMenuItem(value: s, child: Text('Status: $s')))
                        .toList(),
                    onChanged: (v) => setState(() => _statusFilter = v ?? 'All'),
                  ),
                  DropdownButton<String>(
                    value: _eventFilter,
                    items: ['All', 'Dining', 'Lunch', 'Dinner', 'Birthday Party', 'Anniversary', 'Custom']
                        .map((s) => DropdownMenuItem(value: s, child: Text('Event: $s')))
                        .toList(),
                    onChanged: (v) => setState(() => _eventFilter = v ?? 'All'),
                  ),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search guest, phone, table...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // KPI Cards
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _kpi('Total Bookings', '${rows.length}', Colors.blue),
              _kpi('Total Pax', '$totalPax', Colors.indigo),
              _kpi('Estimated Total', CurrencyService.format(totalCost), Colors.teal),
              _kpi('Advance Paid', CurrencyService.format(totalAdv), Colors.green),
              _kpi('Balance Due', CurrencyService.format(totalCost - totalAdv), Colors.orange),
            ],
          ),
          const SizedBox(height: 12),
          // Table
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: rows.isEmpty
                ? const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No reservations found for selected filters.')))
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Date & Time', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Guest & Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Event', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Tables', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Pax', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Hall', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Items', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Total Cost', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Advance', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                        DataColumn(label: Text('Quotation', style: TextStyle(fontWeight: FontWeight.bold))),
                      ],
                      rows: rows.map((r) {
                        final dt = DateTime.tryParse((r['reservation_time'] ?? '').toString())?.toLocal();
                        final dtStr = dt != null ? DateFormat('dd-MMM-yyyy hh:mm a').format(dt) : '—';
                        final hall = double.tryParse((r['hall_charges'] ?? 0).toString()) ?? 0;
                        final itemsT = double.tryParse((r['items_total'] ?? 0).toString()) ?? 0;
                        final tot = double.tryParse((r['total_cost'] ?? 0).toString()) ?? 0;
                        final adv = double.tryParse((r['advance_paid'] ?? 0).toString()) ?? 0;

                        return DataRow(cells: [
                          DataCell(Text(dtStr)),
                          DataCell(Text('${r['customer_name'] ?? 'Guest'}\n${r['customer_phone'] ?? ''}')),
                          DataCell(Text(ReservationQuotationHelper.formatEvent(r))),
                          DataCell(Text(ReservationQuotationHelper.formatTables(r))),
                          DataCell(Text('${r['guest_count'] ?? 1}')),
                          DataCell(Text(CurrencyService.format(hall))),
                          DataCell(Text(CurrencyService.format(itemsT))),
                          DataCell(Text(CurrencyService.format(tot), style: const TextStyle(fontWeight: FontWeight.bold))),
                          DataCell(Text(CurrencyService.format(adv), style: const TextStyle(color: Colors.green))),
                          DataCell(
                            Builder(builder: (_) {
                              final st = (r['status'] ?? 'Pending').toString();
                              final reason = st.toLowerCase() == 'cancelled' ? ReservationQuotationHelper.extractCancellationReason(r) : '';
                              if (reason.isEmpty) return Text(st);
                              return Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(st, style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w600)),
                                  Text(reason, style: const TextStyle(fontSize: 10.5, color: Color(0xFFDC2626))),
                                ],
                              );
                            }),
                          ),
                          DataCell(Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.visibility_outlined, size: 18, color: Color(0xFF475569)),
                                tooltip: 'View Quotation',
                                onPressed: () => ReservationQuotationHelper.showQuotationDialog(context, r),
                              ),
                              IconButton(
                                icon: const Icon(Icons.print_outlined, size: 18, color: Colors.blue),
                                tooltip: 'Print Quotation',
                                onPressed: () => ReservationQuotationHelper.printQuotation(context, r),
                              ),
                              IconButton(
                                icon: const Icon(Icons.share_outlined, size: 18, color: Colors.green),
                                tooltip: 'Send Quotation',
                                onPressed: () => ReservationQuotationHelper.shareQuotation(context, r),
                              ),
                            ],
                          )),
                        ]);
                      }).toList(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _kpi(String title, String val, Color c) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: c)),
        ],
      ),
    );
  }
}
