
import 'package:attendance_tracker/controllers/home_controller.dart';
import 'package:attendance_tracker/repository/attendance_repository.dart';
import 'package:attendance_tracker/services/geolocation_service.dart';
import 'package:attendance_tracker/services/media_service.dart';
import 'package:attendance_tracker/widgets/date_pick_card.dart';
import 'package:attendance_tracker/widgets/employees_total_card.dart';
import 'package:attendance_tracker/widgets/empty_state.dart';
import 'package:attendance_tracker/widgets/event_tile.dart';
import 'package:attendance_tracker/widgets/punch_buttons.dart';
import 'package:attendance_tracker/widgets/skeletons.dart';
import 'package:attendance_tracker/widgets/summary_card.dart';
import 'package:attendance_tracker/widgets/responsive_widget.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeController ctrl;

  @override
  void initState() {
    super.initState();
    ctrl = HomeController(
      repo: AttendanceRepository(),
      geo: GeolocationService(),
      media: MediaService(),
    );
    // Kick off
    // ignore: discarded_futures
    ctrl.init();
  }

  @override
  void dispose() {
    ctrl.dispose();
    super.dispose();
  }

  String _dateDisplay(DateTime d) {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final tomorrow = now.add(const Duration(days: 1));
    bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    if (sameDay(d, now)) return 'Today';
    if (sameDay(d, yesterday)) return 'Yesterday';
    if (sameDay(d, tomorrow)) return 'Tomorrow';
    return DateFormat('MMM d, yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final email = user.email ?? user.uid;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final canGoForward = !ctrl.isToday;
        return Scaffold(
          drawerBarrierDismissible: false,
          appBar: AppBar(
            title: const Text('Attendance'),
            actions: [
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
                onPressed: ctrl.busy ? null : () => ctrl.confirmAndSignOut(context),
              ),
            ],
            bottom: ctrl.busy
                ? const PreferredSize(
                    preferredSize: Size.fromHeight(3),
                    child: LinearProgressIndicator(minHeight: 3),
                  )
                : null,
          ),
          body: RefreshIndicator(
            onRefresh: ctrl.loadInitial,
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
                  ctrl.loadMore();
                }
                return false;
              },
              child: CustomScrollView(
                slivers: [
                  SliverMaxWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        children: [
                          const CircleAvatar(child: Icon(Icons.person)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user.displayName ?? 'Hello!', style: Theme.of(context).textTheme.titleMedium),
                                Text(email, style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
                          ),
                          if (ctrl.busy)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Status
                  SliverMaxWidth(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: ctrl.status == null
                          ? const SizedBox.shrink()
                          : Padding(
                              key: ValueKey(ctrl.status),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  ctrl.status!,
                                  style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                  if (ctrl.isToday)
                    SliverMaxWidth(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: PunchButtons(
                          busy: ctrl.busy,
                          onIn: () => ctrl.punch(context, 'IN'),
                          onOut: () => ctrl.punch(context, 'OUT'),
                        ),
                      ),
                    ),
                  if (ctrl.isToday) const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // Date picker card
                  SliverMaxWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: DatePickerCard(
                        title: _dateDisplay(ctrl.selectedDate),
                        weekday: ctrl.isToday ? null : DateFormat('EEEE').format(ctrl.selectedDate),
                        canGoForward: canGoForward,
                        onPrev: () => ctrl.changeDate(-1),
                        onNext: canGoForward ? () => ctrl.changeDate(1) : null,
                        onPick: () => ctrl.pickDate(context),
                        onToday: ctrl.isToday ? null : ctrl.goToToday,
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // Summary
                  SliverMaxWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: ctrl.initialLoading ? 0.6 : 1.0,
                        child: SummaryCard(events: ctrl.events),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // Employee totals
                  SliverMaxWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: ctrl.events.isEmpty
                          ? const SizedBox.shrink()
                          : EmployeeTotalsCard(
                              events: ctrl.events,
                              selectedDate: ctrl.selectedDate,
                              isToday: ctrl.isToday,
                            ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),

                  // Header
                  SliverMaxWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.list_alt, size: 20),
                          const SizedBox(width: 8),
                          Text('Detailed Records', style: Theme.of(context).textTheme.titleMedium),
                          const Spacer(),
                          if (ctrl.events.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Theme.of(context).primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text('${ctrl.events.length}',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Theme.of(context).primaryColor)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),

                  // List / Empty / Skeleton
                  if (ctrl.initialLoading)
                    const SliverMaxWidth(
                      child: Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: SkeletonList()),
                    )
                  else if (ctrl.events.isEmpty)
                    SliverMaxWidth(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: EmptyState(isToday: ctrl.isToday, onPunchIn: ctrl.busy ? null : () => ctrl.punch(context, 'IN')),
                      ),
                    )
                  else
                    SliverList.builder(
                      itemCount: ctrl.events.length,
                      itemBuilder: (context, index) {
                        final event = ctrl.events[index];
                        return Padding(
                          padding: EdgeInsets.fromLTRB(16, index == 0 ? 0 : 8, 16, 8),
                          child: EventTile(event: event),
                        );
                      },
                    ),

                  // Pager footer
                  SliverMaxWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: ctrl.loadingMore
                            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                            : (!ctrl.hasMore ? const Text('— End of day —') : const SizedBox.shrink()),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
