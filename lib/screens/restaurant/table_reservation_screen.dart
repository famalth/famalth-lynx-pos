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

  String _selectedTimeSlot = '10:30 PM';
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
  final TextEditingController _customEventCtrl = TextEditingController();
  final TextEditingController _hallChargesCtrl = TextEditingController(text: '0');
  final TextEditingController _bookingAmtCtrl = TextEditingController(text: '0');
  final TextEditingController _advancePaidCtrl = TextEditingController(text: '0');
  List<Map<String, dynamic>> _masterMenuItems = [];
  final List<Map<String, dynamic>> _selectedMenuItems = [];

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
          _selectedTimeSlot = timeStr;
          return;
        }
      }
    }
    _selectedTimeSlot = _sessions.values.first.first['time']!;
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

  DateTime? _getSelectedSlotDateTime() {
    final slot = _selectedTimeSlot;
    if (slot == null || slot.isEmpty) return null;
    try {
      final parts = slot.split(' ');
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

  bool _isTableOccupiedOrBooked(dynamic table, RestaurantController ctrl) {
    final int tableId = table['id'];
    final selectedSlotTime = _getSelectedSlotDateTime();

    // Check existing reservations for time slot overlap
    for (final resv in ctrl.reservations) {
      final int? resvTableId = resv['table_id'] ?? resv['table']?['id'];
      if (resvTableId == tableId) {
        final String resvStatus = (resv['status'] ?? '').toString().toLowerCase();
        if (resvStatus != 'cancelled' && resvStatus != 'completed' && resvStatus != 'rejected') {
          final DateTime? resvTime = DateTime.tryParse(resv['reservation_time'] ?? '');
          if (resvTime != null) {
            final isSameDay = resvTime.year == _selectedDate.year &&
                resvTime.month == _selectedDate.month &&
                resvTime.day == _selectedDate.day;

            if (isSameDay) {
              if (selectedSlotTime != null) {
                final diffInMinutes = resvTime.difference(selectedSlotTime).inMinutes.abs();
                if (diffInMinutes < 60) {
                  return true; // Already booked for this time slot
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

      if (isToday && selectedSlotTime != null) {
        final diffInMinutes = now.difference(selectedSlotTime).inMinutes.abs();
        if (diffInMinutes < 90) {
          return true;
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

            // ── Section 2: Select Time Slot ─────────────────────────
            _cardSection(
              title: 'Select Time Slot',
              icon: Icons.access_time_outlined,
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
                            final isSelected = _selectedTimeSlot == timeStr;
                            final isPast = _isSlotPast(timeStr);

                            return InkWell(
                              onTap: isPast
                                  ? null
                                  : () {
                                      setState(() {
                                        _selectedTimeSlot = timeStr;
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
                children: [
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

  double get _itemsTotal => _selectedMenuItems.fold<double>(
      0, (s, m) => s + ((double.tryParse((m['qty'] ?? 1).toString()) ?? 1) * (double.tryParse((m['rate'] ?? 0).toString()) ?? 0)));

  Map<String, dynamic> _buildReservationPayload() {
    final formattedTimeStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final hall = double.tryParse(_hallChargesCtrl.text.trim()) ?? 0;
    final bookAmt = double.tryParse(_bookingAmtCtrl.text.trim()) ?? 0;
    final advPaid = double.tryParse(_advancePaidCtrl.text.trim()) ?? 0;
    final itemsTot = _itemsTotal;
    final totalCost = hall + itemsTot + bookAmt;
    return {
      'table_id': _selectedTableId,
      'table_ids': _selectedTableIds,
      'table_names': _selectedTableName,
      'customer_name': _guestNameCtrl.text.trim().isEmpty ? 'Guest' : _guestNameCtrl.text.trim(),
      'customer_phone': _phoneCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'guest_count': _guestCount,
      'reservation_time': '$formattedTimeStr $_selectedTimeSlot',
      'status': 'Confirmed',
      'remarks': _notesCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'gstin': _gstinCtrl.text.trim(),
      'event_type': _eventType,
      'custom_event_name': _eventType == 'Custom' ? _customEventCtrl.text.trim() : null,
      'menu_items': _selectedMenuItems,
      'hall_charges': hall,
      'items_total': itemsTot,
      'booking_amount': bookAmt,
      'advance_paid': advPaid,
      'total_cost': totalCost,
    };
  }

  Widget _buildEventAndQuotationSection() {
    final hall = double.tryParse(_hallChargesCtrl.text.trim()) ?? 0;
    final bookAmt = double.tryParse(_bookingAmtCtrl.text.trim()) ?? 0;
    final advPaid = double.tryParse(_advancePaidCtrl.text.trim()) ?? 0;
    final itemsTot = _itemsTotal;
    final totalCost = hall + itemsTot + bookAmt;
    final balance = totalCost - advPaid;

    return _cardSection(
      title: 'Event Type, Menu Items & Estimated Quotation',
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
          const SizedBox(height: 12),
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
              final q = double.tryParse((m['qty'] ?? 1).toString()) ?? 1;
              final r = double.tryParse((m['rate'] ?? 0).toString()) ?? 0;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('${m['item_name']}  (${q.toStringAsFixed(0)} x ₹${r.toStringAsFixed(2)})', style: const TextStyle(fontSize: 13)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('₹${(q * r).toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 17, color: Colors.red),
                      onPressed: () => setState(() => _selectedMenuItems.removeAt(idx)),
                    ),
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _hallChargesCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Hall / Venue Charges (₹)', isDense: true, border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _bookingAmtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Booking Amount (₹)', isDense: true, border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _advancePaidCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Advance Paid (₹)', isDense: true, border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
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
                Text('Items Total: ₹${itemsTot.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                Text('Hall: ₹${hall.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
