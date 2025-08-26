import 'dart:typed_data';
import 'package:attendance_punch/admin/panel/model.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp, QueryDocumentSnapshot, Blob;
import 'package:intl/intl.dart';

String rangeLabel(DateTime a, DateTime b) {
  final sameYear = a.year == b.year;
  final fmtA = sameYear ? DateFormat('MMM d') : DateFormat('MMM d, yyyy');
  final fmtB = DateFormat('MMM d, yyyy');
  return '${fmtA.format(a)} – ${fmtB.format(b)}';
}

String primaryName(Map<String, dynamic> data) {
  final name = (data['userDisplayName'] as String?)?.trim();
  if (name != null && name.isNotEmpty) return name;
  final email = (data['userEmail'] as String?)?.trim();
  if (email != null && email.isNotEmpty) return email.split('@').first;
  final uid = data['uid'] as String?;
  return uid ?? 'Unknown';
}

String? emailOf(Map<String, dynamic> data) {
  final email = (data['userEmail'] as String?)?.trim();
  return (email != null && email.isNotEmpty) ? email : null;
}

String groupIdFor(Map<String, dynamic> data) {
  final email = (data['userEmail'] as String?)?.toLowerCase();
  if (email != null && email.isNotEmpty) return email;
  final uid = data['uid'] as String?;
  return uid ?? 'unknown';
}

Uint8List? decodeThumb(dynamic t) {
  if (t == null) return null;
  if (t is Uint8List) return t;
  if (t is Blob) return t.bytes;
  if (t is List<int>) return Uint8List.fromList(t);
  return null;
}

Duration calculateWorkingTime(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  Duration totalTime = Duration.zero;
  final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>> dayGroups = {};

  for (final doc in docs) {
    final data = doc.data();
    final ts = (data['capturedAt'] as Timestamp?) ?? (data['createdAt'] as Timestamp?) ?? Timestamp.fromMillisecondsSinceEpoch(0);
    final dayKey = DateFormat('yyyy-MM-dd').format(ts.toDate());
    dayGroups.putIfAbsent(dayKey, () => []).add(doc);
  }

  for (final day in dayGroups.values) {
    day.sort((a, b) {
      final ta = (a.data()['capturedAt'] as Timestamp?) ?? (a.data()['createdAt'] as Timestamp?) ?? Timestamp.fromMillisecondsSinceEpoch(0);
      final tb = (b.data()['capturedAt'] as Timestamp?) ?? (b.data()['createdAt'] as Timestamp?) ?? Timestamp.fromMillisecondsSinceEpoch(0);
      return ta.compareTo(tb);
    });

    DateTime? inTime;
    for (final rec in day) {
      final d = rec.data();
      final type = d['type'] as String?;
      final ts = (d['capturedAt'] as Timestamp?) ?? (d['createdAt'] as Timestamp?) ?? Timestamp.fromMillisecondsSinceEpoch(0);
      final t = ts.toDate();
      if (type == 'IN') {
        inTime = t;
      } else if (type == 'OUT' && inTime != null) {
        final dur = t.difference(inTime);
        if (dur.inMilliseconds > 0) totalTime += dur;
        inTime = null;
      }
    }
  }
  return totalTime;
}

String formatDuration(Duration d) {
  if (d == Duration.zero) return '0h';
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  if (h == 0) return '${m}m';
  if (m == 0) return '${h}h';
  return '${h}h ${m}m';
}

String workingDaysText(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
  final s = <String>{};
  for (final doc in docs) {
    final data = doc.data();
    final ts = (data['capturedAt'] as Timestamp?) ?? (data['createdAt'] as Timestamp?) ?? Timestamp.fromMillisecondsSinceEpoch(0);
    s.add(DateFormat('yyyy-MM-dd').format(ts.toDate()));
  }
  final n = s.length;
  return n == 1 ? '1 day' : '$n days';
}

List<GroupInfo> buildGroups(List<QueryDocumentSnapshot<Map<String, dynamic>>> rows) {
  final Map<String, GroupInfo> map = {};
  for (final doc in rows) {
    final data = doc.data();
    final id = groupIdFor(data);
    final name = primaryName(data);
    final email = emailOf(data);
    map.putIfAbsent(id, () => GroupInfo(id: id, title: name, subtitle: email, docs: [], workingTime: Duration.zero)).docs.add(doc);
  }
  final groups = map.values.toList()
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  for (final g in groups) {
    g.docs.sort((a, b) {
      final ta = (a.data()['capturedAt'] as Timestamp?) ?? (a.data()['createdAt'] as Timestamp?) ?? Timestamp.fromMillisecondsSinceEpoch(0);
      final tb = (b.data()['capturedAt'] as Timestamp?) ?? (b.data()['createdAt'] as Timestamp?) ?? Timestamp.fromMillisecondsSinceEpoch(0);
      return tb.compareTo(ta);
    });
    g.workingTime = calculateWorkingTime(g.docs);
  }
  return groups;
}
