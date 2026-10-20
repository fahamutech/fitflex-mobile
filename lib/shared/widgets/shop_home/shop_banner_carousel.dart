import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../i18n.dart';
import '../../shop_home.dart';
import 'shop_focus_ring.dart';
import 'shop_product_rail.dart' show shopIconButtonStyle;

/// The Shop home's hero carousel (Phase 2 S1; docs/design/shop-home.md §6.3,
/// §11 and shop-home-phase2.md §5.1): the live banners for this role, in the
/// server's order, each drawn with [FFPhotoHero] over its network photo.
///
/// No auto-advance. Swipe, the Previous / Next buttons (48dp) or a screen
/// reader's increase / decrease gestures change the slide; the page dots
/// show where you are (pointer only: the slide's label says "Banner 1 of 3").
/// A vendor's banner shows "From {vendor}" top-left; it is never labelled
/// "Sponsored". With reduced motion the slides change without a fade.
class ShopBannerCarousel extends StatefulWidget {
  const ShopBannerCarousel({
    super.key,
    required this.banners,
    required this.onOpen,
  });

  final List<ShopBanner> banners;

  /// The slide's button was tapped: open its target.
  final ValueChanged<ShopBanner> onOpen;

  @override
  State<ShopBannerCarousel> createState() => _ShopBannerCarouselState();
}

class _ShopBannerCarouselState extends State<ShopBannerCarousel> {
  int _index = 0;

  /// Dots up to this many slides; past it a "2 / 9" counter.
  static const _maxDots = 6;

  int get _count => widget.banners.length;

  @override
  void didUpdateWidget(ShopBannerCarousel old) {
    super.didUpdateWidget(old);
    if (_index >= _count) _index = math.max(0, _count - 1);
  }

  void _go(int index) {
    if (_count < 2) return;
    setState(() => _index = (index + _count) % _count);
  }

  void _next() => _go(_index + 1);
  void _previous() => _go(_index - 1);

  String _text(ShopText? text, String lang) => text?.of(lang).trim() ?? '';

  String _ctaLabel(BuildContext context, ShopBanner banner, String lang) {
    final own = _text(banner.ctaLabel, lang);
    if (own.isNotEmpty) return own;
    return context.tr(switch (banner.target.type) {
      'product' => 'shop.banner.cta.viewProduct',
      'vendor_store' => 'shop.banner.cta.visitStore',
      _ => 'shop.banner.cta.shopNow',
    });
  }

  String _fromLabel(BuildContext context, ShopBanner banner) => context
      .tr('shop.banner.from')
      .replaceAll('{vendor}', banner.vendorName!.trim());

