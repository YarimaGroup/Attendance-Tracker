import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart'
    show QueryDocumentSnapshot, Timestamp;
import '../../panel/utils.dart';

class RecordTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final DateFormat dfDate;
  final DateFormat dfTime;
  final bool isGrouped;
  final VoidCallback? onTap;
  const RecordTile({
    super.key,
    required this.doc,
    required this.dfDate,
    required this.dfTime,
    this.isGrouped = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final String type = (data['type'] as String?) ?? '?';
    final ts = data['capturedAt'] as Timestamp?;
    final time =
        ts?.toDate() ??
        (data['createdAt'] as Timestamp?)?.toDate() ??
        DateTime.fromMillisecondsSinceEpoch(0);

    final name = primaryName(data);
    final email = emailOf(data);
    final address = data['address'] as String?;

    final thumb = decodeThumb(data['thumb']);

    final color = type == 'IN' ? Colors.green : Colors.orange;
    final icon = type == 'IN' ? Icons.login : Icons.logout;

    return ListTile(
      contentPadding: EdgeInsets.all(isGrouped ? 12 : 16),
      leading: thumb == null
          ? CircleAvatar(
              backgroundColor: color.withOpacity(0.15),
              child: Icon(icon, color: color, size: 20),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  border: Border.all(color: color.withOpacity(0.3), width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Image.memory(thumb, fit: BoxFit.cover),
              ),
            ),
      title: Row(
        children: [
          if (!isGrouped)
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (!isGrouped) const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(
                  'Clock $type',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (isGrouped) const Spacer(),
          if (isGrouped)
            Text(
              dfTime.format(time),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                Icons.schedule,
                size: 14,
                color: Theme.of(context).colorScheme.outline,
              ),
              const SizedBox(width: 4),
              Text('${dfDate.format(time)} • ${dfTime.format(time)} IST'),
              if (email != null && !isGrouped) ...[
                const SizedBox(width: 8),
                const Text('•'),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    email,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (address != null && address.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              children: [
                Icon(
                  Icons.location_on,
                  size: 14,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    address,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      trailing: Icon(
        Icons.arrow_forward_ios,
        size: 16,
        color: Theme.of(context).colorScheme.outline,
      ),
      onTap: onTap,
    );
  }
}
