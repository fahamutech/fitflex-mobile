import 'package:flutter/material.dart';
import '../design_tokens.dart';
import 'ff_card.dart';

/// Tappable list tile in a card — common pattern throughout the app.
class FFActionTile extends StatelessWidget {
  const FFActionTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: FFTokens.bgSecondary,
                border: Border.all(color: FFTokens.borderSecondary),
                borderRadius: BorderRadius.circular(FFTokens.radiusLg),
              ),
              child: Icon(icon, color: FFTokens.fgBrand, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: FFTokens.fgPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: FFTokens.fgQuaternary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                const Icon(
                  Icons.chevron_right,
                  color: FFTokens.fgDisabled,
                  size: 20,
                ),
          ],
        ),
      ),
    );
  }
}
