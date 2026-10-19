import 'package:flutter/material.dart';

import '../../design_tokens.dart';
import '../../i18n.dart';

/// Card width for a rail: 156 on phones, 180 on tablets, 200 on wide screens,
/// and at least 180 from 160% text size so names and prices still fit.
double shopRailCardWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  final base = width >= 1024
      ? 200.0
      : width >= 600
      ? 180.0
      : 156.0;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return scale >= 1.6 && base < 180 ? 180 : base;
}

/// 48×48 targets everywhere, whatever density the platform picks (desktop
/// and web default to a compact 40px).
const _target = Size(48, 48);

ButtonStyle shopIconButtonStyle() => IconButton.styleFrom(
  minimumSize: _target,
  tapTargetSize: MaterialTapTargetSize.padded,
  visualDensity: VisualDensity.standard,
);

/// A titled home section: header (title, "Why am I seeing this?", "View all"
/// and, on wide screens, previous/next) over a horizontally scrolling row of
/// cards. The row runs edge to edge with [inset] padding, so the next card
/// peeks; it is as tall as its tallest card, so nothing is clipped.
class ShopProductRail extends StatefulWidget {
  const ShopProductRail({
    super.key,
    required this.sectionKey,
    required this.title,
    required this.children,
    this.inset = 16,
    this.onWhy,
    this.onViewAll,
    this.onShown,
  });

  final String sectionKey;
  final String title;
  final List<Widget> children;

  /// The page gutter: header text and the first card line up with it.
  final double inset;
  final VoidCallback? onWhy;
  final VoidCallback? onViewAll;

  /// Called once, when the section is first built (it is near the screen:
  /// the page builds lazily).
  final VoidCallback? onShown;

  @override
  State<ShopProductRail> createState() => _ShopProductRailState();
}

class _ShopProductRailState extends State<ShopProductRail> {
  final _scroll = ScrollController();
  bool _canBack = false;
  bool _canForward = false;

  @override
  void initState() {
    super.initState();
    widget.onShown?.call();
    _scroll.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!mounted || !_scroll.hasClients) return;
    final p = _scroll.position;
    final back = p.pixels > p.minScrollExtent + 1;
    final forward = p.pixels < p.maxScrollExtent - 1;
    if (back != _canBack || forward != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = forward;
      });
    }
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final target = (p.pixels + direction * p.viewportDimension * 0.8).clamp(
      p.minScrollExtent,
      p.maxScrollExtent,
    );
    if (MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(target);
    } else {
      _scroll.animateTo(
        target,
        duration: FFTokens.motionSlow,
        curve: FFTokens.motionEmphasized,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final wide = MediaQuery.sizeOf(context).width >= 1024;
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: widget.inset),
            child: _header(context, showArrows: wide),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          SingleChildScrollView(
            key: Key('shop-home-rail-${widget.sectionKey}'),
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: widget.inset),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.children.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  widget.children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, {required bool showArrows}) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w700,
    );
    final viewAllLabel = context.tr('shop.home.viewAll');
    final arrows = showArrows && (_canBack || _canForward);
    final controls = <Widget>[
      if (widget.onWhy != null)
        IconButton(
          key: Key('shop-home-why-${widget.sectionKey}'),
          style: shopIconButtonStyle(),
          tooltip: context.tr('shop.why.a11y'),
          icon: const Icon(Icons.info_outline),
          onPressed: widget.onWhy,
        ),
      if (widget.onViewAll != null)
        Semantics(
          button: true,
          excludeSemantics: true,
          label: context
              .tr('shop.a11y.viewAll')
              .replaceAll('{section}', widget.title),
          onTap: widget.onViewAll,
          child: TextButton.icon(
            key: Key('shop-home-viewall-${widget.sectionKey}'),
            style: TextButton.styleFrom(
              minimumSize: _target,
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
            onPressed: widget.onViewAll,
            iconAlignment: IconAlignment.end,
            icon: const Icon(Icons.arrow_forward, size: 18),
            label: Text(viewAllLabel),
          ),
        ),
      if (arrows) ...[
        IconButton(
          key: Key('shop-home-prev-${widget.sectionKey}'),
          style: shopIconButtonStyle(),
          tooltip: context
              .tr('shop.a11y.showPrevious')
              .replaceAll('{section}', widget.title),
          icon: const Icon(Icons.chevron_left),
          onPressed: _canBack ? () => _page(-1) : null,
        ),
        IconButton(
          key: Key('shop-home-next-${widget.sectionKey}'),
          style: shopIconButtonStyle(),
          tooltip: context
              .tr('shop.a11y.showMore')
              .replaceAll('{section}', widget.title),
          icon: const Icon(Icons.chevron_right),
          onPressed: _canForward ? () => _page(1) : null,
        ),
      ],
    ];
    final title = Semantics(
      header: true,
      child: Text(
        widget.title,
        key: Key('shop-home-title-${widget.sectionKey}'),
        style: titleStyle,
      ),
    );
    if (controls.isEmpty) {
      return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Align(alignment: Alignment.centerLeft, child: title),
      );
    }
    final trailing = Row(mainAxisSize: MainAxisSize.min, children: controls);
    return LayoutBuilder(
      builder: (context, constraints) {
        // Measure: the controls share the title's line only when both fit.
        final scaler = MediaQuery.textScalerOf(context);
        final direction = Directionality.of(context);
        double measure(String text, TextStyle? style) => (TextPainter(
          text: TextSpan(text: text, style: style),
          textScaler: scaler,
          textDirection: direction,
          maxLines: 1,
        )..layout()).width;
        final titleWidth = measure(widget.title, titleStyle);
        var controlsWidth = 0.0;
        if (widget.onWhy != null) controlsWidth += 48;
        if (widget.onViewAll != null) {
          // Label + gap + 18px icon + the button's 12px side padding.
          controlsWidth +=
              measure(viewAllLabel, theme.textTheme.labelLarge) + 8 + 18 + 24;
        }
        if (arrows) controlsWidth += 96;
        final fits =
            titleWidth + FFTokens.spacingSm + controlsWidth <=
            constraints.maxWidth;
        if (fits) {
          return Row(
            children: [
              Expanded(child: title),
              trailing,
            ],
          );
        }
        // Too long (Swahili, large text): controls drop to line 2, right.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title,
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: trailing,
              ),
            ),
          ],
        );
      },
    );
  }
}
