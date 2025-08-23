import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = FirebaseFirestore.instance;
  final _picker = ImagePicker();
  final _uuid = const Uuid();

  bool _busy = false;
  String? _status;

  Future<void> _punch(String type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _busy = true;
      _status = null;
    });

    String? tempImagePath;
    try {
      // 1) Capture selfie (front camera)
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 100, // full; we will compress deterministically
      );
      if (shot == null) {
        setState(() => _status = 'Photo capture cancelled');
        return;
      }
      tempImagePath = shot.path;

      final file = File(shot.path);
      if (!await file.exists()) throw Exception('Photo file not found');
      final raw = await file.readAsBytes();

      // 2) Compress for Firestore (target ~700KB) and make a thumb (~144px wide)
      final Uint8List photo = await _compressForFirestore(
        raw,
        maxBytes: 700 * 1024,
      );
      final Uint8List thumb = await _makeThumb(raw, maxBytes: 90 * 1024);

      // 3) Location
      final pos = await _getPosition();

      // 4) Create record doc (thumb only in main doc)
      final recordId = _uuid.v4();
      final docRef = _db.collection('attendanceRecords').doc(recordId);
      final now = FieldValue.serverTimestamp();

      final mainData = {
        'uid': user.uid,
        'type': type, // 'IN' | 'OUT'
        'status': 'SYNCED',
        'capturedAt': now,
        'createdAt': now,
        'timezone': 'Asia/Kolkata',
        'location': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracyM': pos.accuracy,
        },
        'hasPhoto': true,
        'photoDocId': 'photo',
        'thumb': thumb, // small preview in main doc
      };

      await docRef.set(mainData);

      // 5) Store full selfie bytes in subcollection doc
      final mediaRef = docRef.collection('media').doc('photo');
      final mediaData = {
        'photo': photo,
        'photoMime': 'image/jpeg',
        'createdAt': now,
      };
      await mediaRef.set(mediaData);

      if (!mounted) return;
      setState(() => _status = '$type successful');
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$type recorded successfully')));
    } on PermissionDeniedException catch (e) {
      _showError('Location permission denied: ${e.message}');
    } on FirebaseException catch (e) {
      _showError('Firebase error: ${e.message ?? e.code}');
    } catch (e) {
      _showError('Could not complete: $e');
    } finally {
      if (tempImagePath != null) _cleanupTempFile(tempImagePath);
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<Uint8List> _compressForFirestore(
    Uint8List input, {
    required int maxBytes,
  }) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw Exception('Invalid image');
    }

    int width = decoded.width;
    int height = decoded.height;
    // Start at a practical width to reduce size quickly
    int targetW = width > 1000 ? 1000 : width;
    int quality = 80;

    Uint8List out = _encodeJpg(decoded, targetW, quality);

    // Reduce until within budget or limits reached
    while (out.lengthInBytes > maxBytes && (quality > 45 || targetW > 600)) {
      if (quality > 45) quality -= 5;
      if (targetW > 600) targetW = math.max(600, targetW - 100);
      out = _encodeJpg(decoded, targetW, quality);
    }

    return out;
  }

  Uint8List _encodeJpg(img.Image decoded, int width, int quality) {
    final resized = img.copyResize(decoded, width: width);
    return Uint8List.fromList(img.encodeJpg(resized, quality: quality));
  }

  Future<Uint8List> _makeThumb(Uint8List input, {required int maxBytes}) async {
    final decoded = img.decodeImage(input);
    if (decoded == null) {
      throw Exception('Invalid image');
    }
    int w = 144;
    int q = 60;
    Uint8List out = Uint8List.fromList(
      img.encodeJpg(img.copyResize(decoded, width: w), quality: q),
    );
    while (out.lengthInBytes > maxBytes && (q > 40 || w > 96)) {
      if (q > 40) q -= 5;
      if (w > 96) w -= 16;
      out = Uint8List.fromList(
        img.encodeJpg(img.copyResize(decoded, width: w), quality: q),
      );
    }
    return out;
  }

  Future<Position> _getPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw PermissionDeniedException('Location services are disabled.');
    }

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      throw PermissionDeniedException('Please allow location to punch.');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      timeLimit: const Duration(seconds: 12),
    );
  }

  void _cleanupTempFile(String? path) {
    if (path == null) return;
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  void _showError(String msg) {
    if (!mounted) return;
    setState(() => _status = msg);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final email = user.email ?? user.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _busy
                ? null
                : () async {
                    await FirebaseAuth.instance.signOut();
                  },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.person)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? 'Hello!',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(email, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (_busy)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _status!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _punch('IN'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Clock In'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _punch('OUT'),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 14),
                      child: Text('Clock Out'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(child: _RecentRecordsList(uid: user.uid)),
        ],
      ),
    );
  }
}

class _RecentRecordsList extends StatelessWidget {
  final String uid;
  const _RecentRecordsList({required this.uid});

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final q = db
        .collection('attendanceRecords')
        .where('uid', isEqualTo: uid)
        .orderBy('capturedAt', descending: true)
        .limit(30);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Could not load records: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('No punches yet.'));
        }
        return ListView.separated(
          itemCount: docs.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final d = docs[i].data();
            final ts = d['capturedAt'] ?? d['createdAt'];
            DateTime? t;
            if (ts is Timestamp) t = ts.toDate();
            final time = t != null
                ? DateFormat('MMM d, hh:mm a').format(t)
                : '—';
            final type = (d['type'] ?? '').toString();
            final status = (d['status'] ?? '').toString();

            final Uint8List? thumbBytes = d['thumb'] is Uint8List
                ? d['thumb'] as Uint8List
                : null;

            final color = type == 'IN'
                ? Colors.green
                : (type == 'OUT' ? Colors.orange : Colors.grey);

            return ListTile(
              leading: CircleAvatar(
                backgroundColor: color.withOpacity(0.15),
                child: Text(
                  type.isNotEmpty ? type[0] : '?',
                  style: TextStyle(color: color, fontWeight: FontWeight.bold),
                ),
              ),
              title: Text('$type · $time'),
              subtitle: Text(status),
              trailing: (thumbBytes == null)
                  ? const SizedBox(width: 48, height: 48)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        thumbBytes,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      ),
                    ),
              onTap: () async {
                // Optional: open full photo from subcollection
                final docId = (d['photoDocId'] ?? 'photo').toString();
                final parentId = snap.data!.docs[i].id;
                final media = await db
                    .collection('attendanceRecords')
                    .doc(parentId)
                    .collection('media')
                    .doc(docId)
                    .get();
                final bytes = media.data()?['photo'];
                if (bytes is Uint8List) {
                  // Show full-screen image
                  // ignore: use_build_context_synchronously
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      child: InteractiveViewer(child: Image.memory(bytes)),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }
}

class PermissionDeniedException implements Exception {
  final String message;
  PermissionDeniedException(this.message);
  @override
  String toString() => message;
}
