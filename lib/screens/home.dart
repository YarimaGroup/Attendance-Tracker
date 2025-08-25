import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:attendance_punch/screens/event_detail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:geocoding/geocoding.dart';

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

  // Calendar related variables
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<AttendanceEvent>> _events = {};

  @override
  void initState() {
    super.initState();
    _selectedDay = DateTime.now();
    _loadAttendanceData();
    _getCurrentLocation(); // Get location on app start
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await _getPosition();
      await _getAddressFromPosition(position);

      setState(() {});
    } catch (e) {
      debugPrint('Error getting current location: $e');
    }
  }

  Future<String> _getAddressFromPosition(Position position) async {
    try {
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        final place = placemarks[0];

        // Build a comprehensive address
        List<String> addressParts = [];

        if (place.name?.isNotEmpty == true && place.name != place.street) {
          addressParts.add(place.name!);
        }
        if (place.street?.isNotEmpty == true) {
          addressParts.add(place.street!);
        }
        if (place.subLocality?.isNotEmpty == true) {
          addressParts.add(place.subLocality!);
        }
        if (place.locality?.isNotEmpty == true) {
          addressParts.add(place.locality!);
        }
        if (place.administrativeArea?.isNotEmpty == true) {
          addressParts.add(place.administrativeArea!);
        }
        if (place.postalCode?.isNotEmpty == true) {
          addressParts.add(place.postalCode!);
        }

        if (addressParts.isNotEmpty) {
          return addressParts
              .take(3)
              .join(', '); // Limit to first 3 parts for readability
        }
      }
    } catch (e) {
      debugPrint('Error getting address: $e');
    }

    // Fallback to coordinates if address lookup fails
    return 'Location: ${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
  }

  Future<void> _loadAttendanceData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    // Load attendance data for current month
    final start = DateTime(_focusedDay.year, _focusedDay.month, 1);
    final firstDayNextMonth = DateTime(
      _focusedDay.year,
      _focusedDay.month + 1,
      1,
    );

    try {
      final snapshot = await _db
          .collection('attendanceRecords')
          .where('uid', isEqualTo: user.uid)
          .where(
            'capturedAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(start),
          )
          .where(
            'capturedAt',
            isLessThan: Timestamp.fromDate(firstDayNextMonth),
          ) // < next month
          .orderBy('capturedAt')
          .get();

      final Map<DateTime, List<AttendanceEvent>> events = {};

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final timestamp = data['capturedAt'] as Timestamp?;
        final type = data['type'] as String?;
        final location = data['location'] as Map<String, dynamic>?;
        final address = data['address'] as String?;

        if (timestamp != null && type != null) {
          final date = DateTime(
            timestamp.toDate().year,
            timestamp.toDate().month,
            timestamp.toDate().day,
          );

          final event = AttendanceEvent(
            type: type,
            time: timestamp.toDate(),
            id: doc.id,
            location: location,
            address: address,
          );

          if (events[date] == null) {
            events[date] = [];
          }
          events[date]!.add(event);
        }
      }

      setState(() {
        _events = events;
      });
    } catch (e) {
      debugPrint('Error loading attendance data: $e');
    }
  }

  List<AttendanceEvent> _getEventsForDay(DateTime day) {
    return _events[DateTime(day.year, day.month, day.day)] ?? [];
  }

  Future<void> _punch(String type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _busy = true;
      _status = 'Getting location...';
    });

    String? tempImagePath;
    try {
      // 1) Get current location first
      setState(() {
        _status = 'Getting location...';
      });

      final pos = await _getPosition();
      final address = await _getAddressFromPosition(pos);

      setState(() {
        _status = 'Taking photo...';
      });

      // 2) Capture selfie (front camera)
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );
      if (shot == null) {
        setState(() => _status = 'Photo capture cancelled');
        return;
      }
      tempImagePath = shot.path;

      setState(() {
        _status = 'Processing...';
      });

      final file = File(shot.path);
      if (!await file.exists()) throw Exception('Photo file not found');
      final raw = await file.readAsBytes();

      // 3) Compress images
      final Uint8List photo = await _compressForFirestore(
        raw,
        maxBytes: 500 * 1024,
      );
      final Uint8List thumb = await _makeThumb(raw, maxBytes: 50 * 1024);

      // 4) Create record doc
      final recordId = _uuid.v4();
      final docRef = _db.collection('attendanceRecords').doc(recordId);
      final now = DateTime.now();
      final timestamp = FieldValue.serverTimestamp();

      final mainData = {
        'uid': user.uid,
        'type': type,
        'status': 'SYNCED',
        'capturedAt': timestamp,
        'createdAt': timestamp,
        'timezone': 'Asia/Kolkata',
        'location': {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracyM': pos.accuracy,
        },
        'address': address, // Store the address
        'hasPhoto': true,
        'photoDocId': 'photo',
        'thumb': thumb,
      };

      await docRef.set(mainData);

      // 5) Store full selfie bytes in subcollection doc
      final mediaRef = docRef.collection('media').doc('photo');
      final mediaData = {
        'photo': photo,
        'photoMime': 'image/jpeg',
        'createdAt': timestamp,
      };

      final totalDocSize = photo.lengthInBytes + 1000;
      if (totalDocSize > 1048576) {
        throw Exception(
          'Compressed image still too large: $totalDocSize bytes. Try again.',
        );
      }

      await mediaRef.set(mediaData);

      // 6) Update calendar with new event
      final today = DateTime(now.year, now.month, now.day);
      final newEvent = AttendanceEvent(
        type: type,
        time: now,
        id: recordId,
        location: {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracyM': pos.accuracy,
        },
        address: address,
      );

      setState(() {
        if (_events[today] == null) {
          _events[today] = [];
        }
        _events[today]!.add(newEvent);
        _events[today]!.sort((a, b) => a.time.compareTo(b.time));
        _status = '$type successful at $address';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$type recorded successfully'),
              const SizedBox(height: 4),
              Text('Location: $address', style: const TextStyle(fontSize: 12)),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
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
    int targetW = width > 800 ? 800 : width;
    int quality = 70;

    Uint8List out = _encodeJpg(decoded, targetW, quality);

    while (out.lengthInBytes > maxBytes) {
      if (quality > 30) {
        quality -= 10;
      } else if (targetW > 400) {
        targetW = math.max(400, targetW - 100);
        quality = 70;
      } else if (targetW > 300) {
        targetW = math.max(300, targetW - 50);
        quality = 60;
      } else if (quality > 20) {
        quality -= 5;
      } else {
        targetW = math.max(200, targetW - 50);
        quality = 30;
      }

      out = _encodeJpg(decoded, targetW, quality);

      if (targetW <= 200 && quality <= 20) {
        break;
      }
    }

    debugPrint(
      'Compressed image: ${out.lengthInBytes} bytes, width: $targetW, quality: $quality',
    );
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

    // Try cached position first (much faster)
    try {
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        return lastPosition;
      }
    } catch (e) {
      debugPrint('No cached position: $e');
    }

    // Get fresh position with more reasonable settings
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high, // Changed from best to high
      timeLimit: const Duration(seconds: 25), // Increased timeout
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
      drawerBarrierDismissible: false,
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          // IconButton(
          //   tooltip: 'Refresh Location',
          //   icon: const Icon(Icons.my_location),
          //   onPressed: _busy ? null : _getCurrentLocation,
          // ),
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
          // User info section
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

          // Current Location section

          // Status message
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

          // Clock In/Out buttons
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
          const SizedBox(height: 16),

          // Calendar section
          Expanded(
            child: Card(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Attendance Calendar',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TableCalendar<AttendanceEvent>(
                      firstDay: DateTime.utc(2020, 1, 1),
                      lastDay: DateTime.utc(2030, 12, 31),
                      focusedDay: _focusedDay,
                      calendarFormat: CalendarFormat.month,
                      eventLoader: _getEventsForDay,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      selectedDayPredicate: (day) {
                        return isSameDay(_selectedDay, day);
                      },
                      onDaySelected: (selectedDay, focusedDay) {
                        if (!isSameDay(_selectedDay, selectedDay)) {
                          setState(() {
                            _selectedDay = selectedDay;
                            _focusedDay = focusedDay;
                          });
                        }
                      },
                      onPageChanged: (focusedDay) {
                        _focusedDay = focusedDay;
                        _loadAttendanceData(); // Load data for new month
                      },
                      calendarStyle: CalendarStyle(
                        outsideDaysVisible: false,
                        weekendTextStyle: TextStyle(color: Colors.red[400]),
                        holidayTextStyle: TextStyle(color: Colors.red[400]),
                        markersMaxCount: 2,
                        markerDecoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        markersAnchor: 1.2,
                      ),
                      headerStyle: const HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                      ),
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, day, events) {
                          if (events.isEmpty) return null;

                          final attendanceEvents = events
                              .cast<AttendanceEvent>();
                          final hasClockIn = attendanceEvents.any(
                            (e) => e.type == 'IN',
                          );
                          final hasClockOut = attendanceEvents.any(
                            (e) => e.type == 'OUT',
                          );

                          return Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasClockIn)
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (hasClockOut)
                                Container(
                                  width: 6,
                                  height: 6,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 1,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Events for selected day
                    if (_selectedDay != null) ...[
                      Text(
                        'Events for ${DateFormat('MMM d, yyyy').format(_selectedDay!)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: _buildEventsList(
                          _getEventsForDay(_selectedDay!),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEventsList(List<AttendanceEvent> events) {
    if (events.isEmpty) {
      return const Center(
        child: Text(
          'No attendance records for this day',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: events.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final event = events[index];
        final color = event.type == 'IN' ? Colors.green : Colors.orange;
        final icon = event.type == 'IN' ? Icons.login : Icons.logout;

        return InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) {
                  return EventDetailPage(recordId: event.id, event: event);
                },
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Clock ${event.type}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: color,
                        ),
                      ),
                      Text(
                        DateFormat('hh:mm a').format(event.time),
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (event.address != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 12,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                event.address!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else if (event.location != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.location_on,
                              size: 12,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'Lat: ${event.location!['lat'].toStringAsFixed(4)}, '
                                'Lng: ${event.location!['lng'].toStringAsFixed(4)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class AttendanceEvent {
  final String type;
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
}

class PermissionDeniedException implements Exception {
  final String message;
  PermissionDeniedException(this.message);
  @override
  String toString() => message;
}
