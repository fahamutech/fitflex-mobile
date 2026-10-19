import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';

/// One option in a single-choice list (language, account type).
///
/// Behaves as a radio button: it is reachable with Tab, Space or Enter
/// selects it, and assistive tech hears its label, that it belongs to a
/// group, and whether it is selected. Keyboard focus draws the V2 2px ring
/// outside the tile.
class FFChoiceTile extends StatefulWidget {
  const FFChoiceTile({
    super.key,
    required this.title,
    required this.selected,
    required this.onSelected,
    this.subtitle,
    this.leading,
    this.minHeight = 64,
  });

  final String title;
  final String? subtitle;

  /// Optional icon (or other decoration) before the text. Not announced.
  final Widget? leading;
  final bool selected;
  final VoidCallback onSelected;
  final double minHeight;

  @override
  State<FFChoiceTile> createState() => _FFChoiceTileState();
}

class _FFChoiceTileState extends State<FFChoiceTile> {
  bool _focused = false;

  static const _shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
  };

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(
      onInvoke: (_) {
        widget.onSelected();
        return null;
      },
    ),
    ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
      onInvoke: (_) {
        widget.onSelected();
        return null;
      },
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final ring = dark ? ffFocusRingDark : ffFocusRingLight;
    final label = widget.subtitle == null
        ? widget.title
        : '${widget.title}. ${widget.subtitle}';

    final tile = AnimatedContainer(
      duration: FFTokens.motionMedium,
      curve: FFTokens.motionCurve,
      constraints: BoxConstraints(minHeight: widget.minHeight),
      padding: const EdgeInsets.symmetric(
        horizontal: FFTokens.spacingLg,
        vertical: FFTokens.spacingMd,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        border: Border.all(
          color: widget.selected ? scheme.primary : scheme.outline,
          width: widget.selected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: FFTokens.spacingMd),
          ],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title, style: theme.textTheme.titleMedium),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(widget.subtitle!, style: theme.textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: FFTokens.spacingMd),
          FFRadioDot(selected: widget.selected),
        ],
      ),
    );

    return Semantics(
      container: true,
      button: true,
      inMutuallyExclusiveGroup: true,
      checked: widget.selected,
      label: label,
      onTap: widget.onSelected,
      child: FocusableActionDetector(
        shortcuts: _shortcuts,
        actions: _actions,
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        child: GestureDetector(
          onTap: widget.onSelected,
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          child: ExcludeSemantics(
            child: DecoratedBox(
              key: const Key('ff-choice-focus-ring'),
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                border: _focused
                    ? Border.all(
                        color: ring,
                        width: 2,
                        strokeAlign: BorderSide.strokeAlignOutside,
                      )
                    : null,
              ),
              child: tile,
            ),
          ),
        ),
      ),
    );
  }
}

/// The round selected / not-selected marker used by [FFChoiceTile].
class FFRadioDot extends StatelessWidget {
  const FFRadioDot({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: FFTokens.spacingLg,
      height: FFTokens.spacingLg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? scheme.primary : null,
        border: Border.all(
          color: selected ? scheme.primary : scheme.outline,
          width: 2,
        ),
      ),
      child: selected
          ? Center(
              child: CircleAvatar(radius: 5, backgroundColor: scheme.onPrimary),
            )
          : null,
    );
  }
}
