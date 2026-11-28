import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../controllers/restaurant/restaurant_controller.dart';
import '../../core/api/api_client.dart';
import '../../core/api/endpoints.dart';
import 'reservation_report_screen.dart';

class TableReservationScreen extends StatefulWidget {
  const TableReservationScreen({
    super.key,
  });

  @override
  State<TableReservationScreen> createState() => _TableReservationScreenState();
}

class _TableReservationScreenState extends State<TableReservationScreen> {
  late DateTime _selectedDate;
  late List<DateTime> _upcomingDates;

  final List<String> _selectedTimeSlots = ['10:30 PM'];
  String get _selectedTimeSlot => _selectedTimeSlots.isNotEmpty ? _selectedTimeSlots.first : '10:30 PM';
  int _guestCount = 2;
  final List<int> _selectedTableIds = [];
  final List<String> _selectedTableNames = [];
  int? get _selectedTableId => _selectedTableIds.isNotEmpty ? _selectedTableIds.first : null;
  set _selectedTableId(int? v) {
    if (v == null) {
      _selectedTableIds.clear();
      _selectedTableNames.clear();
    }
  }
  String? get _selectedTableName => _selectedTableNames.isNotEmpty ? _selectedTableNames.join(', ') : null;

  String _eventType = 'Dining';
  String _pricingMode = 'VENUE_AND_FOOD'; // 'VENUE_ONLY' | 'VENUE_AND_FOOD'
  final TextEditingController _customEventCtrl = TextEditingController();
  final TextEditingController _hallCountCtrl = TextEditingController(text: '1');
  final TextEditingController _hallRateCtrl = TextEditingController(text: '0');
  final TextEditingController _perPersonRateCtrl = TextEditingController(text: '0');
  final TextEditingController _bookingAmtCtrl = TextEditingController(text: '0');
  final TextEditingController _advancePaidCtrl = TextEditingController(text: '0');
  List<Map<String, dynamic>> _masterMenuItems = [];
  List<Map<String, dynamic>> _customers = [];
  final TextEditingController _customerSearchCtrl = TextEditingController();
  final List<Map<String, dynamic>> _selectedMenuItems = [];
  final List<Map<String, dynamic>> _extraCharges = [];

  final TextEditingController _guestNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _addressCtrl = TextEditingController();
  final TextEditingController _gstinCtrl = TextEditingController();

  // Group slots by session
  final Map<String, List<Map<String, String>>> _sessions = {
    'Morning Session (08:00 AM - 11:30 AM)': [
      {'time': '08:00 AM', 'label': ''},
      {'time': '09:00 AM', 'label': ''},
      {'time': '10:00 AM', 'label': ''},
      {'time': '11:00 AM', 'label': 'Breakfast'},
    ],
    'Lunch Session (12:00 PM - 04:30 PM)': [
      {'time': '12:00 PM', 'label': ''},
      {'time': '01:00 PM', 'label': ''},
      {'time': '02:00 PM', 'label': ''},
      {'time': '03:00 PM', 'label': ''},
      {'time': '04:00 PM', 'label': 'Lunch Walk-in'},
    ],
    'Evening Session (06:00 PM - 11:00 PM)': [
      {'time': '06:00 PM', 'label': ''},
      {'time': '07:00 PM', 'label': ''},
      {'time': '08:00 PM', 'label': ''},
      {'time': '09:00 PM', 'label': ''},
      {'time': '10:30 PM', 'label': ''},
      {'time': '11:00 PM', 'label': 'Walk-in'},
    ],
  };

  static const Color primaryBlue = Color(0xFF0B5CAD);
  static const Color primaryDark = Color(0xFF0F172A);
  static const Color bgGray = Color(0xFFF4F6FA);
  static const Color cardBg = Colors.white;
  static const Color activeBlueBg = Color(0xFFEFF6FF);
  static const Color activeBlueBorder = Color(0xFF2563EB);

  void _selectFirstAvailableSlot() {
    for (final sessionKey in _sessions.keys) {
      for (final slot in _sessions[sessionKey]!) {
        final timeStr = slot['time']!;
        if (!_isSlotPast(timeStr)) {
          _selectedTimeSlots
            ..clear()
            ..add(timeStr);
          return;
        }
      }
    }
    _selectedTimeSlots
      ..clear()
      ..add(_sessions.values.first.first['time']!);
  }

