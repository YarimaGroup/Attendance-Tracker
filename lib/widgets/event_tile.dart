
import 'package:attendance_tracker/model/attendance_event.dart';
import 'package:attendance_tracker/widgets/event_detail.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EventTile extends StatelessWidget {
  final AttendanceEvent event;
  const EventTile({super.key, required this.event});

  @override
  Widget build(BuildContext context) {
    final color = event.type == 'IN' ? Colors.green : Colors.orange;
    final icon = event.type == 'IN' ? Icons.login : Icons.logout;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => EventDetailPage(recordId: event.id, event: event)),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Clock ${event.type}', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
                        const Spacer(),
                        Text(DateFormat('hh:mm a').format(event.time), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      ],
                    ),
                    if (event.employeeName != null || event.employeeId != null) ...[
                      const SizedBox(height: 2),
                      Text(event.employeeName ?? '', style: const TextStyle(fontSize: 15, color: Colors.black87)),
                    ],
                    if (event.address != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.location_on, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(child: Text(event.address!, style: TextStyle(fontSize: 11, color: Colors.grey[700], fontWeight: FontWeight.w500))),
                      ]),
                    ] else if (event.location != null) ...[
                      const SizedBox(height: 4),
                      Row(children: [
                        Icon(Icons.location_on, size: 12, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'Lat: ${event.location!['lat'].toStringAsFixed(4)}, Lng: ${event.location!['lng'].toStringAsFixed(4)}',
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),
                        ),
                      ]),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}