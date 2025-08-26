import 'package:attendance_punch/model/attendance_event.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';




class SummaryCard extends StatelessWidget {
  final List<AttendanceEvent> events;
  const SummaryCard({super.key, required this.events});

  @override
  Widget build(BuildContext context) {
    final clockInEvents = events.where((e) => e.type == 'IN').toList();
    final clockOutEvents = events.where((e) => e.type == 'OUT').toList();

    final firstClockIn = clockInEvents.isNotEmpty ? clockInEvents.first : null;
    final lastClockOut = clockOutEvents.isNotEmpty ? clockOutEvents.last : null;

    Duration? totalWorkTime;
    if (firstClockIn != null && lastClockOut != null) {
      totalWorkTime = lastClockOut.time.difference(firstClockIn.time);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(children: [
              _tile(
                icon: Icons.login,
                color: Colors.green,
                label: 'Clock In',
                value: firstClockIn != null ? DateFormat('hh:mm a').format(firstClockIn.time) : '--:--',
              ),
              _divider(),
              _tile(
                icon: Icons.logout,
                color: Colors.orange,
                label: 'Clock Out',
                value: lastClockOut != null ? DateFormat('hh:mm a').format(lastClockOut.time) : '--:--',
              ),
              _divider(),
              _tile(
                icon: Icons.access_time,
                color: Colors.blue,
                label: 'Total Time',
                value: totalWorkTime != null
                    ? '${totalWorkTime.inHours}h ${totalWorkTime.inMinutes.remainder(60)}m'
                    : '--h --m',
              ),
            ]),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: _chip('Clock Ins: ', clockInEvents.length.toString(), Colors.green)),
              const SizedBox(width: 8),
              Expanded(child: _chip('Clock Outs: ', clockOutEvents.length.toString(), Colors.orange)),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 60, color: Colors.grey[300]);

  Widget _tile({required IconData icon, required Color color, required String label, required String value}) {
    return Expanded(
      child: Column(children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ]),
    );
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ]),
    );
  }
}