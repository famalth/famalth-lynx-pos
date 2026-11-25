import 'package:flutter/material.dart';
import '../../controllers/accounting/financial_reports_controller.dart';
import '../../core/currency/currency_service.dart';

class BalanceSheetScreen extends StatefulWidget {
  final String? outletId;
  const BalanceSheetScreen({super.key, this.outletId});

  @override
  State<BalanceSheetScreen> createState() => _BalanceSheetScreenState();
}

class _BalanceSheetScreenState extends State<BalanceSheetScreen> {
  final FinancialReportsController ctrl = FinancialReportsController();

  @override
  void initState() {
    super.initState();
    ctrl.fetchBalanceSheet(outletId: widget.outletId);
  }

  void _showBalanceSheetInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.balance_rounded, color: Color(0xFF008060)),
            SizedBox(width: 8),
            Text('Corporate Balance Sheet Architecture', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The Balance Sheet follows standard corporate dual-entry accounting:\n'
                'Total Assets = Total Equity + Non-Current Liabilities + Current Liabilities',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
              ),
              SizedBox(height: 12),
              Text(
                '🏛️ ASSETS (Application of Funds):\n'
                '• Non-Current Assets: Fixed assets (machinery, store fixtures, vehicles) recorded at Gross Block less Accumulated Depreciation (wear & tear) to yield Net Block, plus long-term investments.\n'
                '• Current Assets: Liquid operating assets including raw materials/stock, trade debtors, physical cash, bank balances, and Input Tax Credit (ITC).\n\n'
                '💼 LIABILITIES & EQUITY (Source of Funds):\n'
                '• Shareholders\' Equity: Owner\'s capital + Retained earnings (including current year Net Profit / PAT from P&L).\n'
                '• Non-Current Liabilities: Long-term bank borrowings and term loans.\n'
                '• Current Liabilities: Trade creditors/payables, customer advances, and Output GST/tax liabilities.',
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.4),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF008060))),
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
          'Balance Sheet Statement (Corporate Standard)',
          style: TextStyle(color: primaryColor, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: primaryColor),
        actions: [
          IconButton(
            tooltip: 'Balance Sheet Structure Info',
            icon: const Icon(Icons.info_outline, color: primaryColor),
            onPressed: () => _showBalanceSheetInfoDialog(context),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: primaryColor),
            onPressed: () => ctrl.fetchBalanceSheet(outletId: widget.outletId),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          if (ctrl.loading) return const Center(child: CircularProgressIndicator(color: primaryColor));

          final data = ctrl.balanceSheetData;
          final assetsClassified = data['assetsClassified'] as Map? ?? {};
          final liabClassified = data['liabilitiesAndEquityClassified'] as Map? ?? {};
          final totals = data['totals'] ?? {};

          // Non-Current Assets
          final ncAssets = assetsClassified['nonCurrentAssets'] as Map? ?? {};
          final ncAssetItems = (ncAssets['items'] as List? ?? []);
          final double totalNonCurrentAssets = double.tryParse((ncAssets['total'] ?? totals['totalNonCurrentAssets'] ?? 0).toString()) ?? 0.0;

          // Current Assets
          final cAssets = assetsClassified['currentAssets'] as Map? ?? {};
          final cAssetItems = (cAssets['items'] as List? ?? (data['assets'] as List? ?? []));
          final double totalCurrentAssets = double.tryParse((cAssets['total'] ?? totals['totalCurrentAssets'] ?? 0).toString()) ?? 0.0;

          final double totalAssets = double.tryParse((totals['totalAssets'] ?? (totalNonCurrentAssets + totalCurrentAssets)).toString()) ?? 0.0;

          // Equity
          final eq = liabClassified['equity'] as Map? ?? {};
          final eqItems = (eq['items'] as List? ?? (data['equity'] as List? ?? []));
          final double totalEquity = double.tryParse((eq['total'] ?? totals['totalEquity'] ?? 0).toString()) ?? 0.0;

          // Non-Current Liabilities
          final ncLiab = liabClassified['nonCurrentLiabilities'] as Map? ?? {};
          final ncLiabItems = (ncLiab['items'] as List? ?? []);
          final double totalNonCurrentLiab = double.tryParse((ncLiab['total'] ?? totals['totalNonCurrentLiabilities'] ?? 0).toString()) ?? 0.0;

          // Current Liabilities
          final cLiab = liabClassified['currentLiabilities'] as Map? ?? {};
          final cLiabItems = (cLiab['items'] as List? ?? (data['liabilities'] as List? ?? []));
          final double totalCurrentLiab = double.tryParse((cLiab['total'] ?? totals['totalCurrentLiabilities'] ?? 0).toString()) ?? 0.0;

          final double totalLiabAndEquity = double.tryParse((liabClassified['totalLiabilitiesAndEquity'] ?? (totalEquity + totalNonCurrentLiab + totalCurrentLiab)).toString()) ?? (totalEquity + totalNonCurrentLiab + totalCurrentLiab);
          final bool isBalanced = (totals['isBalanced'] == true) || ((totalAssets - totalLiabAndEquity).abs() < 1.0);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top KPI Summary Cards
                _buildSummaryCards(totalAssets, totalNonCurrentAssets, totalCurrentAssets, totalEquity, totalNonCurrentLiab, totalCurrentLiab, isBalanced),
                const SizedBox(height: 16),

                // Main Balance Sheet Side-by-Side or Stacked on Mobile
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 850;
                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildAssetsCard(primaryColor, ncAssetItems, totalNonCurrentAssets, cAssetItems, totalCurrentAssets, totalAssets),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildLiabilitiesCard(primaryColor, eqItems, totalEquity, ncLiabItems, totalNonCurrentLiab, cLiabItems, totalCurrentLiab, totalLiabAndEquity, isBalanced),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildAssetsCard(primaryColor, ncAssetItems, totalNonCurrentAssets, cAssetItems, totalCurrentAssets, totalAssets),
                          const SizedBox(height: 16),
                          _buildLiabilitiesCard(primaryColor, eqItems, totalEquity, ncLiabItems, totalNonCurrentLiab, cLiabItems, totalCurrentLiab, totalLiabAndEquity, isBalanced),
                        ],
                      );
                    }
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCards(
    double totalAssets,
    double totalNonCurrentAssets,
    double totalCurrentAssets,
    double totalEquity,
    double totalNonCurrentLiab,
    double totalCurrentLiab,
    bool isBalanced,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_rounded, size: 20, color: Color(0xFF008060)),
                  const SizedBox(width: 8),
                  const Text('Balance Sheet Equation:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A))),
                  const SizedBox(width: 6),
                  Text('Assets = Equity + Liabilities', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isBalanced ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isBalanced ? const Color(0xFF86EFAC) : const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    Icon(isBalanced ? Icons.check_circle : Icons.error_outline, size: 14, color: isBalanced ? Colors.green : Colors.red),
                    const SizedBox(width: 4),
                    Text(
                      isBalanced ? 'Balanced Statement' : 'Variance Detected',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: isBalanced ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              _metricPill('Total Assets', totalAssets, const Color(0xFF008060)),
              _metricPill('Fixed & Non-Current', totalNonCurrentAssets, const Color(0xFF0284C7)),
              _metricPill('Liquid Current Assets', totalCurrentAssets, const Color(0xFF0D9488)),
              _metricPill('Shareholders\' Equity', totalEquity, const Color(0xFF7C3AED)),
              _metricPill('Long-Term Borrowings', totalNonCurrentLiab, const Color(0xFFD97706)),
              _metricPill('Current Liabilities', totalCurrentLiab, const Color(0xFFDC2626)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metricPill(String label, double amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
          Text(
            CurrencyService.format(amount),
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold, color: color, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetsCard(
    Color primaryColor,
    List ncAssetItems,
    double totalNonCurrentAssets,
    List cAssetItems,
    double totalCurrentAssets,
    double totalAssets,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.inventory_2_outlined, color: Color(0xFF008060), size: 20),
                SizedBox(width: 8),
                Text('ASSETS (Application of Funds)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF008060))),
              ],
            ),
            const Divider(height: 20),

            // Section 1: Non-Current Assets
            const Text(
              '1. Non-Current Assets (Fixed Assets & Investments)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF0284C7)),
            ),
            const SizedBox(height: 4),
            if (ncAssetItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('  No fixed capital assets recorded.', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
              )
            else
              ...ncAssetItems.map((a) {
                final double amt = double.tryParse((a['amount'] ?? 0).toString()) ?? 0.0;
                return _itemRow(a['name'] ?? 'Fixed Asset', amt, isSub: true);
              }),
            _subtotalRow('Subtotal Non-Current Assets', totalNonCurrentAssets, const Color(0xFF0284C7)),
            const Divider(height: 18),

            // Section 2: Current Assets
            const Text(
              '2. Current Assets (Liquid & Operational)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF0D9488)),
            ),
            const SizedBox(height: 4),
            ...cAssetItems.map((a) {
              final double amt = double.tryParse((a['amount'] ?? 0).toString()) ?? 0.0;
              return _itemRow(a['name'] ?? 'Current Asset', amt, isSub: true);
            }),
            _subtotalRow('Subtotal Current Assets', totalCurrentAssets, const Color(0xFF0D9488)),
            const Divider(height: 24),

            // Total Assets
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFBBF7D0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL ASSETS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF15803D))),
                  Text(
                    CurrencyService.format(totalAssets),
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Color(0xFF15803D), fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLiabilitiesCard(
    Color primaryColor,
    List eqItems,
    double totalEquity,
    List ncLiabItems,
    double totalNonCurrentLiab,
    List cLiabItems,
    double totalCurrentLiab,
    double totalLiabAndEquity,
    bool isBalanced,
  ) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF7C3AED), size: 20),
                SizedBox(width: 8),
                Text('LIABILITIES & CAPITAL (Source of Funds)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF7C3AED))),
              ],
            ),
            const Divider(height: 20),

            // Section 1: Shareholders' Equity
            const Text(
              '1. Shareholders\' Funds / Equity',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFF7C3AED)),
            ),
            const SizedBox(height: 4),
            ...eqItems.map((e) {
              final double amt = double.tryParse((e['amount'] ?? 0).toString()) ?? 0.0;
              return _itemRow(e['name'] ?? 'Equity', amt, isSub: true);
            }),
            _subtotalRow('Subtotal Equity / Net Worth', totalEquity, const Color(0xFF7C3AED)),
            const Divider(height: 18),

            // Section 2: Non-Current Liabilities
            const Text(
              '2. Non-Current Liabilities (Long-Term Debt)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFFD97706)),
            ),
            const SizedBox(height: 4),
            if (ncLiabItems.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: Text('  No active long-term bank loans.', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
              )
            else
              ...ncLiabItems.map((l) {
                final double amt = double.tryParse((l['amount'] ?? 0).toString()) ?? 0.0;
                return _itemRow(l['name'] ?? 'Long-Term Loan', amt, isSub: true);
              }),
            _subtotalRow('Subtotal Non-Current Debt', totalNonCurrentLiab, const Color(0xFFD97706)),
            const Divider(height: 18),

            // Section 3: Current Liabilities
            const Text(
              '3. Current Liabilities (Payables & Dues)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: Color(0xFFDC2626)),
            ),
            const SizedBox(height: 4),
            ...cLiabItems.map((l) {
              final double amt = double.tryParse((l['amount'] ?? 0).toString()) ?? 0.0;
              return _itemRow(l['name'] ?? 'Liability', amt, isSub: true);
            }),
            _subtotalRow('Subtotal Current Liabilities', totalCurrentLiab, const Color(0xFFDC2626)),
            const Divider(height: 24),

            // Total Liabilities & Equity
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isBalanced ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isBalanced ? const Color(0xFFBBF7D0) : const Color(0xFFFECACA)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('TOTAL LIABILITIES & EQUITY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF15803D))),
                  Text(
                    CurrencyService.format(totalLiabAndEquity),
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: isBalanced ? const Color(0xFF15803D) : const Color(0xFFB91C1C),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _itemRow(String name, double amount, {bool isSub = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.5, horizontal: isSub ? 8.0 : 0.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(fontSize: 12, color: isSub ? Colors.black87 : Colors.black),
            ),
          ),
          Text(
            CurrencyService.format(amount),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }

  Widget _subtotalRow(String label, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: color)),
          Text(
            CurrencyService.format(amount),
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: color, fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}
