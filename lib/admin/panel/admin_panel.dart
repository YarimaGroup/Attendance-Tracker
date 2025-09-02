import 'dart:async';
import 'package:attendance_tracker/admin/panel/model.dart';
import 'package:attendance_tracker/admin/panel/utils.dart';
import 'package:attendance_tracker/admin/widgets/filter_panel.dart';
import 'package:attendance_tracker/admin/widgets/group_card.dart';
import 'package:attendance_tracker/admin/widgets/load_more.dart';
import 'package:attendance_tracker/admin/widgets/record_tile.dart';
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
  // Filters (start with TODAY)
  DateTime _from = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );
  DateTime _to = DateTime(
    DateTime.now().year,
    DateTime.now().month,
    DateTime.now().day,
  );

  final _emailCtrl = TextEditingController();
  final _employeeIdCtrl = TextEditingController(); // NEW
  final _orgCtrl = TextEditingController();
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
    _emailCtrl.addListener(_onFilterChanged);
    _employeeIdCtrl.addListener(_onFilterChanged);
    _orgCtrl.addListener(_onFilterChanged);
    _runInitialQuery();
    _setCurrentDate(DateTime.now());
  }

  @override
  void dispose() {
    _emailCtrl.removeListener(_onFilterChanged); // CHANGED
    _employeeIdCtrl.removeListener(_onFilterChanged); // NEW
    _orgCtrl.removeListener(_onFilterChanged); // NEW
    _emailCtrl.dispose();
    _employeeIdCtrl.dispose(); // NEW
    _orgCtrl.dispose(); // NEW
    _debounce?.cancel();
    super.dispose();
  }

  // REPLACE the old method with this day-clamped version
  List<_EmpTotal> _computeEmployeeTotalsFromRows() {
    // Hard day bounds based on _currentDate (not the broader _from/_to window)
    final startOfDay = DateTime(
      _currentDate.year,
      _currentDate.month,
      _currentDate.day,
    );
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final now = DateTime.now();
    final boundaryNow = _isToday
        ? (now.isBefore(endOfDay) ? now : endOfDay)
        : endOfDay;

    // 1) Pre-filter docs to selected day only
    final dayDocs = _rows.where((d) {
      final data = d.data();
      final ts =
          (data['capturedAt'] as Timestamp?) ??
          (data['createdAt'] as Timestamp?);
      if (ts == null) return false;
      final t = ts.toDate();
      return !t.isBefore(startOfDay) && t.isBefore(endOfDay);
    }).toList();

    // 2) Group by employee (stable key)
    final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> byEmp =
        {};
    for (final d in dayDocs) {
      final data = d.data();
      final empId = data['employeeId'] as String?;
      final empName =
          (data['employeeName'] as String?) ?? (empId ?? 'Unassigned');
      final key = empId ?? 'name:$empName';
      (byEmp[key] ??= []).add(d);
    }

    // 3) For each employee, pair IN→OUT with clipping to day bounds
    final List<_EmpTotal> out = [];
    byEmp.forEach((key, docs) {
      // Sort ascending
      docs.sort((a, b) {
        DateTime ta =
            ((a.data()['capturedAt'] as Timestamp?) ??
                    (a.data()['createdAt'] as Timestamp?))
                ?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        DateTime tb =
            ((b.data()['capturedAt'] as Timestamp?) ??
                    (b.data()['createdAt'] as Timestamp?))
                ?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return ta.compareTo(tb);
      });

      Duration sum = Duration.zero;
      DateTime? openIn; // IN time within the day (clipped to startOfDay)

      for (final doc in docs) {
        final data = doc.data();
        final type = (data['type'] as String?) ?? '';
        final t =
            ((data['capturedAt'] as Timestamp?) ??
                    (data['createdAt'] as Timestamp?))
                ?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);

        // Clip event time into [startOfDay, endOfDay]
        final tt = t.isBefore(startOfDay)
            ? startOfDay
            : (t.isAfter(endOfDay) ? endOfDay : t);

        if (type == 'IN') {
          if (openIn == null) {
            openIn = tt; // start inside the day
          } else {
            // Double IN: close previous at this IN (both within the day)
            if (tt.isAfter(openIn)) sum += tt.difference(openIn);
            openIn = tt; // start new
          }
        } else if (type == 'OUT') {
          if (openIn != null) {
            // Normal close
            final outT = tt;
            if (outT.isAfter(openIn)) sum += outT.difference(openIn);
            openIn = null;
          } else {
            // Starts the day already clocked in (carry-over):
            // We saw an OUT but no IN today -> count from startOfDay to this OUT.
            if (tt.isAfter(startOfDay)) sum += tt.difference(startOfDay);
            // remain closed
          }
        }
      }

      // If still open at end of the last event, count to day boundary (now for today)
      if (openIn != null) {
        final end = boundaryNow;
        if (end.isAfter(openIn)) sum += end.difference(openIn);
      }

      final any = docs.first.data();
      final employeeId = any['employeeId'] as String?;
      final displayName =
          (any['employeeName'] as String?) ?? (employeeId ?? 'Unassigned');

      out.add(
        _EmpTotal(
          employeeId: employeeId,
          displayName: displayName,
          duration: sum,
        ),
      );
    });

    out.sort((a, b) => b.duration.compareTo(a.duration)); // longest first
    return out;
  }

  /// Org picker used by the new window's left icon button
  Future<void> _pickOrgForWindow() async {
    final snap = await _db
        .collection('orgs')
        .where('isActive', isEqualTo: true)
        .orderBy('nameLower')
        .limit(200)
        .get();

    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        if (snap.docs.isEmpty) {
          return const SizedBox(
            height: 240,
            child: Center(child: Text('No active orgs')),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: snap.docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final d = snap.docs[i];
            final name = (d.data()['name'] as String?) ?? d.id;
            return ListTile(
              leading: const Icon(Icons.apartment_outlined),
              title: Text(name),
              subtitle: Text(d.id),
              onTap: () => Navigator.pop(ctx, d.id),
            );
          },
        );
      },
    );

    if (choice != null) {
      _orgCtrl.text = choice; // set filter to this org
      await _runInitialQuery(); // refresh list for selected day & org
    }
  }

  void _onFilterChanged() {
    // CHANGED (was _onEmailChanged)
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

    // LEGACY filter (kept)
    final email = _emailCtrl.text.trim();
    if (email.isNotEmpty) q = q.where('userEmail', isEqualTo: email);

    // NEW: org + employee filters (optional, additive)
    final org = _orgCtrl.text.trim(); // NEW
    if (org.isNotEmpty) q = q.where('orgId', isEqualTo: org);

    final empId = _employeeIdCtrl.text.trim(); // NEW
    if (empId.isNotEmpty) q = q.where('employeeId', isEqualTo: empId);

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

  // REPLACE _showAddOrgDialog with this:   // CHANGED
  Future<void> _showAddOrgDialog() async {
    final orgNameCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Organization'),
        content: TextField(
          controller: orgNameCtrl,
          decoration: const InputDecoration(
            labelText: 'Organization Name',
            prefixIcon: Icon(Icons.apartment_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final orgName = orgNameCtrl.text.trim();
    if (orgName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Organization name is required')),
      );
      return;
    }

    final orgId = _makeOrgId(orgName); // AUTO ID                     // NEW

    try {
      await _db.collection('orgs').doc(orgId).set({
        'name': orgName,
        'nameLower': orgName.toLowerCase(),
        'createdAt': Timestamp.now(),
        'isActive': true,
        'generated': true, // optional flag                            // NEW
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Org "$orgName" created as $orgId')),
        );
        // convenience: set the filter to this org
        _orgCtrl.text = orgId; // NEW
        _runInitialQuery();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to create org: $e')));
      }
    }
  }

  String _slug(String s) {
    final cleaned = s.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]+'),
      '-',
    );
    final slug = cleaned
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return (slug.isEmpty ? 'ORG' : slug);
  }

  String _rand(int len) {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final now = DateTime.now().microsecondsSinceEpoch;
    var x = now ^ (now >> 7);
    final b = StringBuffer();
    for (var i = 0; i < len; i++) {
      x = 1664525 * x + 1013904223; // LCG
      b.write(alphabet[x.abs() % alphabet.length]);
    }
    return b.toString();
  }

  String _makeOrgId(String name) {
    // NEW
    final base = _slug(name);
    return '$base-${_rand(4)}'; // e.g., LAL-FOODS-7QHM
  }

  // REPLACE _showAddEmployeeDialog with this:                 // CHANGED
  Future<void> _showAddEmployeeDialog() async {
    String? selectedOrgId = _orgCtrl.text.trim().isNotEmpty
        ? _orgCtrl.text.trim()
        : null; // preselect if filtered
    final nameCtrl = TextEditingController();
    bool isActive = true;

    // Load org list for dropdown (simple snapshot once)
    final orgsSnap = await _db
        .collection('orgs')
        .where('isActive', isEqualTo: true)
        .orderBy('nameLower')
        .limit(100)
        .get();
    final orgItems = orgsSnap.docs
        .map((d) => MapEntry(d.id, (d.data()['name'] ?? d.id) as String))
        .toList();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Add Employee'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Org dropdown
                DropdownButtonFormField<String>(
                  value: selectedOrgId,
                  decoration: const InputDecoration(
                    labelText: 'Organization',
                    prefixIcon: Icon(Icons.apartment_outlined),
                  ),
                  items: orgItems
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: Text('${e.value}  •  ${e.key}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setS(() => selectedOrgId = v),
                ),
                const SizedBox(height: 8),
                // Employee name
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Employee Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 8),
                // Active switch
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  onChanged: (v) => setS(() => isActive = v),
                  title: const Text('Active'),
                ),
                const SizedBox(height: 4),
                // Info (no PIN needed)
                Row(
                  children: const [
                    Icon(Icons.info_outline, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Employee ID will be generated automatically.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final orgId = selectedOrgId?.trim() ?? '';
    final name = nameCtrl.text.trim();

    if (orgId.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Organization and Employee Name are required'),
        ),
      );
      return;
    }

    final employeeId = _makeEmployeeId(name); // AUTO ID               // NEW

    try {
      final ref = _db
          .collection('orgs')
          .doc(orgId)
          .collection('employees')
          .doc(employeeId);
      await ref.set({
        'name': name,
        'nameLower': name.toLowerCase(),
        'isActive': isActive,
        'createdAt': Timestamp.now(),
        'generated': true, // optional flag                            // NEW
        // NO pinHash
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Employee "$name" created as $employeeId')),
        );
        // convenience: pre-fill filters
        if (_orgCtrl.text.trim().isEmpty) _orgCtrl.text = orgId;
        _employeeIdCtrl.text = employeeId;
        _runInitialQuery();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to add employee: $e')));
      }
    }
  }

  String _makeEmployeeId(String name) {
    // NEW
    final parts = name.trim().toUpperCase().split(RegExp(r'\s+'));
    final init = parts.map((p) => p.isEmpty ? '' : p[0]).join();
    final base = (init.isEmpty ? 'EMP' : init);
    return '$base-${_rand(4)}'; // e.g., MS-5K9T
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

          // NEW: quick admin actions
          PopupMenuButton<String>(
            tooltip: 'Admin actions',
            onSelected: (v) async {
              if (v == 'add_org') {
                await _showAddOrgDialog();
              } else if (v == 'add_emp') {
                await _showAddEmployeeDialog();
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'add_org',
                child: ListTile(
                  leading: Icon(Icons.apartment_outlined),
                  title: Text('Add Org'),
                ),
              ),
              const PopupMenuItem(
                value: 'add_emp',
                child: ListTile(
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
        onRefresh: _runInitialQuery,
        child: CustomScrollView(
          slivers: [
            if (_showFilters) // (existing)
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
            // NEW: light inline fields for Org & Employee
            if (_showFilters)
              SliverMaxWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _orgCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Org ID',
                                hintText: 'e.g. ORG001',
                                prefixIcon: Icon(Icons.apartment_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _employeeIdCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Employee ID',
                                hintText: 'e.g. EMP001',
                                prefixIcon: Icon(Icons.badge_outlined),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _loading ? null : _runInitialQuery,
                          icon: const Icon(Icons.search),
                          label: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            // NEW: Org Working Time window
            SliverMaxWidth(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: [
                        // Header row: [Pick Org]   Org Label   [Refresh/Clear]
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Pick organization',
                              icon: const Icon(Icons.apartment_outlined),
                              onPressed: _loading ? null : _pickOrgForWindow,
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Organization',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                    ),
                                  ),
                                  Text(
                                    _orgCtrl.text.trim().isEmpty
                                        ? 'All'
                                        : _orgCtrl.text.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Working time for ${DateFormat('MMM d, yyyy').format(_currentDate)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Right icon button: clear org (if set) else refresh
                            IconButton(
                              tooltip: _orgCtrl.text.trim().isEmpty
                                  ? 'Refresh'
                                  : 'Clear organization filter',
                              icon: Icon(
                                _orgCtrl.text.trim().isEmpty
                                    ? Icons.refresh
                                    : Icons.close,
                              ),
                              onPressed: _loading
                                  ? null
                                  : () async {
                                      if (_orgCtrl.text.trim().isEmpty) {
                                        await _runInitialQuery();
                                      } else {
                                        _orgCtrl.clear();
                                        await _runInitialQuery();
                                      }
                                    },
                            ),
                          ],
                        ),
                        const Divider(height: 1),

                        // Totals list
                        Builder(
                          builder: (context) {
                            final totals = _computeEmployeeTotalsFromRows();
                            if (_loading && _rows.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              );
                            }
                            if (totals.isEmpty) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(
                                  child: Text('No work time yet for this day'),
                                ),
                              );
                            }

                            final totalAll = totals.fold<Duration>(
                              Duration.zero,
                              (acc, t) => acc + t.duration,
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
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                                const Divider(height: 1),
                                ...totals.map(
                                  (t) => ListTile(
                                    dense: true,
                                    leading: const Icon(Icons.person_outline),
                                    title: Text(
                                      t.displayName,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    subtitle: t.employeeId == null
                                        ? null
                                        : Text(
                                            t.employeeId!,
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                    trailing: Text(
                                      _fmtDur(t.duration),
                                      style: const TextStyle(
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    onTap: () {
                                      // quick drill-in: filter by this employeeId then refresh
                                      final id = t.employeeId;
                                      if (id != null && !_loading) {
                                        _employeeIdCtrl.text = id;
                                        _runInitialQuery();
                                      }
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
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

    // NEW: read employee fields if present
    final employeeId = data['employeeId'] as String?; // NEW
    final employeeName = data['employeeName'] as String?; // NEW

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
            employeeId: employeeId, // NEW
            employeeName: employeeName, // NEW
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

class _EmpTotal {
  final String? employeeId;
  final String displayName;
  final Duration duration;
  _EmpTotal({
    required this.employeeId,
    required this.displayName,
    required this.duration,
  });
}

String _fmtDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}
