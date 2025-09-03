import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class EmpTotalVM {
  final String? employeeId;
  final String displayName;
  final Duration duration;
  EmpTotalVM({
    required this.employeeId,
    required this.displayName,
    required this.duration,
  });
}

class OrgWorkingTimeCard extends StatelessWidget {
  final String orgLabel;
  final String dateLabel;
  final bool loading;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> rows;
  final List<dynamic> totals; // accepts AdminController.EmpTotal
  final VoidCallback? onPickOrg;
  final VoidCallback? onClearOrRefresh;
  final void Function(String? employeeId)? onEmployeeTap;

  const OrgWorkingTimeCard({
    super.key,
    required this.orgLabel,
    required this.dateLabel,
    required this.loading,
    required this.rows,
    required this.totals,
    this.onPickOrg,
    this.onClearOrRefresh,
    this.onEmployeeTap,
  });

  String _fmtDur(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    return '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Pick organization',
                  icon: const Icon(Icons.apartment_outlined),
                  onPressed: onPickOrg,
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text(
                        'Organization',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      Text(
                        orgLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Working time for $dateLabel',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: orgLabel == 'All'
                      ? 'Refresh'
                      : 'Clear organization filter',
                  icon: Icon(orgLabel == 'All' ? Icons.refresh : Icons.close),
                  onPressed: onClearOrRefresh,
                ),
              ],
            ),
            const Divider(height: 1),
            Builder(
              builder: (context) {
                if (loading && rows.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (totals.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: Text('No work time yet for this day')),
                  );
                }
                final totalAll = totals.fold<Duration>(
                  Duration.zero,
                  (acc, t) => acc + (t as dynamic).duration,
                );
                return Column(
                  children: [
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.timer_outlined),
                      title: const Text('Total (all employees)'),
                      trailing: Text(
                        _fmtDur(totalAll),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                    const Divider(height: 1),
                    ...totals.map((t) {
                      final tt = t as dynamic;
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.person_outline),
                        title: Text(
                          tt.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: tt.employeeId == null
                            ? null
                            : Text(
                                tt.employeeId as String,
                                style: const TextStyle(fontSize: 12),
                              ),
                        trailing: Text(
                          _fmtDur(tt.duration as Duration),
                          style: const TextStyle(
                            fontFeatures: [FontFeature.tabularFigures()],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () =>
                            onEmployeeTap?.call(tt.employeeId as String?),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
