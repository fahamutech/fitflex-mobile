import 'dart:convert';

import 'package:flutter/material.dart';

/// Global provider cache so the same URL always reuses the same ImageProvider
/// instance, avoiding unnecessary HTTP re-fetches across widget rebuilds.
final Map<String, ImageProvider> _remoteImageCache = {};

class FFRemoteImage extends StatefulWidget {
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
  State<FFRemoteImage> createState() => _FFRemoteImageState();
}

class _FFRemoteImageState extends State<FFRemoteImage>
    with AutomaticKeepAliveClientMixin {
  ImageProvider? _provider;
  bool _invalid = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _resolveProvider(widget.src);
  }

  @override
  void didUpdateWidget(FFRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src) {
      _provider = null;
      _invalid = false;
      _resolveProvider(widget.src);
    }
  }

  void _resolveProvider(String src) {
    if (_remoteImageCache.containsKey(src)) {
      _provider = _remoteImageCache[src];
      return;
    }
    final dataMatch = RegExp(r'^data:image/[^;]+;base64,(.+)$').firstMatch(src);
    if (dataMatch != null) {
      try {
        final bytes = base64Decode(dataMatch.group(1)!);
        _provider = MemoryImage(bytes);
        _remoteImageCache[src] = _provider!;
      } catch (_) {
        _invalid = true;
      }
    } else {
      _provider = NetworkImage(src);
      _remoteImageCache[src] = _provider!;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final fallbackWidget = widget.fallback ?? const Icon(Icons.broken_image);
    if (_invalid || _provider == null) return fallbackWidget;

    return Image(
      image: _provider!,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stackTrace) => fallbackWidget,
    );
  }
}
