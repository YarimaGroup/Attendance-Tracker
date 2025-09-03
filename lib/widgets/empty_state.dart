import 'package:flutter/material.dart';

class EmptyState extends StatelessWidget {
  final bool isToday;
  final VoidCallback? onPunchIn;
  const EmptyState({super.key, required this.isToday, this.onPunchIn});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.event_busy, size: 56, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(
          isToday ? "You're all set for today" : 'No attendance records',
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isToday
              ? 'Start the day by clocking in.'
              : 'Pick another date or go back to today.',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (isToday)
          FilledButton.icon(
            onPressed: onPunchIn,
            icon: const Icon(Icons.login),
            label: const Text('Clock In Now'),
          ),
      ],
    );
  }
}
