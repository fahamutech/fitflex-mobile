import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Tab-style toggle group — matches portal's Segmented component.
class FFSegmented extends StatelessWidget {
  const FFSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<(String id, String label)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(FFTokens.spacingXs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final selected = opt.$1 == value;
          return Flexible(
            child: GestureDetector(
              onTap: () => onChanged(opt.$1),
              child: AnimatedContainer(
                duration: FFTokens.motionFast,
                curve: FFTokens.motionCurve,
                padding: const EdgeInsets.symmetric(
                  horizontal: FFTokens.spacingSm,
                  vertical: FFTokens.spacingXs + 2,
                ),
                // Same tint as the selected bottom-nav tab. The track is the
                // card colour, so a card-coloured pill wouldn't show.
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.18)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                ),
                // Shrink a long label to one line rather than breaking it
                // mid-word when options share a narrow row.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    opt.$2,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected
                          ? theme.colorScheme.onSurface
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : null,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
