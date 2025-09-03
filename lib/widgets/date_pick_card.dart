import 'package:flutter/material.dart';

class DatePickerCard extends StatelessWidget {
  final String title;
  final String? weekday;
  final bool canGoForward;
  final VoidCallback onPrev;
  final VoidCallback? onNext;
  final VoidCallback onPick;
  final VoidCallback? onToday;

  const DatePickerCard({
    super.key,
    required this.title,
    required this.weekday,
    required this.canGoForward,
    required this.onPrev,
    this.onNext,
    required this.onPick,
    this.onToday,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPick,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left), tooltip: 'Previous day'),
              Expanded(
                child: Column(
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                    if (weekday != null)
                      Text(weekday!, style: TextStyle(fontSize: 12, color: Colors.grey[600]), textAlign: TextAlign.center),
                    const SizedBox(height: 2),
                    Text('Tap to pick a date', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                  ],
                ),
              ),
              IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right), tooltip: canGoForward ? 'Next day' : 'Cannot go beyond today'),
              if (onToday != null) ...[
                const SizedBox(width: 8),
                TextButton(onPressed: onToday, child: const Text('Today')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}