  bool _isSlotPast(String timeStr) {
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    if (!isToday) return false;

    try {
      final parts = timeStr.split(' ');
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      final int minute = int.parse(timeParts[1]);
      final amPm = parts[1].toUpperCase();

      if (amPm == 'PM' && hour != 12) {
        hour += 12;
      } else if (amPm == 'AM' && hour == 12) {
        hour = 0;
      }

      final slotTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour, minute);
      return slotTime.isBefore(now);
    } catch (e) {
      return false;
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _upcomingDates = List.generate(14, (i) => DateTime.now().add(Duration(days: i)));
    _selectFirstAvailableSlot();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctrl = Provider.of<RestaurantController>(context, listen: false);
      ctrl.loadTables();
      ctrl.loadReservations();
      try {
        final res = await ApiClient.get(ApiEndpoints.items);
        if (res['success'] == true && res['data'] is List && mounted) {
          setState(() {
            _masterMenuItems = List<Map<String, dynamic>>.from(res['data']);
          });
        }
      } catch (_) {}
      try {
        final cRes = await ApiClient.get(ApiEndpoints.salesCustomers, silent: true);
        if (cRes['success'] == true && cRes['data'] is List && mounted) {
          setState(() {
            _customers = (cRes['data'] as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _guestNameCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    _addressCtrl.dispose();
    _gstinCtrl.dispose();
    super.dispose();
  }

  DateTime? _parseSlotDateTime(String slotStr) {
    if (slotStr.trim().isEmpty) return null;
    try {
      final parts = slotStr.trim().split(' ');
      final timeParts = parts[0].split(':');
      int hour = int.parse(timeParts[0]);
      final int minute = int.parse(timeParts[1]);
      final amPm = parts[1].toUpperCase();

      if (amPm == 'PM' && hour != 12) {
        hour += 12;
      } else if (amPm == 'AM' && hour == 12) {
        hour = 0;
      }

      return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  DateTime? _getSelectedSlotDateTime() => _parseSlotDateTime(_selectedTimeSlot);

  List<DateTime> _parseReservationSlotTimes(dynamic resv, DateTime baseResvTime) {
    final List<DateTime> times = [baseResvTime];
    final remarks = (resv['remarks'] ?? '').toString();
    final match = RegExp(r'\[Slots:\s*([^\]]+)\]').firstMatch(remarks);
    if (match != null) {
      final rawSlots = match.group(1)!.split(',');
      for (final s in rawSlots) {
        final parsed = _parseSlotDateTime(s.trim());
        if (parsed != null) {
          times.add(DateTime(baseResvTime.year, baseResvTime.month, baseResvTime.day, parsed.hour, parsed.minute));
        }
      }
    }
    return times;
  }

  bool _isTableOccupiedOrBooked(dynamic table, RestaurantController ctrl) {
    final int tableId = int.tryParse('${table['id']}') ?? -1;
    final selectedSlotTimes = _selectedTimeSlots.map(_parseSlotDateTime).whereType<DateTime>().toList();

    // Check existing reservations for multi-slot & multi-table overlap
    for (final resv in ctrl.reservations) {
      final int? resvTableId = int.tryParse('${resv['table_id'] ?? resv['table']?['id']}');
      final List<int> resvTableIds = (resv['table_ids'] is List)
          ? (resv['table_ids'] as List).map((e) => int.tryParse('$e')).whereType<int>().toList()
          : <int>[];
      final bool matchesTable = resvTableId == tableId || resvTableIds.contains(tableId);

      if (matchesTable) {
        final String resvStatus = (resv['status'] ?? '').toString().toLowerCase();
        if (resvStatus != 'cancelled' && resvStatus != 'completed' && resvStatus != 'rejected') {
          final DateTime? resvTime = DateTime.tryParse(resv['reservation_time'] ?? '')?.toLocal();
          if (resvTime != null) {
            final isSameDay = resvTime.year == _selectedDate.year &&
                resvTime.month == _selectedDate.month &&
                resvTime.day == _selectedDate.day;

            if (isSameDay) {
              if (selectedSlotTimes.isNotEmpty) {
                final existingTimes = _parseReservationSlotTimes(resv, resvTime);
                for (final selDt in selectedSlotTimes) {
                  for (final exDt in existingTimes) {
                    if (exDt.difference(selDt).inMinutes.abs() < 60) {
                      return true; // Overlaps with an already booked slot
                    }
                  }
                }
              } else {
                return true;
              }
            }
          }
        }
      }
    }

    // Check if table is currently Occupied or Billed physically on canvas right now
    final String currentStatus = (table['status'] ?? '').toString();
    if (currentStatus == 'Occupied' || currentStatus == 'Billed') {
      final now = DateTime.now();
      final isToday = _selectedDate.year == now.year &&
          _selectedDate.month == now.month &&
          _selectedDate.day == now.day;

      if (isToday && selectedSlotTimes.isNotEmpty) {
        for (final selDt in selectedSlotTimes) {
          if (now.difference(selDt).inMinutes.abs() < 90) {
            return true;
          }
        }
      }
    }

    return false;
  }

  Widget _cardSection({required String title, IconData? icon, Widget? trailing, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardBg,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: primaryBlue),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: primaryDark,
                    ),
                  ),
                ],
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Future<void> _showCustomGuestCountDialog() async {
    int enteredCount = _guestCount;
    final res = await showDialog<int>(
      context: context,
      builder: (context) {
        final textCtrl = TextEditingController(text: enteredCount > 8 ? enteredCount.toString() : '');
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Text('Enter Custom Guest Count', style: TextStyle(fontWeight: FontWeight.bold)),
          content: TextField(
            controller: textCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Number of Guests',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final int? val = int.tryParse(textCtrl.text);
                if (val != null && val > 0) {
                  Navigator.pop(context, val);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter a valid guest count')),
                  );
                }
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
    if (res != null) {
      setState(() {
        _guestCount = res;
        _selectedTableId = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = context.watch<RestaurantController>();

    return Scaffold(
      backgroundColor: bgGray,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryDark, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Book Table',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: primaryDark),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryBlue,
                side: const BorderSide(color: Color(0xFFBFDBFE)),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.assessment_outlined, size: 16),
              label: const Text('Reports', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReservationReportScreen()),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section 1: Select Date ──────────────────────────────────────
            _cardSection(
              title: 'Select Date',
              icon: Icons.calendar_month_outlined,
              trailing: IconButton(
                icon: const Icon(Icons.edit_calendar, color: primaryBlue, size: 20),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 30)),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (picked != null) {
                    setState(() {
                      final index = _upcomingDates.indexWhere((d) =>
                          d.year == picked.year &&
                          d.month == picked.month &&
                          d.day == picked.day);
                      if (index == -1) {
                        if (picked.isAfter(DateTime.now())) {
                          final diff = picked.difference(DateTime.now()).inDays;
                          _upcomingDates = List.generate(diff + 7, (i) => DateTime.now().add(Duration(days: i)));
                        } else {
                          _upcomingDates.insert(0, picked);
                        }
                      }
                      _selectedDate = picked;
                      _selectedTableId = null;
                      _selectFirstAvailableSlot();
                    });
                  }
                },
              ),
              child: SizedBox(
                height: 64,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _upcomingDates.length,
                  itemBuilder: (context, index) {
                    final dt = _upcomingDates[index];
                    final isSelected = dt.year == _selectedDate.year &&
                        dt.month == _selectedDate.month &&
                        dt.day == _selectedDate.day;

                    final dayName = DateFormat('EEE').format(dt);
                    final dayDate = DateFormat('d MMM').format(dt);

                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedDate = dt;
                            _selectedTableId = null;
                            _selectFirstAvailableSlot();
                          });
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 76,
                          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? activeBlueBg : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? activeBlueBorder : const Color(0xFFCBD5E1),
                              width: isSelected ? 1.8 : 1.0,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dayName,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? primaryBlue : Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                dayDate,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? primaryBlue : primaryDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Section 2: Select Time Slot (Multi-Slot Supported) ────
            _cardSection(
              title: 'Select Time Slot(s) — Multi-Slot for 2h/4h+ Events',
              icon: Icons.access_time_outlined,
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: activeBlueBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: activeBlueBorder.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${_selectedTimeSlots.length} Slot${_selectedTimeSlots.length > 1 ? 's' : ''} (${_selectedTimeSlots.length}h)',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryBlue),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _sessions.keys.map((sessionName) {
                  final slots = _sessions[sessionName]!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              sessionName.contains('Morning')
                                  ? Icons.wb_sunny_outlined
                                  : sessionName.contains('Lunch')
                                      ? Icons.lunch_dining_outlined
                                      : Icons.nightlight_round,
                              color: const Color(0xFF475569),
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              sessionName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                  color: primaryDark),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: slots.map((slot) {
                            final timeStr = slot['time']!;
                            final labelStr = slot['label']!;
                            final isSelected = _selectedTimeSlots.contains(timeStr);
                            final isPast = _isSlotPast(timeStr);

                            return InkWell(
                              onTap: isPast
                                  ? null
                                  : () {
                                      setState(() {
                                        if (_selectedTimeSlots.contains(timeStr)) {
                                          if (_selectedTimeSlots.length > 1) {
                                            _selectedTimeSlots.remove(timeStr);
                                          }
                                        } else {
                                          _selectedTimeSlots.add(timeStr);
                                        }
                                        _selectedTimeSlots.sort((a, b) {
                                          final da = _parseSlotDateTime(a);
                                          final db = _parseSlotDateTime(b);
                                          if (da == null || db == null) return 0;
                                          return da.compareTo(db);
                                        });
                                        _selectedTableId = null;
                                      });
                                    },
                              borderRadius: BorderRadius.circular(8),
                              child: Opacity(
                                opacity: isPast ? 0.4 : 1.0,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? activeBlueBg
                                        : (isPast ? bgGray : Colors.white),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isSelected
                                          ? activeBlueBorder
                                          : const Color(0xFFCBD5E1),
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        timeStr,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11.5,
                                          color: isSelected
                                              ? primaryBlue
                                              : (isPast
                                                  ? Colors.grey
                                                  : primaryDark),
                                        ),
                                      ),
                                      if (labelStr.isNotEmpty) ...[
                                        const SizedBox(height: 1),
                                        Text(
                                          labelStr,
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: isSelected
                                                ? primaryBlue
                                                : Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 16),

            // ── Section 3: Number of Guests ────────────────────────────────
            _cardSection(
              title: 'Number of Guests',
              icon: Icons.people_outline,
              child: SizedBox(
                height: 42,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: 9,
                  itemBuilder: (context, index) {
                    if (index == 8) {
                      final bool isCustomSelected = _guestCount > 8;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: InkWell(
                          onTap: _showCustomGuestCountDialog,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isCustomSelected ? activeBlueBg : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCustomSelected ? activeBlueBorder : const Color(0xFFCBD5E1),
                                width: isCustomSelected ? 1.8 : 1.0,
                              ),
                            ),
                            child: Text(
                              isCustomSelected ? '$_guestCount' : 'Custom...',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isCustomSelected ? primaryBlue : primaryDark,
                              ),
                            ),
                          ),
                        ),
                      );
                    }

                    final count = index + 1;
                    final isSelected = _guestCount == count;

                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _guestCount = count;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? activeBlueBg : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? activeBlueBorder : const Color(0xFFCBD5E1),
                              width: isSelected ? 1.8 : 1.0,
                            ),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13.5,
                              color: isSelected ? primaryBlue : primaryDark,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── Section 4: Multiple Table Selection ────────────────────────
            _cardSection(
              title: 'Select Table(s) — Multi-Table Supported',
              icon: Icons.table_restaurant,
              child: ctrl.tables.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'No tables configured yet.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: ctrl.tables.map((table) {
                        final bool isOccupied = _isTableOccupiedOrBooked(table, ctrl);
                        final int tid = int.tryParse((table['id'] ?? 0).toString()) ?? 0;
                        final String tname = (table['table_name'] ?? 'Table').toString();
                        final bool isSelected = _selectedTableIds.contains(tid);

                        return InkWell(
                          onTap: isOccupied
                              ? null
                              : () {
                                  setState(() {
                                    if (isSelected) {
                                      _selectedTableIds.remove(tid);
                                      _selectedTableNames.remove(tname);
                                    } else {
                                      _selectedTableIds.add(tid);
                                      _selectedTableNames.add(tname);
                                    }
                                  });
                                },
                          borderRadius: BorderRadius.circular(10),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: isOccupied
                                  ? const Color(0xFFF1F5F9)
                                  : isSelected
                                      ? activeBlueBg
                                      : Colors.white,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isOccupied
                                    ? const Color(0xFFE2E8F0)
                                    : isSelected
                                        ? activeBlueBorder
                                        : const Color(0xFFCBD5E1),
                                width: isSelected ? 2.0 : 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.table_restaurant_outlined,
                                  size: 18,
                                  color: isOccupied
                                      ? Colors.grey.shade400
                                      : isSelected
                                          ? primaryBlue
                                          : primaryBlue.withValues(alpha: 0.8),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      table['table_name'] ?? '',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: isOccupied ? Colors.grey.shade500 : primaryDark,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Cap: ${table['capacity'] ?? 2}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: isOccupied ? Colors.grey.shade400 : Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isOccupied ? const Color(0xFFFEE2E2) : const Color(0xFFDCFCE7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isOccupied ? 'Booked' : 'Free',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: isOccupied ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
            ),

            const SizedBox(height: 16),

            // ── Section 5: Guest Information ──────────────────────────────
            _cardSection(
              title: 'Guest Details',
              icon: Icons.person_outline,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _customerSearchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Search Existing Customer (Name or Phone)',
                      hintText: 'Type customer name or phone number...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _customerSearchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(() => _customerSearchCtrl.clear()),
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_customerSearchCtrl.text.trim().isNotEmpty) ...[
                    Builder(
                      builder: (_) {
                        final q = _customerSearchCtrl.text.trim().toLowerCase();
                        final matches = _customers.where((c) {
                          final name = (c['name'] ?? c['customer_name'] ?? '').toString().toLowerCase();
                          final phone = (c['phone'] ?? c['mobile'] ?? c['customer_phone'] ?? '').toString().toLowerCase();
                          return name.contains(q) || phone.contains(q);
                        }).take(6).toList();
                        if (matches.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.only(top: 6, bottom: 4),
                            child: Text('No matching saved customer found — enter details below.', style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B))),
                          );
                        }
                        return Container(
                          margin: const EdgeInsets.only(top: 6, bottom: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Column(
                            children: matches.map((c) {
                              final cName = (c['name'] ?? c['customer_name'] ?? 'Guest').toString();
                              final cPhone = (c['phone'] ?? c['mobile'] ?? c['customer_phone'] ?? '').toString();
                              final cAddr = (c['address'] ?? '').toString();
                              final cGstin = (c['gstin'] ?? '').toString();
                              return ListTile(
                                dense: true,
                                leading: const Icon(Icons.person, size: 18, color: primaryBlue),
                                title: Text(cName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                subtitle: cPhone.isNotEmpty ? Text(cPhone, style: const TextStyle(fontSize: 11.5)) : null,
                                trailing: const Text('Select', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: primaryBlue)),
                                onTap: () {
                                  setState(() {
                                    _guestNameCtrl.text = cName;
                                    _phoneCtrl.text = cPhone;
                                    if (cAddr.isNotEmpty) _addressCtrl.text = cAddr;
                                    if (cGstin.isNotEmpty) _gstinCtrl.text = cGstin;
                                    _customerSearchCtrl.clear();
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _guestNameCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Guest Name',
                            hintText: 'e.g. Rajesh Kumar',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Phone Number',
                            hintText: 'e.g. +91 9876543210',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _addressCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Address',
                            hintText: 'Address',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _gstinCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'GSTIN',
                            hintText: 'GSTIN',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Section 5: Event Type, Menu Items & Estimated Quotation ────
            _buildEventAndQuotationSection(),

            const SizedBox(height: 20),

            // Print / Send Quotation + Confirm Buttons
            Row(
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.print_outlined, size: 18),
                  label: const Text('Print Quote'),
                  onPressed: () => ReservationQuotationHelper.printQuotation(context, _buildReservationPayload()),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.share_outlined, size: 18, color: Colors.green),
                  label: const Text('Send Quote'),
                  onPressed: () => ReservationQuotationHelper.shareQuotation(context, _buildReservationPayload()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 1,
                      ),
                      onPressed: _selectedTableIds.isEmpty
                          ? null
                          : () async {
                              final String guestName = _guestNameCtrl.text.trim();
                              if (guestName.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Please enter guest name.')),
                                );
                                return;
                              }
                              final payload = _buildReservationPayload();
                              final success = await ctrl.saveReservation(payload);
                              if (mounted) {
                                if (success) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Table $_selectedTableName booked successfully for $guestName!'),
                                      backgroundColor: Colors.green.shade700,
                                    ),
                                  );
                                  Navigator.pop(context);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Failed to save reservation. Please try again.')),
                                  );
                                }
                              }
                            },
                      child: Text(
                        _selectedTableIds.isEmpty
                            ? 'Select Table(s) above'
                            : 'Confirm Booking (${_selectedTableName ?? ''})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasPerPersonCharge => _pricingMode == 'VENUE_AND_FOOD' && _perPersonRate > 0;

  double get _itemsTotal => _hasPerPersonCharge
      ? 0.0
      : _selectedMenuItems.fold<double>(
          0, (s, m) => s + ((double.tryParse((m['qty'] ?? 1).toString()) ?? 1) * (double.tryParse((m['rate'] ?? 0).toString()) ?? 0)));

  double get _extraChargesTotal => _extraCharges.fold<double>(
      0, (s, m) => s + ((double.tryParse((m['qty'] ?? 1).toString()) ?? 1) * (double.tryParse((m['rate'] ?? 0).toString()) ?? 0)));

  int get _hallCount => int.tryParse(_hallCountCtrl.text.trim()) ?? 0;
  double get _hallRate => double.tryParse(_hallRateCtrl.text.trim()) ?? 0;
  double get _hallTotal => _hallCount * _hallRate;
  double get _perPersonRate => _pricingMode == 'VENUE_AND_FOOD' ? (double.tryParse(_perPersonRateCtrl.text.trim()) ?? 0) : 0;
  double get _perPersonTotal => _pricingMode == 'VENUE_AND_FOOD' ? (_guestCount * _perPersonRate) : 0;
  double get _autoTotalBookingAmount => _hallTotal + _perPersonTotal + _itemsTotal + _extraChargesTotal;

  Map<String, dynamic> _buildReservationPayload() {
    final formattedTimeStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final hall = _hallTotal;
    final perPersonTot = _perPersonTotal;
    final extraTot = _extraChargesTotal;
    final advPaid = double.tryParse(_advancePaidCtrl.text.trim()) ?? 0;
    final menuItemsTot = _itemsTotal;
    final combinedItemsTot = menuItemsTot + perPersonTot + extraTot;
    final totalCost = _autoTotalBookingAmount;

    final effectiveMenuItems = _selectedMenuItems.map((m) {
      if (_hasPerPersonCharge) {
        return {
          ...m,
          'rate': 0.0,
          'amount': 0.0,
          'included_in_per_person': true,
        };
      }
      return m;
    }).toList();

    final List<Map<String, dynamic>> quoteItems = [
      ...effectiveMenuItems,
      if (_hasPerPersonCharge)
        {
          'item_name': 'Food Package (Per Person)',
          'qty': _guestCount,
          'rate': _perPersonRate,
          'amount': perPersonTot,
          'category': 'PER_PERSON',
        },
      ..._extraCharges.map((e) => {...e, 'category': 'EXTRA_CHARGE'}),
    ];

    final baseRemarks = _notesCtrl.text.trim();
    final slotTag = _selectedTimeSlots.length > 1 ? '[Slots: ${_selectedTimeSlots.join(', ')}]' : '';
    final fullRemarks = [baseRemarks, slotTag].where((s) => s.isNotEmpty).join(' ').trim();

    return {
      'table_id': _selectedTableId,
      'table_ids': _selectedTableIds,
      'table_names': _selectedTableName,
      'customer_name': _guestNameCtrl.text.trim().isEmpty ? 'Guest' : _guestNameCtrl.text.trim(),
      'customer_phone': _phoneCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'guest_count': _guestCount,
      'reservation_time': '$formattedTimeStr $_selectedTimeSlot',
      'selected_slots': _selectedTimeSlots,
      'duration_hours': _selectedTimeSlots.length,
      'status': 'Confirmed',
      'remarks': fullRemarks,
      'address': _addressCtrl.text.trim(),
      'gstin': _gstinCtrl.text.trim(),
      'event_type': _eventType,
      'custom_event_name': _eventType == 'Custom' ? _customEventCtrl.text.trim() : null,
      'menu_items': quoteItems,
      'hall_charges': hall,
      'hall_count': _hallCount,
      'hall_rate': _hallRate,
      'pricing_mode': _pricingMode,
      'per_person_rate': _perPersonRate,
      'items_total': combinedItemsTot,
      'booking_amount': totalCost,
      'advance_paid': advPaid,
      'total_cost': totalCost,
    };
  }

  Widget _buildEventAndQuotationSection() {
    final hall = _hallTotal;
    final perPersonTot = _perPersonTotal;
    final extraTot = _extraChargesTotal;
    final advPaid = double.tryParse(_advancePaidCtrl.text.trim()) ?? 0;
    final itemsTot = _itemsTotal;
    final totalCost = _autoTotalBookingAmount;
    final balance = totalCost - advPaid;
    _bookingAmtCtrl.text = totalCost.toStringAsFixed(2);

    return _cardSection(
      title: 'Event Type, Venue / Food & Estimated Quotation',
      icon: Icons.celebration_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['Dining', 'Lunch', 'Dinner', 'Birthday Party', 'Anniversary', 'Custom'].map((ev) {
              final sel = _eventType == ev;
              return ChoiceChip(
                label: Text(ev, style: TextStyle(fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                selected: sel,
                onSelected: (_) => setState(() => _eventType = ev),
              );
            }).toList(),
          ),
          if (_eventType == 'Custom') ...[
            const SizedBox(height: 10),
            TextField(
              controller: _customEventCtrl,
              decoration: const InputDecoration(
                labelText: 'Custom Event Name',
                hintText: 'e.g. Corporate Meetup, Engagement...',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          const Text('Booking Charge Option', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Venue / Hall Only', style: TextStyle(fontSize: 12)),
                selected: _pricingMode == 'VENUE_ONLY',
                onSelected: (_) => setState(() => _pricingMode = 'VENUE_ONLY'),
              ),
              ChoiceChip(
                label: const Text('Venue + Food (Per Person)', style: TextStyle(fontSize: 12)),
                selected: _pricingMode == 'VENUE_AND_FOOD',
                onSelected: (_) => setState(() => _pricingMode = 'VENUE_AND_FOOD'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 145,
                child: TextField(
                  controller: _hallCountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Halls / Venues Qty', isDense: true, border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: 170,
                child: TextField(
                  controller: _hallRateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Rate / Venue (₹)',
                    helperText: 'Total: ₹${hall.toStringAsFixed(0)}',
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              if (_pricingMode == 'VENUE_AND_FOOD')
                SizedBox(
                  width: 195,
                  child: TextField(
                    controller: _perPersonRateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Food Rate / Person (₹)',
                      helperText: '$_guestCount Pax × ₹${_perPersonRate.toStringAsFixed(0)} = ₹${perPersonTot.toStringAsFixed(0)}',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              SizedBox(
                width: 185,
                child: TextField(
                  controller: _bookingAmtCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Booking Amount (Auto ₹)',
                    filled: true,
                    fillColor: Color(0xFFF1F5F9),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              SizedBox(
                width: 165,
                child: TextField(
                  controller: _advancePaidCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Advance Paid (₹)', isDense: true, border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pre-Selected Menu Items (${_selectedMenuItems.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              OutlinedButton.icon(
                icon: const Icon(Icons.restaurant_menu, size: 15),
                label: const Text('Add Menu Item', style: TextStyle(fontSize: 12)),
                onPressed: _openMenuPickerDialog,
              ),
            ],
          ),
          if (_selectedMenuItems.isNotEmpty) ...[
            const SizedBox(height: 6),
            ..._selectedMenuItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final m = entry.value;
              final q = (double.tryParse((m['qty'] ?? 1).toString()) ?? 1).round();
              final r = double.tryParse((m['rate'] ?? 0).toString()) ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${m['item_name']}  (@ ₹${r.toStringAsFixed(2)})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: q > 1
                          ? () => setState(() {
                                _selectedMenuItems[idx]['qty'] = q - 1;
                                _selectedMenuItems[idx]['amount'] = (q - 1) * r;
                              })
                          : null,
                    ),
                    Text('$q', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 18, color: primaryBlue),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _selectedMenuItems[idx]['qty'] = q + 1;
                        _selectedMenuItems[idx]['amount'] = (q + 1) * r;
                      }),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 95,
                      child: Text(
                        _hasPerPersonCharge ? 'Included (₹0)' : '₹${(q * r).toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: _hasPerPersonCharge ? 11.5 : 13,
                          color: _hasPerPersonCharge ? const Color(0xFF059669) : const Color(0xFF0F172A),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 17, color: Colors.red),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _selectedMenuItems.removeAt(idx)),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Extra Charges / Decoration (${_extraCharges.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              OutlinedButton.icon(
                icon: const Icon(Icons.auto_awesome, size: 15),
                label: const Text('Add Extra Charge', style: TextStyle(fontSize: 12)),
                onPressed: _openAddExtraChargeDialog,
              ),
            ],
          ),
          if (_extraCharges.isNotEmpty) ...[
            const SizedBox(height: 6),
            ..._extraCharges.asMap().entries.map((entry) {
              final idx = entry.key;
              final ex = entry.value;
              final q = (double.tryParse((ex['qty'] ?? 1).toString()) ?? 1).round();
              final r = double.tryParse((ex['rate'] ?? 0).toString()) ?? 0;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${ex['item_name']}  (@ ₹${r.toStringAsFixed(2)})',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                      visualDensity: VisualDensity.compact,
                      onPressed: q > 1
                          ? () => setState(() {
                                _extraCharges[idx]['qty'] = q - 1;
                                _extraCharges[idx]['amount'] = (q - 1) * r;
                              })
                          : null,
                    ),
                    Text('$q', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 18, color: primaryBlue),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() {
                        _extraCharges[idx]['qty'] = q + 1;
                        _extraCharges[idx]['amount'] = (q + 1) * r;
                      }),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 85,
                      child: Text(
                        '₹${(q * r).toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 17, color: Colors.red),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => setState(() => _extraCharges.removeAt(idx)),
                    ),
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
            child: Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                Text('Hall ($_hallCount × ₹${_hallRate.toStringAsFixed(0)}): ₹${hall.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (_pricingMode == 'VENUE_AND_FOOD' && perPersonTot > 0)
                  Text('Food ($_guestCount × ₹${_perPersonRate.toStringAsFixed(0)}): ₹${perPersonTot.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (itemsTot > 0)
                  Text('Menu Items: ₹${itemsTot.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                if (extraTot > 0)
                  Text('Extra/Decor: ₹${extraTot.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('Total Cost: ₹${totalCost.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: primaryBlue)),
                Text('Advance: ₹${advPaid.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green)),
                Text('Balance: ₹${balance.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openAddExtraChargeDialog() async {
    final nameCtrl = TextEditingController();
    final qtyCtrl = TextEditingController(text: '1');
    final rateCtrl = TextEditingController(text: '0');
    final presets = ['Balloons & Decoration', 'DJ & Sound', 'Projector & Screen', 'Stage Lighting', 'Flower Decor'];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDs) => AlertDialog(
          title: const Text('Add Extra Charge / Decoration'),
          content: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: presets.map((p) => ActionChip(
                    label: Text(p, style: const TextStyle(fontSize: 11)),
                    onPressed: () => setDs(() => nameCtrl.text = p),
                  )).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Item / Service Name', isDense: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qty', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Rate (₹)', isDense: true, border: OutlineInputBorder()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(dCtx, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
      final rate = double.tryParse(rateCtrl.text.trim()) ?? 0;
      setState(() {
        _extraCharges.add({
          'item_name': nameCtrl.text.trim(),
          'qty': qty < 1 ? 1 : qty,
          'rate': rate,
          'amount': (qty < 1 ? 1 : qty) * rate,
        });
      });
    }
  }

  Future<void> _openMenuPickerDialog() async {
    String q = '';
    final picked = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setDs) {
          final filtered = _masterMenuItems
              .where((it) => q.isEmpty || (it['item_name'] ?? '').toString().toLowerCase().contains(q.toLowerCase()))
              .take(40)
              .toList();
          return AlertDialog(
            title: const Text('Select Menu Item'),
            content: SizedBox(
              width: 400,
              height: 360,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'Search menu item...', prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder()),
                    onChanged: (v) => setDs(() => q = v),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, idx) {
                        final it = filtered[idx];
                        final rate = double.tryParse((it['retail_sale_price'] ?? it['rate'] ?? 0).toString()) ?? 0;
                        return ListTile(
                          dense: true,
                          title: Text((it['item_name'] ?? '').toString()),
                          trailing: Text('₹${rate.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                          onTap: () => Navigator.pop(dCtx, it),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (picked == null) return;
    final rate = double.tryParse((picked['retail_sale_price'] ?? picked['rate'] ?? 0).toString()) ?? 0;
    setState(() {
      _selectedMenuItems.add({
        'item_id': picked['id'],
        'item_name': picked['item_name'],
        'qty': _guestCount,
        'rate': rate,
        'amount': _guestCount * rate,
      });
    });
  }
}
