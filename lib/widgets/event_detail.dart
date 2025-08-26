import 'package:attendance_punch/model/attendance_event.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, Blob;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      photoBytes = _asBytes(data['photo']);
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
    if (v is Uint8List) return v;
    if (v is Blob) return v.bytes;
    if (v is List) return Uint8List.fromList(List<int>.from(v));
    return null;
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('$label copied'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final color = e.type == 'IN' ? Colors.green : Colors.orange;
    final typeIcon = e.type == 'IN' ? Icons.login : Icons.logout;

    return Scaffold(
      body: FutureBuilder<_EventMedia>(
        future: _loadMedia(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Attendance Details')),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Could not load media: ${snap.error}'),
                ),
              ),
            );
          }

          final media = snap.data!;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 300,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                title: const Text('Attendance Details'),
                flexibleSpace: FlexibleSpaceBar(
                  background: media.photoBytes != null
                      ? Hero(
                          tag: 'record-photo-${widget.recordId}',
                          child: InteractiveViewer(
                            minScale: 1,
                            maxScale: 4,
                            child: Container(
                              color: Colors.black,
                              alignment: Alignment.center,
                              child: Image.memory(
                                media.photoBytes!,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: double.infinity,
                              ),
                            ),
                          ),
                        )
                      : Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFFeef2f7), Color(0xFFdfe7f1)],
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.photo,
                              size: 72,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: color.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: color.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(typeIcon, size: 16, color: color),
                            const SizedBox(width: 6),
                            Text(
                              'Clock ${e.type}',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (media.mime != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            media.mime!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.grey.withOpacity(0.25)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          _MetaTile(
                            icon: Icons.schedule,
                            title: 'Time',
                            subtitle: DateFormat(
                              'EEE, MMM d, yyyy • hh:mm a',
                            ).format(e.time),
                            onCopy: () => _copy(
                              'Time',
                              DateFormat('yyyy-MM-dd HH:mm:ss').format(e.time),
                            ),
                          ),
                          if (media.address != null)
                            _MetaTile(
                              icon: Icons.place_outlined,
                              title: 'Address',
                              subtitle: media.address!,
                              onCopy: () => _copy('Address', media.address!),
                            ),
                          if (media.location != null) ...[
                            const Divider(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: _MetaTile(
                                    icon: Icons.my_location,
                                    title: 'Latitude',
                                    subtitle: _fmt(media.location!['lat']),
                                    onCopy: () => _copy(
                                      'Latitude',
                                      _fmt(media.location!['lat']),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _MetaTile(
                                    icon: Icons.my_location,
                                    title: 'Longitude',
                                    subtitle: _fmt(media.location!['lng']),
                                    onCopy: () => _copy(
                                      'Longitude',
                                      _fmt(media.location!['lng']),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (media.location!['accuracyM'] != null)
                              _MetaTile(
                                icon: Icons.precision_manufacturing_outlined,
                                title: 'Accuracy',
                                subtitle: '${media.location!['accuracyM']} m',
                              ),
                          ],
                          const Divider(height: 16),
                          _MetaTile(
                            icon: Icons.key_outlined,
                            title: 'Record ID',
                            subtitle: widget.recordId,
                            onCopy: () => _copy('Record ID', widget.recordId),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
          );
        },
      ),
    );
  }

  String _fmt(dynamic v) {
    if (v is num) return v.toStringAsFixed(6);
    return v?.toString() ?? '';
  }
}

class _MetaTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onCopy;
  const _MetaTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(subtitle),
              ],
            ),
          ),
          if (onCopy != null)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: onCopy,
            ),
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
