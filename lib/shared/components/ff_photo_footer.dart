import 'dart:convert';

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../i18n.dart';
import 'ff_button.dart';
import 'ff_photo_hero.dart';

/// The footer pool, in table order (photo-hero spec §34.1).
const footerPhotoPool = [
  FFHeroPhoto.footerWarmGym,
  FFHeroPhoto.footerBoxing,
  FFHeroPhoto.footerWindow,
  FFHeroPhoto.footerStairs,
];

/// The footer photo of each footer page while photos are bundled (spec
/// §33.6): fixed, so it can be reviewed, and never from the same scene as
/// the page's top photo.
const footerPagePhotos = <String, FFHeroPhoto>{
  'member.home': FFHeroPhoto.footerWindow,
  'member.activity': FFHeroPhoto.footerBoxing,
  'member.profile': FFHeroPhoto.footerStairs,
  'member.passes': FFHeroPhoto.footerWarmGym,
  'member.gyms': FFHeroPhoto.footerBoxing,
  'member.trainers': FFHeroPhoto.footerWindow,
  'member.shop': FFHeroPhoto.footerStairs,
  'member.gymDetail': FFHeroPhoto.footerWindow,
  'member.trainerDetail': FFHeroPhoto.footerStairs,
  'trainer.home': FFHeroPhoto.footerBoxing,
  'vendor.products': FFHeroPhoto.footerWarmGym,
  'owner.home': FFHeroPhoto.footerStairs,
};

