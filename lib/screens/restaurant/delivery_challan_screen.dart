import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import '../../models/inventory/item_model.dart';
import '../../controllers/inventory/item_controller.dart';
import '../../controllers/restaurant/restaurant_controller.dart';
import '../../controllers/transport/transport_controller.dart';
import '../../core/printing/pos_invoice_printer.dart';
import '../../core/utils/geo_helper.dart';
import '../inventory/salescreen.dart';

class DeliveryChallanScreen extends StatefulWidget {
  const DeliveryChallanScreen({super.key});

  @override
  State<DeliveryChallanScreen> createState() => _DeliveryChallanScreenState();
}

class _DeliveryChallanScreenState extends State<DeliveryChallanScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ItemController _itemController = ItemController();
  final TextEditingController _searchCtrl = TextEditingController();
  String _selectedStatusFilter = 'ALL';
  String _selectedDateFilter = 'ALL'; // 'ALL', 'TODAY', 'WEEK', 'MONTH', 'CUSTOM'
  DateTimeRange? _customDateRange;
  bool _isInit = false;

  final NumberFormat _qtyFmt = NumberFormat.decimalPattern();

  // Multi-challan trip selection state
  final Set<int> _selectedChallanIdsForTrip = {};
  int? _tripVehicleId;
  int? _tripDriverId;
  final TextEditingController _tripEWayBillCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    _tripEWayBillCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _registeredCustomers = [];

  Future<void> _loadData() async {
    final restCtrl = Provider.of<RestaurantController>(context, listen: false);
    final transportCtrl = Provider.of<TransportController>(context, listen: false);

    await Future.wait([
      restCtrl.loadChallans(),
      transportCtrl.loadVehicles(),
      transportCtrl.loadDrivers(),
      transportCtrl.loadActiveTrips(),
      _itemController.load(),
      _loadRegisteredCustomers(),
    ]);
    if (mounted) {
      setState(() => _isInit = true);
    }
  }

  Future<void> _loadRegisteredCustomers() async {
    try {
      final res = await ApiClient.get(ApiEndpoints.salesCustomers, silent: true);
      if (res['success'] == true && res['data'] is List) {
        _registeredCustomers = List<Map<String, dynamic>>.from(res['data']);
      }
    } catch (_) {}
  }

  List<dynamic> _getDateFilteredChallans(List<dynamic> list) {
    if (_selectedDateFilter == 'ALL') return list;

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7)).subtract(const Duration(milliseconds: 1));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0, 23, 59, 59, 999);

    return list.where((item) {
      final rawDate = item['challan_date'] ?? item['created_at'];
      if (rawDate == null) return false;
      final dt = DateTime.tryParse(rawDate.toString())?.toLocal();
      if (dt == null) return false;

      if (_selectedDateFilter == 'TODAY') {
        return !dt.isBefore(todayStart) && !dt.isAfter(todayEnd);
      } else if (_selectedDateFilter == 'WEEK') {
        return !dt.isBefore(weekStart) && !dt.isAfter(weekEnd);
      } else if (_selectedDateFilter == 'MONTH') {
        return !dt.isBefore(monthStart) && !dt.isAfter(monthEnd);
      } else if (_selectedDateFilter == 'CUSTOM' && _customDateRange != null) {
        final start = DateTime(_customDateRange!.start.year, _customDateRange!.start.month, _customDateRange!.start.day);
        final end = DateTime(_customDateRange!.end.year, _customDateRange!.end.month, _customDateRange!.end.day, 23, 59, 59, 999);
        return !dt.isBefore(start) && !dt.isAfter(end);
      }
      return true;
    }).toList();
  }

  List<dynamic> _getFilteredChallans(List<dynamic> list) {
    final dateFiltered = _getDateFilteredChallans(list);
    final query = _searchCtrl.text.trim().toLowerCase();
    return dateFiltered.where((item) {
      final status = (item['status'] ?? '').toString().toUpperCase();
      final deliveryStatus = (item['delivery_status'] ?? '').toString().toUpperCase();

      if (_selectedStatusFilter == 'ISSUED' && (status != 'ISSUED' && deliveryStatus != 'PENDING')) return false;
      if (_selectedStatusFilter == 'IN_TRANSIT' && deliveryStatus != 'IN_TRANSIT') return false;
      if (_selectedStatusFilter == 'DELIVERED' && deliveryStatus != 'DELIVERED') return false;
      if (_selectedStatusFilter == 'CONVERTED' && status != 'CONVERTED_TO_SALE') return false;

      if (query.isEmpty) return true;
      final challanNo = (item['challan_no'] ?? '').toString().toLowerCase();
      final customer = (item['customer_name'] ?? '').toString().toLowerCase();
      final phone = (item['customer_phone'] ?? '').toString().toLowerCase();
      final vehicle = (item['vehicle_number'] ?? '').toString().toLowerCase();
      final driver = (item['driver_name'] ?? '').toString().toLowerCase();
      return challanNo.contains(query) ||
          customer.contains(query) ||
          phone.contains(query) ||
          vehicle.contains(query) ||
          driver.contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RestaurantController>();
    final transportCtrl = context.watch<TransportController>();
    final allChallans = ctrl.challans;
    final dateFiltered = _getDateFilteredChallans(allChallans);
    final filteredList = _getFilteredChallans(allChallans);

    final totalCount = dateFiltered.length;
    final inTransitCount = dateFiltered.where((c) => (c['delivery_status'] ?? '').toString().toUpperCase() == 'IN_TRANSIT').length;
    final deliveredCount = dateFiltered.where((c) => (c['delivery_status'] ?? '').toString().toUpperCase() == 'DELIVERED').length;
    final pendingCount = dateFiltered.where((c) => c['status'] == 'Issued').length;
    final totalDispatchedQty = dateFiltered.fold<double>(
      0.0,
      (sum, c) => sum + (double.tryParse(c['total_qty']?.toString() ?? '0') ?? 0.0),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.local_shipping, color: Color(0xFF008060)),
            SizedBox(width: 10),
            Text(
              'Delivery Challan & Transportation Fleet Hub',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh All Logistics & Challans',
            onPressed: _loadData,
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF008060),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => _openIssueChallanDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text(
                'Issue Delivery Challan',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF008060),
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: const Color(0xFF008060),
          indicatorWeight: 3,
          tabs: [
            Tab(
              icon: const Icon(Icons.description_outlined),
              text: 'Delivery Challans (${allChallans.length})',
            ),
            Tab(
              icon: const Icon(Icons.rv_hookup),
              text: 'Fleet / Trucks (${transportCtrl.vehicles.length})',
            ),
            Tab(
              icon: const Icon(Icons.badge_outlined),
              text: 'Drivers (${transportCtrl.drivers.length})',
            ),
            Tab(
              icon: const Icon(Icons.alt_route_outlined),
              text: 'Dispatch Manifest & Trips (${transportCtrl.activeTrips.length})',
            ),
          ],
        ),
      ),
      body: ctrl.loading && !_isInit
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                // TAB 1: DELIVERY CHALLANS LIST
                _buildChallansTab(
                  allChallans,
                  filteredList,
                  totalCount,
                  inTransitCount,
                  deliveredCount,
                  pendingCount,
                  totalDispatchedQty,
                  ctrl,
                  transportCtrl,
                ),

                // TAB 2: TRUCKS & VEHICLES
                _buildVehiclesTab(transportCtrl),

                // TAB 3: DRIVER PROFILES
                _buildDriversTab(transportCtrl),

                // TAB 4: DISPATCH MANIFEST & MULTI-CHALLAN GROUPING
                _buildDispatchManifestTab(allChallans, transportCtrl),
              ],
            ),
    );
  }

  // =========================================================================
  // TAB 1: DELIVERY CHALLANS LIST
  // =========================================================================
  Widget _buildChallansTab(
    List<dynamic> allChallans,
    List<dynamic> filteredList,
    int totalCount,
    int inTransitCount,
    int deliveredCount,
    int pendingCount,
    double totalDispatchedQty,
    RestaurantController ctrl,
    TransportController transportCtrl,
  ) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KPI Metrics Row (Responsive Layout)
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 900;
                if (isWide) {
                  return Row(
                    children: [
                      _buildKpiCard(
                        title: 'Total Challans Issued',
                        value: '$totalCount',
                        subtitle: '${_qtyFmt.format(totalDispatchedQty)} Units Dispatched',
                        icon: Icons.local_shipping_outlined,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 12),
                      _buildKpiCard(
                        title: 'In-Transit on Trucks',
                        value: '$inTransitCount',
                        subtitle: 'En route with Drivers',
                        icon: Icons.directions_bus_filled_outlined,
                        color: Colors.indigo,
                      ),
                      const SizedBox(width: 12),
                      _buildKpiCard(
                        title: 'Delivered (OTP Verified)',
                        value: '$deliveredCount',
                        subtitle: 'Successfully Received',
                        icon: Icons.task_alt,
                        color: Colors.teal,
                      ),
                      const SizedBox(width: 12),
                      _buildKpiCard(
                        title: 'Pending Invoicing',
                        value: '$pendingCount',
                        subtitle: 'Ready to Convert to Sale',
                        icon: Icons.pending_actions_outlined,
                        color: Colors.orange,
                      ),
                    ],
                  );
                }

                final cardWidth = constraints.maxWidth > 550
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildKpiCard(
                      title: 'Total Challans Issued',
                      value: '$totalCount',
                      subtitle: '${_qtyFmt.format(totalDispatchedQty)} Units Dispatched',
                      icon: Icons.local_shipping_outlined,
                      color: Colors.blue,
                      width: cardWidth,
                    ),
                    _buildKpiCard(
                      title: 'In-Transit on Trucks',
                      value: '$inTransitCount',
                      subtitle: 'En route with Drivers',
                      icon: Icons.directions_bus_filled_outlined,
                      color: Colors.indigo,
                      width: cardWidth,
                    ),
                    _buildKpiCard(
                      title: 'Delivered (OTP Verified)',
                      value: '$deliveredCount',
                      subtitle: 'Successfully Received',
                      icon: Icons.task_alt,
                      color: Colors.teal,
                      width: cardWidth,
                    ),
                    _buildKpiCard(
                      title: 'Pending Invoicing',
                      value: '$pendingCount',
                      subtitle: 'Ready to Convert to Sale',
                      icon: Icons.pending_actions_outlined,
                      color: Colors.orange,
                      width: cardWidth,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Search & Filter Toolbar (Responsive Status & Date Filters)
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Search by Challan #, Customer Name, Phone, Truck #, or Driver...',
                        hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        border: InputBorder.none,
                        suffixIcon: _searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                    ),
                    const Divider(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        // Status Filter Chips
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildFilterChip('ALL', 'All Status', _selectedStatusFilter == 'ALL', (v) {
                              setState(() => _selectedStatusFilter = 'ALL');
                            }),
                            _buildFilterChip('IN_TRANSIT', 'In-Transit', _selectedStatusFilter == 'IN_TRANSIT', (v) {
                              setState(() => _selectedStatusFilter = 'IN_TRANSIT');
                            }),
                            _buildFilterChip('DELIVERED', 'Delivered', _selectedStatusFilter == 'DELIVERED', (v) {
                              setState(() => _selectedStatusFilter = 'DELIVERED');
                            }),
                            _buildFilterChip('ISSUED', 'Pending Sale', _selectedStatusFilter == 'ISSUED', (v) {
                              setState(() => _selectedStatusFilter = 'ISSUED');
                            }),
                          ],
                        ),
                        // Date Filter Chips: Today, Week, Month, Date Range
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _buildDateChip('ALL', 'All Dates'),
                            _buildDateChip('TODAY', 'Today'),
                            _buildDateChip('WEEK', 'This Week'),
                            _buildDateChip('MONTH', 'This Month'),
                            _buildCustomDateChip(),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Challan Table
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: filteredList.isEmpty
                    ? Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(40),
                        color: Colors.white,
                        child: Column(
                          children: [
                            Icon(Icons.local_shipping_outlined, size: 54, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No Delivery Challans Found',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Click "Issue Delivery Challan" to dispatch goods to a retailer or client.',
                              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : Container(
                        color: Colors.white,
                        width: double.infinity,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                          headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                          dataRowMaxHeight: 76,
                          columns: const [
                            DataColumn(label: Text('Challan No & Date', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Customer / Retailer', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Dispatched Qty', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Assigned Truck & Driver', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Delivery Status & OTP', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: filteredList.map((item) {
                            final stUpper = (item['status'] ?? '').toString().toUpperCase();
                            final isIssued = stUpper != 'CONVERTED_TO_SALE' && stUpper != 'CANCELLED' && stUpper != 'RETURNED';
                            final deliveryStatus = (item['delivery_status'] ?? 'PENDING').toString().toUpperCase();
                            final dateStr = item['challan_date'] != null
                                ? DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.parse(item['challan_date']))
                                : 'N/A';

                            final vehicleNo = item['vehicle_number'] ?? 'Unassigned';
                            final driverName = item['driver_name'] ?? 'No Driver';
                            final driverPhone = item['driver_phone'] ?? '';
                            final otp = item['delivery_otp'];

                            return DataRow(
                              cells: [
                                // Challan No & Date
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['challan_no'] ?? 'N/A',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo),
                                      ),
                                      Text(dateStr, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                      if (item['e_way_bill_no'] != null && item['e_way_bill_no'].toString().isNotEmpty)
                                        Text('E-Way: ${item['e_way_bill_no']}', style: const TextStyle(fontSize: 10, color: Colors.blueGrey)),
                                    ],
                                  ),
                                ),

                                // Customer / Retailer
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item['customer_name'] ?? 'Walk-in Customer',
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      ),
                                      Text(
                                        item['customer_phone'] ?? 'No Phone',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                      ),
                                    ],
                                  ),
                                ),

                                // Dispatched Qty
                                DataCell(
                                  Text(
                                    '${item['total_qty'] ?? 0} Units',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),

                                // Assigned Truck & Driver
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.fire_truck_outlined,
                                            size: 15,
                                            color: vehicleNo != 'Unassigned' ? Colors.indigo : Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            vehicleNo,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                              color: vehicleNo != 'Unassigned' ? Colors.indigo.shade900 : Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.person_pin,
                                            size: 14,
                                            color: driverName != 'No Driver' ? Colors.teal : Colors.grey,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            driverName + (driverPhone.isNotEmpty ? ' ($driverPhone)' : ''),
                                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Delivery Status & OTP
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _getDeliveryStatusBg(deliveryStatus),
                                          border: Border.all(color: _getDeliveryStatusBorder(deliveryStatus)),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _getDeliveryStatusLabel(deliveryStatus),
                                          style: TextStyle(
                                            color: _getDeliveryStatusTextColor(deliveryStatus),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                      if (otp != null && deliveryStatus == 'IN_TRANSIT') ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'OTP: $otp',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                            color: Color(0xFF008060),
                                          ),
                                        ),
                                      ],
                                      if (deliveryStatus == 'DELIVERED' && item['delivered_at'] != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          DateFormat('dd-MM hh:mm a').format(DateTime.parse(item['delivered_at'])),
                                          style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),

                                // Actions
                                DataCell(
                                  Row(
                                    children: [
                                      // Print Challan Bill
                                      IconButton(
                                        icon: const Icon(Icons.print_outlined, color: Colors.indigo),
                                        tooltip: 'Print Delivery Challan & Dispatch Bill',
                                        onPressed: () => _printChallanToPrinter(context, item['id']),
                                      ),

                                      // If In-Transit or Pending, show Delivery Verification (OTP / Submit)
                                      if (deliveryStatus != 'DELIVERED') ...[
                                        IconButton(
                                          icon: const Icon(Icons.verified_outlined, color: Color(0xFF008060)),
                                          tooltip: 'Verify OTP / Confirm Delivered',
                                          onPressed: () => _openVerifyDeliveryDialog(item),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.assignment_ind_outlined, color: Colors.deepPurple),
                                          tooltip: 'Assign Truck & Driver',
                                          onPressed: () => _openAssignTransportDialog(item),
                                        ),
                                      ],

                                      // Convert to Final Sales Invoice
                                      if (isIssued) ...[
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: const Color(0xFF008060),
                                            side: const BorderSide(color: Color(0xFF008060)),
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          onPressed: () => _openInBillingScreen(context, item['id']),
                                          icon: const Icon(Icons.point_of_sale, size: 14),
                                          label: const Text('Issue Bill', style: TextStyle(fontSize: 11)),
                                        ),
                                        const SizedBox(width: 4),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF008060),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          onPressed: () async {
                                            final success = await ctrl.updateChallanStatus(item['id'], 'Converted_To_Sale');
                                            if (success && context.mounted) {
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Delivery Challan converted to final Sales Invoice!'),
                                                  backgroundColor: Color(0xFF008060),
                                                ),
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.check, size: 14),
                                          label: const Text('Convert', style: TextStyle(fontSize: 11)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // TAB 2: TRUCKS & VEHICLES FLEET MANAGEMENT
  // =========================================================================
  Widget _buildVehiclesTab(TransportController transportCtrl) {
    final list = transportCtrl.vehicles;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Company Transportation & Fleet Directory',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Manage Trucks, Tippers, Trailers, LCVs, and Pickups for factory and distributor supply.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                onPressed: () => _openVehicleDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Vehicle / Truck'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (list.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.rv_hookup, size: 54, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No Vehicles Saved in Fleet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Click "Add Vehicle / Truck" to register your delivery trucks and vehicles.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          else
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.white,
                  width: double.infinity,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                    dataRowMaxHeight: 64,
                    columns: const [
                      DataColumn(label: Text('Vehicle Number & Type', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Capacity / Tonnage', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Model / Specs', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Current Driver', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: list.map((v) {
                      final status = (v['status'] ?? 'AVAILABLE').toString().toUpperCase();
                      final isBooked = status == 'BOOKED' || status == 'IN_TRANSIT';
                      final driver = v['current_driver'];

                      return DataRow(
                        cells: [
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  v['vehicle_number'] ?? 'N/A',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo),
                                ),
                                Text(
                                  v['vehicle_type'] ?? 'Truck',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Text(
                              '${v['capacity_tonnage'] ?? 0} ${v['capacity_unit'] ?? 'Tons'}',
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          DataCell(Text(v['model'] ?? 'Standard')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isBooked ? Colors.orange.shade50 : Colors.green.shade50,
                                border: Border.all(color: isBooked ? Colors.orange.shade300 : Colors.green.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isBooked ? 'BOOKED / IN-TRANSIT' : 'AVAILABLE',
                                style: TextStyle(
                                  color: isBooked ? Colors.orange.shade900 : Colors.green.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            driver != null
                                ? Text('${driver['driver_name']} (${driver['phone']})', style: const TextStyle(fontWeight: FontWeight.w600))
                                : Text('None', style: TextStyle(color: Colors.grey.shade500)),
                          ),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.indigo),
                                  tooltip: 'Edit Vehicle',
                                  onPressed: () => _openVehicleDialog(existing: v),
                                ),
                                if (isBooked)
                                  IconButton(
                                    icon: const Icon(Icons.lock_open, size: 18, color: Colors.orange),
                                    tooltip: 'Mark Available (Release Trip)',
                                    onPressed: () async {
                                      await transportCtrl.releaseTrip(vehicleId: v['id']);
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  tooltip: 'Delete Vehicle',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete Vehicle'),
                                        content: Text('Are you sure you want to remove vehicle ${v['vehicle_number']}?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await transportCtrl.deleteVehicle(v['id']);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 3: DRIVER PROFILES MANAGEMENT
  // =========================================================================
  Widget _buildDriversTab(TransportController transportCtrl) {
    final list = transportCtrl.drivers;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Company Drivers Directory',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Driver profiles with mobile phone, driving license, and live booking availability.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                onPressed: () => _openDriverDialog(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Driver Profile'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (list.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Icon(Icons.badge_outlined, size: 54, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('No Drivers Registered', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  const Text('Click "Add Driver Profile" to register your transportation drivers.', style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          else
            Card(
              elevation: 0.5,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  color: Colors.white,
                  width: double.infinity,
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF1F5F9)),
                    dataRowMaxHeight: 64,
                    columns: const [
                      DataColumn(label: Text('Driver Name', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Mobile Phone', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Driving License #', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Booking Status', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Assigned Vehicle', style: TextStyle(fontWeight: FontWeight.bold))),
                      DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                    ],
                    rows: list.map((d) {
                      final status = (d['status'] ?? 'AVAILABLE').toString().toUpperCase();
                      final isBooked = status == 'BOOKED' || status == 'ON_TRIP';
                      final vehicle = d['current_vehicle'];

                      return DataRow(
                        cells: [
                          DataCell(
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: const Color(0xFF008060).withValues(alpha: 0.1),
                                  child: Text(
                                    (d['driver_name'] ?? 'D')[0].toUpperCase(),
                                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF008060)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  d['driver_name'] ?? 'N/A',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                          DataCell(
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d['phone'] ?? 'N/A'),
                                if ((d['email'] ?? '').toString().trim().isNotEmpty)
                                  Text(
                                    d['email'].toString(),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                              ],
                            ),
                          ),
                          DataCell(Text(d['license_number'] ?? 'Standard DL')),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: isBooked ? Colors.orange.shade50 : Colors.green.shade50,
                                border: Border.all(color: isBooked ? Colors.orange.shade300 : Colors.green.shade300),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isBooked ? 'BOOKED ON TRIP' : 'AVAILABLE',
                                style: TextStyle(
                                  color: isBooked ? Colors.orange.shade900 : Colors.green.shade900,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            vehicle != null
                                ? Text('${vehicle['vehicle_number']} (${vehicle['vehicle_type']})', style: const TextStyle(fontWeight: FontWeight.w600))
                                : Text('None', style: TextStyle(color: Colors.grey.shade500)),
                          ),
                          DataCell(
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, size: 18, color: Colors.indigo),
                                  tooltip: 'Edit Driver Profile',
                                  onPressed: () => _openDriverDialog(existing: d),
                                ),
                                if (isBooked)
                                  IconButton(
                                    icon: const Icon(Icons.lock_open, size: 18, color: Colors.orange),
                                    tooltip: 'Mark Available (Release Driver)',
                                    onPressed: () async {
                                      await transportCtrl.releaseTrip(driverId: d['id']);
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  tooltip: 'Delete Driver',
                                  onPressed: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Delete Driver Profile'),
                                        content: Text('Are you sure you want to remove driver ${d['driver_name']}?'),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                          FilledButton(
                                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Delete'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      await transportCtrl.deleteDriver(d['id']);
                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 4: DISPATCH MANIFEST & MULTI-CHALLAN GROUPING PER TRUCK
  // =========================================================================
  Widget _buildDispatchManifestTab(List<dynamic> allChallans, TransportController transportCtrl) {
    // Only pending/unassigned challans can be grouped into new dispatch
    final pendingChallans = allChallans.where((c) {
      final delStatus = (c['delivery_status'] ?? 'PENDING').toString().toUpperCase();
      final hasTrip = (c['trip_id'] != null && c['trip_id'].toString().trim().isNotEmpty);
      return delStatus != 'DELIVERED' && delStatus != 'IN_TRANSIT' && !hasTrip && c['status'] != 'Converted_To_Sale';
    }).toList();

    final fleetVehicles = transportCtrl.vehicles.where((v) => (v['status'] ?? 'AVAILABLE') != 'MAINTENANCE').toList();
    final fleetDrivers = transportCtrl.drivers.where((d) => (d['status'] ?? 'AVAILABLE') != 'TERMINATED' && (d['status'] ?? 'AVAILABLE') != 'INACTIVE').toList();
    final activeTrips = transportCtrl.activeTrips;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dispatch Trip Box
          Card(
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.alt_route, color: Color(0xFF008060)),
                      SizedBox(width: 8),
                      Text(
                        'Dispatch Multi-Challan Truck Trip',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Load multiple Delivery Challans destined for different retailers/sites into one Truck, assign a driver, and dispatch with unique OTPs.',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      // Select Vehicle
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _tripVehicleId,
                          decoration: const InputDecoration(
                            labelText: 'Select Truck / Vehicle *',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.rv_hookup, size: 20),
                          ),
                          items: fleetVehicles.map<DropdownMenuItem<int>>((v) {
                            final isAvailable = (v['status'] ?? 'AVAILABLE') == 'AVAILABLE';
                            return DropdownMenuItem<int>(
                              value: v['id'],
                              child: Text(
                                '${v['vehicle_number']} (${v['vehicle_type']} • ${isAvailable ? 'Available' : 'On Trip: Add Consignment'})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _tripVehicleId = val;
                              // If vehicle is already on trip, auto-select its current driver
                              if (val != null) {
                                final selectedVehicle = fleetVehicles.firstWhere((v) => v['id'] == val, orElse: () => {});
                                if (selectedVehicle['current_driver_id'] != null) {
                                  _tripDriverId = selectedVehicle['current_driver_id'];
                                }
                              }
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Select Driver
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _tripDriverId,
                          decoration: const InputDecoration(
                            labelText: 'Select Driver *',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.person_pin, size: 20),
                          ),
                          items: fleetDrivers.map<DropdownMenuItem<int>>((d) {
                            final isAvailable = (d['status'] ?? 'AVAILABLE') == 'AVAILABLE';
                            return DropdownMenuItem<int>(
                              value: d['id'],
                              child: Text(
                                '${d['driver_name']} (Ph: ${d['phone']} • ${isAvailable ? 'Available' : 'On Trip'})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: (val) => setState(() => _tripDriverId = val),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // E-Way Bill Number (Optional)
                      Expanded(
                        child: TextField(
                          controller: _tripEWayBillCtrl,
                          decoration: const InputDecoration(
                            labelText: 'E-Way Bill No (Optional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                            prefixIcon: Icon(Icons.confirmation_number_outlined, size: 20),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Select Challans Checklist
                  const Text(
                    'Select Delivery Challans to Load into this Truck:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),

                  if (pendingChallans.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                      child: const Center(child: Text('No pending delivery challans available for dispatch.', style: TextStyle(color: Colors.grey))),
                    )
                  else
                    Container(
                      height: 180,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: pendingChallans.length,
                        itemBuilder: (context, idx) {
                          final c = pendingChallans[idx];
                          final id = c['id'] as int;
                          final isChecked = _selectedChallanIdsForTrip.contains(id);

                          return CheckboxListTile(
                            dense: true,
                            value: isChecked,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selectedChallanIdsForTrip.add(id);
                                } else {
                                  _selectedChallanIdsForTrip.remove(id);
                                }
                              });
                            },
                            title: Text(
                              '${c['challan_no']} - ${c['customer_name']} (Qty: ${c['total_qty']} Units)',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            subtitle: Text(
                              'Destination: ${c['destination_address'] ?? 'Customer Address'} | Current: ${c['delivery_status'] ?? 'Pending'}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),

                  // Submit Dispatch Button
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF008060),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                      onPressed: () async {
                        if (_tripVehicleId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a Truck/Vehicle')));
                          return;
                        }
                        if (_tripDriverId == null) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select a Driver')));
                          return;
                        }
                        if (_selectedChallanIdsForTrip.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select at least one delivery challan')));
                          return;
                        }

                        final res = await transportCtrl.assignTrip(
                          vehicleId: _tripVehicleId!,
                          driverId: _tripDriverId!,
                          challanIds: _selectedChallanIdsForTrip.toList(),
                          eWayBillNo: _tripEWayBillCtrl.text.trim(),
                        );

                        if (res != null && context.mounted) {
                          setState(() {
                            _selectedChallanIdsForTrip.clear();
                            _tripVehicleId = null;
                            _tripDriverId = null;
                            _tripEWayBillCtrl.clear();
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(res['message'] ?? 'Trip dispatched successfully!'),
                              backgroundColor: const Color(0xFF008060),
                            ),
                          );
                          _loadData();
                        }
                      },
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: Text('Dispatch Truck (${_selectedChallanIdsForTrip.length} Challans Loaded)'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Active Road Trips & Manifest Cards
          const Text(
            'Active Road Trips & Delivery Manifests',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),

          if (activeTrips.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Icon(Icons.check_circle_outline, size: 48, color: Colors.green.shade400),
                  const SizedBox(height: 8),
                  const Text('No Active Trips on the Road', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  const Text('All trucks and drivers are currently available.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            )
          else
            ...activeTrips.map((trip) {
              final vehicle = trip['vehicle'] ?? {};
              final driver = trip['driver'] ?? {};
              final challans = trip['challans'] as List? ?? [];

              return Card(
                elevation: 0.5,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isNarrow = constraints.maxWidth < 650;
                          final infoWidget = Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.local_shipping, color: Colors.deepOrange),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Truck: ${vehicle['vehicle_number'] ?? 'N/A'} (${vehicle['vehicle_type'] ?? 'Truck'})',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    Text(
                                      'Driver: ${driver['driver_name'] ?? 'Assigned'} (Ph: ${driver['phone'] ?? 'N/A'})',
                                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                    ),
                                    _buildDriverLiveGpsWidget(driver),
                                  ],
                                ),
                              ),
                            ],
                          );

                          final actionsWidget = Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  border: Border.all(color: Colors.blue.shade200),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${trip['challan_count'] ?? 0} Challans Onboard',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue.shade900),
                                ),
                              ),
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                onPressed: () async {
                                  await transportCtrl.releaseTrip(
                                    vehicleId: vehicle['id'],
                                    driverId: driver['id'],
                                    tripId: trip['trip_id'],
                                  );
                                },
                                icon: const Icon(Icons.cancel_outlined, size: 14),
                                label: const Text('Release Truck', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          );

                          if (isNarrow) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                infoWidget,
                                const SizedBox(height: 10),
                                actionsWidget,
                              ],
                            );
                          }

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(child: infoWidget),
                              const SizedBox(width: 12),
                              actionsWidget,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 6),

                      // List of challans on this truck
                      ...challans.map((ch) {
                        final isDelivered = ch['delivery_status'] == 'DELIVERED';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${ch['challan_no']} - ${ch['customer_name']} (Qty: ${ch['total_qty']} Units)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        decoration: isDelivered ? TextDecoration.lineThrough : null,
                                      ),
                                    ),
                                    if (ch['delivery_otp'] != null && !isDelivered)
                                      Text('Delivery OTP: ${ch['delivery_otp']}', style: const TextStyle(fontSize: 11, color: Color(0xFF008060), fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (!isDelivered)
                                FilledButton.tonal(
                                  onPressed: () => _openVerifyDeliveryDialog(ch),
                                  child: const Text('Verify OTP / Mark Delivered', style: TextStyle(fontSize: 11)),
                                )
                              else
                                const Row(
                                  children: [
                                    Icon(Icons.check_circle, size: 16, color: Colors.green),
                                    SizedBox(width: 4),
                                    Text('Delivered', style: TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // =========================================================================
  // DIALOG: VERIFY DELIVERY (OTP OR DRIVER SUBMIT)
  // =========================================================================
  void _openVerifyDeliveryDialog(Map<String, dynamic> challan) {
    final otpCtrl = TextEditingController();
    final remarkCtrl = TextEditingController();
    final receiverCtrl = TextEditingController();
    final challanId = challan['id'] as int;
    final expectedOtp = challan['delivery_otp'] ?? '';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              const Icon(Icons.verified, color: Color(0xFF008060)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Confirm Delivery - ${challan['challan_no']}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Customer: ${challan['customer_name']} (${challan['customer_phone'] ?? 'No Phone'})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 2),
                        Text('Loaded on: ${challan['vehicle_number'] ?? 'Truck'} | Driver: ${challan['driver_name'] ?? 'Driver'}'),
                        const SizedBox(height: 2),
                        Text('Total Quantity: ${challan['total_qty']} Units'),
                        if (expectedOtp.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text('Generated OTP: $expectedOtp (Shared with Customer)', style: const TextStyle(color: Color(0xFF008060), fontWeight: FontWeight.bold)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Option A: Enter OTP
                  const Text('Option A: Customer 6-Digit Delivery OTP (Recommended)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: otpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Enter 6-Digit OTP from Retailer / Client',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.pin, size: 20),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Option B: Direct Driver Submit
                  const Text('Option B: Direct Handover Confirmation by Driver', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: receiverCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Receiver Name / Authorized Person',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person_outline, size: 20),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: remarkCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Delivery Remarks / Gate Pass Ref',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.notes, size: 20),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
              onPressed: () async {
                final otpVal = otpCtrl.text.trim();
                final receiverVal = receiverCtrl.text.trim();
                final remarkVal = remarkCtrl.text.trim();

                final transportCtrl = Provider.of<TransportController>(context, listen: false);
                final res = await transportCtrl.verifyDelivery(
                  challanId: challanId,
                  otp: otpVal.isNotEmpty ? otpVal : null,
                  receiverName: receiverVal.isNotEmpty ? receiverVal : null,
                  remark: remarkVal.isNotEmpty ? remarkVal : null,
                );

                if (res['success'] == true && context.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res['message'] ?? 'Challan marked DELIVERED!'),
                      backgroundColor: const Color(0xFF008060),
                    ),
                  );
                  _loadData();
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(res['message'] ?? 'Failed to verify delivery'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: const Text('Confirm Delivery Handover'),
            ),
          ],
        );
      },
    );
  }

  // =========================================================================
  // DIALOG: ASSIGN TRANSPORT (VEHICLE & DRIVER) TO SINGLE CHALLAN
  // =========================================================================
  void _openAssignTransportDialog(Map<String, dynamic> challan) {
    final transportCtrl = Provider.of<TransportController>(context, listen: false);
    int? selectedVehicleId = challan['vehicle_id'];
    int? selectedDriverId = challan['driver_id'];
    final eWayCtrl = TextEditingController(text: challan['e_way_bill_no'] ?? '');

    final availableVehicles = transportCtrl.vehicles;
    final availableDrivers = transportCtrl.drivers;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Text('Assign Vehicle & Driver - ${challan['challan_no']}'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      value: selectedVehicleId,
                      decoration: const InputDecoration(
                        labelText: 'Select Vehicle / Truck *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.rv_hookup),
                        isDense: true,
                      ),
                      items: availableVehicles.map<DropdownMenuItem<int>>((v) {
                        return DropdownMenuItem<int>(
                          value: v['id'],
                          child: Text('${v['vehicle_number']} (${v['vehicle_type']} - ${v['status']})'),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedVehicleId = val),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: selectedDriverId,
                      decoration: const InputDecoration(
                        labelText: 'Select Driver *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person_pin),
                        isDense: true,
                      ),
                      items: availableDrivers.map<DropdownMenuItem<int>>((d) {
                        return DropdownMenuItem<int>(
                          value: d['id'],
                          child: Text('${d['driver_name']} (${d['phone']} - ${d['status']})'),
                        );
                      }).toList(),
                      onChanged: (val) => setDialogState(() => selectedDriverId = val),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: eWayCtrl,
                      decoration: const InputDecoration(
                        labelText: 'E-Way Bill Number (Optional)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.receipt_long),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                  onPressed: () async {
                    if (selectedVehicleId == null || selectedDriverId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please select vehicle and driver')));
                      return;
                    }

                    final res = await transportCtrl.assignTrip(
                      vehicleId: selectedVehicleId!,
                      driverId: selectedDriverId!,
                      challanIds: [challan['id']],
                      eWayBillNo: eWayCtrl.text.trim(),
                    );

                    if (res != null && context.mounted) {
                      Navigator.pop(dialogCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(res['message'] ?? 'Assigned successfully!'),
                          backgroundColor: const Color(0xFF008060),
                        ),
                      );
                      _loadData();
                    }
                  },
                  child: const Text('Assign & Dispatch'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // DIALOG: ADD / EDIT VEHICLE
  // =========================================================================
  void _openVehicleDialog({Map<String, dynamic>? existing}) {
    final numberCtrl = TextEditingController(text: existing?['vehicle_number'] ?? '');
    String vehicleType = existing?['vehicle_type'] ?? 'Truck';
    final capacityCtrl = TextEditingController(text: existing?['capacity_tonnage']?.toString() ?? '5.0');
    String capacityUnit = existing?['capacity_unit'] ?? 'Tons';
    final modelCtrl = TextEditingController(text: existing?['model'] ?? '');
    final notesCtrl = TextEditingController(text: existing?['notes'] ?? '');

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  const Icon(Icons.rv_hookup, color: Color(0xFF008060)),
                  const SizedBox(width: 8),
                  Text(existing == null ? 'Add Vehicle / Truck Profile' : 'Edit Vehicle Profile'),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: numberCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle / Registration Number * (e.g. MH12AB1234)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: vehicleType,
                        decoration: const InputDecoration(
                          labelText: 'Vehicle Type *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Truck', child: Text('Truck (Heavy Goods)')),
                          DropdownMenuItem(value: 'Tipper', child: Text('Tipper (Building Materials / Sand)')),
                          DropdownMenuItem(value: 'Trailer', child: Text('Trailer (Long Haul)')),
                          DropdownMenuItem(value: 'LCV', child: Text('LCV / Mini Truck (Tata 407/Bolero)')),
                          DropdownMenuItem(value: 'Pickup', child: Text('Pickup Van / Utility')),
                          DropdownMenuItem(value: 'Tractor', child: Text('Tractor / Trolley')),
                          DropdownMenuItem(value: '3-Wheeler', child: Text('3-Wheeler Goods Carrier')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => vehicleType = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: capacityCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'Load Capacity *',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: capacityUnit,
                              decoration: const InputDecoration(
                                labelText: 'Unit',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Tons', child: Text('Tons')),
                                DropdownMenuItem(value: 'Kg', child: Text('Kg')),
                                DropdownMenuItem(value: 'Bags', child: Text('Bags')),
                                DropdownMenuItem(value: 'Trips', child: Text('Trips')),
                              ],
                              onChanged: (val) {
                                if (val != null) setDialogState(() => capacityUnit = val);
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: modelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Make & Model (e.g. Tata 1616 / Ashok Leyland)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Notes / Permit Details',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                  onPressed: () async {
                    if (numberCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vehicle Number is required')));
                      return;
                    }

                    final transportCtrl = Provider.of<TransportController>(context, listen: false);
                    bool ok = false;
                    if (existing == null) {
                      ok = await transportCtrl.addVehicle(
                        vehicleNumber: numberCtrl.text.trim(),
                        vehicleType: vehicleType,
                        capacityTonnage: double.tryParse(capacityCtrl.text) ?? 0.0,
                        capacityUnit: capacityUnit,
                        model: modelCtrl.text.trim(),
                        notes: notesCtrl.text.trim(),
                      );
                    } else {
                      ok = await transportCtrl.updateVehicle(existing['id'], {
                        'vehicle_number': numberCtrl.text.trim(),
                        'vehicle_type': vehicleType,
                        'capacity_tonnage': double.tryParse(capacityCtrl.text) ?? 0.0,
                        'capacity_unit': capacityUnit,
                        'model': modelCtrl.text.trim(),
                        'notes': notesCtrl.text.trim(),
                      });
                    }

                    if (ok && context.mounted) {
                      Navigator.pop(dialogCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(existing == null ? 'Vehicle added to fleet successfully!' : 'Vehicle profile updated!'),
                          backgroundColor: const Color(0xFF008060),
                        ),
                      );
                    }
                  },
                  child: Text(existing == null ? 'Save Vehicle' : 'Update Vehicle'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // DIALOG: ADD / EDIT DRIVER
  // =========================================================================
  void _openDriverDialog({Map<String, dynamic>? existing}) {
    final nameCtrl = TextEditingController(text: existing?['driver_name']?.toString() ?? '');
    final phoneCtrl = TextEditingController(text: existing?['phone']?.toString() ?? '');
    final emailCtrl = TextEditingController(text: existing?['email']?.toString() ?? '');
    final passwordCtrl = TextEditingController();
    final dlCtrl = TextEditingController(text: existing?['license_number']?.toString() ?? '');
    final addressCtrl = TextEditingController(text: existing?['address']?.toString() ?? '');
    String status = existing?['status'] ?? 'AVAILABLE';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: Row(
                children: [
                  const Icon(Icons.badge, color: Color(0xFF008060)),
                  const SizedBox(width: 8),
                  Text(existing == null ? 'Add Driver Profile' : 'Edit Driver Profile'),
                ],
              ),
              content: SizedBox(
                width: 460,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Driver Full Name *',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: phoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Mobile Phone Number (Login ID) *',
                          hintText: 'e.g. 9876543210',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Driver Email ID (Login & OTP Reset)',
                          hintText: 'driver@company.com',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: passwordCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: existing == null ? 'Initial App Password *' : 'Update Password (Optional)',
                          hintText: existing == null ? 'Default: 123456' : 'Encrypted (enter new password to change)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: status,
                        decoration: const InputDecoration(
                          labelText: 'Driver Status',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'AVAILABLE', child: Text('AVAILABLE (Active on fleet)')),
                          DropdownMenuItem(value: 'BOOKED', child: Text('BOOKED (On active trip)')),
                          DropdownMenuItem(value: 'ON_LEAVE', child: Text('ON LEAVE')),
                          DropdownMenuItem(value: 'INACTIVE', child: Text('INACTIVE (Auto-logout driver app)')),
                          DropdownMenuItem(value: 'TERMINATED', child: Text('TERMINATED (Block app access)')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => status = val);
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: dlCtrl,
                        textCapitalization: TextCapitalization.characters,
                        decoration: const InputDecoration(
                          labelText: 'Driving License (DL) Number',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: addressCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Address / Emergency Contact Details',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Driver Name is required')));
                      return;
                    }
                    if (phoneCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone Number is required')));
                      return;
                    }

                    final transportCtrl = Provider.of<TransportController>(context, listen: false);
                    bool ok = false;
                    if (existing == null) {
                      ok = await transportCtrl.addDriver(
                        driverName: nameCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        email: emailCtrl.text.trim(),
                        password: passwordCtrl.text.trim().isNotEmpty ? passwordCtrl.text.trim() : '123456',
                        licenseNumber: dlCtrl.text.trim(),
                        address: addressCtrl.text.trim(),
                        status: status,
                      );
                    } else {
                      final Map<String, dynamic> updateData = {
                        'driver_name': nameCtrl.text.trim(),
                        'phone': phoneCtrl.text.trim(),
                        'email': emailCtrl.text.trim(),
                        'license_number': dlCtrl.text.trim(),
                        'address': addressCtrl.text.trim(),
                        'status': status,
                      };
                      if (passwordCtrl.text.trim().isNotEmpty) {
                        updateData['password'] = passwordCtrl.text.trim();
                      }
                      ok = await transportCtrl.updateDriver(existing['id'], updateData);
                    }

                    if (ok && context.mounted) {
                      Navigator.pop(dialogCtx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(existing == null ? 'Driver profile created successfully!' : 'Driver profile updated!'),
                          backgroundColor: const Color(0xFF008060),
                        ),
                      );
                    }
                  },
                  child: Text(existing == null ? 'Save Driver' : 'Update Driver'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // DIALOG: SEARCH & SELECT MULTIPLE CATALOG ITEMS
  // =========================================================================
  void _openMultiItemPickerDialog(
    BuildContext context,
    List<Item> catalogItems,
    Function(List<Map<String, dynamic>> items) onAddItems,
  ) {
    String searchQuery = '';
    final Map<int, double> selectedQtys = {};

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setPickerState) {
            final filteredItems = catalogItems.where((it) {
              if (searchQuery.isEmpty) return true;
              final q = searchQuery.toLowerCase();
              final name = it.itemName.toLowerCase();
              final code = (it.itemCode ?? '').toLowerCase();
              final barcode = (it.barcode ?? '').toLowerCase();
              return name.contains(q) || code.contains(q) || barcode.contains(q);
            }).toList();

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Row(
                children: [
                  Icon(Icons.inventory_2_outlined, color: Color(0xFF008060)),
                  SizedBox(width: 8),
                  Text('Search & Add Multiple Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 620,
                height: 520,
                child: Column(
                  children: [
                    TextField(
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search by item name, item code, or barcode...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () => setPickerState(() => searchQuery = ''),
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      onChanged: (val) => setPickerState(() => searchQuery = val),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredItems.isEmpty
                          ? const Center(child: Text('No items found matching search', style: TextStyle(color: Colors.grey)))
                          : ListView.separated(
                              itemCount: filteredItems.length,
                              separatorBuilder: (_, __) => const Divider(height: 1),
                              itemBuilder: (ctx, i) {
                                final item = filteredItems[i];
                                final isSelected = selectedQtys.containsKey(item.id);
                                final qty = selectedQtys[item.id] ?? 1.0;

                                return ListTile(
                                  dense: true,
                                  leading: Checkbox(
                                    value: isSelected,
                                    activeColor: const Color(0xFF008060),
                                    onChanged: (val) {
                                      setPickerState(() {
                                        if (val == true) {
                                          selectedQtys[item.id] = 1.0;
                                        } else {
                                          selectedQtys.remove(item.id);
                                        }
                                      });
                                    },
                                  ),
                                  title: Text(
                                    item.itemName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    'Code: ${item.itemCode ?? 'N/A'} • Unit: ${item.unit} • Rate: ₹${item.rate.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                                  ),
                                  trailing: isSelected
                                      ? SizedBox(
                                          width: 140,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.remove_circle_outline, size: 20, color: Colors.red),
                                                onPressed: () {
                                                  setPickerState(() {
                                                    if (qty > 1) {
                                                      selectedQtys[item.id] = qty - 1;
                                                    } else {
                                                      selectedQtys.remove(item.id);
                                                    }
                                                  });
                                                },
                                              ),
                                              Expanded(
                                                child: Text(
                                                  '$qty ${item.unit}',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF008060)),
                                                onPressed: () {
                                                  setPickerState(() {
                                                    selectedQtys[item.id] = qty + 1;
                                                  });
                                                },
                                              ),
                                            ],
                                          ),
                                        )
                                      : OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            side: const BorderSide(color: Color(0xFF008060)),
                                          ),
                                          onPressed: () {
                                            setPickerState(() {
                                              selectedQtys[item.id] = 1.0;
                                            });
                                          },
                                          child: const Text('+ Add', style: TextStyle(color: Color(0xFF008060), fontSize: 12)),
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
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                  onPressed: selectedQtys.isEmpty
                      ? null
                      : () {
                          final List<Map<String, dynamic>> result = [];
                          selectedQtys.forEach((itemId, qty) {
                            final it = catalogItems.firstWhere((element) => element.id == itemId);
                            result.add({
                              'item_id': it.id,
                              'item_name': it.itemName,
                              'unit': it.unit,
                              'qty': qty,
                            });
                          });
                          onAddItems(result);
                          Navigator.pop(dialogCtx);
                        },
                  icon: const Icon(Icons.playlist_add_check, size: 18),
                  label: Text('Add Selected (${selectedQtys.length} Items)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // DIALOG: ISSUE NEW DELIVERY CHALLAN (WITH OPTIONAL TRUCK & DRIVER ASSIGNMENT)
  // =========================================================================
  void _openIssueChallanDialog(BuildContext mainContext) {
    _loadRegisteredCustomers();
    final customerNameCtrl = TextEditingController();
    final customerPhoneCtrl = TextEditingController();
    final destinationCtrl = TextEditingController();
    final eWayCtrl = TextEditingController();

    customerPhoneCtrl.addListener(() {
      final text = customerPhoneCtrl.text.trim();
      if (text.length >= 10 && customerNameCtrl.text.trim().isEmpty) {
        final digits = text.replaceAll(RegExp(r'\D'), '');
        final last10 = digits.length >= 10 ? digits.substring(digits.length - 10) : digits;
        final match = _registeredCustomers.firstWhere(
          (c) {
            final p = (c['customer_phone'] ?? c['phone'] ?? c['mobile'] ?? '').toString().replaceAll(RegExp(r'\D'), '');
            return p.isNotEmpty && p.endsWith(last10);
          },
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          final nm = (match['customer_name'] ?? match['name'] ?? '').toString().trim();
          final addr = (match['customer_address'] ?? match['address'] ?? match['shipping_address'] ?? '').toString().trim();
          if (nm.isNotEmpty && customerNameCtrl.text.trim().isEmpty) {
            customerNameCtrl.text = nm;
          }
          if (addr.isNotEmpty && destinationCtrl.text.trim().isEmpty) {
            destinationCtrl.text = addr;
          }
        }
      }
    });

    int? assignedVehicleId;
    int? assignedDriverId;

    List<Map<String, dynamic>> lineItems = [];
    final catalogItems = _itemController.list;
    final transportCtrl = Provider.of<TransportController>(mainContext, listen: false);
    final availableVehicles = transportCtrl.vehicles.where((v) => (v['status'] ?? 'AVAILABLE') != 'MAINTENANCE').toList();
    final availableDrivers = transportCtrl.drivers.where((d) => (d['status'] ?? 'AVAILABLE') != 'TERMINATED' && (d['status'] ?? 'AVAILABLE') != 'INACTIVE').toList();

    showDialog(
      context: mainContext,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              title: const Row(
                children: [
                  Icon(Icons.local_shipping, color: Color(0xFF008060)),
                  SizedBox(width: 10),
                  Text('Issue New Delivery Challan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Customer info with Autocomplete (Searchable Name & Phone)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: RawAutocomplete<Map<String, dynamic>>(
                              textEditingController: customerNameCtrl,
                              focusNode: FocusNode(),
                              optionsBuilder: (TextEditingValue textEditingValue) {
                                if (textEditingValue.text.trim().isEmpty) {
                                  return const Iterable<Map<String, dynamic>>.empty();
                                }
                                final q = textEditingValue.text.toLowerCase().trim();
                                return _registeredCustomers.where((c) {
                                  final name = (c['customer_name'] ?? c['name'] ?? '').toString().toLowerCase();
                                  final phone = (c['customer_phone'] ?? c['phone'] ?? c['mobile'] ?? '').toString().toLowerCase();
                                  final addr = (c['customer_address'] ?? c['address'] ?? c['shipping_address'] ?? '').toString().toLowerCase();
                                  return name.contains(q) || phone.contains(q) || addr.contains(q);
                                });
                              },
                              displayStringForOption: (c) => (c['customer_name'] ?? c['name'] ?? '').toString(),
                              onSelected: (Map<String, dynamic> selection) {
                                setDialogState(() {
                                  final name = (selection['customer_name'] ?? selection['name'] ?? '').toString().trim();
                                  final ph = (selection['customer_phone'] ?? selection['phone'] ?? selection['mobile'] ?? '').toString().trim();
                                  final addr = (selection['customer_address'] ?? selection['address'] ?? selection['shipping_address'] ?? selection['billing_address'] ?? selection['city'] ?? '').toString().trim();
                                  if (name.isNotEmpty) customerNameCtrl.text = name;
                                  if (ph.isNotEmpty) customerPhoneCtrl.text = ph;
                                  if (addr.isNotEmpty) destinationCtrl.text = addr;
                                });
                              },
                              fieldViewBuilder: (context, fieldTextEditingController, focusNode, onFieldSubmitted) {
                                return TextField(
                                  controller: fieldTextEditingController,
                                  focusNode: focusNode,
                                  decoration: const InputDecoration(
                                    labelText: 'Customer / Retailer Name *',
                                    hintText: 'Type to search customer...',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    prefixIcon: Icon(Icons.person, size: 18),
                                  ),
                                );
                              },
                              optionsViewBuilder: (context, onSelected, options) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 6.0,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 350,
                                      constraints: const BoxConstraints(maxHeight: 220),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        itemBuilder: (BuildContext context, int index) {
                                          final c = options.elementAt(index);
                                          final name = (c['customer_name'] ?? c['name'] ?? '').toString();
                                          final phone = (c['customer_phone'] ?? c['phone'] ?? c['mobile'] ?? '').toString();
                                          final addr = (c['customer_address'] ?? c['address'] ?? c['shipping_address'] ?? '').toString();
                                          return ListTile(
                                            dense: true,
                                            leading: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF008060).withValues(alpha: 0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.person_pin_circle_rounded, size: 18, color: Color(0xFF008060)),
                                            ),
                                            title: Text(
                                              name.isNotEmpty ? name : 'Customer ($phone)',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                            ),
                                            subtitle: Text(
                                              [
                                                if (phone.isNotEmpty) '📞 $phone',
                                                if (addr.isNotEmpty) '📍 $addr',
                                              ].join('  •  '),
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onTap: () => onSelected(c),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: RawAutocomplete<Map<String, dynamic>>(
                              textEditingController: customerPhoneCtrl,
                              focusNode: FocusNode(),
                              optionsBuilder: (TextEditingValue textEditingValue) {
                                if (textEditingValue.text.trim().isEmpty) {
                                  return const Iterable<Map<String, dynamic>>.empty();
                                }
                                final q = textEditingValue.text.toLowerCase().trim();
                                return _registeredCustomers.where((c) {
                                  final phone = (c['customer_phone'] ?? c['phone'] ?? c['mobile'] ?? '').toString().toLowerCase();
                                  final name = (c['customer_name'] ?? c['name'] ?? '').toString().toLowerCase();
                                  final addr = (c['customer_address'] ?? c['address'] ?? c['shipping_address'] ?? '').toString().toLowerCase();
                                  return phone.contains(q) || name.contains(q) || addr.contains(q);
                                });
                              },
                              displayStringForOption: (c) => (c['customer_phone'] ?? c['phone'] ?? c['mobile'] ?? '').toString(),
                              onSelected: (Map<String, dynamic> selection) {
                                setDialogState(() {
                                  final ph = (selection['customer_phone'] ?? selection['phone'] ?? selection['mobile'] ?? '').toString().trim();
                                  final nm = (selection['customer_name'] ?? selection['name'] ?? '').toString().trim();
                                  final addr = (selection['customer_address'] ?? selection['address'] ?? selection['shipping_address'] ?? selection['billing_address'] ?? selection['city'] ?? '').toString().trim();
                                  if (ph.isNotEmpty) customerPhoneCtrl.text = ph;
                                  if (nm.isNotEmpty) customerNameCtrl.text = nm;
                                  if (addr.isNotEmpty) destinationCtrl.text = addr;
                                });
                              },
                              fieldViewBuilder: (context, fieldTextEditingController, focusNode, onFieldSubmitted) {
                                return TextField(
                                  controller: fieldTextEditingController,
                                  focusNode: focusNode,
                                  keyboardType: TextInputType.phone,
                                  decoration: const InputDecoration(
                                    labelText: 'Customer Phone *',
                                    hintText: 'Type to search phone...',
                                    border: OutlineInputBorder(),
                                    isDense: true,
                                    prefixIcon: Icon(Icons.phone, size: 18),
                                  ),
                                );
                              },
                              optionsViewBuilder: (context, onSelected, options) {
                                return Align(
                                  alignment: Alignment.topLeft,
                                  child: Material(
                                    elevation: 6.0,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      width: 350,
                                      constraints: const BoxConstraints(maxHeight: 220),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: const Color(0xFFE2E8F0)),
                                      ),
                                      child: ListView.builder(
                                        padding: EdgeInsets.zero,
                                        shrinkWrap: true,
                                        itemCount: options.length,
                                        itemBuilder: (BuildContext context, int index) {
                                          final c = options.elementAt(index);
                                          final name = (c['customer_name'] ?? c['name'] ?? '').toString();
                                          final phone = (c['customer_phone'] ?? c['phone'] ?? c['mobile'] ?? '').toString();
                                          final addr = (c['customer_address'] ?? c['address'] ?? c['shipping_address'] ?? '').toString();
                                          return ListTile(
                                            dense: true,
                                            leading: Container(
                                              padding: const EdgeInsets.all(5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF008060).withValues(alpha: 0.1),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.phone_iphone, size: 18, color: Color(0xFF008060)),
                                            ),
                                            title: Text(
                                              phone.isNotEmpty ? phone : 'No Phone',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)),
                                            ),
                                            subtitle: Text(
                                              [
                                                if (name.isNotEmpty) '👤 $name',
                                                if (addr.isNotEmpty) '📍 $addr',
                                              ].join('  •  '),
                                              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            onTap: () => onSelected(c),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Destination Address & E-Way Bill
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: destinationCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Delivery Site / Destination Address (Optional)',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: eWayCtrl,
                              decoration: const InputDecoration(
                                labelText: 'E-Way Bill #',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Optional Transportation Upfront
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF008060).withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF008060).withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Assign Transportation Fleet (Optional)',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF008060)),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: assignedVehicleId,
                                    decoration: const InputDecoration(
                                      labelText: 'Select Truck / Vehicle',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      prefixIcon: Icon(Icons.rv_hookup, size: 18),
                                    ),
                                    items: [
                                      const DropdownMenuItem<int>(value: null, child: Text('Assign Later')),
                                      ...availableVehicles.map((v) => DropdownMenuItem<int>(
                                            value: v['id'],
                                            child: Text('${v['vehicle_number']} (${v['vehicle_type']})'),
                                          )),
                                    ],
                                    onChanged: (val) => setDialogState(() => assignedVehicleId = val),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    value: assignedDriverId,
                                    decoration: const InputDecoration(
                                      labelText: 'Select Driver',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                      prefixIcon: Icon(Icons.person_pin, size: 18),
                                    ),
                                    items: [
                                      const DropdownMenuItem<int>(value: null, child: Text('Assign Later')),
                                      ...availableDrivers.map((d) => DropdownMenuItem<int>(
                                            value: d['id'],
                                            child: Text('${d['driver_name']} (Ph: ${d['phone']})'),
                                          )),
                                    ],
                                    onChanged: (val) => setDialogState(() => assignedDriverId = val),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 8),

                      // Items list header with Multi-Add button (Case 3)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Dispatch Line Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF008060),
                                  side: const BorderSide(color: Color(0xFF008060)),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                                onPressed: () {
                                  _openMultiItemPickerDialog(mainContext, catalogItems, (newItems) {
                                    setDialogState(() {
                                      lineItems.addAll(newItems);
                                    });
                                  });
                                },
                                icon: const Icon(Icons.playlist_add, size: 18),
                                label: const Text('Search & Add Multiple Items'),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                onPressed: () {
                                  if (catalogItems.isNotEmpty) {
                                    final first = catalogItems.first;
                                    setDialogState(() {
                                      lineItems.add({
                                        'item_id': first.id,
                                        'item_name': first.itemName,
                                        'unit': first.unit,
                                        'qty': 1.0,
                                      });
                                    });
                                  }
                                },
                                icon: const Icon(Icons.add_circle_outline, size: 18),
                                label: const Text('Add Single'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      if (lineItems.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'No line items added yet. Click "+ Search & Add Multiple Items" above.',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: lineItems.length,
                          itemBuilder: (context, idx) {
                            final row = lineItems[idx];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8.0),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: DropdownButtonFormField<int>(
                                      value: row['item_id'],
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Item',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                      ),
                                      items: catalogItems.map((catItem) {
                                        return DropdownMenuItem<int>(
                                          value: catItem.id,
                                          child: Text('${catItem.itemCode} - ${catItem.itemName} (${catItem.unit})'),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val != null) {
                                          final found = catalogItems.firstWhere((it) => it.id == val, orElse: () => catalogItems.first);
                                          setDialogState(() {
                                            row['item_id'] = found.id;
                                            row['item_name'] = found.itemName;
                                            row['unit'] = found.unit;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 1,
                                    child: TextFormField(
                                      initialValue: row['qty'].toString(),
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: 'Qty (${row['unit']})',
                                        isDense: true,
                                        border: const OutlineInputBorder(),
                                      ),
                                      onChanged: (val) {
                                        row['qty'] = double.tryParse(val) ?? 1.0;
                                      },
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () {
                                      setDialogState(() {
                                        lineItems.removeAt(idx);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Cancel'),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF008060)),
                  onPressed: () async {
                    if (customerNameCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(mainContext).showSnackBar(
                        const SnackBar(content: Text('Customer Name is required')),
                      );
                      return;
                    }
                    if (lineItems.isEmpty) {
                      ScaffoldMessenger.of(mainContext).showSnackBar(
                        const SnackBar(content: Text('Please add at least 1 item to dispatch')),
                      );
                      return;
                    }

                    // Resolve selected vehicle and driver objects if chosen
                    Map<String, dynamic>? selectedVehicleObj;
                    Map<String, dynamic>? selectedDriverObj;
                    if (assignedVehicleId != null) {
                      selectedVehicleObj = availableVehicles.firstWhere(
                        (v) => v['id'] == assignedVehicleId,
                        orElse: () => <String, dynamic>{},
                      );
                    }
                    if (assignedDriverId != null) {
                      selectedDriverObj = availableDrivers.firstWhere(
                        (d) => d['id'] == assignedDriverId,
                        orElse: () => <String, dynamic>{},
                      );
                    }

                    Navigator.pop(dialogCtx);
                    final restCtrl = Provider.of<RestaurantController>(mainContext, listen: false);
                    final success = await restCtrl.saveChallan({
                      'customer_name': customerNameCtrl.text.trim(),
                      'customer_phone': customerPhoneCtrl.text.trim(),
                      'destination_address': destinationCtrl.text.trim(),
                      'e_way_bill_no': eWayCtrl.text.trim(),
                      'vehicle_id': assignedVehicleId,
                      'vehicle_number': selectedVehicleObj?['vehicle_number'],
                      'vehicle_type': selectedVehicleObj?['vehicle_type'],
                      'driver_id': assignedDriverId,
                      'driver_name': selectedDriverObj?['driver_name'],
                      'driver_phone': selectedDriverObj?['phone'],
                      'items': lineItems,
                    });

                    if (success && mainContext.mounted) {
                      final enteredName = customerNameCtrl.text.trim();
                      final enteredPhone = customerPhoneCtrl.text.trim();
                      final enteredAddr = destinationCtrl.text.trim();
                      if (enteredPhone.isNotEmpty) {
                        final exists = _registeredCustomers.any((c) =>
                            (c['customer_phone'] ?? c['phone'] ?? '').toString().trim() == enteredPhone);
                        if (!exists) {
                          _registeredCustomers.insert(0, {
                            'customer_name': enteredName,
                            'customer_phone': enteredPhone,
                            'customer_address': enteredAddr,
                          });
                        }
                      }
                      ScaffoldMessenger.of(mainContext).showSnackBar(
                        const SnackBar(
                          content: Text('Delivery Challan issued successfully! Customer synced & stock deducted.'),
                          backgroundColor: Color(0xFF008060),
                        ),
                      );
                      _loadData();
                      _loadRegisteredCustomers();
                    }
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Issue Challan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // =========================================================================
  // BILLING NAVIGATION & PRINTABLE DELIVERY CHALLAN BILL ENGINE
  // =========================================================================
  Future<void> _openInBillingScreen(BuildContext context, int challanId) async {
    final restCtrl = Provider.of<RestaurantController>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final details = await restCtrl.getChallanDetails(challanId);
    if (context.mounted) Navigator.pop(context); // Dismiss loader

    if (details == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load delivery challan details')),
        );
      }
      return;
    }

    final List<Map<String, dynamic>> preloadedItems = (details['items'] as List? ?? []).map((it) {
      return {
        'item_id': it['item_id'],
        'item_name': it['item_name'],
        'unit': it['unit'] ?? 'PCS',
        'qty': double.tryParse(it['qty']?.toString() ?? '1') ?? 1.0,
        'rate': double.tryParse((it['rate'] ?? it['price'] ?? 0).toString()) ?? 0.0,
      };
    }).toList();

    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SaleScreen(
            preloadedItems: preloadedItems,
            preloadedCustomerName: details['customer_name'],
            preloadedCustomerPhone: details['customer_phone'],
            challanNo: details['challan_no'],
            affectStock: false,
          ),
        ),
      );

      await restCtrl.updateChallanStatus(challanId, 'Converted_To_Sale');
      _loadData();
    }
  }

  Future<void> _printChallanToPrinter(BuildContext context, int challanId) async {
    final restCtrl = Provider.of<RestaurantController>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final details = await restCtrl.getChallanDetails(challanId);
    if (context.mounted) Navigator.pop(context);

    if (details == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to load full delivery challan details')),
        );
      }
      return;
    }

    final challanNo = details['challan_no'] ?? 'DC-UNKNOWN';
    final customerName = details['customer_name'] ?? 'Walk-In Customer';
    final customerPhone = details['customer_phone'] ?? 'N/A';
    final destination = details['destination_address'] ?? 'Customer Delivery Address';
    final vehicleNo = details['vehicle_number'] ?? 'N/A';
    final vehicleType = details['vehicle_type'] ?? 'Truck';
    final driverName = details['driver_name'] ?? 'N/A';
    final driverPhone = details['driver_phone'] ?? 'N/A';
    final eWay = details['e_way_bill_no'] ?? '';
    final deliveryOtp = details['delivery_otp'] ?? '';
    final status = details['status'] ?? 'Issued';
    final deliveryStatus = details['delivery_status'] ?? 'PENDING';
    final rawDate = details['challan_date'];
    final dateStr = rawDate != null
        ? DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.parse(rawDate.toString()))
        : DateFormat('dd-MM-yyyy hh:mm a').format(DateTime.now());

    final List<dynamic> itemsList = details['items'] ?? [];
    final double totalQty = details['total_qty'] != null
        ? double.tryParse(details['total_qty'].toString()) ?? 0.0
        : itemsList.fold<double>(0.0, (sum, it) => sum + (double.tryParse(it['qty']?.toString() ?? '0') ?? 0.0));

    final pdf = await PosInvoicePrinter.createDocument();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context pwContext) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'DELIVERY CHALLAN & DISPATCH NOTE',
                        style: pw.TextStyle(
                          fontSize: 20,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue900,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(
                        'FACTORY & DISTRIBUTOR SUPPLY LOGISTICS',
                        style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.blueGrey800, width: 1),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          'Challan No: $challanNo',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11),
                        ),
                        pw.Text('Date: $dateStr', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('Status: $status - Delivery: $deliveryStatus', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey700)),
                      ],
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Divider(color: PdfColors.grey400, thickness: 1),
              pw.SizedBox(height: 10),

              // Consignee and Fleet Information Block
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  border: pw.Border.all(color: PdfColors.grey300),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Consignee / Customer Details:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey800)),
                        pw.SizedBox(height: 4),
                        pw.Text('Name: $customerName', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
                        pw.Text('Phone: $customerPhone', style: const pw.TextStyle(fontSize: 9)),
                        pw.Text('Delivery Destination: $destination', style: const pw.TextStyle(fontSize: 9)),
                        if (deliveryOtp.isNotEmpty)
                          pw.Text('Customer Delivery OTP: $deliveryOtp', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.teal900)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text('Transportation & Logistics:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10, color: PdfColors.grey800)),
                        pw.SizedBox(height: 4),
                        pw.Text('Truck/Vehicle: $vehicleNo ($vehicleType)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                        pw.Text('Driver: $driverName (Ph: $driverPhone)', style: const pw.TextStyle(fontSize: 9)),
                        if (eWay.isNotEmpty)
                          pw.Text('E-Way Bill No: $eWay', style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),

              // Items Table
              pw.Text('Dispatched Line Items Summary', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
              pw.SizedBox(height: 6),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    children: [
                      _pdfCell('#', bold: true, alignment: pw.Alignment.center),
                      _pdfCell('Item Code', bold: true),
                      _pdfCell('Item Description', bold: true),
                      _pdfCell('Unit', bold: true, alignment: pw.Alignment.center),
                      _pdfCell('Quantity Dispatched', bold: true, alignment: pw.Alignment.centerRight),
                    ],
                  ),
                  ...List.generate(itemsList.length, (idx) {
                    final row = itemsList[idx];
                    final qtyVal = double.tryParse(row['qty']?.toString() ?? '0') ?? 0.0;
                    return pw.TableRow(
                      children: [
                        _pdfCell('${idx + 1}', alignment: pw.Alignment.center),
                        _pdfCell(row['item_code'] ?? 'N/A'),
                        _pdfCell(row['item_name'] ?? 'Item'),
                        _pdfCell(row['unit'] ?? 'PCS', alignment: pw.Alignment.center),
                        _pdfCell(qtyVal.toStringAsFixed(2), alignment: pw.Alignment.centerRight, bold: true),
                      ],
                    );
                  }),
                ],
              ),
              pw.SizedBox(height: 14),

              // Totals Box
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Container(
                  width: 220,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text('Total Dispatched Qty:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                      pw.Text('${totalQty.toStringAsFixed(2)} Units', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blue900)),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(height: 20),

              // Declarations
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey50,
                  border: pw.Border.all(color: PdfColors.grey200),
                ),
                child: pw.Text(
                  'Declaration: Received the above mentioned goods/materials in good condition, correct quantity, and intact order as specified in this delivery challan.',
                  style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                ),
              ),

              pw.Spacer(),

              // Signatures Block
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 120, height: 1, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Dispatched By (Store/Factory)', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 120, height: 1, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Driver / Transporter Signature', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Container(width: 120, height: 1, color: PdfColors.grey500),
                      pw.SizedBox(height: 4),
                      pw.Text('Receiver Signature & Stamp', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      name: 'Delivery_Challan_$challanNo',
      onLayout: (format) async => pdf.save(),
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false, pw.Alignment alignment = pw.Alignment.centerLeft}) {
    return pw.Container(
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: bold ? PdfColors.grey900 : PdfColors.grey800,
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    double? width,
  }) {
    final card = Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(14),
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
                  Text(title, style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Colors.grey.shade900)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: card);
    }
    return Expanded(child: card);
  }

  Widget _buildFilterChip(String value, String label, bool isSelected, Function(bool) onSelected) {
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : Colors.black87,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF008060),
      checkmarkColor: Colors.white,
      showCheckmark: false,
      backgroundColor: Colors.grey.shade100,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? const Color(0xFF008060) : Colors.grey.shade300),
      ),
      onSelected: onSelected,
    );
  }

  Widget _buildDateChip(String key, String label) {
    final isSelected = _selectedDateFilter == key;
    return FilterChip(
      avatar: isSelected ? null : const Icon(Icons.calendar_today, size: 12, color: Colors.blueGrey),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : Colors.blueGrey.shade800,
        ),
      ),
      selected: isSelected,
      selectedColor: const Color(0xFF0B5CAD),
      checkmarkColor: Colors.white,
      showCheckmark: false,
      backgroundColor: Colors.blueGrey.shade50,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? const Color(0xFF0B5CAD) : Colors.blueGrey.shade200),
      ),
      onSelected: (_) {
        setState(() {
          _selectedDateFilter = key;
        });
      },
    );
  }

  Widget _buildCustomDateChip() {
    final isSelected = _selectedDateFilter == 'CUSTOM';
    String label = 'Date Range';
    if (_customDateRange != null && isSelected) {
      final f = DateFormat('dd MMM');
      label = '${f.format(_customDateRange!.start)} - ${f.format(_customDateRange!.end)}';
    }

    return ActionChip(
      avatar: Icon(Icons.date_range, size: 13, color: isSelected ? Colors.white : const Color(0xFF0B5CAD)),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
          color: isSelected ? Colors.white : const Color(0xFF0B5CAD),
        ),
      ),
      backgroundColor: isSelected ? const Color(0xFF0B5CAD) : Colors.blue.shade50,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: isSelected ? const Color(0xFF0B5CAD) : Colors.blue.shade300),
      ),
      onPressed: () async {
        final now = DateTime.now();
        final picked = await showDateRangePicker(
          context: context,
          firstDate: DateTime(now.year - 2),
          lastDate: DateTime(now.year + 1),
          initialDateRange: _customDateRange ?? DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
          builder: (context, child) {
            return Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.light(
                  primary: Color(0xFF008060),
                  onPrimary: Colors.white,
                ),
              ),
              child: child!,
            );
          },
        );
        if (picked != null) {
          setState(() {
            _customDateRange = picked;
            _selectedDateFilter = 'CUSTOM';
          });
        }
      },
    );
  }

  Widget _buildDriverLiveGpsWidget(Map<String, dynamic> driver) {
    final rawAddr = driver['last_location_address']?.toString().trim();
    final lat = driver['last_latitude'] != null ? double.tryParse(driver['last_latitude'].toString()) : null;
    final lng = driver['last_longitude'] != null ? double.tryParse(driver['last_longitude'].toString()) : null;

    if ((rawAddr == null || rawAddr.isEmpty) && lat == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_searching, size: 13, color: Colors.orange.shade700),
            const SizedBox(width: 4),
            Text(
              'Live GPS: Waiting for driver location...',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      );
    }

    // Trigger async geocode if needed
    if (lat != null && lng != null) {
      final key = '${lat.toStringAsFixed(3)},${lng.toStringAsFixed(3)}';
      if (!GeoHelper.hasCached(key)) {
        GeoHelper.reverseGeocode(lat, lng).then((res) {
          if (res != null && mounted) setState(() {});
        });
      }
    }

    final displayText = GeoHelper.formatLocation(rawAddr, lat, lng);

    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 4,
        children: [
          const Icon(Icons.location_on, size: 14, color: Colors.green),
          Text(
            'Live GPS: $displayText',
            style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Color _getDeliveryStatusBg(String status) {
    switch (status) {
      case 'IN_TRANSIT':
        return Colors.indigo.shade50;
      case 'DELIVERED':
        return Colors.green.shade50;
      case 'RETURNED':
        return Colors.red.shade50;
      default:
        return Colors.orange.shade50;
    }
  }

  Color _getDeliveryStatusBorder(String status) {
    switch (status) {
      case 'IN_TRANSIT':
        return Colors.indigo.shade200;
      case 'DELIVERED':
        return Colors.green.shade300;
      case 'RETURNED':
        return Colors.red.shade300;
      default:
        return Colors.orange.shade200;
    }
  }

  Color _getDeliveryStatusTextColor(String status) {
    switch (status) {
      case 'IN_TRANSIT':
        return Colors.indigo.shade900;
      case 'DELIVERED':
        return Colors.green.shade900;
      case 'RETURNED':
        return Colors.red.shade900;
      default:
        return Colors.orange.shade900;
    }
  }

  String _getDeliveryStatusLabel(String status) {
    switch (status) {
      case 'IN_TRANSIT':
        return 'IN-TRANSIT (ON ROAD)';
      case 'DELIVERED':
        return 'DELIVERED & VERIFIED';
      case 'RETURNED':
        return 'RETURNED';
      default:
        return 'PENDING DISPATCH';
    }
  }
}
