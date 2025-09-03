import 'package:flutter/material.dart';

class OrgEmployeeFiltersInline extends StatelessWidget {
  final TextEditingController orgCtrl;
  final TextEditingController employeeIdCtrl;
  final VoidCallback? onApply;
  const OrgEmployeeFiltersInline({
    super.key,
    required this.orgCtrl,
    required this.employeeIdCtrl,
    this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: orgCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Org ID',
                    hintText: 'e.g. ORG001',
                    prefixIcon: Icon(Icons.apartment_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: employeeIdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Employee ID',
                    hintText: 'e.g. EMP001',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: onApply,
              icon: const Icon(Icons.search),
              label: const Text('Apply'),
            ),
          ),
        ],
      ),
    );
  }
}
