import 'dart:typed_data';
import 'package:attendance_punch/screens/home.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class EventDetailPage extends StatefulWidget {
  final String recordId;
  final AttendanceEvent event;

  const EventDetailPage({
    super.key,
    required this.recordId,
    required this.event,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final _db = FirebaseFirestore.instance;
  Future<_EventMedia> _loadMedia() async {
    final docRef = _db.collection('attendanceRecords').doc(widget.recordId);

    final mainSnap = await docRef.get();
    final mediaSnap = await docRef.collection('media').doc('photo').get();

    Uint8List? photoBytes;
    String? mime;

    if (mediaSnap.exists) {
      final data = mediaSnap.data()!;
      photoBytes = _asBytes(data['photo']); // <-- normalize here
      mime = data['photoMime'] as String?;
    }

    final main = mainSnap.data();
    final String? address = main?['address'] as String?;
    final Map<String, dynamic>? location =
        main?['location'] as Map<String, dynamic>?;

    return _EventMedia(
      photoBytes: photoBytes,
      mime: mime,
      address: address ?? widget.event.address,
      location: location ?? widget.event.location,
    );
  }

  Uint8List? _asBytes(dynamic v) {
    if (v == null) return null;
    if (v is Uint8List) return v; // already good
    if (v is Blob) return v.bytes; // Firestore Blob -> Uint8List
    if (v is List) {
      // List<dynamic>/List<int> -> Uint8List
      return Uint8List.fromList(List<int>.from(v));
    }
    return null;
  }


  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final color = e.type == 'IN' ? Colors.green : Colors.orange;

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance Details')),
      body: FutureBuilder<_EventMedia>(
        future: _loadMedia(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Could not load media: ${snap.error}'),
              ),
            );
          }

          final media = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Photo (if present)
                if (media.photoBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(media.photoBytes!, fit: BoxFit.cover),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  Container(
                    height: 200,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: const Center(child: Text('No photo found')),
                  ),
                  const SizedBox(height: 16),
                ],

                // Basic details
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.withOpacity(0.25)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            e.type == 'IN' ? Icons.login : Icons.logout,
                            color: color,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Clock ${e.type}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: color,
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _kv(
                        'Time',
                        DateFormat('MMM d, yyyy • hh:mm a').format(e.time),
                      ),
                      if (media.address != null) _kv('Address', media.address!),
                      if (media.location != null) ...[
                        _kv(
                          'Coordinates',
                          'Lat: ${_fmt(media.location!['lat'])}, Lng: ${_fmt(media.location!['lng'])}',
                        ),
                        if (media.location!['accuracyM'] != null)
                          _kv('Accuracy', '${media.location!['accuracyM']} m'),
                      ],
                      _kv('Record ID', widget.recordId),
                      if (media.mime != null) _kv('Photo MIME', media.mime!),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v is num) return v.toStringAsFixed(5);
    return v?.toString() ?? '';
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(v)),
        ],
      ),
    );
  }
}

class _EventMedia {
  final Uint8List? photoBytes;
  final String? mime;
  final String? address;
  final Map<String, dynamic>? location;

  _EventMedia({
    required this.photoBytes,
    required this.mime,
    required this.address,
    required this.location,
  });
}
