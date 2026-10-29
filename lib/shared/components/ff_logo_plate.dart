import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// A partner logo on its contrast plate (spec §40.2): light (white) for dark
/// or coloured logos, dark (navy) for light or white ones. 40 tall, the logo
/// fit inside 108 x 28 with its aspect kept, 6px each side, at most 120
/// wide. Never announced (the band's eyebrow already names the business or
/// greets) and never tappable. Fades in with its logo (instant under reduced
/// motion); a logo that fails to load shows no plate at all.
class FFLogoPlate extends StatelessWidget {
  const FFLogoPlate({
    super.key,
    required this.image,
    required this.aspect,
    required this.dark,
    this.scale = 1,
  });

  final ImageProvider image;

  /// The logo's width / height.
  final double aspect;

  /// The dark plate.
  final bool dark;

  /// 2: the sheet's large swatches (80 tall).
  final double scale;

  /// The drawn logo and the plate width for a logo of [aspect], at 1x.
  static ({double logoWidth, double logoHeight, double plateWidth}) sizeFor(
    double aspect,
  ) {
    final a = aspect.isFinite && aspect > 0 ? aspect : 1.0;
    const maxW = FFTokens.logoPlateLogoMaxWidth;
    const maxH = FFTokens.logoPlateLogoMaxHeight;
    final w = a >= maxW / maxH ? maxW : maxH * a;
    final h = a >= maxW / maxH ? maxW / a : maxH;
    final plate = (w + 2 * FFTokens.logoPlatePad).clamp(
      FFTokens.logoPlateMinWidth,
      FFTokens.logoPlateMaxWidth,
    );
    return (logoWidth: w, logoHeight: h, plateWidth: plate);
  }

  @override
  Widget build(BuildContext context) {
    final s = sizeFor(aspect);
    final hc = MediaQuery.highContrastOf(context);
    final instant = MediaQuery.disableAnimationsOf(context);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final border = dark
        ? Border.all(
            color: hc
                ? FFTokens.logoPlateDarkBorderStrong
                : FFTokens.logoPlateDarkBorder,
          )
        // On the navy high-contrast ground the white plate needs no edge.
        : hc
        ? null
        : Border.all(color: FFTokens.logoPlateLightBorder);
    final cacheWidth = (s.logoWidth * scale * dpr).ceil();
    return ExcludeSemantics(
      child: IgnorePointer(
        child: Image(
          key: const Key('ff-logo-plate-image'),
          image: ResizeImage.resizeIfNeeded(
            cacheWidth > 0 ? cacheWidth : null,
            null,
            image,
          ),
          width: s.logoWidth * scale,
          height: s.logoHeight * scale,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => const SizedBox.shrink(),
          frameBuilder: (context, child, frame, sync) => AnimatedOpacity(
            opacity: sync || frame != null ? 1 : 0,
            duration: instant
                ? Duration.zero
                : const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: Container(
              key: const Key('ff-logo-plate'),
              width: s.plateWidth * scale,
              height: FFTokens.logoPlateHeight * scale,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: dark ? FFTokens.logoPlateDark : FFTokens.logoPlateLight,
                border: border,
                borderRadius: BorderRadius.circular(FFTokens.radiusSm * scale),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
