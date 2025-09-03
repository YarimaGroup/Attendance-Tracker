import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class DayNavigatorBar extends StatelessWidget {
  final DateTime currentDate;
  final bool isToday;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback? onToday;
  const DayNavigatorBar({
    super.key,
    required this.currentDate,
    required this.isToday,
    this.onPrev,
    this.onNext,
    this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('MMM d, yyyy');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Previous day',
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
          ),
          const SizedBox(width: 8),
          Text(
            df.format(currentDate),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Next day',
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
          const SizedBox(width: 12),
          ActionChip(label: const Text('Today'), onPressed: onToday),
        ],
      ),
    );
  }
}
