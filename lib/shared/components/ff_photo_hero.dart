import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import '../i18n.dart';
import 'ff_skeleton.dart';

/// Bundled hero photos (people-free licensed stock until FitFlex has its own
/// shoot; see assets/photos/hero/LICENSES.md). Never fetched from a network.
enum FFHeroPhoto {
  language('hero_language', 4 / 5),
  signIn('hero_sign_in', 4 / 5),
  signUp('hero_sign_up', 4 / 5),
  role('hero_role', 16 / 9),

  /// Home with no QR: no pass, payment pending, ended.
  homeStart('hero_home_start', 4 / 5),

  /// Home with a working pass (QR states).
  homePass('hero_home_pass', 3 / 2);

  const FFHeroPhoto(this.file, this.aspect);

  final String file;

  /// Width / height of the bundled file.
  final double aspect;

  String get asset => 'assets/photos/hero/$file.webp';
}

/// How the hero is laid out.
/// [full] and [compact] stack the text over a vertical scrim (phones);
/// [panel] puts it bottom-left over a horizontal scrim (desktop, wide
/// banners).
enum FFHeroVariant { full, compact, panel }

/// The decode size for [photo] drawn with `BoxFit.cover` into [box], rounded
/// up to a 128px step so the pre-cache and the hero share one cache entry
/// more often.
ImageProvider heroImageProvider(FFHeroPhoto photo, Size box, double dpr) {
  final logical = box.width > box.height * photo.aspect
      ? box.width
      : box.height * photo.aspect;
  final px = ((logical * dpr) / 128).ceil() * 128;
  return ResizeImage.resizeIfNeeded(
    px <= 0 ? null : px,
    null,
    AssetImage(photo.asset),
  );
}

/// Decodes hero photos ahead of time so they appear without a placeholder.
/// Sized for a phone-width hero; errors are ignored (the placeholder shows).
void precacheHeroPhotos(BuildContext context, Iterable<FFHeroPhoto> photos) {
  final size = MediaQuery.sizeOf(context);
  final dpr = MediaQuery.devicePixelRatioOf(context);
  for (final p in photos) {
    precacheImage(
      heroImageProvider(p, Size(size.width, size.height * 0.5), dpr),
      context,
      onError: (_, _) {},
    );
  }
}

/// A photo under a slate-950 scrim with light text: the "always-dark island"
/// of docs/design/photo-hero-screens.md.
///
/// Scrim rule (§5): the text block sits on a solid 80% scrim that starts 24px
/// above the first line of text, whatever the text scale, so every text pixel
/// is at least 10.6:1 even over a pure-white photo. Above that, the scrim
/// fades from 50% (status bar, app bar icons, logo) to 80%; nothing but the
/// photo sits there.
class FFPhotoHero extends StatelessWidget {
  const FFPhotoHero({
    super.key,
    required this.photo,
    this.variant = FFHeroVariant.full,
    this.minHeight = 0,
    this.topInset = 0,
    this.eyebrow,
    this.chip,
    this.headlineLead,
    this.headlineAccent,
    this.headlineLoading = false,
    this.secondLead,
    this.secondAccent,
    this.subline,
    this.actions = const [],
    this.logo,
    this.rounded = false,
    this.wideHeadline = false,
  });

  final FFHeroPhoto photo;
  final FFHeroVariant variant;

  /// The hero never gets shorter than this; text at large scales grows it.
  final double minHeight;

  /// Space kept clear at the top for the status bar and app bar.
  final double topInset;

  /// Mono label above the headline, written in normal case (shown uppercase).
  final String? eyebrow;

  /// Fuel state chip (e.g. "PASS ENDS SOON").
  final String? chip;
  final String? headlineLead;

  /// The last words of the headline, in the accent colour.
  final String? headlineAccent;

  /// Two placeholder lines instead of the headline while data loads.
  final bool headlineLoading;

