import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// The search-focus rule under a section band (photo-hero spec §32.1): when
/// the search field gains focus and its top edge is lower than 40% of the
/// visible viewport (the viewport shrinks when the keyboard opens), the page
/// scrolls so the field's top sits 8px below the viewport's top edge (the
/// app bar), 300ms ease-out, instant under reduced motion. The band simply
/// scrolls away; nothing scrolls back on unfocus.
///
/// [builder] gets the focus node to give the field. With [enabled] false
/// (flag off) the field is built exactly as before, with no node.
class FFSearchFocusScroll extends StatefulWidget {
  const FFSearchFocusScroll({
    super.key,
    required this.enabled,
    required this.builder,
  });

  final bool enabled;
  final Widget Function(BuildContext context, FocusNode? focusNode) builder;

  @override
  State<FFSearchFocusScroll> createState() => _FFSearchFocusScrollState();
}

class _FFSearchFocusScrollState extends State<FFSearchFocusScroll> {
  final FocusNode _node = FocusNode(debugLabel: 'search-focus-scroll');
  double _inset = 0;
  Timer? _later;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocus);
  }

  @override
  void dispose() {
    _later?.cancel();
    _node
      ..removeListener(_onFocus)
      ..dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_node.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _scroll());
    // Again once the keyboard has had time to open and shrink the viewport.
    _later?.cancel();
    _later = Timer(const Duration(milliseconds: 350), _scroll);
  }

  void _scroll() {
    if (!mounted || !_node.hasFocus) return;
    final box = context.findRenderObject();
    final position = Scrollable.maybeOf(context)?.position;
    if (box is! RenderBox || !box.attached || position == null) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null || !position.hasViewportDimension) return;
    // The scroll offset that puts the field's top at the viewport's top.
    final reveal = viewport.getOffsetToReveal(box, 0).offset;
    final onScreen = reveal - position.pixels;
    if (onScreen <= 0.4 * position.viewportDimension) return;
    final target = (reveal - 8).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      position.jumpTo(target);
    } else {
      position.animateTo(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.builder(context, null);
    // The keyboard opening (or closing) changes the visible viewport.
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    if (inset != _inset) {
      _inset = inset;
      if (_node.hasFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _scroll());
      }
    }
    return widget.builder(context, _node);
  }
}
