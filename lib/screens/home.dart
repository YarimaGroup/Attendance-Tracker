import 'dart:async';
import 'package:attendance_tracker/model/attendance_event.dart';
import 'package:attendance_tracker/repository/attendance_repository.dart';
import 'package:attendance_tracker/services/geolocation_service.dart';
import 'package:attendance_tracker/services/media_service.dart';
import 'package:attendance_tracker/widgets/responsive_widget.dart';
import 'package:attendance_tracker/widgets/summary_card.dart';
import 'package:attendance_tracker/widgets/event_detail.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _repo = AttendanceRepository();
  final _geo = GeolocationService();
  final _media = MediaService();

  bool _busy = false;
  String? _status;

  DateTime _selectedDate = DateTime.now();
  final List<AttendanceEvent> _events = [];
  final Set<String> _seenIds = <String>{};

  // Paging state
  bool _initialLoading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Timestamp? _cursor;

  @override
  void initState() {
    super.initState();
    _loadInitial();
    _prewarmLocation();
  }

  void _appendUnique(List<AttendanceEvent> incoming) {
    // If repo can return same logical record with a different id,
    // you can switch the key below to a composite like "$id|${time.millisecondsSinceEpoch}".
    for (final e in incoming) {
      if (_seenIds.add(e.id)) {
        _events.add(e);
      }
    }
  }

  Future<void> _prewarmLocation() async {
    try {
      final pos = await _geo.getPosition();
      await _geo.addressFromPosition(pos);
      if (mounted) setState(() {});
    } catch (_) {}
  }

  bool _isToday() {
    final now = DateTime.now();
    return _sameDay(_selectedDate, now);
  }

  String _dateDisplay() {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final tomorrow = now.add(const Duration(days: 1));
    if (_isToday()) return 'Today';
    if (_sameDay(_selectedDate, yesterday)) return 'Yesterday';
    if (_sameDay(_selectedDate, tomorrow)) return 'Tomorrow';
    return DateFormat('MMM d, yyyy').format(_selectedDate);
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _loadInitial() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _initialLoading = true;
      _events.clear();
      _seenIds.clear(); // <-- reset seen ids
      _cursor = null;
      _hasMore = true;
    });
    try {
      final page = await _repo.eventsForDatePaged(
        _selectedDate,
        user.uid,
        limit: 20,
      );
      setState(() {
        _appendUnique(page.events); // <-- unique add
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      debugPrint('Error loading attendance data: $e');
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.eventsForDatePaged(
        _selectedDate,
        user.uid,
        limit: 20,
        startAfter: _cursor,
      );
      setState(() {
        _appendUnique(page.events); // <-- unique add
        _cursor = page.nextCursor;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      debugPrint('Error loading more: $e');
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _changeDate(int days) {
    setState(() => _selectedDate = _selectedDate.add(Duration(days: days)));
    _loadInitial();
  }

  void _goToToday() {
    setState(() => _selectedDate = DateTime.now());
    _loadInitial();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _selectedDate.isAfter(now) ? now : _selectedDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      helpText: 'Jump to date',
    );
    if (picked != null && !_sameDay(picked, _selectedDate)) {
      setState(() => _selectedDate = picked);
      _loadInitial();
    }
  }

  Future<void> _punch(String type) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() {
      _busy = true;
      _status = 'Getting location...';
    });

    String? tempPath;
    try {
      final pos = await _geo.getPosition();
      final address = await _geo.addressFromPosition(pos);

      setState(() => _status = 'Taking photo...');

      final shot = await _media.takeFrontCameraPhoto();
      if (shot == null) {
        setState(() => _status = 'Photo capture cancelled');
        return;
      }
      tempPath = shot.path;

      setState(() => _status = 'Processing...');

      final raw = await _media.readBytes(shot.path);
      final Uint8List photo = await _media.compressForFirestore(
        raw,
        maxBytes: 500 * 1024,
      );
      final Uint8List thumb = await _media.makeThumb(raw, maxBytes: 50 * 1024);

      await _repo.createPunch(
        type: type,
        uid: user.uid,
        userEmail: user.email, // NEW
        userDisplayName: user.displayName, // NEW
        location: {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'accuracyM': pos.accuracy,
        },
        address: address,
        photo: photo,
        thumb: thumb,
      );

      if (_isToday()) await _loadInitial();

      setState(() => _status = '$type successful at $address');
      if (!mounted) return;
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
      setState(() => _status = 'Could not complete: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          content: Text('Error: $e'),
        ),
      );
    } finally {
      _media.cleanupTemp(tempPath);
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndSignOut() async {
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    final email = user.email ?? user.uid;
    final canGoForward = !_isToday();

    return Scaffold(
      drawerBarrierDismissible: false,
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _busy ? null : _confirmAndSignOut,
          ),
        ],
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(3),
                child: LinearProgressIndicator(minHeight: 3),
              )
            : null,
      ),
      body: RefreshIndicator(
        onRefresh: _loadInitial,
        child: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            if (n.metrics.pixels > n.metrics.maxScrollExtent - 200) {
              _loadMore();
            }
            return false;
          },
          child: CustomScrollView(
            slivers: [
              SliverMaxWidth(
                child: Padding(
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
                            Text(
                              email,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
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
              ),

              // Status line (animated)
              SliverMaxWidth(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _status == null
                      ? const SizedBox.shrink()
                      : Padding(
                          key: ValueKey(_status),
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
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),

              // Punch buttons (only today)
              if (_isToday())
                SliverMaxWidth(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 180),
                            scale: _busy ? 0.98 : 1.0,
                            child: FilledButton.icon(
                              onPressed: _busy ? null : () => _punch('IN'),
                              icon: const Icon(Icons.login),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text('Clock In'),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 180),
                            scale: _busy ? 0.98 : 1.0,
                            child: OutlinedButton.icon(
                              onPressed: _busy ? null : () => _punch('OUT'),
                              icon: const Icon(Icons.logout),
                              label: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 14),
                                child: Text('Clock Out'),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isToday())
                const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // DateSliverMaxWidth nav + picker
              SliverMaxWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickDate,
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            IconButton(
                              onPressed: () => _changeDate(-1),
                              icon: const Icon(Icons.chevron_left),
                              tooltip: 'Previous day',
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    _dateDisplay(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                  if (!_isToday())
                                    Text(
                                      DateFormat('EEEE').format(_selectedDate),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Tap to pick a date',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: canGoForward
                                  ? () => _changeDate(1)
                                  : null,
                              icon: const Icon(Icons.chevron_right),
                              tooltip: canGoForward
                                  ? 'Next day'
                                  : 'Cannot go beyond today',
                            ),
                            if (!_isToday()) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: _goToToday,
                                child: const Text('Today'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Summary (fade in)
              SliverMaxWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 250),
                    opacity: _initialLoading ? 0.6 : 1.0,
                    child: SummaryCard(events: _events),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),

              // Header row with count
              SliverMaxWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Icon(Icons.list_alt, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Detailed Records',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Spacer(),
                      if (_events.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_events.length}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),

              // Events list (paged)
              if (_initialLoading)
                const SliverMaxWidth(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: _SkeletonList(),
                  ),
                )
              else if (_events.isEmpty)
                SliverMaxWidth(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _EmptyState(
                      isToday: _isToday(),
                      onPunchIn: _busy ? null : () => _punch('IN'),
                    ),
                  ),
                )
              else
                SliverList.builder(
                  itemCount: _events.length,
                  itemBuilder: (context, index) {
                    final event = _events[index];
                    return Padding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        index == 0 ? 0 : 8,
                        16,
                        8,
                      ),
                      child: _AnimatedEventTile(event: event),
                    );
                  },
                ),

              // Load more indicator / spacer
              SliverMaxWidth(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: _loadingMore
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : (!_hasMore
                              ? const Text('— End of day —')
                              : const SizedBox.shrink()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnimatedEventTile extends StatelessWidget {
  final AttendanceEvent event;
  const _AnimatedEventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    final color = event.type == 'IN' ? Colors.green : Colors.orange;
    final icon = event.type == 'IN' ? Icons.login : Icons.logout;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, v, child) {
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, (1 - v) * 12),
            child: child,
          ),
        );
      },
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EventDetailPage(recordId: event.id, event: event),
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
                    Row(
                      children: [
                        Text(
                          'Clock ${event.type}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          DateFormat('hh:mm a').format(event.time),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
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
                              'Lat: ${event.location!['lat'].toStringAsFixed(4)}, Lng: ${event.location!['lng'].toStringAsFixed(4)}',
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
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isToday;
  final VoidCallback? onPunchIn;
  const _EmptyState({required this.isToday, this.onPunchIn});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.event_busy, size: 56, color: Colors.grey[400]),
        const SizedBox(height: 12),
        Text(
          isToday ? "You're all set for today" : 'No attendance records',
          style: TextStyle(
            color: Colors.grey[700],
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          isToday
              ? 'Start the day by clocking in.'
              : 'Pick another date or go back to today.',
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        const SizedBox(height: 16),
        if (isToday)
          FilledButton.icon(
            onPressed: onPunchIn,
            icon: const Icon(Icons.login),
            label: const Text('Clock In Now'),
          ),
      ],
    );
  }
}

class _SkeletonList extends StatelessWidget {
  const _SkeletonList();
  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(6, (i) => const _SkeletonTile()).toList(),
    );
  }
}

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 56,
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
