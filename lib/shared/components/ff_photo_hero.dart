import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import '../hero_images/hero_image_store.dart';
import '../i18n.dart';
import '../media/media_src.dart';
import 'ff_skeleton.dart';

/// Bundled hero photos: FitFlex Africa's own AI-generated scenes (Figma AI,
/// 2026-10-22 and 2026-10-28, no people). The four test-only photos the
/// owner collected from the internet were replaced on 2026-10-28 (owner
/// approval in chat), so [kTestOnlyHeroAssets] is empty. See
/// assets/photos/hero/LICENSES.md. Never
/// fetched from a network. With `HERO_IMAGES_REMOTE` on, an admin-published
/// photo for the same slot (hero_images/hero_slots.dart) may replace one
/// once it is saved and decoded ([HeroImageStore]); the bundled file stays
/// the fallback.
/// No crop shows another brand's logo or signage (owner rule 2026-10-20);
/// the FitFlex Africa signage in the generated scenes is kept in the clear
/// photo above the scrim where the crop allows, and otherwise cropped out:
/// never a sign partly behind the text (owner 2026-10-22).
enum FFHeroPhoto {
  // Every file is its own scene (sourceId), so no two slots share one.
  // Focal y = 2 x (the sign's or subject's height in the file, 0..1) - 1:
  // the sign keeps its place relative to the box on any shape, from a
  // phone hero to an 840+ banner, so it stays in the clear photo.
  language(
    'hero_language',
    864 / 1080,
    'fitflex-gen-01-reception',
    Alignment(0, -0.3),
  ),
  signIn(
    'hero_sign_in',
    864 / 1080,
    'fitflex-gen-04-entrance',
    Alignment(0, -0.45),
  ),
  signUp(
    'hero_sign_up',
    864 / 1080,
    'fitflex-gen-05-locker-towel',
    Alignment(0, -0.4),
  ),
  role(
    'hero_role',
    864 / 1100,
    'fitflex-gen-07-wide-floor',
    Alignment.topCenter,
  ),

  /// Home with no QR: no pass, payment pending, ended.
  homeStart(
    'hero_home_start',
    864 / 1080,
    'fitflex-gen-08-sunrise-neon',
    Alignment(0, -0.6),
  ),

  /// Home with a working pass (QR states).
  homePass(
    'hero_home_pass',
    864 / 576,
    'fitflex-gen-09-rack-shaker',
    Alignment(0, -0.3),
  ),

  profile(
    'hero_profile',
    864 / 864,
    'fitflex-gen-10-towel-bench',
    Alignment(0, 0.1),
  ),
  // PIN's thin strip (owner 2026-10-22) is all text under the bar: the
  // crop is the gym floor above the desk plate, so no sign sits behind the
  // headline.
  pin('hero_pin', 864 / 540, 'fitflex-gen-06-desk-sign', Alignment(0, 0.2)),
  // Upgrade's band has no room for clear photo (its plan cards come
  // first), so the crop is below the wall sign: no sign behind the text.
  upgrade(
    'hero_upgrade',
    864 / 576,
    'fitflex-gen-11-premium-zone',
    Alignment(0, -0.2),
  ),
  // Today: the bottle printed "FitFlex Africa" sits in the clear photo
  // above the text; the crop stops short of the right shoe's maker mark.
  activityToday(
    'hero_activity_today',
    810 / 540,
    'fitflex-gen-23-activity-today-sunrise',
    Alignment(0, -0.3),
  ),
  activityTraining(
    'hero_activity_training',
    864 / 576,
    'fitflex-gen-12-cable-zone',
    Alignment(0, -0.2),
  ),
  // Challenges: below the wall sign (wider than the phone crop shows, so
  // it would be cut at both edges).
  activityChallenges(
    'hero_activity_challenges',
    864 / 576,
    'fitflex-gen-24-activity-challenges-zone',
    Alignment(0, -0.2),
  ),
  activityProgress(
    'hero_activity_progress',
    864 / 576,
    'fitflex-gen-13-treadmills-decal',
    Alignment(0, 0.15),
  ),
  // Trainer and vendor homes: below the wall sign and the taped boxes. A
  // band whose clear photo gives way (Swahili, phones under 760 tall) has
  // text from its top edge, and a sign there would sit behind it.
  trainer(
    'hero_trainer',
    864 / 546,
    'fitflex-gen-14-coaching',
    Alignment(0, -0.3),
  ),
  vendor(
    'hero_vendor',
    864 / 576,
    'fitflex-gen-15-vendor-packing',
    Alignment.topCenter,
  ),
  owner(
    'hero_owner',
    864 / 576,
    'fitflex-gen-03-gym-floor',
    Alignment(0, -0.3),
  ),

  // Section bands (photo-hero spec §32, §34.1): member Gyms, Trainers and
  // Shop home. Gyms: the window row below the wall sign (the sign is as
  // wide as the phone crop, so it would touch both edges). Trainers: the
  // polo printed "FitFlex Africa" in the clear photo, focal right so the
  // print stays in frame on a phone band.
  gyms(
    'hero_gyms',
    864 / 487,
    'fitflex-gen-21-gyms-bright-floor',
    Alignment(0, -0.3),
  ),
  trainers(
    'hero_trainers',
    864 / 516,
    'fitflex-gen-22-trainers-station',
    Alignment(0.5, -0.5),
  ),
  // Shop (owner 2026-10-22): the whole FitFlex Africa sign above the
  // band's text. A 4:5 crop from the top of the source, focal top: a phone
  // band (taller than 4:5 is wide) shows the full width, the sign at the
  // top, and its clear photo below it before the text.
  shop('hero_shop', 864 / 1080, 'fitflex-gen-02-shop', Alignment.topCenter),

