import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show QueryDocumentSnapshot;
import '../panel/utils.dart';

class SummaryPanel extends StatelessWidget {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> rows;
  final bool groupByUser;
  final DateTime from;
  final DateTime to;
  const SummaryPanel({
    super.key,
    required this.rows,
    required this.groupByUser,
    required this.from,
    required this.to,
  });

  @override
  Widget build(BuildContext context) {
    // Compute metrics
    final totalRecords = rows.length;
    final clockIns = rows.where((d) => d.data()['type'] == 'IN').length;
    final clockOuts = rows.where((d) => d.data()['type'] == 'OUT').length;
    final uniqueUsers = rows.map((d) => groupIdFor(d.data())).toSet().length;

    // final totalWorkingTime = groupByUser
    //     ? buildGroups(
    //         rows,
    //       ).fold<Duration>(Duration.zero, (acc, g) => acc + g.workingTime)
    //     : calculateWorkingTime(rows);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.analytics_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Summary',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    rangeLabel(from, to),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SummaryStat(
                    icon: Icons.receipt_long,
                    label: 'Total Records',
                    value: '$totalRecords',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryStat(
                    icon: Icons.login,
                    label: 'Clock Ins',
                    value: '$clockIns',
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryStat(
                    icon: Icons.logout,
                    label: 'Clock Outs',
                    value: '$clockOuts',
                    color: Colors.orange,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SummaryStat(
                    icon: Icons.people,
                    label: 'Unique Users',
                    value: '$uniqueUsers',
                    color: Colors.purple,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // WorkingTimeCard(totalWorkingTime: totalWorkingTime, uniqueUsers: uniqueUsers),
          ],
        ),
      ),
    );
  }
}

class SummaryStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const SummaryStat({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}

class WorkingTimeCard extends StatelessWidget {
  final Duration totalWorkingTime;
  final int uniqueUsers;
  const WorkingTimeCard({
    super.key,
    required this.totalWorkingTime,
    required this.uniqueUsers,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.indigo.withOpacity(0.1),
            Colors.blue.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.schedule, color: Colors.indigo, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Working Time',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  formatDuration(totalWorkingTime),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
          ),
          if (uniqueUsers > 0)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Avg per User',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatDuration(
                    Duration(
                      milliseconds:
                          totalWorkingTime.inMilliseconds ~/ uniqueUsers,
                    ),
                  ),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.indigo,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
