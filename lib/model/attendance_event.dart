import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceEvent {
  final String type; // 'IN' or 'OUT'
  final DateTime time;
  final String id;
  final Map<String, dynamic>? location;
  final String? address;

  // NEW (for display & reports)
  final String? employeeId;
  final String? employeeName;

  AttendanceEvent({
    required this.type,
    required this.time,
    required this.id,
    this.location,
    this.address,
    this.employeeId, // NEW
    this.employeeName, // NEW
  });

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
      employeeId: data['employeeId'] as String?, // NEW
      employeeName: data['employeeName'] as String?, // NEW
    );
  }
}
