import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class AdminController extends ChangeNotifier {
  AdminController({FirebaseFirestore? db})
    : _db = db ?? FirebaseFirestore.instance {
    emailCtrl.addListener(_onFilterChanged);
    employeeIdCtrl.addListener(_onFilterChanged);
    orgCtrl.addListener(_onFilterChanged);
    setCurrentDate(DateTime.now());
    runInitialQuery();
  }

  final FirebaseFirestore _db;

  // Filters
  DateTime from = _startOfDay(DateTime.now());
  DateTime to = _startOfDay(DateTime.now());
  final emailCtrl = TextEditingController();
  final employeeIdCtrl = TextEditingController();
  final orgCtrl = TextEditingController();
  bool groupByUser = true;
  bool showFilters = false;
  DateTime currentDate = DateTime.now();

  // Paging
  static const int pageSize = 30;
  bool loading = false;
  bool hasMore = true;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> rows = [];
  DocumentSnapshot? lastDoc;

  // Track loaded document IDs to prevent duplicates across all operations
  final Set<String> _loadedIds = <String>{};

  // UI state
  final Map<String, bool> expanded = {};
  Timer? _debounce;

  // Formats
  final dfDate = DateFormat('MMM d, yyyy');
  final dfTime = DateFormat('hh:mm a');

  // Lifecycle
  @override
  void dispose() {
    emailCtrl.removeListener(_onFilterChanged);
    employeeIdCtrl.removeListener(_onFilterChanged);
    orgCtrl.removeListener(_onFilterChanged);
    emailCtrl.dispose();
    employeeIdCtrl.dispose();
    orgCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  static DateTime _startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
  bool get isToday {
    final now = DateTime.now();
    final today = _startOfDay(now);
    final cd = _startOfDay(currentDate);
    return cd == today;
  }

  void toggleFilters() {
    showFilters = !showFilters;
    notifyListeners();
  }

  void setGroupByUser(bool v) {
    groupByUser = v;
    notifyListeners();
  }

  void _onFilterChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), runInitialQuery);
  }

  /// Reset all pagination state
  void _resetPaginationState() {
    rows.clear();
    _loadedIds.clear();
    lastDoc = null;
    hasMore = true;
  }

  Query<Map<String, dynamic>> _buildQuery() {
    final startTs = Timestamp.fromDate(_startOfDay(from));
    final endTs = Timestamp.fromDate(
      _startOfDay(to).add(const Duration(days: 1)),
    );

    Query<Map<String, dynamic>> q = _db
        .collection('attendanceRecords')
        .where('capturedAt', isGreaterThanOrEqualTo: startTs)
        .where('capturedAt', isLessThan: endTs)
        .orderBy('capturedAt', descending: true)
        .limit(pageSize);

    final email = emailCtrl.text.trim();
    if (email.isNotEmpty) q = q.where('userEmail', isEqualTo: email);

    final org = orgCtrl.text.trim();
    if (org.isNotEmpty) q = q.where('orgId', isEqualTo: org);

    final empId = employeeIdCtrl.text.trim();
    if (empId.isNotEmpty) q = q.where('employeeId', isEqualTo: empId);

    if (lastDoc != null) q = q.startAfterDocument(lastDoc!);
    return q;
  }

  Future<void> runInitialQuery() async {
    if (loading) return; // Prevent multiple simultaneous calls

    loading = true;
    _resetPaginationState(); // Always reset state for initial query
    notifyListeners();

    try {
      final snap = await _buildQuery().get();

      if (snap.docs.isNotEmpty) {
        // Add all unique documents
        for (final doc in snap.docs) {
          if (_loadedIds.add(doc.id)) {
            // add() returns true if the element was added
            rows.add(doc);
          }
        }

        // Set lastDoc for pagination
        lastDoc = snap.docs.last;

        // Determine if there might be more data
        hasMore = snap.docs.length == pageSize;
      } else {
        hasMore = false;
      }

      debugPrint('Initial query loaded ${rows.length} unique documents');
    } catch (e) {
      debugPrint('Error in runInitialQuery: $e');
      hasMore = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loading || !hasMore) return;

    loading = true;
    notifyListeners();

    try {
      final snap = await _buildQuery().get();

      if (snap.docs.isNotEmpty) {
        int newDocsAdded = 0;

        // Add only new unique documents
        for (final doc in snap.docs) {
          if (_loadedIds.add(doc.id)) {
            // add() returns true if the element was added
            rows.add(doc);
            newDocsAdded++;
          }
        }

        debugPrint(
          'LoadMore: Fetched ${snap.docs.length} docs, added $newDocsAdded new unique docs',
        );

        // Update pagination state
        lastDoc = snap.docs.last;

        // If we didn't get any new documents or didn't get a full page, we're done
        hasMore = snap.docs.length == pageSize && newDocsAdded > 0;

        // If we got no new documents despite getting a full page, try one more time
        // This handles edge cases where the cursor position has duplicates
        if (newDocsAdded == 0 && snap.docs.length == pageSize && hasMore) {
          debugPrint(
            'No new documents added, but full page received. Trying once more...',
          );
          // Set lastDoc to the actual last document and try again
          hasMore = true;
        }
      } else {
        hasMore = false;
      }
    } catch (e) {
      debugPrint('Error in loadMore: $e');
      hasMore = false;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void applyQuickRange(DateTimeRange r) {
    from = r.start;
    to = r.end;
    showFilters = false;
    runInitialQuery();
  }

  Future<void> pickRange(BuildContext context) async {
    final now = DateTime.now();
    final res = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: from,
        end: to.isAfter(now) ? now : to,
      ),
      helpText: 'Select date range',
    );
    if (res != null) {
      from = res.start;
      to = res.end;
      showFilters = false;
      runInitialQuery();
    }
  }

  void setCurrentDate(DateTime d) {
    final day = _startOfDay(d);
    currentDate = day;
    from = day;
    to = day;
    runInitialQuery();
  }

  void shiftByDays(int days) {
    final next = currentDate.add(Duration(days: days));
    final today = _startOfDay(DateTime.now());
    final clamped = next.isAfter(today) ? today : next;
    setCurrentDate(clamped);
  }

  Future<void> pickOrgForWindow(BuildContext context) async {
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
      orgCtrl.text = choice;
      await runInitialQuery();
    }
  }

  // --- Create Org / Employee helpers ---
  String _slug(String s) {
    final cleaned = s.trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]+'),
      '-',
    );
    final slug = cleaned
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-\$'), '');
    return (slug.isEmpty ? 'ORG' : slug);
  }

  String _rand(int len) {
    const alphabet = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final now = DateTime.now().microsecondsSinceEpoch;
    var x = now ^ (now >> 7);
    final b = StringBuffer();
    for (var i = 0; i < len; i++) {
      x = 1664525 * x + 1013904223;
      b.write(alphabet[x.abs() % alphabet.length]);
    }
    return b.toString();
  }

  String makeOrgId(String name) => '${_slug(name)}-${_rand(4)}';
  String makeEmployeeId(String name) {
    final parts = name.trim().toUpperCase().split(RegExp(r'\s+'));
    final init = parts.map((p) => p.isEmpty ? '' : p[0]).join();
    final base = (init.isEmpty ? 'EMP' : init);
    return '$base-${_rand(4)}';
  }

  Future<void> showAddOrgDialog(BuildContext context) async {
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
    final orgId = makeOrgId(orgName);
    try {
      await _db.collection('orgs').doc(orgId).set({
        'name': orgName,
        'nameLower': orgName.toLowerCase(),
        'createdAt': Timestamp.now(),
        'isActive': true,
        'generated': true,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Org "$orgName" created as $orgId')),
      );
      orgCtrl.text = orgId;
      runInitialQuery();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create org: $e')));
    }
  }

  Future<void> showAddEmployeeDialog(BuildContext context) async {
    String? selectedOrgId = orgCtrl.text.trim().isNotEmpty
        ? orgCtrl.text.trim()
        : null;
    final nameCtrl = TextEditingController();
    bool isActive = true;

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
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Employee Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  onChanged: (v) => setS(() => isActive = v),
                  title: const Text('Active'),
                ),
                const SizedBox(height: 4),
                const Row(
                  children: [
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
    final orgId = (selectedOrgId ?? '').trim();
    final name = nameCtrl.text.trim();
    if (orgId.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Organization and Employee Name are required'),
        ),
      );
      return;
    }

    final employeeId = makeEmployeeId(name);
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
        'generated': true,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Employee "$name" created as $employeeId')),
      );
      if (orgCtrl.text.trim().isEmpty) orgCtrl.text = orgId;
      employeeIdCtrl.text = employeeId;
      runInitialQuery();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add employee: $e')));
    }
  }

  // --- Per-employee totals for current day (clipped to bounds) ---
  List<EmpTotal> computeEmployeeTotalsForDay() {
    // Bounds for the selected day only
    final startOfDay = DateTime(
      currentDate.year,
      currentDate.month,
      currentDate.day,
    );
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final now = DateTime.now();
    final boundaryNow = isToday
        ? (now.isBefore(endOfDay) ? now : endOfDay)
        : endOfDay;

    // 1) Only rows that actually fall inside the day
    final dayDocs = rows.where((d) {
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

    // 3) Pair IN→OUT strictly within the day (no carry-over)
    final List<EmpTotal> out = [];
    byEmp.forEach((_, docs) {
      docs.sort((a, b) {
        DateTime dt(QueryDocumentSnapshot<Map<String, dynamic>> x) =>
            ((x.data()['capturedAt'] as Timestamp?) ??
                    (x.data()['createdAt'] as Timestamp?))
                ?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return dt(a).compareTo(dt(b));
      });

      Duration sum = Duration.zero;
      DateTime? openIn;

      for (final doc in docs) {
        final data = doc.data();
        final type = (data['type'] as String?) ?? '';
        final t =
            ((data['capturedAt'] as Timestamp?) ??
                    (data['createdAt'] as Timestamp?))
                ?.toDate() ??
            DateTime.fromMillisecondsSinceEpoch(0);

        // we already filtered to [startOfDay, endOfDay), so no extra clipping needed
        if (type == 'IN') {
          if (openIn == null) {
            openIn = t;
          } else {
            if (t.isAfter(openIn)) sum += t.difference(openIn);
            openIn = t; // start a new interval
          }
        } else if (type == 'OUT') {
          if (openIn != null) {
            if (t.isAfter(openIn)) sum += t.difference(openIn);
            openIn = null;
          } else {
            // *** IMPORTANT CHANGE ***
            // Ignore stray OUTs if we didn't see an IN today.
            // (Prevents "yesterday" time from bleeding into today.)
          }
        }
      }

      // If still open after the last event, count up to boundary (only if IN happened today)
      if (openIn != null) {
        final end = boundaryNow;
        if (end.isAfter(openIn)) sum += end.difference(openIn);
      }

      final any = docs.first.data();
      final employeeId = any['employeeId'] as String?;
      final displayName =
          (any['employeeName'] as String?) ?? (employeeId ?? 'Unassigned');

      out.add(
        EmpTotal(
          employeeId: employeeId,
          displayName: displayName,
          duration: sum,
        ),
      );
    });

    out.sort((a, b) => b.duration.compareTo(a.duration));
    return out;
  }
}

class EmpTotal {
  final String? employeeId;
  final String displayName;
  final Duration duration;
  EmpTotal({
    required this.employeeId,
    required this.displayName,
    required this.duration,
  });
}
