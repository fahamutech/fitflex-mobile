import 'package:flutter/material.dart';

import '../media/media_src.dart';

/// A server-supplied photo (gym, trainer, vendor, product, event, profile).
///
/// Only sources [resolveMediaSrc] allows are drawn: checked data URIs, our
/// own `/storage/...` paths and API-host addresses, bundled assets, and with
/// [profilePhoto] also Google sign-in photos. Anything else shows [fallback]
/// and makes no network request (fitflex-functions#273).

class FFRemoteImage extends StatefulWidget {
  const FFRemoteImage({
    super.key,
    required this.src,
    this.width,
    this.height,
    this.fit,
    this.fallback,
    this.headers,
    this.profilePhoto = false,
  });

  final String src;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final Widget? fallback;

  /// Sent with a network image request (a private preview that needs the
  /// signed-in session, e.g. a vendor's own banner photo before approval).
  /// Only ever sent to the API host.
  final Map<String, String>? headers;

  /// A person's own photo (avatar, trainer photo): also allows the Google
  /// sign-in photo host the server copies into `photoUrl`.
  final bool profilePhoto;

  @override
  State<FFRemoteImage> createState() => _FFRemoteImageState();
}

class _FFRemoteImageState extends State<FFRemoteImage> {
  ImageProvider? _provider;
  bool _invalid = false;
  String? _apiBase;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The API base of the app's ApiClient (AppScope), else the configured one.
    final base = mediaApiBaseOf(context);
    if (base != _apiBase || (_provider == null && !_invalid)) {
      _apiBase = base;
      _resolveProvider(widget.src);
    }
  }

  @override
  void didUpdateWidget(FFRemoteImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src ||
        oldWidget.profilePhoto != widget.profilePhoto ||
        oldWidget.headers?['authorization'] !=
            widget.headers?['authorization']) {
      _provider = null;
      _invalid = false;
      _resolveProvider(widget.src);
    }
  }

  void _resolveProvider(String src) {
    _provider = mediaImageProvider(
      src,
      apiBase: _apiBase,
      profilePhoto: widget.profilePhoto,
      headers: widget.headers,
    );
    _invalid = _provider == null;
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
