import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import 'ff_photo_hero.dart';

/// Where and how big a page's hero is drawn.
typedef FFHeroFrame = ({
  FFHeroVariant variant,
  double minHeight,
  double topInset,
  bool wide,
});

/// Layout for the pre-sign-in screens with a photo hero (§6):
/// - phone (< 600): the hero behind a transparent app bar, the content below
///   on the ground (dark) or an overlapping sheet (light); all one scroll.
/// - tablet / narrow web (600-1023): a 280px hero band with rounded bottom
///   corners, the content column (max 420) centred under it.
/// - desktop (>= 1024): a split layout, the hero panel on the left 58%, the
///   content vertically centred on the right.
class FFPhotoHeroPage extends StatefulWidget {
  const FFPhotoHeroPage({
    super.key,
    required this.hero,
    required this.content,
    this.leading,
    this.logo,
    this.actions = const [],
    this.phoneFraction = 0.38,
    this.shortPhoneFraction = 0.34,
    this.phoneMinHeight = 240,
    this.phoneVariant = FFHeroVariant.compact,
  });

  /// Builds the hero for the frame this layout picked.
  final Widget Function(BuildContext context, FFHeroFrame frame) hero;
  final Widget content;
  final Widget? leading;

  /// Logo for the app bar (phones) or the panel corner (desktop).
  final Widget? logo;
  final List<Widget> actions;

  /// Hero height as a share of the viewport on phones; the short value is
  /// used below 700px of height.
  final double phoneFraction;
  final double shortPhoneFraction;
  final double phoneMinHeight;

  /// [FFHeroVariant.full] or [FFHeroVariant.compact] below 1024 wide.
  final FFHeroVariant phoneVariant;

  @override
  State<FFPhotoHeroPage> createState() => _FFPhotoHeroPageState();
}

class _FFPhotoHeroPageState extends State<FFPhotoHeroPage> {
  final _heroKey = GlobalKey();
  bool _solid = false;

  bool _onScroll(ScrollNotification n, double topInset) {
    if (n.depth != 0) return false;
    final h = _heroKey.currentContext?.size?.height ?? 0;
    final solid = h > 0 && n.metrics.pixels >= h - topInset;
    if (solid != _solid) setState(() => _solid = solid);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = size.width;
    final ground = Theme.of(context).scaffoldBackgroundColor;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: widget.content,
    );

    if (width >= 1024) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 58,
              child: widget.hero(context, (
                variant: FFHeroVariant.panel,
                minHeight: size.height,
                topInset: 0,
                wide: true,
              )),
            ),
            Expanded(
              flex: 42,
              child: ColoredBox(
                color: ground,
                child: SafeArea(
                  child: Column(
                    children: [
                      SizedBox(
                        height: kToolbarHeight,
                        child: Row(
                          children: [
                            ?widget.leading,
                            const Spacer(),
                            ...widget.actions,
                          ],
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(FFTokens.spacingLg),
                            child: content,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final tablet = width >= 600;
    final heroMin = tablet
        ? 280.0
        : (size.height *
                  (size.height < 700
                      ? widget.shortPhoneFraction
                      : widget.phoneFraction))
              .clamp(widget.phoneMinHeight, double.infinity);
    Widget hero = KeyedSubtree(
      key: _heroKey,
      child: widget.hero(context, (
        variant: widget.phoneVariant,
        minHeight: heroMin.toDouble(),
        topInset: topInset,
        wide: false,
      )),
    );
    if (tablet) {
      hero = ClipRRect(
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(FFTokens.radiusXl),
        ),
        child: hero,
      );
    }
    final onPhoto = !_solid;
    Widget bar(Widget w) => onPhoto ? FFOnPhotoTheme(child: w) : w;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: onPhoto ? FFTokens.heroText : null,
        systemOverlayStyle: onPhoto ? SystemUiOverlayStyle.light : null,
        automaticallyImplyLeading: false,
        // Logo top-left on every platform (§6).
        centerTitle: false,
        flexibleSpace: AnimatedOpacity(
          opacity: _solid ? 1 : 0,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          child: ColoredBox(color: Theme.of(context).colorScheme.surface),
        ),
        leading: widget.leading == null ? null : bar(widget.leading!),
        titleSpacing: widget.leading == null ? FFTokens.spacingLg : 0,
        title: widget.logo == null ? null : bar(widget.logo!),
        actions: [
          bar(Row(mainAxisSize: MainAxisSize.min, children: widget.actions)),
        ],
      ),
      body: NotificationListener<ScrollNotification>(
        onNotification: (n) => _onScroll(n, topInset),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hero,
              FFHeroSheet(
                padding: EdgeInsets.fromLTRB(
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg,
                  FFTokens.spacingLg + MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(child: content),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
