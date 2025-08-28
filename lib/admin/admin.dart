// import 'dart:async';
// import 'dart:typed_data';
// import 'package:attendance_tracker/model/attendance_event.dart';
// import 'package:attendance_tracker/widgets/event_detail.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'
//     show
//         FirebaseFirestore,
//         Query,
//         QueryDocumentSnapshot,
//         DocumentSnapshot,
//         Timestamp,
//         Blob;
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';

// class AdminPanel extends StatefulWidget {
//   const AdminPanel({super.key});

//   @override
//   State<AdminPanel> createState() => _AdminPanelState();
// }

// class _AdminPanelState extends State<AdminPanel>
//     with SingleTickerProviderStateMixin {
//   final _db = FirebaseFirestore.instance;

//   final DateFormat _dfDate = DateFormat('MMM d, yyyy');
//   final DateFormat _dfTime = DateFormat('hh:mm a');

//   // Filters
//   DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
//   DateTime _to = DateTime.now();
//   final _emailCtrl = TextEditingController();
//   bool _groupByEmail = true;
//   Timer? _debounce;

//   // Paging
//   static const int _pageSize = 30;
//   bool _loading = false;
//   bool _hasMore = true;
//   final List<QueryDocumentSnapshot<Map<String, dynamic>>> _rows = [];
//   DocumentSnapshot? _lastDoc;

//   // Expansion state per group id (email or uid)
//   final Map<String, bool> _expanded = {};

//   // Animation controller for smooth transitions
//   late AnimationController _animationController;

//   // Filter panel visibility
//   bool _showFilters = false;