  /// "From {vendor}. {headline}. {subline}. Banner {n} of {total}".
  String _slideLabel(BuildContext context, ShopBanner banner, int i) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final headline = [
      _text(banner.headlineLead, lang),
      _text(banner.headlineAccent, lang),
    ].where((s) => s.isNotEmpty).join(' ');
    return [
      if (banner.fromVendor) _fromLabel(context, banner),
      headline,
      _text(banner.subline, lang),
      context
          .tr('shop.home.bannerOf')
          .replaceAll('{n}', '${i + 1}')
          .replaceAll('{total}', '$_count'),
    ].where((s) => s.isNotEmpty).join('. ');
  }

  /// Room kept clear above the text for the "From" chip (two lines at the
  /// current text scale, plus its 16 inset and a gap).
  double _chipReserve(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return FFTokens.spacingMd +
        2 * scaler.scale(16) +
        2 * FFTokens.spacing2xs +
        FFTokens.spacingSm;
  }

  Widget _chip(BuildContext context, ShopBanner banner, bool active) =>
      ExcludeSemantics(
        child: FFBadge(
          key: active ? Key('shop-banner-from-${banner.id}') : null,
          label: _fromLabel(context, banner),
          tone: FFBadgeTone.onPhoto,
          // Two lines at most (a long store name at 130% on a 375 phone); the
          // slide label still reads the whole name.
          maxLines: 2,
          wrap: true,
        ),
      );

  /// One slide. Only the [active] one has keys, a working button and
  /// semantics; the others are laid out invisibly to reserve the height of
  /// the tallest, so changing slides never moves the page.
  Widget _slide(
    BuildContext context,
    ShopBanner banner,
    int i,
    double width, {
    required bool active,
  }) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final wide = width >= 840;
    final lead = _text(banner.headlineLead, lang);
    final accent = _text(banner.headlineAccent, lang);
    final subline = _text(banner.subline, lang);
    final cta = FFButton(
      key: active ? Key('shop-banner-cta-${banner.id}') : null,
      label: _ctaLabel(context, banner, lang),
      trailingIcon: Icons.arrow_forward,
      visualDensity: VisualDensity.standard,
      maxLines: 2,
      onPressed: active ? () => widget.onOpen(banner) : null,
    );
    final chip = banner.fromVendor ? _chip(context, banner, active) : null;
    final hero = FFPhotoHero(
      networkImage: FFHeroNetworkImage(
        banner.image.pick(width, dpr) ?? '',
        focal: Alignment(banner.image.focalX, banner.image.focalY),
      ),
      variant: wide ? FFHeroVariant.panel : FFHeroVariant.band,
      rounded: wide,
      // Phone about 16:10 (min 200); 3:1 up to 360 on wide screens. Text at
      // large scales grows it.
      minHeight: wide ? math.min(width / 3, 360) : math.max(200, width / 1.6),
      topInset: !wide && chip != null ? _chipReserve(context) : 0,
      headlineLead: lead.isEmpty ? null : lead,
      headlineAccent: accent.isEmpty ? null : accent,
      subline: subline.isEmpty ? null : subline,
      logo: wide ? chip : null,
      excludeHeadingSemantics: true,
      actions: [cta],
    );
    final body = chip == null || wide
        ? hero
        : Stack(
            children: [
              hero,
              Positioned(
                left: FFTokens.spacingMd,
                top: FFTokens.spacingMd,
                right: FFTokens.spacingMd,
                child: Align(alignment: Alignment.centerLeft, child: chip),
              ),
            ],
          );
    if (!active) return body;
    final many = _count > 1;
    return Semantics(
      key: Key('shop-banner-slide-$i'),
      container: true,
      label: _slideLabel(context, banner, i),
      onIncrease: many ? _next : null,
      onDecrease: many ? _previous : null,
      child: body,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    final instant = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final slides = Stack(
          children: [
            // The tallest slide sets the height (invisible, not read).
            for (var i = 0; i < _count; i++)
              Visibility(
                visible: false,
                maintainSize: true,
                maintainAnimation: true,
                maintainState: true,
                child: _slide(
                  context,
                  widget.banners[i],
                  i,
                  width,
                  active: false,
                ),
              ),
            Positioned.fill(
              child: instant
                  ? _slide(
                      context,
                      widget.banners[_index],
                      _index,
                      width,
                      active: true,
                    )
                  : AnimatedSwitcher(
                      duration: instant
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeOut,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [...previous, ?current],
                      ),
                      child: KeyedSubtree(
                        key: ValueKey('${widget.banners[_index].id}#$_index'),
                        child: _slide(
                          context,
                          widget.banners[_index],
                          _index,
                          width,
                          active: true,
                        ),
                      ),
                    ),
            ),
          ],
        );
        return Column(
          key: const Key('shop-banners'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_count > 1)
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragEnd: (details) {
                  final v = details.primaryVelocity ?? 0;
                  if (v < -200) _next();
                  if (v > 200) _previous();
                },
                child: slides,
              )
            else
              slides,
            if (_count > 1) _controls(context),
          ],
        );
      },
    );
  }

  /// Previous, the dots (or a counter), Next. Under the photo, on the page
  /// ground: Volt only in the dark theme (the theme's primary colour).
  Widget _controls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Inactive dots at >= 3:1 against the page: slate-500 / slate-400.
    final inactive = dark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    Widget arrow(String key, IconData icon, String label, VoidCallback onTap) =>
        ShopFocusRing(
          shape: BoxShape.circle,
          builder: (node) => IconButton(
            key: Key(key),
            focusNode: node,
            style: shopIconButtonStyle(),
            tooltip: context.tr(label),
            onPressed: onTap,
            icon: Icon(icon),
          ),
        );
    final Widget position = _count <= _maxDots
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < _count; i++)
                InkResponse(
                  key: Key('shop-banner-dot-$i'),
                  canRequestFocus: false,
                  radius: 22,
                  onTap: () => _go(i),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                      child: AnimatedContainer(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : FFTokens.motionMedium,
                        width: i == _index ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? scheme.primary : inactive,
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusFull,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingSm),
            child: Text(
              '${_index + 1} / $_count',
              key: const Key('shop-banner-counter'),
              style: Theme.of(context).textTheme.labelLarge,
            ),
          );
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          arrow(
            'shop-banner-prev',
            Icons.chevron_left,
            'shop.home.prevBanner',
            _previous,
          ),
          // The slide's own label says where you are.
          Flexible(child: ExcludeSemantics(child: position)),
          arrow(
            'shop-banner-next',
            Icons.chevron_right,
            'shop.home.nextBanner',
            _next,
          ),
        ],
      ),
    );
  }
}
