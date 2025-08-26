import 'package:cloud_firestore/cloud_firestore.dart' show QueryDocumentSnapshot;
import 'package:flutter/material.dart';

class GroupInfo {
  final String id;          // email (lowercased) or uid
  final String title;       // display name or email local-part
  final String? subtitle;   // full email
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  Duration workingTime;
  GroupInfo({required this.id, required this.title, required this.subtitle, required this.docs, required this.workingTime});
}

class QuickDateFilter {
  final String label;
  final DateTimeRange Function() getRange;
  QuickDateFilter(this.label, this.getRange);
}

// Default quick filters
final List<QuickDateFilter> quickFiltersDefault = [
  QuickDateFilter('Today', () {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
  }),
  QuickDateFilter('Yesterday', () {
    final y = DateTime.now().subtract(const Duration(days: 1));
    return DateTimeRange(start: DateTime(y.year, y.month, y.day), end: DateTime(y.year, y.month, y.day, 23, 59, 59));
  }),
  QuickDateFilter('This Week', () {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    return DateTimeRange(start: DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day), end: now);
  }),
  QuickDateFilter('This Month', () {
    final now = DateTime.now();
    return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
  }),
];