/// FNV-1a 32-bit over UTF-8: the same on the VM and on the web (unlike
/// `String.hashCode`).
int fnv1a32(String s) {
  var hash = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    hash = ((hash ^ b) * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// The footer photo for [pageKey]: its §33.6 photo, or for a page not in
/// the table a stable pick by hash. If that photo shares a scene with [top]
/// (e.g. after an owner photo replaces a stand-in), the next pool photo in
/// table order is used (spec §34.3).
FFHeroPhoto footerPhotoFor(String pageKey, {FFHeroPhoto? top}) {
  final n = footerPhotoPool.length;
  final fixed = footerPagePhotos[pageKey];
  final start = fixed != null
      ? footerPhotoPool.indexOf(fixed)
      : fnv1a32(pageKey) % n;
  for (var i = 0; i < n; i++) {
    final p = footerPhotoPool[(start + i) % n];
    if (p.sourceId != top?.sourceId) return p;
  }
  return footerPhotoPool[start];
}

/// The band's minimum height (spec §33.2): 160 on phones, 140 below 360
/// wide or 640 tall, growing with text up to 200; 220 at 840 wide and up.
/// Content that needs more (very large text) makes it taller still.
double photoFooterHeight(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= 840) return 220;
  final base = size.width < 360 || size.height < 640 ? 140.0 : 160.0;
  final scale = MediaQuery.textScalerOf(context).scale(1);
  return (base * scale).clamp(base, 200.0);
}

/// The photo band that closes a long page (photo-hero spec §33): a photo
/// under a uniform 80% scrim, the FitFlex wordmark and "That's all for
/// now.", plus "Back to top" on Gyms, Trainers and Shop.
///
/// Use [FFPhotoFooter.sliver] as the last sliver of the page's scroll view
/// (see [footerListView] for pages that were a ListView).
abstract final class FFPhotoFooter {
  /// [pageKey] names the page (spec §33.6) and picks the photo; [top] is the
  /// page's top hero photo, if any. [enabled] is the page's "loaded and not
  /// empty" condition. [gap] is the space above the band (32 less any
  /// bottom padding the content already has). [headingFocus] is the top
  /// hero heading's focus node, for Back to top. [hiddenExtent] is the space
  /// left at the end while the footer is not shown.
  static Widget sliver({
    Key? key,
    required String pageKey,
    FFHeroPhoto? top,
    bool backToTop = false,
    ScrollController? controller,
    FocusNode? headingFocus,
    double extraBottom = 0,
    bool enabled = true,
    double gap = FFTokens.spacingXl,
    double inset = FFTokens.spacingLg,
    double maxWidth = 960,
    double hiddenExtent = 0,
  }) => _FooterSliver(
    key: key,
    pageKey: pageKey,
    top: top,
    backToTop: backToTop,
    controller: controller,
    headingFocus: headingFocus,
    extraBottom: extraBottom,
    enabled: enabled,
    gap: gap,
    inset: inset,
    maxWidth: maxWidth,
    hiddenExtent: hiddenExtent,
  );
}

/// A [ListView] when there is no [footer] (flag off: exactly as before);
/// otherwise the same children in a [CustomScrollView] that ends with the
/// footer sliver. The scroll view keeps [key] either way.
Widget footerListView({
  Key? key,
  EdgeInsetsGeometry padding = EdgeInsets.zero,
  ScrollController? controller,
  required List<Widget> children,
  Widget? footer,
}) {
  if (footer == null) {
    return ListView(
      key: key,
      controller: controller,
      padding: padding,
      children: children,
    );
  }
  return CustomScrollView(
    key: key,
    controller: controller,
    slivers: [
      SliverPadding(
        padding: padding,
        sliver: SliverList(delegate: SliverChildListDelegate(children)),
      ),
      footer,
    ],
  );
}

class _FooterSliver extends StatefulWidget {
  const _FooterSliver({
    super.key,
    required this.pageKey,
    required this.top,
    required this.backToTop,
    required this.controller,
    required this.headingFocus,
    required this.extraBottom,
    required this.enabled,
    required this.gap,
    required this.inset,
    required this.maxWidth,
    required this.hiddenExtent,
  });

  final String pageKey;
  final FFHeroPhoto? top;
  final bool backToTop;
  final ScrollController? controller;
  final FocusNode? headingFocus;
  final double extraBottom;
  final bool enabled;
  final double gap;
  final double inset;
  final double maxWidth;

  /// Space kept at the end of the page while the footer is not shown (the
  /// room a page had under its last item before the footer existed).
  final double hiddenExtent;

  @override
  State<_FooterSliver> createState() => _FooterSliverState();
}

class _FooterSliverState extends State<_FooterSliver> {
  /// Once shown on this page visit it stays (hysteresis, §33.3) until the
  /// page turns [_FooterSliver.enabled] off.
  bool _shown = false;

  /// The photo decodes only once the footer reaches the cache area just
  /// beyond the viewport (lazy, AC-M13).
  bool _near = false;

  @override
  void didUpdateWidget(_FooterSliver old) {
    super.didUpdateWidget(old);
    if (!widget.enabled) {
      _shown = false;
      _near = false;
    }
  }

  double _bottom(BuildContext context) =>
      FFTokens.spacingLg +
      MediaQuery.paddingOf(context).bottom +
      widget.extraBottom;

  Future<void> _toTop(BuildContext context) async {
    final position =
        widget.controller?.position ?? Scrollable.maybeOf(context)?.position;
    if (position != null) {
      final start = position.minScrollExtent;
      if (MediaQuery.disableAnimationsOf(context)) {
        position.jumpTo(start);
      } else {
        await position.animateTo(
          start,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    }
    widget.headingFocus?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return SliverToBoxAdapter(
        child: SizedBox(
          key: const Key('photo-footer-off'),
          height: widget.hiddenExtent,
        ),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final extent =
            widget.gap + photoFooterHeight(context) + _bottom(context);
        // The extent above does not depend on the footer, so this cannot
        // feed back on itself.
        if (!_shown &&
            constraints.precedingScrollExtent + extent >
                constraints.viewportMainAxisExtent) {
          _shown = true;
        }
        if (!_shown) {
          return SliverToBoxAdapter(
            child: SizedBox(
              key: const Key('photo-footer-short'),
              height: widget.hiddenExtent,
            ),
          );
        }
        if (constraints.remainingCacheExtent > 0) _near = true;
        return SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              widget.inset,
              widget.gap,
              widget.inset,
              _bottom(context),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: widget.maxWidth),
                child: _band(context),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _band(BuildContext context) {
    final photo = footerPhotoFor(widget.pageKey, top: widget.top);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return ClipRRect(
      key: const Key('photo-footer'),
      borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      child: Stack(
        children: [
          Positioned.fill(
            child: _FooterPhotoLayer(photo: photo, load: _near),
          ),
          // One uniform 80% layer: every pixel meets the text rule over any
          // photo (§33.2, DD-9).
          Positioned.fill(
            child: ColoredBox(
              key: const Key('photo-footer-scrim'),
              color: FFTokens.heroScrim.withValues(
                alpha: FFTokens.heroScrimText,
              ),
            ),
          ),
          // The content sets the band's height (at least the minimum).
          ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: photoFooterHeight(context),
              minWidth: double.infinity,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                child: Semantics(
                  container: true,
                  explicitChildNodes: true,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ExcludeSemantics(child: FFWordmark()),
                      const SizedBox(height: FFTokens.spacingSm),
                      Text(
                        context.tr('footer.endLine'),
                        key: const Key('photo-footer-line'),
                        textAlign: TextAlign.center,
                        maxLines: scale > 1.15 ? 3 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: FFTokens.fontSans,
                          fontSize: 16,
                          height: 1.5,
                          fontWeight: FontWeight.w600,
                          color: FFTokens.heroText,
                        ),
                      ),
                      if (widget.backToTop) ...[
                        const SizedBox(height: FFTokens.spacingSm + 4),
                        FFButton(
                          key: const Key('photo-footer-back-to-top'),
                          label: context.tr('footer.backToTop'),
                          icon: Icons.arrow_upward,
                          variant: FFButtonVariant.onPhoto,
                          size: FFButtonSize.sm,
                          onPressed: () => _toTop(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The footer photo decoded at its display size, fading in over 250ms
/// (instant under reduced motion). Under high contrast, or before the
/// footer nears the viewport, the navy ground only. Never in the
/// accessibility tree.
class _FooterPhotoLayer extends StatelessWidget {
  const _FooterPhotoLayer({required this.photo, required this.load});

  final FFHeroPhoto photo;
  final bool load;

  @override
  Widget build(BuildContext context) {
    final noPhoto = MediaQuery.highContrastOf(context) || !load;
    final instant = MediaQuery.disableAnimationsOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ExcludeSemantics(
      child: ColoredBox(
        key: const Key('photo-footer-ground'),
        color: FFTokens.heroPlaceholder,
        child: noPhoto
            ? const SizedBox.expand()
            : LayoutBuilder(
                builder: (context, c) => Image(
                  key: const Key('photo-footer-photo'),
                  image: heroImageProvider(photo, c.biggest, dpr),
                  fit: BoxFit.cover,
                  alignment: photo.focal,
                  width: c.maxWidth,
                  height: c.maxHeight,
                  excludeFromSemantics: true,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.expand(),
                  frameBuilder: (context, child, frame, sync) {
                    if (sync) return child;
                    return AnimatedOpacity(
                      opacity: frame == null ? 0 : 1,
                      duration: instant
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      child: child,
                    );
                  },
                ),
              ),
      ),
    );
  }
}