//   // Quick date filter options
//   final List<_QuickDateFilter> _quickFilters = [
//     _QuickDateFilter('Today', () {
//       final now = DateTime.now();
//       return DateTimeRange(
//         start: DateTime(now.year, now.month, now.day),
//         end: now,
//       );
//     }),
//     _QuickDateFilter('Yesterday', () {
//       final yesterday = DateTime.now().subtract(const Duration(days: 1));
//       return DateTimeRange(
//         start: DateTime(yesterday.year, yesterday.month, yesterday.day),
//         end: DateTime(
//           yesterday.year,
//           yesterday.month,
//           yesterday.day,
//           23,
//           59,
//           59,
//         ),
//       );
//     }),
//     _QuickDateFilter('This Week', () {
//       final now = DateTime.now();
//       final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
//       return DateTimeRange(
//         start: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day),
//         end: now,
//       );
//     }),
//     _QuickDateFilter('This Month', () {
//       final now = DateTime.now();
//       return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
//     }),
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _animationController = AnimationController(
//       duration: const Duration(milliseconds: 200),
//       vsync: this,
//     );
//     _runInitialQuery();
//     _emailCtrl.addListener(_onEmailChanged);
//   }

//   @override
//   void dispose() {
//     _emailCtrl.removeListener(_onEmailChanged);
//     _emailCtrl.dispose();
//     _debounce?.cancel();
//     _animationController.dispose();
//     super.dispose();
//   }

//   void _onEmailChanged() {
//     _debounce?.cancel();
//     _debounce = Timer(const Duration(milliseconds: 450), () {
//       _runInitialQuery();
//     });
//   }

//   Query<Map<String, dynamic>> _buildQuery() {
//     final startTs = Timestamp.fromDate(
//       DateTime(_from.year, _from.month, _from.day),
//     );
//     final endExclusive = DateTime(
//       _to.year,
//       _to.month,
//       _to.day,
//     ).add(const Duration(days: 1));
//     final endTs = Timestamp.fromDate(endExclusive);

//     Query<Map<String, dynamic>> q = _db
//         .collection('attendanceRecords')
//         .where('capturedAt', isGreaterThanOrEqualTo: startTs)
//         .where('capturedAt', isLessThan: endTs)
//         .orderBy('capturedAt', descending: true)
//         .limit(_pageSize);

//     final email = _emailCtrl.text.trim();
//     if (email.isNotEmpty) {
//       q = q.where('userEmail', isEqualTo: email);
//     }
//     if (_lastDoc != null) {
//       q = q.startAfterDocument(_lastDoc!);
//     }
//     return q;
//   }

//   Future<void> _runInitialQuery() async {
//     setState(() {
//       _rows.clear();
//       _hasMore = true;
//       _lastDoc = null;
//       _loading = true;
//     });

//     _animationController.forward();

//     try {
//       final snap = await _buildQuery().get();
//       setState(() {
//         _rows.addAll(snap.docs);
//         if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
//         _hasMore = snap.docs.length == _pageSize;
//       });
//     } finally {
//       if (mounted) {
//         setState(() => _loading = false);
//         _animationController.reverse();
//       }
//     }
//   }

//   Future<void> _loadMore() async {
//     if (_loading || !_hasMore) return;
//     setState(() => _loading = true);
//     try {
//       final snap = await _buildQuery().get();
//       setState(() {
//         _rows.addAll(snap.docs);
//         if (snap.docs.isNotEmpty) _lastDoc = snap.docs.last;
//         _hasMore = snap.docs.length == _pageSize;
//       });
//     } finally {
//       if (mounted) setState(() => _loading = false);
//     }
//   }

//   void _applyQuickFilter(_QuickDateFilter filter) {
//     final range = filter.getRange();
//     setState(() {
//       _from = range.start;
//       _to = range.end;
//       _showFilters = false;
//     });
//     _runInitialQuery();
//   }

//   Future<void> _pickRange() async {
//     final now = DateTime.now();
//     final res = await showDateRangePicker(
//       context: context,
//       firstDate: DateTime(2020, 1, 1),
//       lastDate: now,
//       initialDateRange: DateTimeRange(
//         start: _from,
//         end: _to.isAfter(now) ? now : _to,
//       ),
//       helpText: 'Select date range',
//       builder: (context, child) {
//         return Theme(
//           data: Theme.of(context).copyWith(
//             colorScheme: Theme.of(context).colorScheme.copyWith(
//               primary: Theme.of(context).colorScheme.primary,
//             ),
//           ),
//           child: child!,
//         );
//       },
//     );
//     if (res != null) {
//       setState(() {
//         _from = res.start;
//         _to = res.end;
//         _showFilters = false;
//       });
//       _runInitialQuery();
//     }
//   }

//   String _rangeLabel(DateTime a, DateTime b) {
//     final sameYear = a.year == b.year;
//     final fmtA = sameYear ? DateFormat('MMM d') : DateFormat('MMM d, yyyy');
//     final fmtB = DateFormat('MMM d, yyyy');
//     return '${fmtA.format(a)} – ${fmtB.format(b)}';
//   }

//   String _primaryName(Map<String, dynamic> data) {
//     final name = (data['userDisplayName'] as String?)?.trim();
//     if (name != null && name.isNotEmpty) return name;
//     final email = (data['userEmail'] as String?)?.trim();
//     if (email != null && email.isNotEmpty) {
//       return email.split('@').first;
//     }
//     final uid = data['uid'] as String?;
//     return uid ?? 'Unknown';
//   }

//   String? _emailOf(Map<String, dynamic> data) {
//     final email = (data['userEmail'] as String?)?.trim();
//     return (email != null && email.isNotEmpty) ? email : null;
//   }

//   String _groupIdFor(Map<String, dynamic> data) {
//     final email = (data['userEmail'] as String?)?.toLowerCase();
//     if (email != null && email.isNotEmpty) return email;
//     final uid = data['uid'] as String?;
//     return uid ?? 'unknown';
//   }

//   List<_Group> _buildGroups() {
//     final Map<String, _Group> map = {};

//     for (final doc in _rows) {
//       final data = doc.data();
//       final id = _groupIdFor(data);
//       final name = _primaryName(data);
//       final email = _emailOf(data);
//       final g = map.putIfAbsent(
//         id,
//         () => _Group(id: id, title: name, subtitle: email),
//       );
//       g.docs.add(doc);
//     }

//     final groups = map.values.toList()
//       ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

//     for (final g in groups) {
//       g.docs.sort((a, b) {
//         final ta =
//             (a.data()['capturedAt'] as Timestamp?) ??
//             (a.data()['createdAt'] as Timestamp?) ??
//             Timestamp.fromMillisecondsSinceEpoch(0);
//         final tb =
//             (b.data()['capturedAt'] as Timestamp?) ??
//             (b.data()['createdAt'] as Timestamp?) ??
//             Timestamp.fromMillisecondsSinceEpoch(0);
//         return tb.compareTo(ta);
//       });

//       // Calculate working time for this group
//       g.workingTime = _calculateWorkingTime(g.docs);
//     }

//     return groups;
//   }

//   Duration _calculateWorkingTime(
//     List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
//   ) {
//     Duration totalTime = Duration.zero;

//     // Group records by date to handle multiple sessions per day
//     final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
//     dayGroups = {};

//     for (final doc in docs) {
//       final data = doc.data();
//       final timestamp =
//           (data['capturedAt'] as Timestamp?) ??
//           (data['createdAt'] as Timestamp?) ??
//           Timestamp.fromMillisecondsSinceEpoch(0);
//       final date = timestamp.toDate();
//       final dayKey = DateFormat('yyyy-MM-dd').format(date);

//       dayGroups.putIfAbsent(dayKey, () => []).add(doc);
//     }

//     // Calculate working time for each day
//     for (final dayRecords in dayGroups.values) {
//       // Sort records by time for this day
//       dayRecords.sort((a, b) {
//         final ta =
//             (a.data()['capturedAt'] as Timestamp?) ??
//             (a.data()['createdAt'] as Timestamp?) ??
//             Timestamp.fromMillisecondsSinceEpoch(0);
//         final tb =
//             (b.data()['capturedAt'] as Timestamp?) ??
//             (b.data()['createdAt'] as Timestamp?) ??
//             Timestamp.fromMillisecondsSinceEpoch(0);
//         return ta.compareTo(tb);
//       });

//       DateTime? clockInTime;

//       for (final record in dayRecords) {
//         final data = record.data();
//         final type = data['type'] as String?;
//         final timestamp =
//             (data['capturedAt'] as Timestamp?) ??
//             (data['createdAt'] as Timestamp?) ??
//             Timestamp.fromMillisecondsSinceEpoch(0);
//         final time = timestamp.toDate();

//         if (type == 'IN') {
//           clockInTime = time;
//         } else if (type == 'OUT' && clockInTime != null) {
//           final sessionDuration = time.difference(clockInTime);
//           if (sessionDuration.inMilliseconds > 0) {
//             totalTime += sessionDuration;
//           }
//           clockInTime = null; // Reset for next session
//         }
//       }
//     }

//     return totalTime;
//   }

//   String _formatDuration(Duration duration) {
//     if (duration == Duration.zero) return '0h';

//     final hours = duration.inHours;
//     final minutes = duration.inMinutes.remainder(60);

//     if (hours == 0) {
//       return '${minutes}m';
//     } else if (minutes == 0) {
//       return '${hours}h';
//     } else {
//       return '${hours}h ${minutes}m';
//     }
//   }

//   Widget _buildSummaryCard() {
//     final totalRecords = _rows.length;
//     final clockIns = _rows.where((doc) => doc.data()['type'] == 'IN').length;
//     final clockOuts = _rows.where((doc) => doc.data()['type'] == 'OUT').length;
//     final uniqueUsers = _rows
//         .map((doc) => _groupIdFor(doc.data()))
//         .toSet()
//         .length;

//     // Calculate total working time across all users
//     final totalWorkingTime = _calculateTotalWorkingTime();

//     return Card(
//       margin: const EdgeInsets.all(16),
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Row(
//               children: [
//                 Icon(
//                   Icons.analytics_outlined,
//                   color: Theme.of(context).colorScheme.primary,
//                 ),
//                 const SizedBox(width: 8),
//                 Text(
//                   'Summary',
//                   style: Theme.of(context).textTheme.titleMedium?.copyWith(
//                     fontWeight: FontWeight.w600,
//                   ),
//                 ),
//                 const Spacer(),
//                 Container(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 8,
//                     vertical: 4,
//                   ),
//                   decoration: BoxDecoration(
//                     color: Theme.of(context).colorScheme.primaryContainer,
//                     borderRadius: BorderRadius.circular(8),
//                   ),
//                   child: Text(
//                     _rangeLabel(_from, _to),
//                     style: Theme.of(context).textTheme.bodySmall?.copyWith(
//                       color: Theme.of(context).colorScheme.onPrimaryContainer,
//                       fontWeight: FontWeight.w500,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 16),
//             Row(
//               children: [
//                 Expanded(
//                   child: _SummaryItem(
//                     icon: Icons.receipt_long,
//                     label: 'Total Records',
//                     value: totalRecords.toString(),
//                     color: Colors.blue,
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: _SummaryItem(
//                     icon: Icons.login,
//                     label: 'Clock Ins',
//                     value: clockIns.toString(),
//                     color: Colors.green,
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: _SummaryItem(
//                     icon: Icons.logout,
//                     label: 'Clock Outs',
//                     value: clockOuts.toString(),
//                     color: Colors.orange,
//                   ),
//                 ),
//                 const SizedBox(width: 8),
//                 Expanded(
//                   child: _SummaryItem(
//                     icon: Icons.people,
//                     label: 'Unique Users',
//                     value: uniqueUsers.toString(),
//                     color: Colors.purple,
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 12),
//             // Total working time card
//             Container(
//               width: double.infinity,
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 gradient: LinearGradient(
//                   colors: [
//                     Colors.indigo.withOpacity(0.1),
//                     Colors.blue.withOpacity(0.05),
//                   ],
//                   begin: Alignment.topLeft,
//                   end: Alignment.bottomRight,
//                 ),
//                 borderRadius: BorderRadius.circular(12),
//                 border: Border.all(color: Colors.indigo.withOpacity(0.2)),
//               ),
//               child: Row(
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.all(12),
//                     decoration: BoxDecoration(
//                       color: Colors.indigo.withOpacity(0.15),
//                       borderRadius: BorderRadius.circular(8),
//                     ),
//                     child: const Icon(
//                       Icons.schedule,
//                       color: Colors.indigo,
//                       size: 24,
//                     ),
//                   ),
//                   const SizedBox(width: 16),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text(
//                           'Total Working Time',
//                           style: Theme.of(context).textTheme.titleSmall
//                               ?.copyWith(
//                                 fontWeight: FontWeight.w600,
//                                 color: Colors.indigo,
//                               ),
//                         ),
//                         const SizedBox(height: 4),
//                         Text(
//                           _formatDuration(totalWorkingTime),
//                           style: Theme.of(context).textTheme.headlineSmall
//                               ?.copyWith(
//                                 fontWeight: FontWeight.bold,
//                                 color: Colors.indigo,
//                               ),
//                         ),
//                       ],
//                     ),
//                   ),
//                   if (uniqueUsers > 0) ...[
//                     Column(
//                       crossAxisAlignment: CrossAxisAlignment.end,
//                       children: [
//                         Text(
//                           'Avg per User',
//                           style: Theme.of(context).textTheme.bodySmall
//                               ?.copyWith(
//                                 color: Theme.of(context).colorScheme.outline,
//                               ),
//                         ),
//                         const SizedBox(height: 2),
//                         Text(
//                           _formatDuration(
//                             Duration(
//                               milliseconds:
//                                   totalWorkingTime.inMilliseconds ~/
//                                   uniqueUsers,
//                             ),
//                           ),
//                           style: Theme.of(context).textTheme.titleMedium
//                               ?.copyWith(
//                                 fontWeight: FontWeight.w600,
//                                 color: Colors.indigo,
//                               ),
//                         ),
//                       ],
//                     ),
//                   ],
//                 ],
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Duration _calculateTotalWorkingTime() {
//     // If grouped, sum up all group working times
//     if (_groupByEmail) {
//       final groups = _buildGroups();
//       return groups.fold<Duration>(
//         Duration.zero,
//         (total, group) => total + group.workingTime,
//       );
//     } else {
//       // Calculate working time for all records
//       return _calculateWorkingTime(_rows);
//     }
//   }

//   Future<void> _confirmAndSignOut() async {
//     final ok = await showDialog<bool>(
//       context: context,
//       builder: (ctx) => AlertDialog(
//         title: const Text('Sign out?'),
//         content: const Text(
//           'You will need to sign in again to manage attendance.',
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.of(ctx).pop(false),
//             child: const Text('Cancel'),
//           ),
//           FilledButton(
//             onPressed: () => Navigator.of(ctx).pop(true),
//             child: const Text('Sign out'),
//           ),
//         ],
//       ),
//     );
//     if (ok == true) await FirebaseAuth.instance.signOut();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final grouped = _groupByEmail ? _buildGroups() : null;

//     return Scaffold(
//       backgroundColor: Theme.of(context).colorScheme.surface,
//       appBar: AppBar(
//         elevation: 0,
//         backgroundColor: Theme.of(context).colorScheme.surface,
//         foregroundColor: Theme.of(context).colorScheme.onSurface,
//         title: const Text('Attendance Admin'),
//         actions: [
//           IconButton(
//             tooltip: 'Toggle Filters',
//             icon: Icon(
//               _showFilters ? Icons.filter_alt : Icons.filter_alt_outlined,
//               color: _showFilters
//                   ? Theme.of(context).colorScheme.primary
//                   : null,
//             ),
//             onPressed: () => setState(() => _showFilters = !_showFilters),
//           ),
//           IconButton(
//             tooltip: 'Refresh',
//             icon: const Icon(Icons.refresh),
//             onPressed: _loading ? null : _runInitialQuery,
//           ),
//           IconButton(
//             tooltip: 'Sign out',
//             icon: const Icon(Icons.logout),
//             onPressed: _confirmAndSignOut,
//           ),
//         ],
//       ),
//       body: RefreshIndicator(
//         onRefresh: _runInitialQuery,
//         child: CustomScrollView(
//           slivers: [
//             // Enhanced Filters Panel
//             if (_showFilters)
//               SliverToBoxAdapter(
//                 child: AnimatedContainer(
//                   duration: const Duration(milliseconds: 300),
//                   curve: Curves.easeInOut,
//                   decoration: BoxDecoration(
//                     color: Theme.of(
//                       context,
//                     ).colorScheme.primaryContainer.withOpacity(0.3),
//                     border: Border(
//                       bottom: BorderSide(color: Theme.of(context).dividerColor),
//                     ),
//                   ),
//                   padding: const EdgeInsets.all(16),
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       // Quick date filters
//                       Text(
//                         'Quick Filters',
//                         style: Theme.of(context).textTheme.titleSmall?.copyWith(
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                       const SizedBox(height: 8),
//                       Wrap(
//                         spacing: 8,
//                         runSpacing: 8,
//                         children: _quickFilters.map((filter) {
//                           return FilterChip(
//                             label: Text(filter.label),
//                             onSelected: (_) => _applyQuickFilter(filter),
//                           );
//                         }).toList(),
//                       ),
//                       const SizedBox(height: 16),

//                       // Custom range and email filter
//                       Row(
//                         children: [
//                           Expanded(
//                             flex: 2,
//                             child: OutlinedButton.icon(
//                               onPressed: _pickRange,
//                               icon: const Icon(Icons.date_range),
//                               label: Text(_rangeLabel(_from, _to)),
//                             ),
//                           ),
//                           const SizedBox(width: 12),
//                           Expanded(
//                             flex: 3,
//                             child: TextField(
//                               controller: _emailCtrl,
//                               decoration: InputDecoration(
//                                 labelText: 'Filter by email',
//                                 prefixIcon: const Icon(Icons.search),
//                                 isDense: true,
//                                 suffixIcon: _emailCtrl.text.isNotEmpty
//                                     ? IconButton(
//                                         onPressed: () {
//                                           setState(() {
//                                             _emailCtrl.clear();
//                                           });
//                                           _runInitialQuery();
//                                         },
//                                         icon: const Icon(Icons.clear),
//                                       )
//                                     : null,
//                               ),
//                               textInputAction: TextInputAction.search,
//                               onSubmitted: (_) => _runInitialQuery(),
//                             ),
//                           ),
//                         ],
//                       ),
//                       const SizedBox(height: 16),

//                       // Group toggle and apply button
//                       Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Row(
//                             mainAxisSize: MainAxisSize.min,
//                             children: [
//                               const Text('Group by user'),
//                               Switch.adaptive(
//                                 value: _groupByEmail,
//                                 onChanged: (v) =>
//                                     setState(() => _groupByEmail = v),
//                               ),
//                             ],
//                           ),
//                           FilledButton.icon(
//                             onPressed: _loading ? null : _runInitialQuery,
//                             icon: _loading
//                                 ? const SizedBox(
//                                     width: 16,
//                                     height: 16,
//                                     child: CircularProgressIndicator(
//                                       strokeWidth: 2,
//                                     ),
//                                   )
//                                 : const Icon(Icons.search),
//                             label: Text(
//                               _loading ? 'Searching...' : 'Apply Filters',
//                             ),
//                           ),
//                         ],
//                       ),
//                     ],
//                   ),
//                 ),
//               ),

//             // Summary Card
//             if (_rows.isNotEmpty && !_loading)
//               SliverToBoxAdapter(child: _buildSummaryCard()),

//             // Loading state
//             if (_loading && _rows.isEmpty)
//               SliverFillRemaining(
//                 hasScrollBody: false,
//                 child: Center(
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       const CircularProgressIndicator(),
//                       const SizedBox(height: 16),
//                       Text(
//                         'Loading attendance records...',
//                         style: Theme.of(context).textTheme.bodyMedium,
//                       ),
//                     ],
//                   ),
//                 ),
//               )
//             // Empty state
//             else if (_rows.isEmpty && !_loading)
//               SliverFillRemaining(
//                 hasScrollBody: false,
//                 child: Center(
//                   child: Column(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: [
//                       Icon(
//                         Icons.inbox_outlined,
//                         size: 64,
//                         color: Theme.of(context).colorScheme.outline,
//                       ),
//                       const SizedBox(height: 16),
//                       Text(
//                         'No records found',
//                         style: Theme.of(context).textTheme.headlineSmall,
//                       ),
//                       const SizedBox(height: 8),
//                       Text(
//                         'Try adjusting your filters or date range',
//                         style: Theme.of(context).textTheme.bodyMedium?.copyWith(
//                           color: Theme.of(context).colorScheme.outline,
//                         ),
//                       ),
//                     ],
//                   ),
//                 ),
//               )
//             // Content
//             else if (_groupByEmail)
//               SliverPadding(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 sliver: SliverList.builder(
//                   itemCount: (grouped?.length ?? 0) + 1,
//                   itemBuilder: (context, index) {
//                     if (index == grouped!.length) {
//                       return _buildLoadMoreButton();
//                     }

//                     final g = grouped[index];
//                     final id = g.id;
//                     final expanded = _expanded[id] ?? true;

//                     return Card(
//                       margin: const EdgeInsets.only(bottom: 8),
//                       child: Column(
//                         children: [
//                           ListTile(
//                             contentPadding: const EdgeInsets.all(16),
//                             title: Row(
//                               children: [
//                                 CircleAvatar(
//                                   backgroundColor: Theme.of(
//                                     context,
//                                   ).colorScheme.primary.withOpacity(0.1),
//                                   child: Text(
//                                     _initialsFrom(g.title),
//                                     style: TextStyle(
//                                       color: Theme.of(
//                                         context,
//                                       ).colorScheme.primary,
//                                       fontWeight: FontWeight.bold,
//                                     ),
//                                   ),
//                                 ),
//                                 const SizedBox(width: 12),
//                                 Expanded(
//                                   child: Column(
//                                     crossAxisAlignment:
//                                         CrossAxisAlignment.start,
//                                     children: [
//                                       Text(
//                                         g.title,
//                                         style: const TextStyle(
//                                           fontWeight: FontWeight.w600,
//                                         ),
//                                       ),
//                                       if (g.subtitle != null)
//                                         Text(
//                                           g.subtitle!,
//                                           style: Theme.of(context)
//                                               .textTheme
//                                               .bodySmall
//                                               ?.copyWith(
//                                                 color: Theme.of(
//                                                   context,
//                                                 ).colorScheme.outline,
//                                               ),
//                                         ),
//                                       // Working time for this user
//                                       if (g.workingTime > Duration.zero) ...[
//                                         const SizedBox(height: 2),
//                                         Row(
//                                           children: [
//                                             Icon(
//                                               Icons.schedule,
//                                               size: 14,
//                                               color: Colors.indigo,
//                                             ),
//                                             const SizedBox(width: 4),
//                                             Text(
//                                               _formatDuration(g.workingTime),
//                                               style: TextStyle(
//                                                 color: Colors.indigo,
//                                                 fontWeight: FontWeight.w500,
//                                                 fontSize: 12,
//                                               ),
//                                             ),
//                                           ],
//                                         ),
//                                       ],
//                                     ],
//                                   ),
//                                 ),
//                                 Container(
//                                   padding: const EdgeInsets.symmetric(
//                                     horizontal: 12,
//                                     vertical: 6,
//                                   ),
//                                   decoration: BoxDecoration(
//                                     color: Theme.of(
//                                       context,
//                                     ).colorScheme.primary.withOpacity(0.1),
//                                     borderRadius: BorderRadius.circular(12),
//                                   ),
//                                   child: Text(
//                                     '${g.docs.length} records',
//                                     style: TextStyle(
//                                       color: Theme.of(
//                                         context,
//                                       ).colorScheme.primary,
//                                       fontSize: 12,
//                                       fontWeight: FontWeight.w500,
//                                     ),
//                                   ),
//                                 ),
//                                 IconButton(
//                                   icon: AnimatedRotation(
//                                     turns: expanded ? 0.5 : 0,
//                                     duration: const Duration(milliseconds: 200),
//                                     child: const Icon(Icons.expand_more),
//                                   ),
//                                   onPressed: () =>
//                                       setState(() => _expanded[id] = !expanded),
//                                 ),
//                               ],
//                             ),
//                           ),
//                           AnimatedCrossFade(
//                             duration: const Duration(milliseconds: 200),
//                             crossFadeState: expanded
//                                 ? CrossFadeState.showFirst
//                                 : CrossFadeState.showSecond,
//                             firstChild: Column(
//                               children: [
//                                 // Working time breakdown for this user (if expanded)
//                                 if (g.workingTime > Duration.zero &&
//                                     expanded) ...[
//                                   Container(
//                                     margin: const EdgeInsets.symmetric(
//                                       horizontal: 16,
//                                     ),
//                                     padding: const EdgeInsets.all(12),
//                                     decoration: BoxDecoration(
//                                       color: Colors.indigo.withOpacity(0.05),
//                                       borderRadius: BorderRadius.circular(8),
//                                       border: Border.all(
//                                         color: Colors.indigo.withOpacity(0.2),
//                                       ),
//                                     ),
//                                     child: Row(
//                                       children: [
//                                         Icon(
//                                           Icons.timer,
//                                           size: 16,
//                                           color: Colors.indigo,
//                                         ),
//                                         const SizedBox(width: 8),
//                                         Text(
//                                           'Working Time: ${_formatDuration(g.workingTime)}',
//                                           style: TextStyle(
//                                             color: Colors.indigo,
//                                             fontWeight: FontWeight.w500,
//                                             fontSize: 13,
//                                           ),
//                                         ),
//                                         const Spacer(),
//                                         Text(
//                                           _getWorkingDaysText(g.docs),
//                                           style: TextStyle(
//                                             color: Theme.of(
//                                               context,
//                                             ).colorScheme.outline,
//                                             fontSize: 12,
//                                           ),
//                                         ),
//                                       ],
//                                     ),
//                                   ),
//                                   const SizedBox(height: 8),
//                                 ],
//                                 ...g.docs
//                                     .map(
//                                       (doc) =>
//                                           _buildRowTile(doc, isGrouped: true),
//                                     )
//                                     .toList(),
//                               ],
//                             ),
//                             secondChild: const SizedBox.shrink(),
//                           ),
//                         ],
//                       ),
//                     );
//                   },
//                 ),
//               )
//             else
//               SliverPadding(
//                 padding: const EdgeInsets.symmetric(horizontal: 16),
//                 sliver: SliverList.separated(
//                   itemCount: _rows.length + 1,
//                   separatorBuilder: (_, __) => const SizedBox(height: 8),
//                   itemBuilder: (context, index) {
//                     if (index == _rows.length) {
//                       return _buildLoadMoreButton();
//                     }
//                     return Card(child: _buildRowTile(_rows[index]));
//                   },
//                 ),
//               ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildLoadMoreButton() {
//     if (!_hasMore) {
//       return Padding(
//         padding: const EdgeInsets.symmetric(vertical: 32),
//         child: Center(
//           child: Row(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(
//                 Icons.check_circle_outline,
//                 color: Theme.of(context).colorScheme.outline,
//               ),
//               const SizedBox(width: 8),
//               Text(
//                 'All records loaded',
//                 style: TextStyle(color: Theme.of(context).colorScheme.outline),
//               ),
//             ],
//           ),
//         ),
//       );
//     }

//     return Padding(
//       padding: const EdgeInsets.all(16),
//       child: Center(
//         child: OutlinedButton.icon(
//           onPressed: _loading ? null : _loadMore,
//           icon: _loading
//               ? const SizedBox(
//                   height: 18,
//                   width: 18,
//                   child: CircularProgressIndicator(strokeWidth: 2),
//                 )
//               : const Icon(Icons.expand_more),
//           label: Text(_loading ? 'Loading more...' : 'Load more records'),
//         ),
//       ),
//     );
//   }

//   Widget _buildRowTile(
//     QueryDocumentSnapshot<Map<String, dynamic>> doc, {
//     bool isGrouped = false,
//   }) {
//     final data = doc.data();
//     final String type = (data['type'] as String?) ?? '?';
//     final Timestamp? ts = data['capturedAt'] as Timestamp?;
//     final DateTime time =
//         ts?.toDate() ??
//         (data['createdAt'] as Timestamp?)?.toDate() ??
//         DateTime.fromMillisecondsSinceEpoch(0);

//     final String name = _primaryName(data);
//     final String? email = _emailOf(data);
//     final String? address = data['address'] as String?;

//     final dynamic t = data['thumb'];
//     Uint8List? thumb;
//     if (t is Blob) {
//       thumb = t.bytes;
//     } else if (t is Uint8List) {
//       thumb = t;
//     } else if (t is List<int>) {
//       thumb = Uint8List.fromList(t);
//     }

//     final color = type == 'IN' ? Colors.green : Colors.orange;
//     final icon = type == 'IN' ? Icons.login : Icons.logout;

//     return ListTile(
//       contentPadding: EdgeInsets.all(isGrouped ? 12 : 16),
//       leading: thumb == null
//           ? CircleAvatar(
//               backgroundColor: color.withOpacity(0.15),
//               child: Icon(icon, color: color, size: 20),
//             )
//           : ClipRRect(
//               borderRadius: BorderRadius.circular(8),
//               child: Container(
//                 width: 48,
//                 height: 48,
//                 decoration: BoxDecoration(
//                   border: Border.all(color: color.withOpacity(0.3), width: 2),
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: Image.memory(thumb, fit: BoxFit.cover),
//               ),
//             ),
//       title: Row(
//         children: [
//           if (!isGrouped)
//             Expanded(
//               child: Text(
//                 name,
//                 overflow: TextOverflow.ellipsis,
//                 style: const TextStyle(fontWeight: FontWeight.w600),
//               ),
//             ),
//           if (!isGrouped) const SizedBox(width: 8),
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
//             decoration: BoxDecoration(
//               color: color.withOpacity(0.15),
//               borderRadius: BorderRadius.circular(8),
//               border: Border.all(color: color.withOpacity(0.3)),
//             ),
//             child: Row(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 Icon(icon, size: 14, color: color),
//                 const SizedBox(width: 4),
//                 Text(
//                   'Clock $type',
//                   style: TextStyle(
//                     color: color,
//                     fontSize: 12,
//                     fontWeight: FontWeight.w500,
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           if (isGrouped) const Spacer(),
//           if (isGrouped)
//             Text(
//               _dfTime.format(time),
//               style: Theme.of(
//                 context,
//               ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
//             ),
//         ],
//       ),
//       subtitle: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           const SizedBox(height: 4),
//           Row(
//             children: [
//               Icon(
//                 Icons.schedule,
//                 size: 14,
//                 color: Theme.of(context).colorScheme.outline,
//               ),
//               const SizedBox(width: 4),
//               Text('${_dfDate.format(time)} • ${_dfTime.format(time)} IST'),
//               if (email != null && !isGrouped) ...[
//                 const SizedBox(width: 8),
//                 const Text('•'),
//                 const SizedBox(width: 8),
//                 Flexible(
//                   child: Text(
//                     email,
//                     overflow: TextOverflow.ellipsis,
//                     style: TextStyle(
//                       color: Theme.of(context).colorScheme.outline,
//                     ),
//                   ),
//                 ),
//               ],
//             ],
//           ),
//           if (address != null && address.isNotEmpty) ...[
//             const SizedBox(height: 2),
//             Row(
//               children: [
//                 Icon(
//                   Icons.location_on,
//                   size: 14,
//                   color: Theme.of(context).colorScheme.outline,
//                 ),
//                 const SizedBox(width: 4),
//                 Expanded(
//                   child: Text(
//                     address,
//                     maxLines: 1,
//                     overflow: TextOverflow.ellipsis,
//                     style: TextStyle(
//                       color: Theme.of(context).colorScheme.outline,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ],
//       ),
//       trailing: Icon(
//         Icons.arrow_forward_ios,
//         size: 16,
//         color: Theme.of(context).colorScheme.outline,
//       ),
//       onTap: () {
//         Navigator.push(
//           context,
//           MaterialPageRoute(
//             builder: (_) => EventDetailPage(
//               recordId: doc.id,
//               event: AttendanceEvent(
//                 type: type,
//                 time: time,
//                 id: doc.id,
//                 location: data['location'] as Map<String, dynamic>?,
//                 address: address,
//               ),
//             ),
//           ),
//         );
//       },
//     );
//   }

//   String _getWorkingDaysText(
//     List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
//   ) {
//     final Set<String> uniqueDays = {};

//     for (final doc in docs) {
//       final data = doc.data();
//       final timestamp =
//           (data['capturedAt'] as Timestamp?) ??
//           (data['createdAt'] as Timestamp?) ??
//           Timestamp.fromMillisecondsSinceEpoch(0);
//       final date = timestamp.toDate();
//       final dayKey = DateFormat('yyyy-MM-dd').format(date);
//       uniqueDays.add(dayKey);
//     }

//     final dayCount = uniqueDays.length;
//     return dayCount == 1 ? '1 day' : '$dayCount days';
//   }

//   String _initialsFrom(String nameOrEmail) {
//     final s = nameOrEmail.trim();
//     if (s.isEmpty) return '?';
//     final parts = s.split(' ');
//     if (parts.length >= 2) {
//       return (parts[0].isNotEmpty ? parts[0][0] : '').toUpperCase() +
//           (parts[1].isNotEmpty ? parts[1][0] : '').toUpperCase();
//     }
//     final local = s.contains('@') ? s.split('@').first : s;
//     return local.isNotEmpty ? local[0].toUpperCase() : '?';
//   }
// }

// class _Group {
//   final String id;
//   final String title;
//   final String? subtitle;
//   final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
//   Duration workingTime = Duration.zero;

//   _Group({required this.id, required this.title, required this.subtitle})
//     : docs = [];
// }

// class _QuickDateFilter {
//   final String label;
//   final DateTimeRange Function() getRange;

//   _QuickDateFilter(this.label, this.getRange);
// }

// class _SummaryItem extends StatelessWidget {
//   final IconData icon;
//   final String label;
//   final String value;
//   final Color color;

//   const _SummaryItem({
//     required this.icon,
//     required this.label,
//     required this.value,
//     required this.color,
//   });

//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.1),
//         borderRadius: BorderRadius.circular(8),
//         border: Border.all(color: color.withOpacity(0.2)),
//       ),
//       child: Column(
//         children: [
//           Icon(icon, color: color, size: 24),
//           const SizedBox(height: 8),
//           Text(
//             value,
//             style: TextStyle(
//               fontSize: 20,
//               fontWeight: FontWeight.bold,
//               color: color,
//             ),
//           ),
//           const SizedBox(height: 4),
//           Text(
//             label,
//             style: Theme.of(context).textTheme.bodySmall?.copyWith(
//               color: Theme.of(context).colorScheme.outline,
//             ),
//             textAlign: TextAlign.center,
//           ),
//         ],
//       ),
//     );
//   }
// }
