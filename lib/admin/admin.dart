import 'dart:typed_data';
import 'package:attendance_punch/screens/event_detail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:attendance_punch/screens/home.dart';

/// Admin panel to review attendance across ALL users.
///
/// Requirements:
/// - Firestore security rules must allow admins to read all attendance.
/// - Each attendance record should also store `userEmail` and `userDisplayName`
///   (add these at creation time on the client).
///
/// Optional conveniences:
/// - Filter by date range and exact email.
/// - Pagination with "Load more".
class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final _db = FirebaseFirestore.instance;

  final DateFormat _dfDate = DateFormat('MMM d, yyyy');
  final DateFormat _dfTime = DateFormat('hh:mm a');

  // Filters
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  final _emailCtrl = TextEditingController();

  // Paging
  static const int _pageSize = 30;
  bool _loading = false;
  bool _hasMore = true;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _rows = [];
  DocumentSnapshot? _lastDoc;

  @override
  void initState() {
    super.initState();
    _runInitialQuery();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _buildQuery() {
    // Normalize end date to end-of-day (exclusive by adding 1 day)
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
    if (email.isNotEmpty) {
      // Exact match filter. For partial text search you would need an index/edge-ngrams.
      q = q.where('userEmail', isEqualTo: email);
    }
    if (_lastDoc != null) {
      q = q.startAfterDocument(_lastDoc!);
    }
    return q;
  }

  Future<void> _runInitialQuery() async {
    setState(() {
      _rows.clear();
      _hasMore = true;
      _lastDoc = null;
      _loading = true;
    });
    try {
      final snap = await _buildQuery().get();
      setState(() {
        _rows = snap.docs;
        if (snap.docs.isNotEmpty) {
          _lastDoc = snap.docs.last;
        }
        _hasMore = snap.docs.length == _pageSize;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      final snap = await _buildQuery().get();
      setState(() {
        _rows.addAll(snap.docs);
        if (snap.docs.isNotEmpty) {
          _lastDoc = snap.docs.last;
        }
        _hasMore = snap.docs.length == _pageSize;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFromDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _from,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2030, 12, 31),
    );
    if (d != null) {
      setState(() => _from = d);
      await _runInitialQuery();
    }
  }

  Future<void> _pickToDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _to,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2030, 12, 31),
    );
    if (d != null) {
      setState(() => _to = d);
      await _runInitialQuery();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Attendance'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Filters
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Row(
              children: [
                _DateChip(
                  label: 'From',
                  value: _dfDate.format(_from),
                  onTap: _pickFromDate,
                ),
                const SizedBox(width: 8),
                _DateChip(
                  label: 'To',
                  value: _dfDate.format(_to),
                  onTap: _pickToDate,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Filter by email (exact)',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _runInitialQuery(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _loading ? null : _runInitialQuery,
                  child: const Text('Apply'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: _loading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                ? const Center(child: Text('No records in this range'))
                : ListView.separated(
                    itemCount: _rows.length + 1, // +1 for load-more row
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == _rows.length) {
                        if (!_hasMore) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Center(
                            child: OutlinedButton.icon(
                              onPressed: _loading ? null : _loadMore,
                              icon: const Icon(Icons.expand_more),
                              label: _loading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Load more'),
                            ),
                          ),
                        );
                      }

                      final doc = _rows[index];
                      final data = doc.data();
                      final String type = (data['type'] as String?) ?? '?';
                      final Timestamp? ts = data['capturedAt'] as Timestamp?;
                      final DateTime time =
                          ts?.toDate() ??
                          (data['createdAt'] as Timestamp?)?.toDate() ??
                          DateTime.fromMillisecondsSinceEpoch(0);
                      final String who =
                          (data['userDisplayName'] as String?)
                                  ?.trim()
                                  .isNotEmpty ==
                              true
                          ? data['userDisplayName']
                          : (data['userEmail'] as String?) ?? data['uid'];
                      final String? address = data['address'] as String?;
                      final Uint8List? thumb = (data['thumb'] is Uint8List)
                          ? data['thumb'] as Uint8List
                          : (data['thumb'] is List<int>)
                          ? Uint8List.fromList(List<int>.from(data['thumb']))
                          : null;

                      final color = type == 'IN' ? Colors.green : Colors.orange;

                      return ListTile(
                        leading: thumb == null
                            ? CircleAvatar(
                                backgroundColor: color.withOpacity(0.15),
                                child: Icon(
                                  type == 'IN' ? Icons.login : Icons.logout,
                                  color: color,
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(
                                  thumb,
                                  width: 44,
                                  height: 44,
                                  fit: BoxFit.cover,
                                ),
                              ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                who,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: color.withOpacity(0.4),
                                ),
                              ),
                              child: Text(
                                'Clock $type',
                                style: TextStyle(color: color, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${_dfDate.format(time)}  ·  ${_dfTime.format(time)} IST',
                            ),
                            if (address != null && address.isNotEmpty)
                              Text(
                                address,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => EventDetailPage(
                                recordId: doc.id,
                                event: AttendanceEvent(
                                  type: type,
                                  time: time,
                                  id: doc.id,
                                  location:
                                      data['location'] as Map<String, dynamic>?,
                                  address: address,
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  const _DateChip({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 8),
            Text(value),
            const SizedBox(width: 4),
            const Icon(Icons.calendar_today, size: 16),
          ],
        ),
      ),
    );
  }
}
