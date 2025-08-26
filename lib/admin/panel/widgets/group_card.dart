import 'package:attendance_punch/admin/panel/model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../panel/utils.dart';

class GroupCard extends StatelessWidget {
  final GroupInfo group;
  final bool expanded;
  final VoidCallback onToggle;
  final DateFormat dfDate;
  final DateFormat dfTime;
  final Widget Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)
  buildTile;

  const GroupCard({
    super.key,
    required this.group,
    required this.expanded,
    required this.onToggle,
    required this.dfDate,
    required this.dfTime,
    required this.buildTile,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primary.withOpacity(0.1),
                  child: Text(
                    _initialsFrom(group.title),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.title,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (group.subtitle != null)
                        Text(
                          group.subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.outline,
                              ),
                        ),
                      if (group.workingTime > Duration.zero) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule,
                              size: 14,
                              color: Colors.indigo,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatDuration(group.workingTime),
                              style: const TextStyle(
                                color: Colors.indigo,
                                fontWeight: FontWeight.w500,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${group.docs.length} records',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                IconButton(
                  icon: AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.expand_more),
                  ),
                  onPressed: onToggle,
                ),
              ],
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: expanded
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Column(
              children: [
                if (group.workingTime > Duration.zero)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.indigo.withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer, size: 16, color: Colors.indigo),
                        const SizedBox(width: 8),
                        Text(
                          'Working Time: ${formatDuration(group.workingTime)}',
                          style: const TextStyle(
                            color: Colors.indigo,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          workingDaysText(group.docs),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                ...group.docs.map(buildTile),
              ],
            ),
            secondChild: const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _initialsFrom(String s) {
    final t = s.trim();
    if (t.isEmpty) return '?';
    final parts = t.split(' ');
    if (parts.length >= 2) {
      return parts[0].substring(0, 1).toUpperCase() +
          parts[1].substring(0, 1).toUpperCase();
    }
    final local = t.contains('@') ? t.split('@').first : t;
    return local.substring(0, 1).toUpperCase();
  }
}
