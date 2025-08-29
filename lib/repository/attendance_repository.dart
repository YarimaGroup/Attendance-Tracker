import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, FieldValue, Timestamp, Blob, Query;
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

  Future<void> createPunch({
    required String type, // 'IN' | 'OUT'
    required String uid,
    required Map<String, dynamic> location,
    required String address,
    required Uint8List photo,
    required Uint8List thumb,
    String? userEmail,
    String? userDisplayName,
  }) async {
    // sanitize numbers (Firestore rejects NaN/Infinity)
    double? finite(num? v) {
      if (v == null) return null;
      final d = v.toDouble();
      return d.isFinite ? d : null;
    }

    final safeLocation = <String, dynamic>{
      if (finite(location['lat']) != null) 'lat': finite(location['lat']),
      if (finite(location['lng']) != null) 'lng': finite(location['lng']),
      if (finite(location['accuracyM']) != null)
        'accuracyM': finite(location['accuracyM']),
    };

    // size guard before writes
    final approxDocSize = photo.lengthInBytes + 1000;
    if (approxDocSize > 1048576) {
      throw Exception(
        'Compressed image still too large: $approxDocSize bytes. Try again.',
      );
    }

    final recordId = _uuid.v4();
    final docRef = _db.collection('attendanceRecords').doc(recordId);
    final tsServer = FieldValue.serverTimestamp();
    final ttl = Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 45)),
    );

    final mainData = {
      'uid': uid,
      'userEmail': userEmail ?? '',
      'userDisplayName': userDisplayName ?? '',
      'type': type,
      'status': 'SYNCED',
      'capturedAt': tsServer,
      'createdAt': tsServer,
      'timezone': 'Asia/Kolkata',
      'location': safeLocation,
      'address': address,
      'hasPhoto': true,
      'photoDocId': 'photo',
      // store thumbnail as Blob (constructor, not fromBytes)
      'thumb': Blob(thumb),
      'ttlAt': ttl,
    };

    final mediaData = {
      // full photo as Blob
      'photo': Blob(photo),
      'photoMime': 'image/jpeg',
      'createdAt': tsServer,
      'ttlAt': ttl,
    };

    await docRef.set(mainData);
    await docRef.collection('media').doc('photo').set(mediaData);
  }
}
