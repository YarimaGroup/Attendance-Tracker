import 'package:flutter/material.dart';

class PunchButtons extends StatelessWidget {
  final bool busy;
  final VoidCallback onIn;
  final VoidCallback onOut;
  const PunchButtons({
    super.key,
    required this.busy,
    required this.onIn,
    required this.onOut,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AnimatedScale(
            duration: const Duration(milliseconds: 180),
            scale: busy ? 0.98 : 1.0,
            child: FilledButton.icon(
              onPressed: busy ? null : onIn,
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
            scale: busy ? 0.98 : 1.0,
            child: OutlinedButton.icon(
              onPressed: busy ? null : onOut,
              icon: const Icon(Icons.logout),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Clock Out'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
