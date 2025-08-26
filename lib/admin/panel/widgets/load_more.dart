import 'package:flutter/material.dart';

class LoadMore extends StatelessWidget {
  final bool hasMore; final bool loading; final VoidCallback onLoadMore; const LoadMore({super.key, required this.hasMore, required this.loading, required this.onLoadMore});
  @override
  Widget build(BuildContext context) {
    if (!hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.check_circle_outline, color: Theme.of(context).colorScheme.outline), const SizedBox(width: 8),
          Text('All records loaded', style: TextStyle(color: Theme.of(context).colorScheme.outline)),
        ])),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: loading ? null : onLoadMore,
          icon: loading ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.expand_more),
          label: Text(loading ? 'Loading more…' : 'Load more records'),
        ),
      ),
    );
  }
}