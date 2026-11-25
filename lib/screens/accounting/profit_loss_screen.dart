import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../controllers/accounting/financial_reports_controller.dart';
import '../../core/currency/currency_service.dart';
import '../../core/utils/country_tax_helper.dart';

class ProfitLossScreen extends StatefulWidget {
  final String? outletId;
  const ProfitLossScreen({super.key, this.outletId});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  final FinancialReportsController ctrl = FinancialReportsController();

  String _selectedPeriod = 'today';
  DateTimeRange? _customDateRange;

  final Map<String, String> _periodLabels = {
    'today': 'Today',
    'yesterday': 'Yesterday',
    'this_week': 'This Week',
    'this_month': 'This Month',
    'this_year': 'This Year',
    'all': 'All Time',
    'custom': 'Custom Range',
  };

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    if (_selectedPeriod == 'custom' && _customDateRange != null) {
      final start = DateFormat('yyyy-MM-dd').format(_customDateRange!.start);
      final end = DateFormat('yyyy-MM-dd').format(_customDateRange!.end);
      ctrl.fetchProfitLoss(startDate: start, endDate: end, outletId: widget.outletId);
    } else {
      ctrl.fetchProfitLoss(period: _selectedPeriod, outletId: widget.outletId);
    }
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
    );

    if (picked != null) {
      setState(() {
        _selectedPeriod = 'custom';
        _customDateRange = picked;
      });
      _loadData();
    }
  }

  void _showProfitLossFormulaDialog(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.corporate_fare_rounded, color: Color(0xFF008060)),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Corporate P&L Structure (EBITDA Standard)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Understanding Operating vs. Non-Operating Expenses in Corporate Accounting:',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
              ),
              const SizedBox(height: 12),

              // 1. Operating Expenses (Above EBITDA)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '1. OPERATING EXPENSES (ABOVE EBITDA)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF15803D)),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Direct, day-to-day costs required to run operations:\n'
                      '• Raw materials / Cost of Goods Sold (COGS)\n'
                      '• Employee salaries, wages and bonuses\n'
                      '• Store & office rents and leases\n'
                      '• Electricity, water, utilities, and marketing\n'
                      '• Logistics, fleet transportation & dispatch\n\n'
                      'Subtracting these from Total Revenue gives EBITDA (pure operational profit).',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF166534), height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 2. Non-Operating Expenses (Below EBITDA)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '2. NON-OPERATING & ACCOUNTING EXPENSES (BELOW EBITDA)',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Real financial costs that reduce final cash/shareholder value:\n\n'
                      '• Depreciation & Amortization (Non-Cash Expense):\n'
                      '  Machinery, vehicles, store buildouts and computers wear out. Accounting rules spread the upfront asset purchase cost over their useful life as an annual non-cash expense.\n'
                      '  EBIT = EBITDA - Depreciation\n\n'
                      '• Finance Costs / Interest (Cash Expense):\n'
                      '  Fees and interest paid to banks and lenders for borrowing money.\n'
                      '  EBT (PBT) = EBIT - Finance Costs\n\n'
                      '• Tax Expenses (Cash Expense):\n'
                      '  Mandatory corporate income taxes paid to government on profits.\n'
                      '  Net Profit (PAT) = EBT - Tax Expense',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF334155), height: 1.38),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF008060))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF008060);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: const Text(
          'Statement of Profit & Loss (Corporate EBITDA Standard)',
          style: TextStyle(color: primaryColor, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: primaryColor),
        actions: [
          IconButton(
            tooltip: 'View EBITDA & Accounting Formula',
            icon: const Icon(Icons.functions_rounded, color: primaryColor),
            onPressed: () => _showProfitLossFormulaDialog(context, ctrl.profitLossData),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: primaryColor),
            onPressed: _loadData,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          if (ctrl.loading) return const Center(child: CircularProgressIndicator(color: primaryColor));

          final data = ctrl.profitLossData;
          final trading = data['tradingAccount'] ?? {};
          final opAcc = data['operatingAccount'] ?? {};
          final nonOpAcc = data['nonOperatingAccount'] ?? {};
          final pl = data['profitAndLossAccount'] ?? {};

          final grossSales = double.tryParse((trading['totalRevenue'] ?? 0).toString()) ?? 0.0;
          final salesDiscounts = double.tryParse((trading['salesDiscounts'] ?? 0).toString()) ?? 0.0;
          final netSalesRevenue = double.tryParse((trading['netSalesRevenue'] ?? 0).toString()) ?? (grossSales - salesDiscounts);

          final openingStock = double.tryParse((trading['openingStock'] ?? 0).toString()) ?? 0.0;
          final purchases = double.tryParse((trading['purchases'] ?? 0).toString()) ?? 0.0;
          final directFreight = double.tryParse((trading['directFreight'] ?? 0).toString()) ?? 0.0;
          final closingStock = double.tryParse((trading['closingStock'] ?? 0).toString()) ?? 0.0;
          final cogs = double.tryParse((trading['costOfGoodsSold'] ?? 0).toString()) ?? 0.0;
          final grossProfit = double.tryParse((trading['grossProfit'] ?? 0).toString()) ?? 0.0;
          final grossLoss = double.tryParse((trading['grossLoss'] ?? 0).toString()) ?? 0.0;
          final bool isGrossProfit = (trading['isGrossProfit'] == true) || (grossProfit >= grossLoss);
          final double displayGross = isGrossProfit ? grossProfit : grossLoss;
          final double grossMargin = double.tryParse((trading['grossProfitMargin'] ?? 0).toString()) ?? 0.0;

          // Operating Expenses (Above EBITDA)
          final indirectIncome = double.tryParse((opAcc['indirectIncome'] ?? pl['indirectIncome'] ?? 0).toString()) ?? 0.0;
          final totalOperatingIncome = double.tryParse((opAcc['totalOperatingIncome'] ?? pl['totalOperatingIncome'] ?? grossProfit).toString()) ?? grossProfit;
          final operatingExpenses = double.tryParse((opAcc['operatingExpenses'] ?? pl['operatingExpenses'] ?? 0).toString()) ?? 0.0;
          final expenseBreakdown = (opAcc['expenseBreakdown'] ?? pl['expenseBreakdown']) as List? ?? [];

          // EBITDA
          final ebitda = double.tryParse((opAcc['ebitda'] ?? pl['ebitda'] ?? (totalOperatingIncome - operatingExpenses)).toString()) ?? 0.0;
          final double ebitdaMargin = double.tryParse((opAcc['ebitdaMargin'] ?? 0).toString()) ?? 0.0;
          final bool isEbitdaPositive = ebitda >= 0;

          // Non-Operating (Below EBITDA)
          final depObj = nonOpAcc['depreciation'] as Map? ?? {};
          final double depreciation = double.tryParse((depObj['amount'] ?? pl['depreciation'] ?? 0).toString()) ?? 0.0;

          final ebit = double.tryParse((nonOpAcc['ebit'] ?? pl['ebit'] ?? (ebitda - depreciation)).toString()) ?? (ebitda - depreciation);
          final double ebitMargin = double.tryParse((nonOpAcc['ebitMargin'] ?? 0).toString()) ?? 0.0;

          final finObj = nonOpAcc['financeCosts'] as Map? ?? {};
          final double financeCosts = double.tryParse((finObj['amount'] ?? pl['financeCosts'] ?? 0).toString()) ?? 0.0;

          final ebt = double.tryParse((nonOpAcc['ebt'] ?? (ebit - financeCosts)).toString()) ?? (ebit - financeCosts);

          final taxObj = nonOpAcc['taxExpense'] as Map? ?? {};
          final double taxExpense = double.tryParse((taxObj['amount'] ?? pl['taxExpense'] ?? 0).toString()) ?? 0.0;

          final netProfit = double.tryParse((nonOpAcc['netProfit'] ?? pl['netProfit'] ?? (ebt - taxExpense)).toString()) ?? 0.0;
          final netLoss = double.tryParse((nonOpAcc['netLoss'] ?? pl['netLoss'] ?? 0).toString()) ?? 0.0;
          final bool isNetProfit = (nonOpAcc['isNetProfit'] ?? pl['isNetProfit'] ?? true) == true || (netProfit >= netLoss);
          final double displayNet = isNetProfit ? netProfit : netLoss;
          final double netProfitMargin = double.tryParse((nonOpAcc['netProfitMargin'] ?? 0).toString()) ?? 0.0;

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Filter Bar
              _buildFilterBar(primaryColor),
              const SizedBox(height: 12),

              // KPI Executive Dashboard Grid
              _buildExecutiveKpiRow(
                isNetProfit: isNetProfit,
                displayNet: displayNet,
                netProfitMargin: netProfitMargin,
                ebitda: ebitda,
                ebitdaMargin: ebitdaMargin,
                isGrossProfit: isGrossProfit,
                displayGross: displayGross,
                grossMargin: grossMargin,
                cogs: cogs,
                depreciation: depreciation,
                financeCosts: financeCosts,
              ),
              const SizedBox(height: 16),

              // PART I: REVENUE & DIRECT PRODUCTION COSTS (TRADING)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.storefront_outlined, color: primaryColor, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'TRADING ACCOUNT (Gross Profit / COGS)',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: primaryColor),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isGrossProfit ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Margin: ${grossMargin.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isGrossProfit ? Colors.green.shade800 : Colors.red.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(height: 20),
                      _row('Gross Sales Revenue (Excl. ${CountryTaxHelper.taxName()})', CurrencyService.format(grossSales), Colors.black87),
                      _row('Less: Sales Returns & Discounts', '(${CurrencyService.format(salesDiscounts)})', Colors.red.shade700),
                      const Divider(height: 12),
                      _row('NET OPERATING REVENUE (A)', CurrencyService.format(netSalesRevenue), primaryColor, isBold: true),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Cost of Goods Sold / Raw Materials', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.grey)),
                          Text('(Sold Qty × Purchase Cost Rate)', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                        ],
                      ),
                      _row('  Opening Stock / Raw Materials', CurrencyService.format(openingStock), Colors.black54),
                      _row('  Add: Direct Purchases (Net of Tax)', CurrencyService.format(purchases), Colors.black54),
                      _row('  Add: Direct Inward Freight', CurrencyService.format(directFreight), Colors.black54),
                      _row('  Less: Closing Stock / Inventory', '(${CurrencyService.format(closingStock)})', Colors.green.shade700),
                      _row('TOTAL COGS / RAW MATERIALS (B)', CurrencyService.format(cogs), Colors.red.shade700, isBold: true),
                      const Divider(),
                      _row(
                        isGrossProfit ? 'GROSS PROFIT [ A - B ]' : 'GROSS LOSS [ B - A ]',
                        CurrencyService.format(displayGross),
                        isGrossProfit ? Colors.green.shade800 : Colors.red.shade800,
                        isBold: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // PART II: OPERATING EXPENSES (ABOVE EBITDA)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.speed_rounded, color: Color(0xFF2563EB), size: 20),
                          SizedBox(width: 8),
                          Text(
                            '1. OPERATING EXPENSES (ABOVE EBITDA)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF2563EB)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Day-to-day operational cash costs: Salaries, store rents, utilities, marketing, fleet & logistics.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                      const Divider(height: 20),
                      _row(
                        isGrossProfit ? 'Gross Profit B/F' : 'Gross Loss B/F',
                        isGrossProfit ? CurrencyService.format(displayGross) : '(${CurrencyService.format(displayGross)})',
                        isGrossProfit ? Colors.black87 : Colors.red.shade700,
                      ),
                      if (indirectIncome > 0)
                        _row('Add: Other Operational Income', CurrencyService.format(indirectIncome), Colors.green.shade700),
                      const SizedBox(height: 8),
                      const Text('Operating Expenses Breakdown:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Colors.grey)),
                      if (expenseBreakdown.isEmpty)
                        _row('  General Operating Expenses', CurrencyService.format(operatingExpenses), Colors.red.shade700)
                      else
                        ...expenseBreakdown.map((e) => _row(
                              '  ${e['category'] ?? 'Expense'}',
                              CurrencyService.format(double.tryParse((e['amount'] ?? 0).toString()) ?? 0.0),
                              Colors.red.shade700,
                            )),
                      const Divider(height: 12),
                      _row('TOTAL OPERATING EXPENSES (Above EBITDA)', CurrencyService.format(operatingExpenses), Colors.red.shade700, isBold: true),
                      const Divider(),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isEbitdaPositive ? const Color(0xFFEFF6FF) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isEbitdaPositive ? const Color(0xFFBFDBFE) : const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'EBITDA (Pure Operational Profit)',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E3A8A)),
                                ),
                                Text(
                                  'Earnings Before Interest, Tax, Depreciation & Amortization | Margin: ${ebitdaMargin.toStringAsFixed(1)}%',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF3B82F6)),
                                ),
                              ],
                            ),
                            Text(
                              CurrencyService.format(ebitda),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: isEbitdaPositive ? const Color(0xFF1D4ED8) : Colors.red.shade800,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // PART III: NON-OPERATING & ACCOUNTING EXPENSES (BELOW EBITDA)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.account_balance_outlined, color: Color(0xFF7C3AED), size: 20),
                          SizedBox(width: 8),
                          Text(
                            '2. NON-OPERATING & ACCOUNTING EXPENSES (BELOW EBITDA)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF7C3AED)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Capital allocation, financing and statutory tax costs that reduce final shareholder value.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                      const Divider(height: 20),
                      _row('EBITDA B/F', CurrencyService.format(ebitda), isEbitdaPositive ? Colors.black87 : Colors.red.shade700),
                      _row(
                        'Less: Depreciation & Amortization (Non-Cash Expense on Assets)',
                        '(${CurrencyService.format(depreciation)})',
                        Colors.orange.shade800,
                      ),
                      const Divider(height: 12),
                      _row('EBIT (Operating Profit / Profit Before Interest & Tax)', CurrencyService.format(ebit), const Color(0xFF7C3AED), isBold: true),
                      _row(
                        'Less: Finance Costs (Cash Interest paid on Bank Loans & Borrowings)',
                        '(${CurrencyService.format(financeCosts)})',
                        Colors.red.shade700,
                      ),
                      const Divider(height: 12),
                      _row('EBT (Profit Before Tax / PBT)', CurrencyService.format(ebt), Colors.black87, isBold: true),
                      _row(
                        'Less: Tax Expenses (Corporate Income Tax Paid/Accrued)',
                        '(${CurrencyService.format(taxExpense)})',
                        Colors.red.shade700,
                      ),
                      const Divider(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isNetProfit ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: isNetProfit ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isNetProfit ? 'NET PROFIT AFTER TAX (PAT / Bottom Line)' : 'NET LOSS AFTER TAX',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isNetProfit ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                  ),
                                ),
                                Text(
                                  'Final cash/value left for business reserves & shareholders | Net Margin: ${netProfitMargin.toStringAsFixed(1)}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isNetProfit ? const Color(0xFF16A34A) : Colors.red.shade400,
                                  ),
                                ),
                              ],
                            ),
                            Text(
                              CurrencyService.format(displayNet),
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: isNetProfit ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Icon(Icons.filter_alt_outlined, size: 18, color: Color(0xFF64748B)),
            const SizedBox(width: 8),
            const Text('Period:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: Color(0xFF334155))),
            const SizedBox(width: 8),
            ...['today', 'yesterday', 'this_week', 'this_month', 'this_year', 'all'].map((period) {
              final isSelected = _selectedPeriod == period;
              return Padding(
                padding: const EdgeInsets.only(right: 6.0),
                child: FilterChip(
                  label: Text(_periodLabels[period] ?? period),
                  selected: isSelected,
                  selectedColor: primaryColor.withAlpha(38),
                  checkmarkColor: primaryColor,
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? primaryColor : const Color(0xFF475569),
                  ),
                  onSelected: (val) {
                    if (val) {
                      setState(() {
                        _selectedPeriod = period;
                        _customDateRange = null;
                      });
                      _loadData();
                    }
                  },
                ),
              );
            }),
            FilterChip(
              label: Text(
                _selectedPeriod == 'custom' && _customDateRange != null
                    ? '${DateFormat('dd/MM').format(_customDateRange!.start)} - ${DateFormat('dd/MM').format(_customDateRange!.end)}'
                    : 'Custom',
              ),
              selected: _selectedPeriod == 'custom',
              selectedColor: primaryColor.withAlpha(38),
              checkmarkColor: primaryColor,
              labelStyle: TextStyle(
                fontSize: 11.5,
                fontWeight: _selectedPeriod == 'custom' ? FontWeight.bold : FontWeight.normal,
                color: _selectedPeriod == 'custom' ? primaryColor : const Color(0xFF475569),
              ),
              onSelected: (_) => _selectCustomDateRange(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExecutiveKpiRow({
    required bool isNetProfit,
    required double displayNet,
    required double netProfitMargin,
    required double ebitda,
    required double ebitdaMargin,
    required bool isGrossProfit,
    required double displayGross,
    required double grossMargin,
    required double cogs,
    required double depreciation,
    required double financeCosts,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 650;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpiCard('EBITDA (Operational)', ebitda, '${ebitdaMargin.toStringAsFixed(1)}% Margin', const Color(0xFF1D4ED8), const Color(0xFFEFF6FF), isWide),
            _kpiCard(isGrossProfit ? 'Gross Profit' : 'Gross Loss', displayGross, '${grossMargin.toStringAsFixed(1)}% Margin', isGrossProfit ? const Color(0xFF15803D) : Colors.red.shade800, const Color(0xFFF0FDF4), isWide),
            _kpiCard(isNetProfit ? 'Net Profit (PAT)' : 'Net Loss (PAT)', displayNet, '${netProfitMargin.toStringAsFixed(1)}% Margin', isNetProfit ? const Color(0xFF047857) : Colors.red.shade800, const Color(0xFFECFDF5), isWide),
            _kpiCard('Depreciation (Non-Cash)', depreciation, 'Asset Wear/Tear', Colors.orange.shade800, const Color(0xFFFFFBEB), isWide),
            _kpiCard('Finance Costs', financeCosts, 'Interest / Debt', Colors.purple.shade800, const Color(0xFFFAF5FF), isWide),
          ],
        );
      },
    );
  }

  Widget _kpiCard(String label, double val, String subtitle, Color textColor, Color bgColor, bool isWide) {
    return Container(
      width: isWide ? 190 : 160,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: textColor.withAlpha(50)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textColor), overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            CurrencyService.format(val),
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800, color: textColor, fontFamily: 'monospace'),
          ),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: textColor.withAlpha(200))),
        ],
      ),
    );
  }

  Widget _row(String label, String value, Color color, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, fontWeight: isBold ? FontWeight.bold : FontWeight.normal))),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: color,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}
