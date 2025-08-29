import 'dart:async';
import 'package:attendance_tracker/admin/panel/model.dart';
import 'package:attendance_tracker/admin/panel/utils.dart';
import 'package:attendance_tracker/admin/panel/widgets/filter_panel.dart';
import 'package:attendance_tracker/admin/panel/widgets/group_card.dart';
import 'package:attendance_tracker/admin/panel/widgets/load_more.dart';
import 'package:attendance_tracker/admin/panel/widgets/record_tile.dart';
import 'package:attendance_tracker/admin/panel/widgets/summary_panel.dart';
import 'package:attendance_tracker/model/attendance_event.dart';
import 'package:attendance_tracker/widgets/event_detail.dart';
import 'package:attendance_tracker/widgets/responsive_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show
        FirebaseFirestore,
        Query,
        QueryDocumentSnapshot,
        DocumentSnapshot,
        Timestamp;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel>
    with SingleTickerProviderStateMixin {
  final _db = FirebaseFirestore.instance;

  // Filters
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  final _emailCtrl = TextEditingController();
  bool _groupByUser = true;
  bool _showFilters = false;
  DateTime _currentDate = DateTime.now();
  // Paging
  static const int _pageSize = 30;
  bool _loading = false;
  bool _hasMore = true;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _rows = [];
  DocumentSnapshot? _lastDoc;

  // Group expand state
  final Map<String, bool> _expanded = {};

  // Debounce for email field
  Timer? _debounce;

  // Date formats
  final _dfDate = DateFormat('MMM d, yyyy');
  final _dfTime = DateFormat('hh:mm a');

  // Quick filters
  final List<QuickDateFilter> _quickFilters = quickFiltersDefault;

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(_onEmailChanged);
    _runInitialQuery();
    _setCurrentDate(DateTime.now());
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_onEmailChanged);
    _emailCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onEmailChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _runInitialQuery);
  }

  Query<Map<String, dynamic>> _buildQuery() {
    final startTs = Timestamp.fromDate(
      DateTime(_from.year, _from.month, _from.day),
    );
    final endExclusive = DateTime(
      _to.year,
      _to.month,
      _to.day,
    ).add(const Duration(days: 1));
    final endTs = Timestamp.fromDate(endExclusive);

    Query<Map<String, dynamic>> q = _db
        .collection('attendanceRecords')
        .where('capturedAt', isGreaterThanOrEqualTo: startTs)
        .where('capturedAt', isLessThan: endTs)
        .orderBy('capturedAt', descending: true)
        .limit(_pageSize);

    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty) q = q.where('userEmail', isEqualTo: email);
    if (_lastDoc != null) q = q.startAfterDocument(_lastDoc!);
    return q;
  }

  Future<void> _runInitialQuery() async {
    if (!mounted) return;
    setState(() {
      _rows.clear();
      _hasMore = true;
      _lastDoc = null;
      _loading = true;
    });

    try {
      final snap = await _buildQuery().get();

      if (mounted) {
        setState(() {
          final seen = <String>{};
          _rows
            ..clear()
            ..addAll(snap.docs.where((d) => seen.add(d.id))); // only unique IDs
          if (_rows.isNotEmpty) _lastDoc = _rows.last;
          _hasMore = snap.docs.length == _pageSize;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || !mounted) return;

    setState(() => _loading = true);

    try {
      final snap = await _buildQuery().get();

      if (mounted) {
        setState(() {
          final seen = _rows.map((d) => d.id).toSet();
          final newDocs = snap.docs.where((d) => !seen.contains(d.id));
          _rows.addAll(newDocs);
          if (_rows.isNotEmpty) _lastDoc = _rows.last;
          _hasMore = snap.docs.length == _pageSize;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyQuickFilter(QuickDateFilter filter) {
    final range = filter.getRange();
    setState(() {
      _from = range.start;
      _to = range.end;
      _showFilters = false;
    });
    _runInitialQuery();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _from,
        end: _to.isAfter(now) ? now : _to,
      ),
      helpText: 'Select date range',
    );
    if (res != null) {
      setState(() {
        _from = res.start;
        _to = res.end;
        _showFilters = false;
      });
      _runInitialQuery();
    }
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

  bool get _isToday {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cd = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    return cd == today;
  }

  void _setCurrentDate(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    setState(() {
      _currentDate = day;
      _from = day;
      _to = day;
    });
    _runInitialQuery();
  }

  void _shiftByDays(int days) {
    final next = _currentDate.add(Duration(days: days));
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final clamped = next.isAfter(today) ? today : next;
    _setCurrentDate(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final grouped = _groupByUser ? buildGroups(_rows) : null;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text('Attendance Admin'),
        actions: [
          IconButton(
            tooltip: 'Toggle Filters',
            icon: Icon(
              _showFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
              color: _showFilters
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () => setState(() => _showFilters = !_showFilters),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _runInitialQuery,
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _confirmAndSignOut,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _runInitialQuery,
        child: CustomScrollView(
          slivers: [
            if (_showFilters)
              SliverMaxWidth(
                child: AdminFilterPanel(
                  rangeLabel: rangeLabel(_from, _to),
                  onPickRange: _pickRange,
                  emailCtrl: _emailCtrl,
                  quickFilters: _quickFilters,
                  onQuickFilterTap: _applyQuickFilter,
                  groupByUser: _groupByUser,
                  onGroupToggle: (v) => setState(() => _groupByUser = v),
                  onApply: _loading ? null : _runInitialQuery,
                  loading: _loading,
                ),
              ),

            SliverMaxWidth(
              child: SummaryPanel(
                rows: _rows,
                groupByUser: _groupByUser,
                from: _from,
                to: _to,
              ),
            ),
            SliverMaxWidth(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Previous day',
                      icon: const Icon(Icons.chevron_left),
                      onPressed: _loading ? null : () => _shiftByDays(-1),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _dfDate.format(_currentDate), // e.g., "Aug 29, 2025"
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Next day',
                      icon: const Icon(Icons.chevron_right),
                      onPressed: (_loading || _isToday)
                          ? null
                          : () => _shiftByDays(1),
                    ),
                    const SizedBox(width: 12),
                    // Optional: quick "Today" chip
                    ActionChip(
                      label: const Text('Today'),
                      onPressed: (_loading || _isToday)
                          ? null
                          : () => _setCurrentDate(DateTime.now()),
                    ),
                  ],
                ),
              ),
            ),

            if (_loading && _rows.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_rows.isEmpty && !_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(),
              )
            else if (_groupByUser)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.builder(
                  itemCount: (grouped?.length ?? 0) + 1,
                  itemBuilder: (context, index) {
                    if (index == grouped!.length) {
                      return LoadMore(
                        hasMore: _hasMore,
                        loading: _loading,
                        onLoadMore: _loadMore,
                      );
                    }
                    final g = grouped[index];
                    final expanded = _expanded[g.id] ?? true;
                    return GroupCard(
                      group: g,
                      expanded: expanded,
                      onToggle: () =>
                          setState(() => _expanded[g.id] = !expanded),
                      dfDate: _dfDate,
                      dfTime: _dfTime,
                      buildTile: (doc) => RecordTile(
                        doc: doc,
                        dfDate: _dfDate,
                        dfTime: _dfTime,
                        isGrouped: true,
                        onTap: () => _openDetail(doc),
                      ),
                    );
                  },
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverList.separated(
                  itemCount: _rows.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index == _rows.length) {
                      return LoadMore(
                        hasMore: _hasMore,
                        loading: _loading,
                        onLoadMore: _loadMore,
                      );
                    }
                    return Card(
                      child: RecordTile(
                        doc: _rows[index],
                        dfDate: _dfDate,
                        dfTime: _dfTime,
                        onTap: () => _openDetail(_rows[index]),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetail(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final type = (data['type'] as String?) ?? '?';
    final ts = data['capturedAt'] as Timestamp?;
    final time =
        ts?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final address = data['address'] as String?;

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
