import 'dart:convert';

import 'package:flutter/material.dart';

class FFRemoteImage extends StatefulWidget {
  const FFRemoteImage({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.fit,
    this.fallback,
    this.headers,
  });

  final String src;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? fallback;

  /// Sent with a network image request (a private preview that needs the
  /// signed-in session, e.g. a vendor's own banner photo before approval).
  final Map<String, String>? headers;

  @override
  State<FFRemoteImage> createState() => _FFRemoteImageState();
}

class _FFRemoteImageState extends State<FFRemoteImage> {
  ImageProvider? _provider;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    _resolveProvider(widget.src);
  }

  @override
  void didUpdateWidget(FFRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src ||
        oldWidget.headers?['authorization'] !=
            widget.headers?['authorization']) {
      _provider = null;
      _invalid = false;
      _resolveProvider(widget.src);
    }
  }

  void _resolveProvider(String src) {
    final dataMatch = RegExp(r'^data:image/[^;]+;base64,(.+)$').firstMatch(src);
    if (dataMatch != null) {
      try {
        final bytes = base64Decode(dataMatch.group(1)!);
        _provider = MemoryImage(bytes);
      } catch (_) {
        _invalid = true;
      }
    } else {
      _provider = NetworkImage(src, headers: widget.headers);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fallbackWidget = widget.fallback ?? const Icon(Icons.broken_image);
    if (_invalid || _provider == null) return fallbackWidget;

    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = widget.width?.isFinite == true
        ? (widget.width! * pixelRatio).round()
        : null;
    final cacheHeight = widget.height?.isFinite == true
        ? (widget.height! * pixelRatio).round()
        : null;
    final image = ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      _provider!,
    );

    return Image(
      image: image,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => fallbackWidget,
    );
  }
}