  // Footer pool (spec §33): four square generated scenes, 1024 wide at 2x
  // (the source size; never upscaled). Focal on the sign, so a wide footer
  // keeps it in the clear photo above the lockup.
  footerStretch(
    'footer_stretch',
    1,
    'fitflex-gen-16-footer-stretch',
    Alignment(0, -0.5),
  ),
  footerRooftop(
    'footer_rooftop',
    1,
    'fitflex-gen-17-footer-rooftop',
    Alignment(0, 0.15),
  ),
  footerHydration('footer_hydration', 1, 'fitflex-gen-18-footer-hydration'),
  footerNightHall(
    'footer_night_hall',
    1,
    'fitflex-gen-19-footer-night-hall',
    Alignment(0, -0.55),
  );

  const FFHeroPhoto(
    this.file,
    this.aspect,
    this.sourceId, [
    this.focal = Alignment.center,
  ]);

  final String file;

  /// Width / height of the bundled file.
  final double aspect;

  /// The scene this file shows (spec §34.1): `fitflex-gen-…` for a
  /// generated scene, `owner-…` for an owner-supplied photo (the source
  /// file's name). Crops of one scene would share it, so a page can keep its
  /// footer photo apart from its top hero.
  final String sourceId;

  /// Where `BoxFit.cover` keeps the subject (the image alignment).
  final Alignment focal;

  String get asset => 'assets/photos/hero/$file.webp';
}

/// Bundled hero photos that are OK for testing but NOT cleared for release.
/// Empty since 2026-10-28: the four owner-collected photos (owner
/// 2026-10-22) were replaced by FitFlex Africa scenes. Any photo added here
/// must be replaced, and taken off this list, before PHOTO_HERO_UI goes on
/// for users: `test/photo_hero_release_guard_test.dart` fails a run with
/// `--dart-define=PHOTO_HERO_RELEASE=true` while this is not empty, and the
/// user builds run that guard whenever PHOTO_HERO_UI is on.
const Set<FFHeroPhoto> kTestOnlyHeroAssets = {};

/// A photo fetched from the network for a hero (Shop home banners, Phase 2
/// S1): the same scrim, focal alignment and navy placeholder as a bundled
/// [FFHeroPhoto]. The placeholder shows while it loads, if it fails and
/// under high contrast, so the text on it stays readable.
@immutable
class FFHeroNetworkImage {
  const FFHeroNetworkImage(this.url, {this.focal = Alignment.center});

  final String url;

  /// Where `BoxFit.cover` keeps the subject.
  final Alignment focal;

  @override
  bool operator ==(Object other) =>
      other is FFHeroNetworkImage && other.url == url && other.focal == focal;

  @override
  int get hashCode => Object.hash(url, focal);
}

/// How the hero is laid out.
/// [full] and [compact] stack the text over a vertical scrim (phones);
/// [panel] puts it bottom-left over a horizontal scrim (desktop, wide
/// banners). [band] is an inset card inside the page padding, under a solid
/// app bar: the same vertical scrim, 24px corners, no sheet overlap and no
/// melt into the ground (it is a card with a visible edge, spec C-1).
enum FFHeroVariant { full, compact, panel, band }

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

/// The decode size for a network hero image drawn into [box]: its width at
/// this pixel ratio, rounded up to a 128px step (the aspect is unknown until
/// it loads, so only the width is capped).
///
/// Null when the address fails the image source check ([resolveMediaSrc]:
/// our own storage paths and API host only, fitflex-functions#273); the hero
/// then shows its bundled photo or the placeholder and makes no request.
ImageProvider? heroNetworkImageProvider(
  FFHeroNetworkImage image,
  Size box,
  double dpr, {
  String? apiBase,
}) {
  final provider = mediaImageProvider(image.url, apiBase: apiBase);
  if (provider == null) return null;
  final px = box.width.isFinite ? ((box.width * dpr) / 128).ceil() * 128 : 0;
  return ResizeImage.resizeIfNeeded(px <= 0 ? null : px, null, provider);
}

/// Decodes hero photos ahead of time so they appear without a placeholder.
/// Sized for a phone-width hero; errors are ignored (the placeholder shows).
/// Pass [box] when the hero's size is known, so the pre-cache and the hero
/// share one cache entry (Activity's section switch, §24).
void precacheHeroPhotos(
  BuildContext context,
  Iterable<FFHeroPhoto> photos, {
  Size? box,
}) {
  final size = MediaQuery.sizeOf(context);
  final dpr = MediaQuery.devicePixelRatioOf(context);
  final store = HeroImageStore.instance;
  for (final p in photos) {
    final b = box ?? Size(size.width, size.height * 0.5);
    final remote = store?.peekTop(p);
    precacheImage(
      remote != null
          ? heroRemoteImageProvider(remote, b, dpr)
          : heroImageProvider(p, b, dpr),
      context,
      onError: (_, _) {},
    );
  }
}

/// The decode size for an admin-published photo drawn with `BoxFit.cover`
/// into [box] (as [heroImageProvider]), on phones (the saved file) and on
/// the web (the bytes that decoded in this session) alike.
ImageProvider heroRemoteImageProvider(
  RemoteHeroImage image,
  Size box,
  double dpr,
) {
  final logical = box.width > box.height * image.aspect
      ? box.width
      : box.height * image.aspect;
  final px = logical.isFinite ? ((logical * dpr) / 128).ceil() * 128 : 0;
  return ResizeImage.resizeIfNeeded(px <= 0 ? null : px, null, image.provider);
}

