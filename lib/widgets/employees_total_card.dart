import 'package:attendance_tracker/model/attendance_event.dart';
import 'package:flutter/material.dart';

class EmployeeTotalsCard extends StatelessWidget {
  final List<AttendanceEvent> events;
  final DateTime selectedDate;
  final bool isToday;
  const EmployeeTotalsCard({super.key, required this.events, required this.selectedDate, required this.isToday});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = _computeTotals(events, selectedDate, isToday);
    final totalAll = totals.fold<Duration>(Duration.zero, (acc, t) => acc + t.duration);

    String fmt(Duration d) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return '${h}h ${m.toString().padLeft(2, '0')}m';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            ListTile(
              dense: true,
              leading: const Icon(Icons.groups_outlined),
              title: const Text('Working time by employee'),
              trailing: Text(
                fmt(totalAll),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
              ),
            ),
            const Divider(height: 1),
            ...totals.map(
              (t) => ListTile(
                dense: true,
                leading: const Icon(Icons.person_outline),
                title: Text(t.employeeName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: t.employeeId == null ? null : Text(t.employeeId!, style: const TextStyle(fontSize: 12)),
                trailing: Text(
                  fmt(t.duration),
                  style: theme.textTheme.bodyMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()], fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmpBucket {
  final String? employeeId;
  final String employeeName;
  final List<AttendanceEvent> events = [];
  _EmpBucket({required this.employeeId, required this.employeeName});
}

class _EmpTotal {
  final String? employeeId;
  final String employeeName;
  final Duration duration;
  _EmpTotal({required this.employeeId, required this.employeeName, required this.duration});
}

List<_EmpTotal> _computeTotals(List<AttendanceEvent> events, DateTime selectedDate, bool isToday) {
  final Map<String, _EmpBucket> buckets = {};
  for (final e in events) {
    final empKey = e.employeeId ?? (e.employeeName != null ? 'name:${e.employeeName}' : 'unassigned');
    final b = buckets.putIfAbsent(empKey, () => _EmpBucket(employeeId: e.employeeId, employeeName: e.employeeName ?? (e.employeeId ?? 'Unassigned')));
    b.events.add(e);
  }

  final now = DateTime.now();
  final startOfDay = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
  final endOfDay = startOfDay.add(const Duration(days: 1));

  final List<_EmpTotal> out = [];
  for (final b in buckets.values) {
    b.events.sort((a, z) => a.time.compareTo(z.time));
    Duration sum = Duration.zero;
    DateTime? openIn;
    for (final ev in b.events) {
      if (ev.type == 'IN') {
        if (openIn == null) {
          openIn = ev.time;
        } else {
          if (ev.time.isAfter(openIn)) sum += ev.time.difference(openIn);
          openIn = ev.time;
        }
      } else if (ev.type == 'OUT') {
        if (openIn != null) {
          final outTime = ev.time;
          if (outTime.isAfter(openIn)) sum += outTime.difference(openIn);
          openIn = null;
        }
      }
    }
    if (openIn != null) {
      final boundary = isToday ? now : endOfDay;
      if (boundary.isAfter(openIn)) sum += boundary.difference(openIn);
    }
    out.add(_EmpTotal(employeeId: b.employeeId, employeeName: b.employeeName, duration: sum));
  }

  out.sort((a, z) => z.duration.compareTo(a.duration));
  return out;
}