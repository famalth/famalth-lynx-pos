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
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    ctrl.fetchBalanceSheet(outletId: widget.outletId);
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _showBalanceSheetInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.balance_rounded, color: Color(0xFF0B5CAD)),
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
                'Total Assets = Shareholders\' Equity + Non-Current Liabilities + Current Liabilities',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
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
                style: TextStyle(fontSize: 12, color: Color(0xFF475569), height: 1.45),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B5CAD))),
          ),
        ],
      ),
    );
  }

  bool _isNonCurrentAsset(Map item) {
    if (item['isFixedAsset'] == true || item['isInvestment'] == true) return true;
    final name = (item['name'] ?? '').toString().toLowerCase();
    final cat = (item['category'] ?? '').toString().toLowerCase();
    const keywords = [
      'fixed', 'infrastructure', 'machinery', 'equipment', 'vehicle', 'hardware',
      'investment', 'plant', 'building', 'land', 'furniture', 'fixtures', 'intangible',
      'computer', 'asset'
    ];
    for (final kw in keywords) {
      if (name.contains(kw) || cat.contains(kw)) {
        // Exclude current asset keywords like closing stock or tax credits
        if (name.contains('closing stock') || name.contains('cash') || name.contains('bank') || name.contains('debtor') || name.contains('receivable')) {
          continue;
        }
        return true;
      }
    }
    return false;
  }

  bool _isNonCurrentLiability(Map item) {
    final cat = (item['category'] ?? '').toString().toLowerCase();
    if (cat.contains('long-term') || cat.contains('long term')) return true;
    final name = (item['name'] ?? '').toString().toLowerCase();
    const keywords = ['loan', 'borrowing', 'term loan', 'debenture', 'mortgage', 'secured'];
    for (final kw in keywords) {
      if (name.contains(kw) || cat.contains(kw)) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    const primaryColor = Color(0xFF0B5CAD);
    const bgColor = Color(0xFFF4F6F9);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.account_balance_rounded, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Balance Sheet Statement',
                  style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Corporate Accounting Standard • Dual-Entry Architecture',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
                ),
              ],
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: primaryColor),
        actions: [
          IconButton(
            tooltip: 'Accounting Architecture Guide',
            icon: const Icon(Icons.info_outline, color: primaryColor),
            onPressed: () => _showBalanceSheetInfoDialog(context),
          ),
          IconButton(
            tooltip: 'Refresh Statement',
            icon: const Icon(Icons.refresh_rounded, color: primaryColor),
            onPressed: () => ctrl.fetchBalanceSheet(outletId: widget.outletId),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListenableBuilder(
        listenable: ctrl,
        builder: (context, _) {
          if (ctrl.loading) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: primaryColor),
                  SizedBox(height: 12),
                  Text('Loading financial ledger records...', style: TextStyle(color: Colors.grey, fontSize: 13)),
                ],
              ),
            );
          }

          final data = ctrl.balanceSheetData;
          final assetsClassified = data['assetsClassified'] as Map? ?? {};
          final liabClassified = data['liabilitiesAndEquityClassified'] as Map? ?? {};
          final totals = data['totals'] as Map? ?? {};

          // --- ASSETS CLASSIFICATION & PARSING ---
          List allRawAssets = [];
          if (assetsClassified.isNotEmpty && assetsClassified['nonCurrentAssets'] != null) {
            final ncList = (assetsClassified['nonCurrentAssets']['items'] as List? ?? []);
            final cList = (assetsClassified['currentAssets']?['items'] as List? ?? []);
            allRawAssets = [...ncList, ...cList];
          } else {
            allRawAssets = (data['assets'] as List? ?? []);
          }

          final List ncAssetItems = [];
          final List cAssetItems = [];

          for (final item in allRawAssets) {
            if (item is Map) {
              if (_isNonCurrentAsset(item)) {
                ncAssetItems.add(item);
              } else {
                cAssetItems.add(item);
              }
            }
          }

          // Compute subtotals for assets
          double totalNonCurrentAssets = 0.0;
          for (final item in ncAssetItems) {
            totalNonCurrentAssets += double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
          }

          double totalCurrentAssets = 0.0;
          for (final item in cAssetItems) {
            totalCurrentAssets += double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
          }

          final double totalAssets = double.tryParse((totals['totalAssets'] ?? (totalNonCurrentAssets + totalCurrentAssets)).toString()) ?? (totalNonCurrentAssets + totalCurrentAssets);

          // --- LIABILITIES & EQUITY CLASSIFICATION & PARSING ---
          List allRawLiabilities = [];
          if (liabClassified.isNotEmpty && (liabClassified['nonCurrentLiabilities'] != null || liabClassified['currentLiabilities'] != null)) {
            final ncLiabList = (liabClassified['nonCurrentLiabilities']?['items'] as List? ?? []);
            final cLiabList = (liabClassified['currentLiabilities']?['items'] as List? ?? []);
            allRawLiabilities = [...ncLiabList, ...cLiabList];
          } else {
            allRawLiabilities = (data['liabilities'] as List? ?? []);
          }

          final List ncLiabItems = [];
          final List cLiabItems = [];

          for (final item in allRawLiabilities) {
            if (item is Map) {
              if (_isNonCurrentLiability(item)) {
                ncLiabItems.add(item);
              } else {
                cLiabItems.add(item);
              }
            }
          }

          double totalNonCurrentLiab = 0.0;
          for (final item in ncLiabItems) {
            totalNonCurrentLiab += double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
          }

          double totalCurrentLiab = 0.0;
          for (final item in cLiabItems) {
            totalCurrentLiab += double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
          }

          final double totalLiabilities = totalNonCurrentLiab + totalCurrentLiab;

          // --- SHAREHOLDERS' EQUITY ---
          List eqItems = [];
          if (liabClassified['equity'] != null && liabClassified['equity']['items'] is List) {
            eqItems = liabClassified['equity']['items'] as List;
          } else if (data['equity'] is List) {
            eqItems = data['equity'] as List;
          }

          double totalEquity = 0.0;
          for (final item in eqItems) {
            if (item is Map) {
              totalEquity += double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
            }
          }

          // If equity was not explicitly provided, calculate balancing equity = Total Assets - Total Liabilities
          if (eqItems.isEmpty || (totalEquity == 0.0 && totalAssets > 0)) {
            totalEquity = totalAssets - totalLiabilities;
            eqItems = [
              {"name": "Owner's Capital Account (Net)", "amount": totalEquity, "category": "Capital"}
            ];
          }

          // Total Liabilities and Equity
          final double totalLiabAndEquity = totalEquity + totalLiabilities;
          final double variance = (totalAssets - totalLiabAndEquity).abs();
          final bool isBalanced = variance < 1.0;

          // Filter by search query if any
          List filteredNcAssets = ncAssetItems;
          List filteredCAssets = cAssetItems;
          List filteredEqItems = eqItems;
          List filteredNcLiab = ncLiabItems;
          List filteredCLiab = cLiabItems;

          if (_searchQuery.isNotEmpty) {
            filteredNcAssets = ncAssetItems.where((i) => (i['name'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();
            filteredCAssets = cAssetItems.where((i) => (i['name'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();
            filteredEqItems = eqItems.where((i) => (i['name'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();
            filteredNcLiab = ncLiabItems.where((i) => (i['name'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();
            filteredCLiab = cLiabItems.where((i) => (i['name'] ?? '').toString().toLowerCase().contains(_searchQuery)).toList();
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Executive Equation Header & Status Badge
                _buildEquationBanner(isBalanced, variance),
                const SizedBox(height: 14),

                // KPI Ribbon Cards
                _buildKpiRibbon(
                  totalAssets: totalAssets,
                  totalNonCurrentAssets: totalNonCurrentAssets,
                  totalCurrentAssets: totalCurrentAssets,
                  totalEquity: totalEquity,
                  totalNonCurrentLiab: totalNonCurrentLiab,
                  totalCurrentLiab: totalCurrentLiab,
                ),
                const SizedBox(height: 16),

                // Search Bar
                _buildSearchBar(),
                const SizedBox(height: 16),

                // Dual Pane Layout (Assets vs Liabilities & Capital)
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth > 900;
                    if (isDesktop) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildAssetsPanel(
                              ncAssetItems: filteredNcAssets,
                              totalNonCurrentAssets: totalNonCurrentAssets,
                              cAssetItems: filteredCAssets,
                              totalCurrentAssets: totalCurrentAssets,
                              totalAssets: totalAssets,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _buildLiabilitiesPanel(
                              eqItems: filteredEqItems,
                              totalEquity: totalEquity,
                              ncLiabItems: filteredNcLiab,
                              totalNonCurrentLiab: totalNonCurrentLiab,
                              cLiabItems: filteredCLiab,
                              totalCurrentLiab: totalCurrentLiab,
                              totalLiabAndEquity: totalLiabAndEquity,
                              isBalanced: isBalanced,
                            ),
                          ),
                        ],
                      );
                    } else {
                      return Column(
                        children: [
                          _buildAssetsPanel(
                            ncAssetItems: filteredNcAssets,
                            totalNonCurrentAssets: totalNonCurrentAssets,
                            cAssetItems: filteredCAssets,
                            totalCurrentAssets: totalCurrentAssets,
                            totalAssets: totalAssets,
                          ),
                          const SizedBox(height: 16),
                          _buildLiabilitiesPanel(
                            eqItems: filteredEqItems,
                            totalEquity: totalEquity,
                            ncLiabItems: filteredNcLiab,
                            totalNonCurrentLiab: totalNonCurrentLiab,
                            cLiabItems: filteredCLiab,
                            totalCurrentLiab: totalCurrentLiab,
                            totalLiabAndEquity: totalLiabAndEquity,
                            isBalanced: isBalanced,
                          ),
                        ],
                      );
                    }
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- Top Equation Header ---
  Widget _buildEquationBanner(bool isBalanced, double variance) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B5CAD).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calculate_outlined, color: Color(0xFF0B5CAD), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Fundamental Accounting Equation',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 2),
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(fontSize: 12, color: Color(0xFF475569)),
                          children: [
                            TextSpan(text: 'Total Assets', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF008060))),
                            TextSpan(text: '  =  '),
                            TextSpan(text: 'Shareholders\' Equity', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7C3AED))),
                            TextSpan(text: '  +  '),
                            TextSpan(text: 'Total Liabilities', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFD97706))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: isBalanced ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isBalanced ? const Color(0xFF86EFAC) : const Color(0xFFFECACA), width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isBalanced ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                  size: 16,
                  color: isBalanced ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                ),
                const SizedBox(width: 6),
                Text(
                  isBalanced ? 'STATUS: BALANCED' : 'VARIANCE: ${CurrencyService.format(variance)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                    color: isBalanced ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Executive KPI Ribbon ---
  Widget _buildKpiRibbon({
    required double totalAssets,
    required double totalNonCurrentAssets,
    required double totalCurrentAssets,
    required double totalEquity,
    required double totalNonCurrentLiab,
    required double totalCurrentLiab,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth > 1100
            ? (constraints.maxWidth - 48) / 5
            : constraints.maxWidth > 700
                ? (constraints.maxWidth - 24) / 3
                : (constraints.maxWidth - 12) / 2;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpiCard(
              title: 'TOTAL ASSETS',
              amount: totalAssets,
              icon: Icons.account_balance_wallet_outlined,
              color: const Color(0xFF008060),
              width: cardWidth,
            ),
            _kpiCard(
              title: 'FIXED & NON-CURRENT',
              amount: totalNonCurrentAssets,
              icon: Icons.domain_outlined,
              color: const Color(0xFF0284C7),
              width: cardWidth,
            ),
            _kpiCard(
              title: 'LIQUID CURRENT ASSETS',
              amount: totalCurrentAssets,
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFF0D9488),
              width: cardWidth,
            ),
            _kpiCard(
              title: 'SHAREHOLDERS\' EQUITY',
              amount: totalEquity,
              icon: Icons.pie_chart_outline_rounded,
              color: const Color(0xFF7C3AED),
              width: cardWidth,
            ),
            _kpiCard(
              title: 'TOTAL LIABILITIES',
              amount: totalNonCurrentLiab + totalCurrentLiab,
              subtitle: 'LT: ${CurrencyService.format(totalNonCurrentLiab)} | Cur: ${CurrencyService.format(totalCurrentLiab)}',
              icon: Icons.receipt_long_outlined,
              color: const Color(0xFFD97706),
              width: cardWidth,
            ),
          ],
        );
      },
    );
  }

  Widget _kpiCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
    required double width,
    String? subtitle,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.015),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Colors.grey.shade600,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(icon, size: 14, color: color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            CurrencyService.format(amount),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
              color: color,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  // --- Search Bar ---
  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Filter ledger accounts, fixed assets, or liability items...',
          hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
          prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFF0B5CAD)),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () => _searchCtrl.clear(),
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  // --- Left Panel: ASSETS ---
  Widget _buildAssetsPanel({
    required List ncAssetItems,
    required double totalNonCurrentAssets,
    required List cAssetItems,
    required double totalCurrentAssets,
    required double totalAssets,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF008060).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF008060), size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'ASSETS',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5, color: Color(0xFF008060)),
                ),
                const SizedBox(width: 6),
                const Text(
                  '(Application of Funds)',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Non-Current Assets Header
                _sectionHeaderBadge(
                  title: '1. NON-CURRENT ASSETS',
                  subtitle: 'Fixed Capital Assets, Property & Long-Term Investments',
                  color: const Color(0xFF0284C7),
                  icon: Icons.domain_rounded,
                ),
                const SizedBox(height: 8),

                if (ncAssetItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    child: Text('No fixed capital assets or investments recorded.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                  )
                else
                  ...ncAssetItems.map((item) {
                    final double amt = double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
                    return _ledgerRow(
                      name: item['name'] ?? 'Fixed Asset',
                      amount: amt,
                      category: item['category'] ?? 'Fixed Assets',
                      gross: item['grossAmount'] != null ? double.tryParse(item['grossAmount'].toString()) : null,
                      depreciation: item['depreciation'] != null ? double.tryParse(item['depreciation'].toString()) : null,
                    );
                  }),

                const SizedBox(height: 4),
                _subtotalBar('Subtotal Non-Current Assets', totalNonCurrentAssets, const Color(0xFF0284C7)),
                const SizedBox(height: 20),

                // 2. Current Assets Header
                _sectionHeaderBadge(
                  title: '2. CURRENT ASSETS',
                  subtitle: 'Liquid Operational Assets, Inventories, Debtors, Cash & Bank',
                  color: const Color(0xFF0D9488),
                  icon: Icons.inventory_2_rounded,
                ),
                const SizedBox(height: 8),

                if (cAssetItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    child: Text('No current operational assets recorded.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                  )
                else
                  ...cAssetItems.map((item) {
                    final double amt = double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
                    return _ledgerRow(
                      name: item['name'] ?? 'Current Asset',
                      amount: amt,
                      category: item['category'] ?? 'Operational Assets',
                    );
                  }),

                const SizedBox(height: 4),
                _subtotalBar('Subtotal Current Assets', totalCurrentAssets, const Color(0xFF0D9488)),
                const SizedBox(height: 24),

                // TOTAL ASSETS
                _grandTotalBar(
                  label: 'TOTAL ASSETS',
                  amount: totalAssets,
                  color: const Color(0xFF008060),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Right Panel: LIABILITIES & EQUITY ---
  Widget _buildLiabilitiesPanel({
    required List eqItems,
    required double totalEquity,
    required List ncLiabItems,
    required double totalNonCurrentLiab,
    required List cLiabItems,
    required double totalCurrentLiab,
    required double totalLiabAndEquity,
    required bool isBalanced,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section Title Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.pie_chart_rounded, color: Color(0xFF7C3AED), size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'LIABILITIES & CAPITAL',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, letterSpacing: 0.5, color: Color(0xFF7C3AED)),
                ),
                const SizedBox(width: 6),
                const Text(
                  '(Source of Funds)',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Shareholders' Equity Header
                _sectionHeaderBadge(
                  title: '1. SHAREHOLDERS\' FUNDS / EQUITY',
                  subtitle: 'Owner\'s Capital, Retained Earnings & Current Year PAT',
                  color: const Color(0xFF7C3AED),
                  icon: Icons.account_circle_rounded,
                ),
                const SizedBox(height: 8),

                if (eqItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    child: Text('No capital equity recorded.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                  )
                else
                  ...eqItems.map((item) {
                    final double amt = double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
                    return _ledgerRow(
                      name: item['name'] ?? 'Equity',
                      amount: amt,
                      category: item['category'] ?? 'Shareholders\' Funds',
                      isEquity: true,
                    );
                  }),

                const SizedBox(height: 4),
                _subtotalBar('Subtotal Shareholders\' Equity / Net Worth', totalEquity, const Color(0xFF7C3AED)),
                const SizedBox(height: 20),

                // 2. Non-Current Liabilities Header
                _sectionHeaderBadge(
                  title: '2. NON-CURRENT LIABILITIES',
                  subtitle: 'Long-Term Bank Borrowings & Secured Debt Obligations',
                  color: const Color(0xFFD97706),
                  icon: Icons.account_balance_rounded,
                ),
                const SizedBox(height: 8),

                if (ncLiabItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    child: Text('No active long-term borrowings or bank loans.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                  )
                else
                  ...ncLiabItems.map((item) {
                    final double amt = double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
                    return _ledgerRow(
                      name: item['name'] ?? 'Long-Term Loan',
                      amount: amt,
                      category: item['category'] ?? 'Long-Term Borrowings',
                    );
                  }),

                const SizedBox(height: 4),
                _subtotalBar('Subtotal Non-Current Debt', totalNonCurrentLiab, const Color(0xFFD97706)),
                const SizedBox(height: 20),

                // 3. Current Liabilities Header
                _sectionHeaderBadge(
                  title: '3. CURRENT LIABILITIES',
                  subtitle: 'Trade Payables, Vendor Dues, Customer Advances & Statutory GST',
                  color: const Color(0xFFDC2626),
                  icon: Icons.receipt_rounded,
                ),
                const SizedBox(height: 8),

                if (cLiabItems.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                    child: Text('No current payable liabilities recorded.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
                  )
                else
                  ...cLiabItems.map((item) {
                    final double amt = double.tryParse((item['amount'] ?? 0).toString()) ?? 0.0;
                    return _ledgerRow(
                      name: item['name'] ?? 'Current Liability',
                      amount: amt,
                      category: item['category'] ?? 'Current Liabilities',
                    );
                  }),

                const SizedBox(height: 4),
                _subtotalBar('Subtotal Current Liabilities', totalCurrentLiab, const Color(0xFFDC2626)),
                const SizedBox(height: 24),

                // TOTAL LIABILITIES & EQUITY
                _grandTotalBar(
                  label: 'TOTAL LIABILITIES & EQUITY',
                  amount: totalLiabAndEquity,
                  color: isBalanced ? const Color(0xFF008060) : const Color(0xFFDC2626),
                  isBalanced: isBalanced,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- Sub-Components ---

  Widget _sectionHeaderBadge({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: color, letterSpacing: 0.3),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
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

  Widget _ledgerRow({
    required String name,
    required double amount,
    String? category,
    double? gross,
    double? depreciation,
    bool isEquity = false,
  }) {
    final bool isNegative = amount < 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                ),
                if (gross != null && depreciation != null && depreciation > 0) ...[
                  const SizedBox(height: 1),
                  Text(
                    'Gross: ${CurrencyService.format(gross)}  •  Depreciation: -${CurrencyService.format(depreciation)}',
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
                  ),
                ] else if (category != null && category.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    category,
                    style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            isNegative ? '-${CurrencyService.format(amount.abs())}' : CurrencyService.format(amount),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
              color: isNegative ? const Color(0xFFDC2626) : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _subtotalBar(String label, double amount, Color color) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11.5, color: color),
          ),
          Text(
            CurrencyService.format(amount),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              fontFamily: 'monospace',
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _grandTotalBar({
    required String label,
    required double amount,
    required Color color,
    bool isBalanced = true,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isBalanced ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isBalanced ? const Color(0xFF86EFAC) : const Color(0xFFFECACA), width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(
                isBalanced ? Icons.verified_rounded : Icons.warning_amber_rounded,
                size: 20,
                color: isBalanced ? const Color(0xFF15803D) : const Color(0xFFDC2626),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  letterSpacing: 0.5,
                  color: isBalanced ? const Color(0xFF15803D) : const Color(0xFFDC2626),
                ),
              ),
            ],
          ),
          Text(
            CurrencyService.format(amount),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
              fontFamily: 'monospace',
              color: isBalanced ? const Color(0xFF15803D) : const Color(0xFFDC2626),
            ),
          ),
        ],
      ),
    );
  }
}