/// A photo under a slate-950 scrim with light text: the "always-dark island"
/// of docs/design/photo-hero-screens.md.
///
/// Scrim rule (§5, owner 2026-10-20 "lighter"): the scrim is local, so the
/// photo shows. From the top: a band behind the status bar and app bar
/// ([FFTokens.heroScrimTop], held over the bar, gone by 16% of the height);
/// then the photo, clear; then a ramp that starts 24px above the first line
/// of text (after a 48px soft lead-in) and reaches [FFTokens.heroScrimText]
/// at that line, whatever the text scale. From there down to the bottom
/// edge it stays at that value or darker, so every text pixel is at least
/// 9.7:1 (body) even over a pure-white photo. When the page draws the bar band itself (a
/// [FFPhotoBarHost] above, so it stays put while the hero scrolls), the
/// hero leaves it out.
class FFPhotoHero extends StatelessWidget {
  const FFPhotoHero({
    super.key,
    this.photo,
    this.networkImage,
    this.variant = FFHeroVariant.full,
    this.minHeight = 0,
    this.topInset = 0,
    this.eyebrow,
    this.chip,
    this.headlineLead,
    this.headlineAccent,
    this.headlineLoading = false,
    this.headlineMaxLines,
    this.headlineReserve = const [],
    this.leading,
    this.subline,
    this.actions = const [],
    this.logo,
    this.rounded = false,
    this.wideHeadline = false,
    this.headingFocusNode,
    this.clearPhoto = 0,
    this.maxHeight = double.infinity,
    this.minClearPhoto = 0,
    this.excludeHeadingSemantics = false,
    this.fillHeight = false,
    this.panelSidePad,
  }) : assert(
         photo != null || networkImage != null,
         'Give a photo, a networkImage, or both (photo = fallback)',
       );

  /// A bundled photo (never fetched from the network)...
  final FFHeroPhoto? photo;

  /// ...or one from the network (Shop home banners, an event's own cover).
  /// At least one is set. With both, the network image leads and [photo] is
  /// drawn instead when it fails to load (events S2 spec §11.5).
  final FFHeroNetworkImage? networkImage;
  final FFHeroVariant variant;

  /// The hero never gets shorter than this; text at large scales grows it.
  final double minHeight;

  /// Taller heroes (owner 2026-10-20, spec §5.3; vertical variants only):
  /// the photo kept clear of any scrim between the bar band and the ramp's
  /// lead-in, in logical px. The hero grows to fit it on top of its text.
  /// 0: as before.
  final double clearPhoto;

  /// A soft cap for [clearPhoto]: the clear photo shrinks (to none) so the
  /// hero stays within this height, but the text is never cut, and the hero
  /// is never shorter than [minHeight].
  final double maxHeight;

  /// Under [maxHeight], the least clear photo worth growing the hero for:
  /// when the cap leaves less, the hero keeps today's height instead (a
  /// taller hero that shows no more photo only pushes the content down).
  final double minClearPhoto;

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

  /// Caps the headline (a member's name on Profile: 2 lines, 3 at large
  /// text), with an ellipsis. Null: no cap.
  final int? headlineMaxLines;

  /// Other headlines (lead, accent) this hero may show in its place: the
  /// headline keeps room for the tallest, so switching between them never
  /// changes the hero's height (Activity's sections, spec §24).
  final List<(String?, String?)> headlineReserve;

  /// Drawn above the eyebrow, inside the text zone, and left out of the
  /// heading's semantics (Profile's avatar, spec C-3).
  final Widget? leading;
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

  /// Lets the page's footer "Back to top" move focus to the heading (spec
  /// §32.1): focusable on request, but no extra Tab stop. Null: as before.
  final FocusNode? headingFocusNode;

  /// Leaves the heading out of the semantics tree, for a parent that reads
  /// the hero as one node with its own label (a carousel slide: "Banner 1
  /// of 3"). The actions stay separate buttons.
  final bool excludeHeadingSemantics;

  /// Under a fixed height (a carousel slide sized to the tallest), the text
  /// stays at the bottom over the scrim and the photo fills the rest. Off:
  /// the hero is as tall as its text needs, as before.
  final bool fillHeight;

