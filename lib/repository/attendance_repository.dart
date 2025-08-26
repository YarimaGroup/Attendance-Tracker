import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../model/attendance_event.dart';

class AttendancePage {
  final List<AttendanceEvent> events;
  final Timestamp? nextCursor;
  final bool hasMore;
  const AttendancePage({
    required this.events,
    required this.nextCursor,
    required this.hasMore,
  });
}

class AttendanceRepository {
  final FirebaseFirestore _db;
  final Uuid _uuid;
  AttendanceRepository({FirebaseFirestore? db, Uuid? uuid})
    : _db = db ?? FirebaseFirestore.instance,
      _uuid = uuid ?? const Uuid();

  Future<List<AttendanceEvent>> eventsForDate(
    DateTime dateUtc,
    String uid,
  ) async {
    final startOfDay = DateTime(dateUtc.year, dateUtc.month, dateUtc.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final snapshot = await _db
        .collection('attendanceRecords')
        .where('uid', isEqualTo: uid)
        .where(
          'capturedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('capturedAt', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('capturedAt')
        .get();

    return snapshot.docs.map(AttendanceEvent.fromDoc).toList();
  }

  // New: Paged fetch to reduce reads
  Future<AttendancePage> eventsForDatePaged(
    DateTime dateUtc,
    String uid, {
    int limit = 20,
    Timestamp? startAfter,
  }) async {
    final startOfDay = DateTime(dateUtc.year, dateUtc.month, dateUtc.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    Query<Map<String, dynamic>> q = _db
        .collection('attendanceRecords')
        .where('uid', isEqualTo: uid)
        .where(
          'capturedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .where('capturedAt', isLessThan: Timestamp.fromDate(endOfDay))
        .orderBy('capturedAt')
        .limit(limit);

    if (startAfter != null) {
      q = (q).startAfter([startAfter]);
    }

    final snapshot = await q.get();

    final events = snapshot.docs.map(AttendanceEvent.fromDoc).toList();
    Timestamp? next;
    if (snapshot.docs.isNotEmpty && snapshot.docs.length == limit) {
      final last = snapshot.docs.last.data()['capturedAt'] as Timestamp?;
      next = last; // may be null if serverTimestamp not yet resolved
    }

    return AttendancePage(
      events: events,
      nextCursor: next,
      hasMore: events.length == limit,
    );
  }

  // repository/attendance_repository.dart
  Future<void> createPunch({
    required String type,
    required String uid,
    required Map<String, dynamic> location,
    required String address,
    required Uint8List photo,
    required Uint8List thumb,
    String? userEmail, // NEW
    String? userDisplayName, // NEW
  }) async {
    final recordId = _uuid.v4();
    final docRef = _db.collection('attendanceRecords').doc(recordId);
    final timestamp = FieldValue.serverTimestamp();

    final mainData = {
      'uid': uid,
      'userEmail': userEmail ?? '', // NEW
      'userDisplayName': userDisplayName ?? '', // NEW
      'type': type,
      'status': 'SYNCED',
      'capturedAt': timestamp,
      'createdAt': timestamp,
      'timezone': 'Asia/Kolkata',
      'location': location,
      'address': address,
      'hasPhoto': true,
      'photoDocId': 'photo',
      'thumb': thumb,
    };

    await docRef.set(mainData);
    await docRef.collection('media').doc('photo').set({
      'photo': photo,
      'photoMime': 'image/jpeg',
      'createdAt': timestamp,
    });

    final totalDocSize = photo.lengthInBytes + 1000;
    if (totalDocSize > 1048576) {
      throw Exception(
        'Compressed image still too large: $totalDocSize bytes. Try again.',
      );
    }
  }
}
