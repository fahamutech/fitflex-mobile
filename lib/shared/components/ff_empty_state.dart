import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Empty state placeholder — matches portal's EmptyState component.
class FFEmptyState extends StatelessWidget {
  const FFEmptyState({super.key, required this.title, this.body, this.action});

  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: BoxDecoration(
        color: FFTokens.bgSecondary,
        border: Border.all(
          color: FFTokens.borderPrimary,
          style: BorderStyle.solid,
        ),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgSecondary,
            ),
          ),
          if (body != null) ...[
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                body!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: FFTokens.fgQuaternary,
                ),
              ),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}
