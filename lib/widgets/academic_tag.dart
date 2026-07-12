import 'package:flutter/material.dart';

class AcademicTag extends StatelessWidget {
  final String label;
  final bool emphasized;
  final IconData? icon;

  const AcademicTag({
    super.key,
    required this.label,
    this.emphasized = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: emphasized ? const Color(0xFFD4E3FF) : const Color(0xFFECEEF0),
        border: Border.all(
          color: emphasized ? const Color(0xFF68ABFF) : const Color(0xFFC4C6CD),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: const Color(0xFF1A2B3C)),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF1A2B3C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
