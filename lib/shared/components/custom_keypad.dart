import 'package:flutter/material.dart';
import '../design_tokens.dart';
import '../i18n.dart';

class CustomKeypad extends StatelessWidget {
  const CustomKeypad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    required this.onOk,
    required this.okEnabled,
    this.isLoading = false,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onOk;
  final bool okEnabled;
  final bool isLoading;

  /// Smallest key height and width (WCAG 2.5.5 / Material touch target).
  static const double minKeyExtent = 44;

  /// Smallest height for the four rows: each key keeps [minKeyExtent] plus
  /// its own padding. Give the keypad at least this much.
  static const double minHeight = 4 * (minKeyExtent + 2 * FFTokens.spacingSm);

  Widget _buildKey(
    BuildContext context,
    Widget child,
    VoidCallback? onTap, {
    Color? bgColor,
    String? semanticLabel,
  }) {
    final borderCol = bgColor != null
        ? Colors.transparent
        : Theme.of(context).colorScheme.outline;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingSm),
        child: Material(
          color: bgColor ?? Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
            side: BorderSide(color: borderCol),
          ),
          clipBehavior: Clip.antiAlias,
          child: Semantics(
            button: true,
            label: semanticLabel,
            excludeSemantics: semanticLabel != null,
            child: InkWell(
              onTap: isLoading ? null : onTap,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDigitKey(BuildContext context, int digit) {
    return _buildKey(
      context,
      Text(
        digit.toString(),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      () => onDigit(digit),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDigitKey(context, 1),
              _buildDigitKey(context, 2),
              _buildDigitKey(context, 3),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDigitKey(context, 4),
              _buildDigitKey(context, 5),
              _buildDigitKey(context, 6),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDigitKey(context, 7),
              _buildDigitKey(context, 8),
              _buildDigitKey(context, 9),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildKey(
                context,
                Icon(
                  Icons.backspace_outlined,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: FFTokens.iconLg,
                ),
                onDelete,
                semanticLabel: context.tr('a11y.delete'),
              ),
              _buildDigitKey(context, 0),
              _buildKey(
                context,
                isLoading
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      )
                    : Text(
                        'OK',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: okEnabled
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.38),
                            ),
                      ),
                okEnabled ? onOk : null,
                bgColor: okEnabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Lays out a PIN screen so the keypad always fits: [header] (titles, the
/// contact, help text) on top, then [pinned] (the PIN dots, an error), the
/// [keypad], and [footer] (links) at the bottom.
///
/// The keypad never gets less than [CustomKeypad.minHeight], so every key
/// stays at least 44x44 and on screen. When the screen is short (a small
/// phone, large text) the gaps tighten to [minGap] first, then [header]
/// shrinks and scrolls on its own; the dots, keypad and footer stay put.
/// Spare room grows the gaps back to [gaps], then the keypad up to
/// [maxKeypadHeight]; anything left is below the footer.
///
/// Needs a bounded height (a Scaffold body); see [PinPadLayout.fits].
class PinPadLayout extends StatelessWidget {
  const PinPadLayout({
    super.key,
    required this.header,
    this.pinned,
    required this.keypad,
    this.footer,
    this.gaps = const (24, 24, 16),
    this.minGap = FFTokens.spacingSm,
    this.maxKeypadHeight = double.infinity,
  });

  final Widget header;
  final Widget? pinned;
  final Widget keypad;
  final Widget? footer;

  /// Preferred gaps: header to [pinned], [pinned] to keypad, keypad to
  /// [footer].
  final (double, double, double) gaps;
  final double minGap;
  final double maxKeypadHeight;

  /// Whether [constraints] let this layout work (a bounded height).
  static bool fits(BoxConstraints constraints) => constraints.hasBoundedHeight;

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _PinPadDelegate(
        gaps: gaps,
        minGap: minGap,
        maxKeypad: maxKeypadHeight,
      ),
      children: [
        LayoutId(
          id: _PinPadSlot.header,
          child: SingleChildScrollView(
            key: const Key('pin-pad-header'),
            child: header,
          ),
        ),
        if (pinned != null) LayoutId(id: _PinPadSlot.pinned, child: pinned!),
        LayoutId(id: _PinPadSlot.keypad, child: keypad),
        if (footer != null) LayoutId(id: _PinPadSlot.footer, child: footer!),
      ],
    );
  }
}

enum _PinPadSlot { header, pinned, keypad, footer }

class _PinPadDelegate extends MultiChildLayoutDelegate {
  _PinPadDelegate({
    required this.gaps,
    required this.minGap,
    required this.maxKeypad,
  });

  final (double, double, double) gaps;
  final double minGap;
  final double maxKeypad;

  @override
  void performLayout(Size size) {
    final w = size.width;
    final full = BoxConstraints(minWidth: w, maxWidth: w);
    final hasPinned = hasChild(_PinPadSlot.pinned);
    final hasFooter = hasChild(_PinPadSlot.footer);
    final footerH = hasFooter
        ? layoutChild(_PinPadSlot.footer, full).height
        : 0.0;
    final pinnedH = hasPinned
        ? layoutChild(_PinPadSlot.pinned, full).height
        : 0.0;
    // Gaps in order down the screen: before the dots (when there are
    // any), before the keypad, before the footer (when there is one).
    final preferred = [if (hasPinned) gaps.$1, gaps.$2, if (hasFooter) gaps.$3];
    final lows = [for (final g in preferred) g < minGap ? g : minGap];
    final minGaps = lows.fold(0.0, (a, b) => a + b);
    const minKeypad = CustomKeypad.minHeight;
    final headerMax = (size.height - footerH - pinnedH - minKeypad - minGaps)
        .clamp(0.0, double.infinity);
    final headerH = layoutChild(
      _PinPadSlot.header,
      full.copyWith(maxHeight: headerMax),
    ).height;
    var spare = size.height - footerH - pinnedH - headerH - minKeypad - minGaps;
    if (spare < 0) spare = 0;
    // Gaps grow back first, each in proportion to what it lost.
    final lost = [
      for (var i = 0; i < preferred.length; i++) preferred[i] - lows[i],
    ];
    final totalLost = lost.fold(0.0, (a, b) => a + b);
    final give = spare < totalLost ? spare : totalLost;
    final g = [
      for (var i = 0; i < preferred.length; i++)
        lows[i] + (totalLost == 0 ? 0 : give * lost[i] / totalLost),
    ];
    spare -= give;
    final grow = maxKeypad - minKeypad;
    final keypadH = minKeypad + (spare < grow ? spare : grow);
    layoutChild(_PinPadSlot.keypad, BoxConstraints.tight(Size(w, keypadH)));

    var i = 0;
    var y = 0.0;
    positionChild(_PinPadSlot.header, Offset(0, y));
    y += headerH;
    if (hasPinned) {
      y += g[i++];
      positionChild(_PinPadSlot.pinned, Offset(0, y));
      y += pinnedH;
    }
    y += g[i++];
    positionChild(_PinPadSlot.keypad, Offset(0, y));
    y += keypadH;
    if (hasFooter) {
      y += g[i];
      positionChild(_PinPadSlot.footer, Offset(0, y));
    }
  }

  @override
  bool shouldRelayout(_PinPadDelegate old) =>
      old.gaps != gaps || old.minGap != minGap || old.maxKeypad != maxKeypad;
}
