import 'package:attendance_punch/admin/panel/model.dart';
import 'package:flutter/material.dart';


class AdminFilterPanel extends StatelessWidget {
  final String rangeLabel;
  final VoidCallback onPickRange;
  final TextEditingController emailCtrl;
  final List<QuickDateFilter> quickFilters;
  final void Function(QuickDateFilter) onQuickFilterTap;
  final bool groupByUser;
  final ValueChanged<bool> onGroupToggle;
  final VoidCallback? onApply;
  final bool loading;

  const AdminFilterPanel({
    super.key,
    required this.rangeLabel,
    required this.onPickRange,
    required this.emailCtrl,
    required this.quickFilters,
    required this.onQuickFilterTap,
    required this.groupByUser,
    required this.onGroupToggle,
    required this.onApply,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Quick Filters', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quickFilters
              .map((f) => FilterChip(label: Text(f.label), onSelected: (_) => onQuickFilterTap(f)))
              .toList(),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
            flex: 2,
            child: OutlinedButton.icon(onPressed: onPickRange, icon: const Icon(Icons.date_range), label: Text(rangeLabel)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: TextField(
              controller: emailCtrl,
              decoration: InputDecoration(
                labelText: 'Filter by email (exact)',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                suffixIcon: emailCtrl.text.isNotEmpty
                    ? IconButton(onPressed: () { emailCtrl.clear(); onApply?.call(); }, icon: const Icon(Icons.clear))
                    : null,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onApply?.call(),
            ),
          ),
        ]),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Text('Group by user'),
            Switch.adaptive(value: groupByUser, onChanged: onGroupToggle),
          ]),
          FilledButton.icon(
            onPressed: loading ? null : onApply,
            icon: loading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.search),
            label: Text(loading ? 'Searching…' : 'Apply Filters'),
          ),
        ]),
      ]),
    );
  }
}
