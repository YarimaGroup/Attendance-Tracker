import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PickedEmployee {
  final String id;
  final String name;
  final String orgId; // NEW: carry org back as well
  const PickedEmployee(this.id, this.name, this.orgId);
}

Future<PickedEmployee?> showEmployeePickerSheet(
  BuildContext context, {
  String? orgId, // <-- now nullable
}) async {
  String? chosenOrg = orgId;

  // Step 1: Choose org if not provided
  if (chosenOrg == null) {
    chosenOrg = await _pickOrg(context);
    if (chosenOrg == null) return null; // cancelled
  }

  // Step 2: Choose employee within that org
  final emp = await _pickEmployee(context, chosenOrg);
  return emp;
}

Future<String?> _pickOrg(BuildContext context) async {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.75,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select Organization',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FirebaseFirestore.instance
                    .collection('orgs')
                    .where('isActive', isEqualTo: true)
                    .orderBy('nameLower')
                    .limit(100)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snap.hasData || snap.data!.docs.isEmpty) {
                    return const Center(child: Text('No active organizations'));
                  }
                  final docs = snap.data!.docs;
                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final d = docs[i];
                      final name = (d.data()['name'] as String?) ?? d.id;
                      return ListTile(
                        leading: const Icon(Icons.apartment_outlined),
                        title: Text(name),
                        subtitle: Text(d.id), // show generated orgId
                        onTap: () => Navigator.pop(context, d.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    },
  );
}

Future<PickedEmployee?> _pickEmployee(
  BuildContext context,
  String orgId,
) async {
  final searchCtrl = TextEditingController();

  return showModalBottomSheet<PickedEmployee>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.apartment_outlined, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Org: $orgId',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: searchCtrl,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search employee…',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => (ctx as Element).markNeedsBuild(),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _employeeStream(orgId, searchCtrl.text),
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snap.hasData || snap.data!.docs.isEmpty) {
                      return const Center(child: Text('No active employees'));
                    }
                    final docs = snap.data!.docs;
                    return ListView.separated(
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final d = docs[i];
                        final name = (d.data()['name'] as String?) ?? d.id;
                        return ListTile(
                          leading: const CircleAvatar(
                            child: Icon(Icons.person),
                          ),
                          title: Text(name),
                          subtitle: Text(d.id), // employeeId
                          onTap: () => Navigator.pop(
                            context,
                            PickedEmployee(d.id, name, orgId),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Stream<QuerySnapshot<Map<String, dynamic>>> _employeeStream(
  String orgId,
  String query,
) {
  final base = FirebaseFirestore.instance
      .collection('orgs')
      .doc(orgId)
      .collection('employees')
      .where('isActive', isEqualTo: true);

  if (query.trim().isEmpty) return base.limit(50).snapshots();

  // Prefix search by nameLower if you maintain it
  return base
      .orderBy('nameLower')
      .startAt([query.toLowerCase()])
      .endAt(['${query.toLowerCase()}\uf8ff'])
      .limit(50)
      .snapshots();
}
