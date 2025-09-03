import 'dart:async';
import 'package:attendance_tracker/model/attendance_event.dart';
import 'package:attendance_tracker/repository/attendance_repository.dart';
import 'package:attendance_tracker/services/geolocation_service.dart';
import 'package:attendance_tracker/services/media_service.dart';
import 'package:attendance_tracker/widgets/employee_picker_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class HomeController extends ChangeNotifier {
  final AttendanceRepository repo;
  final GeolocationService geo;
  final MediaService media;

  HomeController({required this.repo, required this.geo, required this.media});

  // UI state
  bool busy = false;
  String? status;

  // Date & events
  DateTime selectedDate = DateTime.now();
  final List<AttendanceEvent> events = [];
  final Set<String> _seenIds = <String>{};

  // Paging
  bool initialLoading = true;
  bool loadingMore = false;
  bool hasMore = true;
  Timestamp? _cursor;

  bool get isToday => _sameDay(selectedDate, DateTime.now());

  Future<void> init() async {
    await _prewarmLocation();
    await loadInitial();
  }

  Future<void> _prewarmLocation() async {
    try {
      final pos = await geo.getPosition();
      await geo.addressFromPosition(pos);
    } catch (_) {}
  }

  Future<void> loadInitial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    initialLoading = true;
    events.clear();
    _seenIds.clear();
    _cursor = null;
    hasMore = true;
    notifyListeners();

    try {
      final page = await repo.eventsForDatePaged(
        selectedDate,
        user.uid,
        limit: 20,
      );
      _appendUnique(page.events);
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (e) {
      debugPrint('Error loading attendance data: $e');
    } finally {
      initialLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMore() async {
    if (loadingMore || !hasMore) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await repo.eventsForDatePaged(
        selectedDate,
        user.uid,
        limit: 20,
        startAfter: _cursor,
      );
      _appendUnique(page.events);
      _cursor = page.nextCursor;
      hasMore = page.hasMore;
    } catch (e) {
      debugPrint('Error loading more: $e');
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void changeDate(int days) {
    selectedDate = selectedDate.add(Duration(days: days));
    loadInitial();
  }

  void goToToday() {
    selectedDate = DateTime.now();
    loadInitial();
  }

  Future<void> pickDate(BuildContext context) async {
    final now = DateTime.now();
    final initial = selectedDate.isAfter(now) ? now : selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Jump to date',
    );
    if (picked != null && !_sameDay(picked, selectedDate)) {
      selectedDate = picked;
      await loadInitial();
    }
  }

  Future<void> punch(BuildContext context, String type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final picked = await showEmployeePickerSheet(context, orgId: null);
    if (picked == null) return;

    busy = true;
    status = 'Getting location...';
    notifyListeners();

    String? tempPath;
    try {
      final pos = await geo.getPosition();
      final address = await geo.addressFromPosition(pos);

      status = 'Taking photo...';
      notifyListeners();

      final shot = await media.takeFrontCameraPhoto();
      if (shot == null) {
        status = 'Photo capture cancelled';
        notifyListeners();
        return;
      }
      tempPath = shot.path;

      status = 'Processing...';
      notifyListeners();

      final raw = await media.readBytes(shot.path);
      final Uint8List photo = await media.compressForFirestore(
        raw,
        maxBytes: 500 * 1024,
      );
      final Uint8List thumb = await media.makeThumb(raw, maxBytes: 50 * 1024);

      await repo.createPunch(
        type: type,
        uid: user.uid,
        userEmail: user.email,
        userDisplayName: user.displayName,
        employeeId: picked.id,
        employeeName: picked.name,
        orgId: picked.orgId,
        location: {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracyM': pos.accuracy,
        },
        address: address,
        photo: photo,
        thumb: thumb,
      );

      if (isToday) await loadInitial();

      status = '$type successful at $address';
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          content: Row(
            children: [
              Icon(type == 'IN' ? Icons.login : Icons.logout),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$type recorded successfully',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Location: $address',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      status = 'Could not complete: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          content: Text('Error: $e'),
        ),
      );
    } finally {
      media.cleanupTemp(tempPath);
      busy = false;
      notifyListeners();
    }
  }

  Future<void> confirmAndSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'You will need to sign in again to record attendance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  // --- helpers ---
  void _appendUnique(List<AttendanceEvent> incoming) {
    for (final e in incoming) {
      if (_seenIds.add(e.id)) {
        events.add(e);
      }
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
