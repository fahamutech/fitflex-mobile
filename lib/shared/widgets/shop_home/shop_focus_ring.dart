import 'package:flutter/material.dart';

import '../../design_tokens.dart';

/// A visible keyboard focus outline (AC-45) for the shop's own controls.
///
/// The ring follows the control's own [FocusNode]: it is drawn only while
/// that node has primary focus and the app is in keyboard (traditional)
/// highlight mode, so exactly one ring is ever visible and none is left
/// behind after a pointer tap or when a sheet closes. Colours are the design
/// system's focus-ring tokens (slate-900 on light, slate-100 on dark), 2px,
/// outside the control so they sit on the page ground (>= 3:1).
class ShopFocusRing extends StatefulWidget {
  const ShopFocusRing({
    super.key,
    required this.builder,
    this.shape = BoxShape.rectangle,
    this.radius = FFTokens.radiusMd,
    this.color,
  });

  /// Builds the control with [node] as its focus node.
  final Widget Function(FocusNode node) builder;
  final BoxShape shape;
  final double radius;

  /// The ring's colour instead of the theme's (white on a photo).
  final Color? color;

  @override
  State<ShopFocusRing> createState() => _ShopFocusRingState();
}

class _ShopFocusRingState extends State<ShopFocusRing> {
  final FocusNode _node = FocusNode();
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_update);
    FocusManager.instance.addHighlightModeListener(_onMode);
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_onMode);
    _node.removeListener(_update);
    _node.dispose();
    super.dispose();
  }

  void _onMode(FocusHighlightMode _) => _update();

  void _update() {
    final visible =
        _node.hasPrimaryFocus &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (mounted && visible != _visible) setState(() => _visible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      key: _visible ? const Key('shop-home-focus-ring') : null,
      position: DecorationPosition.foreground,
      decoration: _visible
          ? BoxDecoration(
              shape: widget.shape,
              borderRadius: widget.shape == BoxShape.rectangle
                  ? BorderRadius.circular(widget.radius)
                  : null,
              border: Border.all(
                color:
                    widget.color ?? (dark ? ffFocusRingDark : ffFocusRingLight),
                width: 2,
                strokeAlign: BorderSide.strokeAlignOutside,
              ),
            )
          : const BoxDecoration(),
      child: widget.builder(_node),
    );
  }
}
