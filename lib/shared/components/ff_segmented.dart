import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Tab-style toggle group — matches portal's Segmented component.
///
/// Each option is at least 48dp tall to tap. Long labels wrap onto a second
/// line instead of shrinking, so they stay readable at large text sizes.
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
      // Vertical padding lives on each option's tap area, so the whole track
      // height is tappable.
      padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingXs),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: options.map((opt) {
            final selected = opt.$1 == value;
            return Flexible(
              child: Semantics(
                button: true,
                selected: selected,
                inMutuallyExclusiveGroup: true,
                label: opt.$2,
                excludeSemantics: true,
                onTap: () => onChanged(opt.$1),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () => onChanged(opt.$1),
                      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: FFTokens.spacingXs,
                        ),
                        child: AnimatedContainer(
                          duration: FFTokens.motionFast,
                          curve: FFTokens.motionCurve,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                            horizontal: FFTokens.spacingSm,
                            vertical: FFTokens.spacingSm + 2,
                          ),
                          // Same tint as the selected bottom-nav tab. The
                          // track is the card colour, so a card-coloured pill
                          // wouldn't show.
                          decoration: BoxDecoration(
                            color: selected
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.18,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(
                              FFTokens.radiusMd,
                            ),
                          ),
                          child: Text(
                            opt.$2,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
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
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