  /// A second, smaller headline (the Swahili tagline on the language screen).
  final String? secondLead;
  final String? secondAccent;
  final String? subline;

  /// Buttons under the text, already built (FFButton primary / onPhoto).
  final List<Widget> actions;

  /// Logo for the panel variant's top-left corner (phones show it in the app
  /// bar instead).
  final Widget? logo;

  /// Rounded corners (desktop Home banner).
  final bool rounded;

  /// Canon h1 (48/52) for the desktop pre-sign-in panel.
  final bool wideHeadline;

  /// The accent colour for the current theme: Volt on dark, brand-500 on
  /// light (large text only).
  static Color accentFor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? FFTokens.heroAccentDark
      : FFTokens.heroAccentLight;

  String get _semanticsLabel => [
    ?eyebrow,
    if (headlineLead != null || headlineAccent != null)
      [?headlineLead, ?headlineAccent].join(' '),
    if (secondLead != null || secondAccent != null)
      [?secondLead, ?secondAccent].join(' '),
    ?subline,
    ?chip,
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final hero = variant == FFHeroVariant.panel
        ? _panel(context)
        : _vertical(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: rounded
          ? ClipRRect(
              borderRadius: BorderRadius.circular(FFTokens.radiusXl),
              child: hero,
            )
          : hero,
    );
  }

