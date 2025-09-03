import 'package:attendance_tracker/admin/widgets/day_navigator_bar.dart';
import 'package:attendance_tracker/admin/widgets/org_employee_filters_inline.dart';
import 'package:attendance_tracker/admin/widgets/org_working_time_card.dart';
import 'package:attendance_tracker/controllers/admin_controller.dart';
import 'package:attendance_tracker/admin/panel/model.dart';
import 'package:attendance_tracker/admin/panel/utils.dart';
import 'package:attendance_tracker/admin/widgets/filter_panel.dart';
import 'package:attendance_tracker/admin/widgets/group_card.dart';
import 'package:attendance_tracker/admin/widgets/load_more.dart';
import 'package:attendance_tracker/admin/widgets/record_tile.dart';
import 'package:attendance_tracker/widgets/responsive_widget.dart';
import 'package:attendance_tracker/widgets/event_detail.dart';
import 'package:attendance_tracker/model/attendance_event.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});
  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late final AdminController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = AdminController();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dfDate = ctrl.dfDate;
    final dfTime = ctrl.dfTime;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final grouped = ctrl.groupByUser ? buildGroups(ctrl.rows) : null;
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBar(
            title: const Text('Attendance Admin'),
            elevation: 0,
            surfaceTintColor: Colors.transparent, // keeps it flat on Material 3
            backgroundColor: Theme.of(context).colorScheme.surface,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            actions: [
              IconButton(
                tooltip: ctrl.showFilters ? 'Hide filters' : 'Show filters',
                icon: Icon(
                  ctrl.showFilters
                      ? Icons.filter_alt
                      : Icons.filter_alt_outlined,
                  color: ctrl.showFilters
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
                onPressed: ctrl.toggleFilters,
              ),
              PopupMenuButton<String>(
                tooltip: 'Admin actions',
                onSelected: (v) async {
                  if (v == 'add_org') {
                    await ctrl.showAddOrgDialog(context);
                  } else if (v == 'add_emp') {
                    await ctrl.showAddEmployeeDialog(context);
                  }
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(
                    value: 'add_org',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.apartment_outlined),
                      title: Text('Add Org'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'add_emp',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.badge_outlined),
                      title: Text('Add Employee'),
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
                onPressed: _confirmAndSignOut,
              ),
            ],
          ),

          body: RefreshIndicator(
            onRefresh: ctrl.runInitialQuery,
            child: CustomScrollView(
              slivers: [
                if (ctrl.showFilters)
                  SliverMaxWidth(
                    child: AdminFilterPanel(
                      rangeLabel: rangeLabel(ctrl.from, ctrl.to),
                      onPickRange: () => ctrl.pickRange(context),
                      emailCtrl: ctrl.emailCtrl,
                      quickFilters: quickFiltersDefault,
                      onQuickFilterTap: (q) =>
                          ctrl.applyQuickRange(q.getRange()),
                      groupByUser: ctrl.groupByUser,
                      onGroupToggle: ctrl.setGroupByUser,
                      onApply: ctrl.loading ? null : ctrl.runInitialQuery,
                      loading: ctrl.loading,
                    ),
                  ),

                if (ctrl.showFilters)
                  SliverMaxWidth(
                    child: OrgEmployeeFiltersInline(
                      orgCtrl: ctrl.orgCtrl,
                      employeeIdCtrl: ctrl.employeeIdCtrl,
                      onApply: ctrl.loading ? null : ctrl.runInitialQuery,
                    ),
                  ),

                SliverMaxWidth(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: OrgWorkingTimeCard(
                      orgLabel: ctrl.orgCtrl.text.trim().isEmpty
                          ? 'All'
                          : ctrl.orgCtrl.text.trim(),
                      dateLabel: DateFormat(
                        'MMM d, yyyy',
                      ).format(ctrl.currentDate),
                      loading: ctrl.loading,
                      rows: ctrl.rows,
                      totals: ctrl.computeEmployeeTotalsForDay(),
                      onPickOrg: ctrl.loading
                          ? null
                          : () => ctrl.pickOrgForWindow(context),
                      onClearOrRefresh: ctrl.loading
                          ? null
                          : () async {
                              if (ctrl.orgCtrl.text.trim().isEmpty) {
                                await ctrl.runInitialQuery();
                              } else {
                                ctrl.orgCtrl.clear();
                                await ctrl.runInitialQuery();
                              }
                            },
                      onEmployeeTap: (id) {
                        if (id != null && !ctrl.loading) {
                          ctrl.employeeIdCtrl.text = id;
                          ctrl.runInitialQuery();
                        }
                      },
                    ),
                  ),
                ),

                SliverMaxWidth(
                  child: DayNavigatorBar(
                    currentDate: ctrl.currentDate,
                    isToday: ctrl.isToday,
                    onPrev: ctrl.loading ? null : () => ctrl.shiftByDays(-1),
                    onNext: (ctrl.loading || ctrl.isToday)
                        ? null
                        : () => ctrl.shiftByDays(1),
                    onToday: (ctrl.loading || ctrl.isToday)
                        ? null
                        : () => ctrl.setCurrentDate(DateTime.now()),
                  ),
                ),

                if (ctrl.loading && ctrl.rows.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (ctrl.rows.isEmpty && !ctrl.loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyState(),
                  )
                else if (ctrl.groupByUser)
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.builder(
                      itemCount: (grouped?.length ?? 0) + 1,
                      itemBuilder: (context, index) {
                        if (index == grouped!.length) {
                          return LoadMore(
                            hasMore: ctrl.hasMore,
                            loading: ctrl.loading,
                            onLoadMore: ctrl.loadMore,
                          );
                        }
                        final g = grouped[index];
                        final expanded = ctrl.expanded[g.id] ?? true;
                        return GroupCard(
                          group: g,
                          expanded: expanded,
                          onToggle: () {
                            ctrl.expanded[g.id] = !expanded;
                            ctrl.notifyListeners();
                          },
                          dfDate: dfDate,
                          dfTime: dfTime,
                          buildTile: (doc) => RecordTile(
                            doc: doc,
                            dfDate: dfDate,
                            dfTime: dfTime,
                            isGrouped: true,
                            onTap: () => _openDetail(context, doc),
                          ),
                        );
                      },
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList.separated(
                      itemCount: ctrl.rows.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index == ctrl.rows.length) {
                          return LoadMore(
                            hasMore: ctrl.hasMore,
                            loading: ctrl.loading,
                            onLoadMore: ctrl.loadMore,
                          );
                        }
                        return Card(
                          child: RecordTile(
                            doc: ctrl.rows[index],
                            dfDate: dfDate,
                            dfTime: dfTime,
                            onTap: () => _openDetail(context, ctrl.rows[index]),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAndSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to manage attendance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await FirebaseAuth.instance.signOut();
  }

  void _openDetail(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final type = (data['type'] as String?) ?? '?';
    final ts = data['capturedAt'] as Timestamp?;
    final time =
        ts?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final address = data['address'] as String?;
    final employeeId = data['employeeId'] as String?;
    final employeeName = data['employeeName'] as String?;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EventDetailPage(
          canDelete: true,
          recordId: doc.id,
          event: AttendanceEvent(
            type: type,
            time: time,
            id: doc.id,
            location: data['location'] as Map<String, dynamic>?,
            address: address,
            employeeId: employeeId,
            employeeName: employeeName,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.inbox_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No records found',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your filters or date range',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