  /// The panel's side padding instead of the default (room for arrows
  /// inside the photo's edges). Null: as before.
  final double? panelSidePad;

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
    ?subline,
    ?chip,
  ].join('\n');

  @override
  Widget build(BuildContext context) {
    final instant = MediaQuery.disableAnimationsOf(context);
    // Only large text scales change the height (C-4); under reduced motion
    // the new height applies at once.
    final hero = variant == FFHeroVariant.panel
        ? _panel(context)
        : instant
        ? _vertical(context)
        : AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _vertical(context),
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: rounded || variant == FFHeroVariant.band
          ? ClipRRect(
              borderRadius: BorderRadius.circular(FFTokens.radiusXl),
              child: hero,
            )
          : hero,
    );
  }

  Widget _vertical(BuildContext context) {
    final band = variant == FFHeroVariant.band;
    // A band is a card: its bottom edge stays at the text value, no melt.
    final dark = !band && Theme.of(context).brightness == Brightness.dark;
    final scrim = FFTokens.heroScrim;
    final hosted = FFPhotoBarHost.of(context);
    // Light theme: the sheet below overlaps the hero, so keep that strip
    // free of text and buttons. A band has no sheet over it.
    final bottomPad =
        FFTokens.spacingLg + (dark || band ? 0 : FFTokens.heroSheetOverlap);
    Widget fadeZone(Widget child) => CustomPaint(
      key: const Key('ff-hero-fade-zone'),
      painter: FFScrimPainter((size) => heroRampStops(size.height)),
      child: child,
    );
    final textZone = CustomPaint(
      key: const Key('ff-hero-text-zone'),
      painter: FFScrimPainter((size) => heroTextZoneStops(size.height)),
      child: Stack(
        children: [
          if (dark)
            // Dark theme: melt into the page ground over the
            // last 48px (text value -> 100%).
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
                      scrim.withValues(alpha: FFTokens.heroScrimGround),
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
    );
    return Stack(
      // fillHeight: a tight height reaches the body, so its photo-only
      // zone grows and the text keeps to the bottom.
      fit: fillHeight ? StackFit.passthrough : StackFit.loose,
      children: [
        Positioned.fill(
          child: _HeroPhotoLayer(photo: photo, networkImage: networkImage),
        ),
        // The status bar / app bar band, unless the page draws it.
        if (!hosted)
          Positioned.fill(
            child: CustomPaint(
              key: const Key('ff-hero-top-band'),
              painter: FFScrimPainter(
                (size) => heroTopBandStops(size.height, topInset),
              ),
            ),
          ),
        if (_tall)
          _HeroTallBody(
            key: const Key('ff-hero-body'),
            minHeight: minHeight,
            maxHeight: maxHeight,
            topInset: topInset,
            clearPhoto: clearPhoto,
            minClearPhoto: minClearPhoto,
            barHosted: hosted,
            children: [fadeZone(const SizedBox.shrink()), textZone],
          )
        else
          ConstrainedBox(
            key: const Key('ff-hero-body'),
            constraints: BoxConstraints(minHeight: minHeight),
            child: IntrinsicHeight(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Photo only: clear, then the soft lead-in to the ramp.
                  Expanded(child: fadeZone(SizedBox(height: topInset))),
                  textZone,
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// The tall layout ([clearPhoto] or [maxHeight] set).
  bool get _tall => clearPhoto > 0 || maxHeight.isFinite;

  /// The panel's left padding (and right): canon h1 panels get more room.
  double get _panelPad =>
      panelSidePad ?? (wideHeadline ? 64.0 : FFTokens.spacingXl);

  /// Width of the panel's text column in a panel [width] wide.
  double _panelTextWidth(double width) =>
      width.isFinite ? (width / 2 - _panelPad).clamp(240.0, 560.0) : 480.0;

  Widget _panel(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: _HeroPhotoLayer(photo: photo, networkImage: networkImage),
        ),
        // Left to right: the text column (and the logo above it) stays at
        // the text value or darker; past it the photo clears towards the
        // far edge.
        Positioned.fill(
          child: CustomPaint(
            key: const Key('ff-hero-panel-scrim'),
            painter: FFScrimPainter(
              (size) => heroPanelStops(
                size.width,
                _panelPad + _panelTextWidth(size.width),
              ),
              horizontal: true,
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: minHeight),
          child: LayoutBuilder(
            builder: (context, c) {
              final pad = _panelPad;
              final textWidth = _panelTextWidth(c.maxWidth);
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

    Widget headline(String? lead, String? acc, Key? key) => Text.rich(
      key: key,
      maxLines: headlineMaxLines,
      overflow: headlineMaxLines == null ? null : TextOverflow.ellipsis,
      TextSpan(
        children: [
          if (lead != null) TextSpan(text: acc == null ? lead : '$lead '),
          if (acc != null)
            TextSpan(
              text: acc,
              style: TextStyle(color: accent),
            ),
        ],
      ),
      style: headlineStyle,
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
        if (headlineReserve.isEmpty)
          headline(headlineLead, headlineAccent, const Key('ff-hero-headline'))
        else
          Stack(
            children: [
              // Invisible, same style: the tallest alternative sets the
              // height.
              for (final (l, a) in headlineReserve)
                Visibility(
                  visible: false,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: headline(l, a, null),
                ),
              headline(
                headlineLead,
                headlineAccent,
                const Key('ff-hero-headline'),
              ),
            ],
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

    final instant = MediaQuery.disableAnimationsOf(context);
    final textColumn = Column(
      key: const Key('ff-hero-text'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: text,
    );
    // Eyebrow, headline, subline and chip are read as one heading.
    final focus = headingFocusNode;
    Widget heading = focus == null
        ? Semantics(
            container: true,
            header: true,
            label: _semanticsLabel,
            excludeSemantics: true,
            child: textColumn,
          )
        : Focus(
            focusNode: focus,
            skipTraversal: true,
            includeSemantics: false,
            child: ListenableBuilder(
              listenable: focus,
              builder: (context, _) => Semantics(
                container: true,
                header: true,
                label: _semanticsLabel,
                excludeSemantics: true,
                focusable: true,
                focused: focus.hasFocus,
                // A visible ring while it holds focus.
                child: Container(
                  key: const Key('ff-hero-heading-focus'),
                  foregroundDecoration: focus.hasFocus
                      ? BoxDecoration(
                          border: Border.all(
                            color: FFTokens.heroText,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusSm,
                          ),
                        )
                      : null,
                  child: textColumn,
                ),
              ),
            ),
          );
    if (!instant) {
      // A new headline (Activity's sections) fades in over 200ms (C-4).
      heading = AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOut,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topLeft,
          children: [
            // The old text keeps its own height; the stack clips it.
            for (final p in previous)
              Positioned(left: 0, right: 0, top: 0, child: p),
            ?current,
          ],
        ),
        child: KeyedSubtree(key: ValueKey(_semanticsLabel), child: heading),
      );
    }
    if (excludeHeadingSemantics) heading = ExcludeSemantics(child: heading);
    if (leading != null) {
      final lead = ExcludeSemantics(
        child: KeyedSubtree(key: const Key('ff-hero-leading'), child: leading!),
      );
      heading = variant == FFHeroVariant.panel
          ? Row(
              children: [
                lead,
                const SizedBox(width: FFTokens.spacingMd),
                Expanded(child: heading),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                lead,
                const SizedBox(height: FFTokens.spacingSm + 4),
                heading,
              ],
            );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
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

/// One stop of a scrim gradient: where (0..1 along the gradient) and the
/// scrim's alpha there.
typedef ScrimStop = (double at, double alpha);

/// A vertical hero's fade zone, [height] px tall (the photo above the text
/// zone): clear, then the soft lead-in to [FFTokens.heroScrimLeadIn] over
/// its last [FFTokens.heroScrimLeadInLength] px.
List<ScrimStop> heroRampStops(double height) {
  const lead = FFTokens.heroScrimLeadIn;
  if (height <= 0) return const [(0, lead), (1, lead)];
  final len = math.min(FFTokens.heroScrimLeadInLength, height);
  return [(0, 0), (1 - len / height, 0), (1, lead)];
}

/// A text zone [height] px tall: from [FFTokens.heroScrimLeadIn] at its top
/// edge up to [FFTokens.heroScrimText] [FFTokens.heroScrimRampLength] px
/// down (where the first line of text starts), then at least that down to
/// [bottom] at the bottom edge.
List<ScrimStop> heroTextZoneStops(
  double height, {
  double bottom = FFTokens.heroScrimText,
}) {
  const text = FFTokens.heroScrimText;
  if (height <= 0) return [(0, text), (1, bottom)];
  final at = math.min(1.0, FFTokens.heroScrimRampLength / height);
  return [(0, FFTokens.heroScrimLeadIn), (at, text), (1, bottom)];
}

/// The status bar / app bar band on a hero [heroHeight] tall whose bar ends
/// [barBottom] px down (0: no bar): [FFTokens.heroScrimTop] held over the
/// bar, then faded to 0 by 16% of the height, and never sooner than
/// [FFTokens.heroScrimBarFade] below the bar.
List<ScrimStop> heroTopBandStops(double heroHeight, double barBottom) {
  const top = FFTokens.heroScrimTop;
  if (heroHeight <= 0) return const [(0, top), (1, 0)];
  final hold = barBottom.clamp(0.0, heroHeight) / heroHeight;
  final end = math.max(
    barBottom > 0 ? barBottom + FFTokens.heroScrimBarFade : 0.0,
    FFTokens.heroScrimTopFade * heroHeight,
  );
  final fadeEnd = math.min(1.0, end / heroHeight);
  return [(0, top), (hold, top), (math.max(hold, fadeEnd), 0), (1, 0)];
}

/// The bar band a page draws itself ([FFPhotoBarScrim]), [height] px tall
/// for a bar that ends [barBottom] px down.
List<ScrimStop> heroBarStops(double height, double barBottom) {
  const top = FFTokens.heroScrimTop;
  if (height <= 0) return const [(0, top), (1, 0)];
  return [(0, top), (math.min(1.0, barBottom / height), top), (1, 0)];
}

/// The panel scrim, left to right, for a panel [width] wide whose text
/// column ends [textRight] px from the left: [FFTokens.heroScrimPanelLead]
/// at the edge, at least [FFTokens.heroScrimText] until 24px past the text,
/// then down to [FFTokens.heroScrimPanelTail] at the far edge.
List<ScrimStop> heroPanelStops(double width, double textRight) {
  const lead = FFTokens.heroScrimPanelLead;
  const text = FFTokens.heroScrimText;
  if (width <= 0) return const [(0, lead), (1, text)];
  final hold = (textRight + FFTokens.spacingLg) / width;
  if (hold >= 1) return const [(0, lead), (1, text)];
  return [(0, lead), (hold, text), (1, FFTokens.heroScrimPanelTail)];
}

/// The scrim's alpha at [t] (0..1) along [stops].
double scrimAlphaAt(List<ScrimStop> stops, double t) {
  if (t <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    final (a0, v0) = stops[i - 1];
    final (a1, v1) = stops[i];
    if (t <= a1) {
      if (t == a1 || a1 == a0) return v1;
      return v0 + (v1 - v0) * (t - a0) / (a1 - a0);
    }
  }
  return stops.last.$2;
}

/// Paints a slate-950 scrim gradient whose stops depend on the painted
/// size (so the ramp keeps its pixel length at any hero height).
class FFScrimPainter extends CustomPainter {
  FFScrimPainter(this.stopsFor, {this.horizontal = false});

  final List<ScrimStop> Function(Size size) stopsFor;
  final bool horizontal;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (rect.isEmpty) return;
    final stops = stopsFor(size);
    final paint = Paint()
      ..shader = LinearGradient(
        begin: horizontal ? Alignment.centerLeft : Alignment.topCenter,
        end: horizontal ? Alignment.centerRight : Alignment.bottomCenter,
        colors: [
          for (final (_, a) in stops) FFTokens.heroScrim.withValues(alpha: a),
        ],
        stops: [for (final (at, _) in stops) at],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(FFScrimPainter old) =>
      old.horizontal != horizontal || old.stopsFor != stopsFor;
}

/// Marks content scrolling under a transparent app bar whose band the page
/// draws itself ([FFPhotoBarScrim]): heroes inside leave out their own.
class FFPhotoBarHost extends InheritedWidget {
  const FFPhotoBarHost({super.key, required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FFPhotoBarHost>() != null;

  @override
  bool updateShouldNotify(FFPhotoBarHost old) => false;
}

/// The band behind a transparent app bar over a photo hero, fixed to the
/// top of the screen so the bar's icons stay at 3:1 however far the hero
/// has scrolled: [FFTokens.heroScrimTop] down to [barBottom], then a
/// [FFTokens.heroScrimBarFade] fade. Hidden once the bar turns solid.
/// Put it above the page body (under the app bar) and the body in a
/// [FFPhotoBarHost].
class FFPhotoBarScrim extends StatelessWidget {
  const FFPhotoBarScrim({
    super.key,
    required this.barBottom,
    required this.visible,
  });

  final double barBottom;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: barBottom + FFTokens.heroScrimBarFade,
      child: IgnorePointer(
        child: ExcludeSemantics(
          child: AnimatedOpacity(
            key: const Key('ff-photo-bar-scrim'),
            opacity: visible ? 1 : 0,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 150),
            child: CustomPaint(
              painter: FFScrimPainter(
                (size) => heroBarStops(size.height, barBottom),
              ),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

/// Taller heroes (owner 2026-10-20, spec §5.3): the clear photo a phone
/// hero aims for in a viewport [viewportHeight] tall at [textScale], or 0
/// below [FFTokens.heroTallMinViewport] (those phones keep today's heights).
double heroTallClearTarget(double viewportHeight, double textScale) {
  if (viewportHeight < FFTokens.heroTallMinViewport) return 0;
  final base = (viewportHeight * FFTokens.heroTallClearShare).clamp(
    FFTokens.heroTallClearMin,
    FFTokens.heroTallClearMax,
  );
  // Larger text takes room from the photo first (never below 0).
  return base / math.max(1.0, textScale);
}

/// The height of a tall hero's photo-only zone above a text zone [text] px
/// tall: enough for [clearPhoto] px with no scrim between the bar band and
/// the lead-in, capped so the hero stays within [maxHeight] (the clear
/// photo gives way, the text does not), and never less than today's
/// layout gives ([minHeight], [topInset]).
///
/// The bar band ends [FFTokens.heroScrimBarFade] below [topInset] when the
/// page draws it ([barHosted], fixed at the top of the screen); otherwise
/// it is the hero's own ([heroTopBandStops]): at least 16% of the hero.
double heroTallFade({
  required double text,
  required double topInset,
  required bool barHosted,
  double clearPhoto = 0,
  double minHeight = 0,
  double maxHeight = double.infinity,
  double minClearPhoto = 0,
}) {
  var target = 0.0;
  if (clearPhoto > 0) {
    const lead = FFTokens.heroScrimLeadInLength;
    final bar = topInset > 0 ? topInset + FFTokens.heroScrimBarFade : 0.0;
    if (barHosted) {
      target = bar + clearPhoto + lead;
    } else {
      // fade - lead - max(bar, 16% of (fade + text)) >= clearPhoto
      const share = FFTokens.heroScrimTopFade;
      target = math.max(
        bar + clearPhoto + lead,
        (clearPhoto + lead + share * text) / (1 - share),
      );
    }
  }
  final today = math.max(topInset, minHeight - text);
  if (maxHeight.isFinite && target > maxHeight - text) {
    target = maxHeight - text;
    // Capped so far that no photo (or less than [minClearPhoto]) would be
    // clear: keep today's height rather than grow the hero for nothing
    // (and push the content down).
    final clear = heroTallClearOf(target, text, topInset, barHosted);
    if (clear <= 0 || clear < minClearPhoto) {
      return today;
    }
  }
  return math.max(today, target);
}

/// The clear photo (no scrim) a vertical hero shows with a photo-only zone
/// [fade] px tall over a text zone [text] px tall (see [heroTallFade]).
double heroTallClearOf(
  double fade,
  double text,
  double topInset,
  bool barHosted,
) {
  final bar = topInset > 0 ? topInset + FFTokens.heroScrimBarFade : 0.0;
  final bandEnd = barHosted
      ? bar
      : math.max(bar, FFTokens.heroScrimTopFade * (fade + text));
  return math.max(0, fade - FFTokens.heroScrimLeadInLength - bandEnd);
}

/// Lays out a tall hero's two zones: the text zone at its own height, the
/// photo-only zone above it sized by [heroTallFade].
class _HeroTallBody extends MultiChildRenderObjectWidget {
  const _HeroTallBody({
    super.key,
    required this.minHeight,
    required this.maxHeight,
    required this.topInset,
    required this.clearPhoto,
    required this.barHosted,
    required super.children,
    this.minClearPhoto = 0,
  }) : assert(children.length == 2);

  final double minHeight;
  final double maxHeight;
  final double topInset;
  final double clearPhoto;
  final double minClearPhoto;
  final bool barHosted;

  @override
  _RenderHeroTallBody createRenderObject(BuildContext context) =>
      _RenderHeroTallBody(
        minHeight: minHeight,
        maxHeight: maxHeight,
        topInset: topInset,
        clearPhoto: clearPhoto,
        minClearPhoto: minClearPhoto,
        barHosted: barHosted,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeroTallBody renderObject,
  ) {
    renderObject
      ..minHeight = minHeight
      ..maxHeight = maxHeight
      ..topInset = topInset
      ..clearPhoto = clearPhoto
      ..minClearPhoto = minClearPhoto
      ..barHosted = barHosted;
  }
}

class _HeroTallParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderHeroTallBody extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _HeroTallParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _HeroTallParentData> {
  _RenderHeroTallBody({
    required double minHeight,
    required double maxHeight,
    required double topInset,
    required double clearPhoto,
    required double minClearPhoto,
    required bool barHosted,
  }) : _minHeight = minHeight,
       _maxHeight = maxHeight,
       _topInset = topInset,
       _clearPhoto = clearPhoto,
       _minClearPhoto = minClearPhoto,
       _barHosted = barHosted;

  double _minHeight;
  set minHeight(double v) {
    if (v == _minHeight) return;
    _minHeight = v;
    markNeedsLayout();
  }

  double _maxHeight;
  set maxHeight(double v) {
    if (v == _maxHeight) return;
    _maxHeight = v;
    markNeedsLayout();
  }

  double _topInset;
  set topInset(double v) {
    if (v == _topInset) return;
    _topInset = v;
    markNeedsLayout();
  }

  double _clearPhoto;
  set clearPhoto(double v) {
    if (v == _clearPhoto) return;
    _clearPhoto = v;
    markNeedsLayout();
  }

  double _minClearPhoto;
  set minClearPhoto(double v) {
    if (v == _minClearPhoto) return;
    _minClearPhoto = v;
    markNeedsLayout();
  }

  bool _barHosted;
  set barHosted(bool v) {
    if (v == _barHosted) return;
    _barHosted = v;
    markNeedsLayout();
  }

  RenderBox get _fade => firstChild!;
  RenderBox get _text => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _HeroTallParentData) {
      child.parentData = _HeroTallParentData();
    }
  }

  double _fadeFor(double text, double minHeight) => heroTallFade(
    text: text,
    topInset: _topInset,
    barHosted: _barHosted,
    clearPhoto: _clearPhoto,
    minHeight: math.max(minHeight, _minHeight),
    maxHeight: _maxHeight,
    minClearPhoto: _minClearPhoto,
  );

  @override
  double computeMinIntrinsicWidth(double height) =>
      _text.getMinIntrinsicWidth(double.infinity);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _text.getMaxIntrinsicWidth(double.infinity);

  @override
  double computeMinIntrinsicHeight(double width) {
    final t = _text.getMinIntrinsicHeight(width);
    return t + _fadeFor(t, 0);
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    final t = _text.getMaxIntrinsicHeight(width);
    return t + _fadeFor(t, 0);
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final w = constraints.maxWidth;
    final t = _text.getDryLayout(BoxConstraints.tightFor(width: w)).height;
    return constraints.constrain(
      Size(w, t + _fadeFor(t, constraints.minHeight)),
    );
  }

  @override
  void performLayout() {
    final w = constraints.maxWidth;
    _text.layout(BoxConstraints.tightFor(width: w), parentUsesSize: true);
    final t = _text.size.height;
    final f = _fadeFor(t, constraints.minHeight);
    _fade.layout(BoxConstraints.tight(Size(w, f)));
    (_fade.parentData! as _HeroTallParentData).offset = Offset.zero;
    (_text.parentData! as _HeroTallParentData).offset = Offset(0, f);
    size = constraints.constrain(Size(w, f + t));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// The photo, or the navy placeholder: before it decodes, if it fails, and
/// always under high contrast. Never in the accessibility tree.
///
/// With admin-published photos on, each bundled [FFHeroPhoto] is looked up
/// once, the first time this layer shows it, and the answer is kept: a photo
/// saved while the screen is open shows only the next time the screen is
/// built (never a swap mid-view). If a saved photo fails to load, the
/// bundled one shows.
class _HeroPhotoLayer extends StatefulWidget {
  const _HeroPhotoLayer({this.photo, this.networkImage});

  final FFHeroPhoto? photo;
  final FFHeroNetworkImage? networkImage;

  @override
  State<_HeroPhotoLayer> createState() => _HeroPhotoLayerState();
}

class _HeroPhotoLayerState extends State<_HeroPhotoLayer> {
  final Map<FFHeroPhoto, RemoteHeroImage?> _resolved = {};

  RemoteHeroImage? _remoteFor(FFHeroPhoto photo) {
    if (_resolved.containsKey(photo)) return _resolved[photo];
    final r = HeroImageStore.instance?.resolveTop(photo);
    _resolved[photo] = r;
    return r;
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    // A network address the source check refuses counts as none: the
    // bundled photo shows when there is one, else the placeholder.
    final requested = widget.networkImage;
    final apiBase = mediaApiBaseOf(context);
    final refused =
        requested != null &&
        requested.url.isNotEmpty &&
        !isAllowedMediaSrc(requested.url, apiBase: apiBase);
    final networkImage = refused && photo != null ? null : requested;
    // A network hero with no file to load shows the placeholder alone.
    final noPhoto =
        MediaQuery.highContrastOf(context) ||
        (networkImage != null && (networkImage.url.isEmpty || refused));
    final instant = MediaQuery.disableAnimationsOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ExcludeSemantics(
      child: ColoredBox(
        key: const Key('ff-hero-placeholder'),
        color: FFTokens.heroPlaceholder,
        child: noPhoto
            ? const SizedBox.expand()
            : LayoutBuilder(
                builder: (context, c) {
                  final saved = photo == null ? null : _remoteFor(photo);
                  Widget bundled() => Image(
                    key: const Key('ff-hero-photo'),
                    image: heroImageProvider(photo!, c.biggest, dpr),
                    fit: BoxFit.cover,
                    alignment: photo.focal,
                    width: c.maxWidth,
                    height: c.maxHeight,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.expand(),
                  );
                  final image = Image(
                    key: const Key('ff-hero-photo'),
                    image: networkImage != null
                        ? heroNetworkImageProvider(
                            networkImage,
                            c.biggest,
                            dpr,
                            apiBase: apiBase,
                          )!
                        : saved != null
                        ? heroRemoteImageProvider(saved, c.biggest, dpr)
                        : heroImageProvider(photo!, c.biggest, dpr),
                    fit: BoxFit.cover,
                    alignment:
                        networkImage?.focal ?? saved?.focal ?? photo!.focal,
                    width: c.maxWidth,
                    height: c.maxHeight,
                    excludeFromSemantics: true,
                    gaplessPlayback: true,
                    // A network image that fails (or a saved remote one)
                    // falls back to the bundled photo when there is one.
                    errorBuilder: (_, _, _) =>
                        (networkImage != null && photo != null) || saved != null
                        ? bundled()
                        : const SizedBox.expand(),
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
                  );
                  // Under reduced motion the new photo replaces the old one in
                  // the same frame; otherwise they cross-fade (C-4).
                  if (instant) return image;
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    layoutBuilder: (current, previous) => Stack(
                      fit: StackFit.expand,
                      children: [...previous, ?current],
                    ),
                    child: KeyedSubtree(
                      key: ValueKey<Object?>(networkImage ?? photo),
                      child: image,
                    ),
                  );
                },
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
/// colour (3.04:1 on the 46% bar band over pure white).
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

/// An inset hero card for pages that keep a solid app bar (Upgrade plan,
/// partner homes, spec C-1): [FFHeroVariant.band] on phones, a rounded
/// [FFHeroVariant.panel] banner at 840 wide and up.
class FFHeroBand extends StatelessWidget {
  const FFHeroBand({
    super.key,
    required this.photo,
    this.minHeight = 200,
    this.wideHeight = 220,
    this.eyebrow,
    this.headlineLead,
    this.headlineAccent,
    this.headlineLoading = false,
    this.subline,
    this.actions = const [],
    this.headingFocusNode,
    this.networkImage,
    this.clearPhoto = 0,
    this.clearPhotoEverywhere = false,
    this.maxHeightAt844 = double.infinity,
  });

  /// The bundled photo; with [networkImage] set it is only the fallback.
  final FFHeroPhoto photo;

  /// Band heroes with photo above the text (owner 2026-10-22): the clear
  /// photo (no scrim) the band keeps between its top fade and the ramp to
  /// the text, at 1.0x text on phones from [FFTokens.heroTallMinViewport]
  /// tall (see [heroBandClear]). The band grows to fit it; the text stays
  /// on the [FFTokens.heroScrimText] zone. 0: as before. Ignored on the
  /// 840+ banner.
  final double clearPhoto;

  /// [clearPhoto] on every phone and at every text scale (Shop home: its
  /// first control sits above the band, and the FitFlex Africa sign must
  /// stay clear of the text). Off: only from 760 tall, divided by the text
  /// scale, like the taller heroes.
  final bool clearPhotoEverywhere;

  /// The tallest this band may grow for [clearPhoto] on a phone 844 tall,
  /// so the screen's first control stays above about 55% of the viewport
  /// (owner 2026-10-22); it moves with the viewport height at
  /// [FFTokens.heroBandControlShare] per px ([heroBandMaxHeight]). The
  /// clear photo gives way (never the text); below
  /// [FFTokens.heroBandMinClearPhoto] of it the band keeps today's height.
  final double maxHeightAt844;

  /// The subject's own photo from the network (an event cover, spec
  /// §11.5). Same scrim and typography; [photo] shows if it fails to load.
  final FFHeroNetworkImage? networkImage;

  /// Phone height (grows with text).
  final double minHeight;

  /// Banner height at 840 wide and up.
  final double wideHeight;
  final String? eyebrow;
  final String? headlineLead;
  final String? headlineAccent;
  final bool headlineLoading;
  final String? subline;
  final List<Widget> actions;
  final FocusNode? headingFocusNode;

  /// The screen's status bar height, from the view itself: under an app
  /// bar the page's MediaQuery no longer has it, but the band sits that
  /// much lower.
  static double _statusBar(BuildContext context) {
    final view = View.of(context);
    return view.padding.top / view.devicePixelRatio;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 840;
    return FFPhotoHero(
      photo: photo,
      networkImage: networkImage,
      variant: wide ? FFHeroVariant.panel : FFHeroVariant.band,
      rounded: wide,
      minHeight: wide ? wideHeight : minHeight,
      clearPhoto: wide
          ? 0
          : heroBandClear(
              clearPhoto,
              viewportHeight: size.height,
              textScale: MediaQuery.textScalerOf(context).scale(1),
              everywhere: clearPhotoEverywhere,
            ),
      maxHeight: wide
          ? double.infinity
          : heroBandMaxHeight(
              maxHeightAt844,
              size.height,
              statusBar: _statusBar(context),
            ),
      minClearPhoto: FFTokens.heroBandMinClearPhoto,
      eyebrow: eyebrow,
      headlineLead: headlineLead,
      headlineAccent: headlineAccent,
      headlineLoading: headlineLoading,
      subline: subline,
      actions: actions,
      headingFocusNode: headingFocusNode,
    );
  }
}

/// The clear photo a phone band (or section hero) keeps above its text
/// for a screen's [clearPhoto] (owner 2026-10-22): none below
/// [FFTokens.heroTallMinViewport] tall (those phones keep today's band, so
/// search and buttons stay where they are), and larger text takes room from
/// the photo first. With [everywhere], [clearPhoto] as is.
double heroBandClear(
  double clearPhoto, {
  required double viewportHeight,
  required double textScale,
  bool everywhere = false,
}) {
  if (clearPhoto <= 0) return 0;
  if (everywhere) return clearPhoto;
  if (viewportHeight < FFTokens.heroTallMinViewport) return 0;
  return clearPhoto / math.max(1.0, textScale);
}

/// A band's [maxHeightAt844] (measured on a 390x844 phone with a 47px
/// status bar) on a phone [viewportHeight] tall with a [statusBar] px
/// status bar: the first control keeps the same share of the screen
/// ([FFTokens.heroBandControlShare]); a taller status bar moves the band
/// down, so the band gives that back.
double heroBandMaxHeight(
  double maxHeightAt844,
  double viewportHeight, {
  double statusBar = 47,
}) => maxHeightAt844.isFinite
    ? maxHeightAt844 +
          FFTokens.heroBandControlShare * (viewportHeight - 844) -
          (statusBar - 47)
    : double.infinity;

/// "Good morning, Amina": the greeting for [now] and the first word of
/// [name] (no email address or phone number), or the greeting alone.
String heroGreeting(BuildContext context, DateTime now, String? name) {
  final greeting = context.tr(
    now.hour < 12
        ? 'member.goodMorning'
        : now.hour < 17
        ? 'member.goodAfternoon'
        : 'member.goodEvening',
  );
  final first = (name ?? '').trim().split(RegExp(r'\s+')).first;
  final usable =
      first.isNotEmpty &&
      !first.contains('@') &&
      !RegExp(r'^[+\d]').hasMatch(first);
  return usable ? '$greeting, $first' : greeting;
}