  Widget _vertical(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scrim = FFTokens.heroScrim;
    // Light theme: the sheet below overlaps the hero, so keep that strip
    // free of text and buttons.
    final bottomPad =
        FFTokens.spacingLg + (dark ? 0 : FFTokens.heroSheetOverlap);
    return Stack(
      children: [
        Positioned.fill(child: _HeroPhotoLayer(photo: photo)),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Photo only: 50% at the top edge, 80% where the text zone
                // starts.
                Expanded(
                  child: DecoratedBox(
                    key: const Key('ff-hero-fade-zone'),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scrim.withValues(alpha: FFTokens.heroScrimTop),
                          scrim.withValues(alpha: FFTokens.heroScrimText),
                        ],
                      ),
                    ),
                    child: SizedBox(height: topInset),
                  ),
                ),
                ColoredBox(
                  key: const Key('ff-hero-text-zone'),
                  color: scrim.withValues(alpha: FFTokens.heroScrimText),
                  child: Stack(
                    children: [
                      if (dark)
                        // Dark theme: melt into the page ground over the
                        // last 48px (80% -> 100%).
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 48,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  scrim.withValues(alpha: 0),
                                  scrim.withValues(
                                    alpha: FFTokens.heroScrimGround,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          FFTokens.spacingLg,
                          FFTokens.spacingLg,
                          FFTokens.spacingLg,
                          bottomPad,
                        ),
                        child: _content(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _panel(BuildContext context) {
    final scrim = FFTokens.heroScrim;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(child: _HeroPhotoLayer(photo: photo)),
        Positioned.fill(
          child: DecoratedBox(
            key: const Key('ff-hero-panel-scrim'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scrim.withValues(alpha: FFTokens.heroScrimPanelLead),
                  scrim.withValues(alpha: FFTokens.heroScrimText),
                  scrim.withValues(alpha: FFTokens.heroScrimPanelTail),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  scrim.withValues(alpha: 0.85),
                  scrim.withValues(alpha: 0),
                ],
                stops: const [0, 0.3],
              ),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: LayoutBuilder(
            builder: (context, c) {
              final pad = wideHeadline ? 64.0 : FFTokens.spacingXl;
              // Text stays in the left half, where the scrim is >= 80%.
              final textWidth = c.maxWidth.isFinite
                  ? (c.maxWidth / 2 - pad).clamp(240.0, 560.0)
                  : 480.0;
              return Stack(
                children: [
                  if (logo != null)
                    Positioned(
                      left: FFTokens.spacingLg,
                      top: FFTokens.spacingLg,
                      child: logo!,
                    ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        pad,
                        pad + (logo != null ? 48 : 0),
                        pad,
                        pad,
                      ),
                      child: ConstrainedBox(
                        key: const Key('ff-hero-text-zone'),
                        constraints: BoxConstraints(maxWidth: textWidth),
                        child: _content(context),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final (size, line) = wideHeadline
        ? (FFTokens.heroDisplaySizeWide, FFTokens.heroDisplayLineWide)
        : width < 375
        ? (FFTokens.heroDisplaySizeSmall, FFTokens.heroDisplayLineSmall)
        : (FFTokens.heroDisplaySize, FFTokens.heroDisplayLine);
    final accent = accentFor(context);
    final headlineStyle = TextStyle(
      fontFamily: FFTokens.fontSans,
      fontSize: size,
      height: line / size,
      fontWeight: FontWeight.w900,
      letterSpacing: size * -0.03,
      color: FFTokens.heroText,
    );

    final text = <Widget>[
      if (eyebrow != null)
        Text(
          _eyebrowText(eyebrow!),
          key: const Key('ff-hero-eyebrow'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: FFTokens.heroEyebrow(),
        ),
      if (chip != null) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            key: const Key('ff-hero-chip'),
            padding: const EdgeInsets.symmetric(
              horizontal: FFTokens.spacingSm + 2,
              vertical: FFTokens.spacingXs,
            ),
            decoration: BoxDecoration(
              color: FFTokens.heroChipFuelFill,
              border: Border.all(color: FFTokens.heroChipFuelBorder),
              borderRadius: BorderRadius.circular(FFTokens.radiusFull),
            ),
            child: Text(
              chip!,
              style: FFTokens.heroEyebrow(color: FFTokens.heroChipFuelText),
            ),
          ),
        ),
      ],
      if (headlineLoading) ...[
        const SizedBox(height: FFTokens.spacingSm),
        _SkeletonOnPhoto(height: size * 0.8, widthFactor: 0.7),
        const SizedBox(height: FFTokens.spacingSm),
        _SkeletonOnPhoto(height: size * 0.8, widthFactor: 0.45),
      ] else if (headlineLead != null || headlineAccent != null) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Text.rich(
          key: const Key('ff-hero-headline'),
          TextSpan(
            children: [
              if (headlineLead != null)
                TextSpan(
                  text: headlineAccent == null
                      ? headlineLead
                      : '$headlineLead ',
                ),
              if (headlineAccent != null)
                TextSpan(
                  text: headlineAccent,
                  style: TextStyle(color: accent),
                ),
            ],
          ),
          style: headlineStyle,
        ),
      ],
      if (secondLead != null || secondAccent != null) ...[
        const SizedBox(height: FFTokens.spacingSm),
        Text.rich(
          key: const Key('ff-hero-second'),
          TextSpan(
            children: [
              if (secondLead != null) TextSpan(text: '$secondLead '),
              if (secondAccent != null)
                TextSpan(
                  text: secondAccent,
                  style: TextStyle(color: accent),
                ),
            ],
          ),
          // >= 24px / w800 so the light-theme accent stays "large text".
          style: const TextStyle(
            fontFamily: FFTokens.fontSans,
            fontSize: 24,
            height: 30 / 24,
            fontWeight: FontWeight.w800,
            color: FFTokens.heroTextBody,
          ),
        ),
      ],
      if (subline != null) ...[
        const SizedBox(height: FFTokens.spacingSm + 4),
        Text(
          subline!,
          key: const Key('ff-hero-subline'),
          style: const TextStyle(
            fontFamily: FFTokens.fontSans,
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w400,
            color: FFTokens.heroTextBody,
          ),
        ),
      ],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Eyebrow, headline, subline and chip are read as one heading.
        Semantics(
          container: true,
          header: true,
          label: _semanticsLabel,
          excludeSemantics: true,
          child: Column(
            key: const Key('ff-hero-text'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: text,
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingMd + 4),
          Wrap(
            spacing: FFTokens.spacingSm + 4,
            runSpacing: FFTokens.spacingSm + 4,
            children: actions,
          ),
        ],
      ],
    );
  }

  /// Uppercase, at most 28 characters on one line.
  static String _eyebrowText(String s) {
    final up = s.toUpperCase();
    return up.length <= 28 ? up : '${up.substring(0, 27)}…';
  }
}

/// The photo, or the navy placeholder: before it decodes, if it fails, and
/// always under high contrast. Never in the accessibility tree.
class _HeroPhotoLayer extends StatelessWidget {
  const _HeroPhotoLayer({required this.photo});

  final FFHeroPhoto photo;

  @override
  Widget build(BuildContext context) {
    final noPhoto = MediaQuery.highContrastOf(context);
    final instant = MediaQuery.disableAnimationsOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ExcludeSemantics(
      child: ColoredBox(
        key: const Key('ff-hero-placeholder'),
        color: FFTokens.heroPlaceholder,
        child: noPhoto
            ? const SizedBox.expand()
            : LayoutBuilder(
                builder: (context, c) => Image(
                  key: const Key('ff-hero-photo'),
                  image: heroImageProvider(photo, c.biggest, dpr),
                  fit: BoxFit.cover,
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

/// A loading line drawn white at up to 12% on the scrim.
class _SkeletonOnPhoto extends StatelessWidget {
  const _SkeletonOnPhoto({required this.height, required this.widthFactor});

  final double height;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Theme(
        data: theme.copyWith(
          colorScheme: theme.colorScheme.copyWith(onSurface: Colors.white),
        ),
        child: FFSkeleton(height: height),
      ),
    );
  }
}

/// The FitFlex athlete mark (without the navy pin, which disappears on a dark
/// scrim) and the wordmark: white "FitFlex", gold "Af".
class FFWordmark extends StatelessWidget {
  const FFWordmark({super.key, this.size = 18});

  final double size;

  static const gold = Color(0xFFFDBE34);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: context.tr('app.title'),
      excludeSemantics: true,
      // A logo: it keeps its size at large text scales and shrinks to fit
      // a narrow app bar rather than running past it.
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          key: const Key('ff-wordmark'),
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/brand/logo-runner.png',
              width: size * 1.8,
              height: size * 1.8,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
            const SizedBox(width: FFTokens.spacingXs),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'FitFlex '),
                  TextSpan(
                    text: 'Af',
                    style: TextStyle(color: gold),
                  ),
                ],
              ),
              textScaler: TextScaler.noScaling,
              style: TextStyle(
                fontFamily: FFTokens.fontSans,
                fontSize: size,
                fontWeight: FontWeight.w800,
                color: FFTokens.heroText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// App bar controls drawn on the photo: icons and labels in the hero text
/// colour (3.5:1 on the 50% band over pure white).
class FFOnPhotoTheme extends StatelessWidget {
  const FFOnPhotoTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    const c = FFTokens.heroText;
    return Theme(
      data: t.copyWith(
        iconTheme: t.iconTheme.copyWith(color: c),
        textTheme: t.textTheme.apply(bodyColor: c, displayColor: c),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: c),
        ),
      ),
      child: IconTheme.merge(
        data: const IconThemeData(color: c),
        child: DefaultTextStyle.merge(
          style: const TextStyle(color: c),
          child: child,
        ),
      ),
    );
  }
}

/// The solid content under a hero. Dark theme: the page ground (the hero
/// has already faded into it). Light theme: a sheet with 24px top corners
/// that overlaps the hero by 24px.
class FFHeroSheet extends StatelessWidget {
  const FFHeroSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(FFTokens.spacingLg),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) {
      return Padding(padding: padding, child: child);
    }
    return Transform.translate(
      offset: const Offset(0, -FFTokens.heroSheetOverlap),
      child: Container(
        key: const Key('ff-hero-sheet'),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(FFTokens.heroSheetRadius),
          ),
        ),
        padding: padding,
        child: child,
      ),
    );
  }
}
