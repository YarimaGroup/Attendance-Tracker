import 'package:attendance_tracker/model/attendance_event.dart';
import 'package:attendance_tracker/widgets/responsive_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show FirebaseFirestore, Blob;
import 'package:firebase_auth/firebase_auth.dart'; // NEW
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class EventDetailPage extends StatefulWidget {
  final String recordId;
  final AttendanceEvent event;
  final bool canDelete;
  const EventDetailPage({
    super.key,
    required this.recordId,
    required this.event,
    this.canDelete = false,
  });

  @override
  State<EventDetailPage> createState() => _EventDetailPageState();
}

class _EventDetailPageState extends State<EventDetailPage> {
  final _db = FirebaseFirestore.instance;

  bool? _isAdmin; // NEW
  bool _deleting = false; // NEW

  @override
  void initState() {
    super.initState();
    _loadAdminFlag(); // NEW
  }

  Future<void> _loadAdminFlag() async {
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null) return setState(() => _isAdmin = false);
      final token = await u.getIdTokenResult(true);
      setState(() => _isAdmin = token.claims?['admin'] == true);
    } catch (_) {
      setState(() => _isAdmin = false);
    }
  }

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

  // NEW: admin-only delete flow
  Future<void> _confirmAndDelete() async {
    if (_deleting) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this record?'),
        content: const Text(
          'This will permanently delete the attendance record and its media. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      final ref = _db.collection('attendanceRecords').doc(widget.recordId);

      // delete subcollections first (best-effort)
      final media = await ref.collection('media').get();
      for (final d in media.docs) {
        await d.reference.delete();
      }
      final chunks = await ref.collection('mediaChunks').get();
      for (final d in chunks.docs) {
        await d.reference.delete();
      }
      await ref.delete();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Record deleted'),
        ),
      );
      Navigator.of(context).maybePop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          content: Text('Delete failed: $e'),
        ),
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.event;
    final color = e.type == 'IN' ? Colors.green : Colors.orange;
    final typeIcon = e.type == 'IN' ? Icons.login : Icons.logout;
    // show delete if admin by token OR caller explicitly allowed it
    final allowDelete = widget.canDelete || (_isAdmin == true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance Details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (allowDelete)
            IconButton(
              tooltip: 'Delete record',
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_forever_outlined),
              onPressed: _deleting ? null : _confirmAndDelete,
            ),
        ],
        bottom: _deleting
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
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

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                expandedHeight: 400,
                automaticallyImplyLeading: false, // leading handled above
                title: const Text(''),
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

              SliverMaxWidth(
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

              const SliverMaxWidth(child: SizedBox(height: 24)),
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
