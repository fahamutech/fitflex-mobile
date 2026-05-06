import 'dart:convert';

import 'package:flutter/material.dart';

class FFRemoteImage extends StatelessWidget {
  const FFRemoteImage({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.fit,
    this.fallback,
  });

  final String src;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final fallbackWidget = fallback ?? const Icon(Icons.broken_image);
    final dataMatch = RegExp(r'^data:image/[^;]+;base64,(.+)$').firstMatch(src);
    if (dataMatch != null) {
      try {
        return Image.memory(
          base64Decode(dataMatch.group(1)!),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => fallbackWidget,
        );
      } catch (_) {
        return fallbackWidget;
      }
    }

    return Image.network(
      src,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => fallbackWidget,
    );
  }
}
