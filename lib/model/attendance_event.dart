import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceEvent {
  final String type; // 'IN' or 'OUT'
  final DateTime time;
  final String id;
  final Map<String, dynamic>? location;
  final String? address;

  AttendanceEvent({
    required this.type,
    required this.time,
    required this.id,
    this.location,
    this.address,
  });

  // Add this factory:
  factory AttendanceEvent.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final ts = data['capturedAt'] as Timestamp?;
    return AttendanceEvent(
      id: doc.id,
      type: data['type'] as String,
      time: (ts ?? Timestamp.now()).toDate(),
      location: data['location'] as Map<String, dynamic>?,
      address: data['address'] as String?,
    );
  }
}
