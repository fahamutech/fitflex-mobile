import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import 'partner_media_models.dart';

/// A picked photo or logo: the original bytes (sent as they are; the server
/// cleans them) and what the phone could read about it.
@immutable
class PickedPartnerImage {
  const PickedPartnerImage({
    required this.bytes,
    required this.filename,
    this.type,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String filename;

  /// The type read from the file's first bytes (never its name), e.g.
  /// `image/jpeg`; `image/svg+xml` for an SVG; null when unknown.
  final String? type;

  /// Upright pixel size, when the phone could read it.
  final int? width;
  final int? height;

  double get aspect =>
      (width ?? 0) > 0 && (height ?? 0) > 0 ? width! / height! : 1.5;
}

/// A refusal before any request (spec §42.1 step 2): the §44.1 error code
/// and its placeholders.
@immutable
class PartnerMediaProblem {
  const PartnerMediaProblem(this.code, [this.values = const {}]);

  final String code;
  final Map<String, Object> values;

  @override
  bool operator ==(Object other) =>
      other is PartnerMediaProblem &&
      other.code == code &&
      mapEquals(other.values, values);

  @override
  int get hashCode => Object.hash(code, values.length);

  @override
  String toString() => 'PartnerMediaProblem($code, $values)';
}

/// The image type of [bytes] from its signature, or null.
String? sniffImageType(List<int> bytes) {
  bool at(int i, List<int> sig) {
    if (bytes.length < i + sig.length) return false;
    for (var k = 0; k < sig.length; k++) {
      if (bytes[i + k] != sig[k]) return false;
    }
    return true;
  }

  if (at(0, const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (at(0, const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return 'image/webp';
  if (at(0, 'GIF8'.codeUnits)) return 'image/gif';
  if (at(4, 'ftyp'.codeUnits) && bytes.length >= 12) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12)).toLowerCase();
    if (const {
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
    }.contains(brand)) {
      return 'image/heic';
    }
    if (const {'mif1', 'msf1', 'heif'}.contains(brand)) return 'image/heif';
  }
  // SVG (or any XML): text that opens with "<", with "<svg" near the start.
  final head = String.fromCharCodes(
    bytes.take(1024).where((b) => b < 0x80),
  ).trimLeft().toLowerCase();
  if (head.startsWith('<') && head.contains('<svg')) return 'image/svg+xml';
  return null;
}

/// What is wrong with [picked] as a [kind] (`hero` or `logo`) under
/// [limits] (from the server), or null. A size the phone could not read
/// (some HEIC files) is left to the server.
PartnerMediaProblem? partnerMediaProblem(
  String kind,
  PickedPartnerImage picked,
  PartnerMediaLimits limits,
) {
  final logo = kind == 'logo';
  final type = picked.type;
  if (type == 'image/svg+xml') {
    return const PartnerMediaProblem('svg_not_allowed');
  }
  final types = logo ? limits.logoTypes : limits.heroTypes;
  if (type == null || !types.contains(type)) {
    return const PartnerMediaProblem('unsupported_file_type');
  }
  final maxBytes = logo ? limits.logoMaxBytes : limits.heroMaxBytes;
  if (picked.bytes.length > maxBytes) {
    return PartnerMediaProblem('file_too_large', {'maxMb': _mb(maxBytes)});
  }
  final w = picked.width;
  final h = picked.height;
  if (w == null || h == null) return null;
  if (logo) {
    // Over the largest side (logoMaxSide) is left to the server: the app has
    // no message that names a pixel limit.
    if (math.min(w, h) < limits.logoMinSide) {
      return PartnerMediaProblem('image_too_small_logo', {
        'minSide': limits.logoMinSide,
      });
    }
  } else if (w < limits.heroMinWidth) {
    return PartnerMediaProblem('image_too_small', {
      'minWidth': limits.heroMinWidth,
    });
  }
  return null;
}

String _mb(int bytes) {
  final mb = bytes / (1024 * 1024);
  return mb == mb.roundToDouble()
      ? mb.round().toString()
      : mb.toStringAsFixed(1);
}

/// The picture's pixel size from its header, without decoding it in full
/// where the platform can (phones); on the web it is decoded once at a
/// small size. Null when it can't be read.
Future<({int width, int height})?> readImageSize(Uint8List bytes) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    try {
      final d = await ui.ImageDescriptor.encoded(buffer);
      final out = (width: d.width, height: d.height);
      d.dispose();
      buffer.dispose();
      return out.width > 0 && out.height > 0 ? out : null;
    } catch (_) {
      // The web has no descriptor: decode a small copy and keep the size.
      var w = 0;
      var h = 0;
      final codec = await ui.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: (iw, ih) {
          w = iw;
          h = ih;
          return const ui.TargetImageSize(width: 64);
        },
      );
      codec.dispose();
      return w > 0 && h > 0 ? (width: w, height: h) : null;
    }
  } catch (_) {
    return null;
  }
}

/// The plate "Automatic" picks for a logo, worked out on the phone with the
/// server's rule (spec §40.2): the alpha-weighted mean relative luminance
/// of its pixels (at 128 px fit-inside) above 0.6 → dark. Null when the
/// logo can't be read; the server's answer wins either way.
Future<bool?> logoWantsDarkPlate(Uint8List bytes) async {
  final lum = await logoLuminance(bytes);
  return lum == null ? null : lum > 0.6;
}

Future<double?> logoLuminance(Uint8List bytes) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (w, h) => w >= h
          ? const ui.TargetImageSize(width: 128)
          : const ui.TargetImageSize(height: 128),
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(
      format: ui.ImageByteFormat.rawStraightRgba,
    );
    if (data == null) return null;
    return luminanceOfRgba(data.buffer.asUint8List());
  } catch (_) {
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}

/// Alpha-weighted mean relative luminance of straight RGBA [rgba]
/// (transparent pixels don't count; all transparent → 0).
double luminanceOfRgba(Uint8List rgba) {
  double lin(int c) {
    final v = c / 255;
    return v <= 0.04045
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  var sum = 0.0;
  var weight = 0.0;
  for (var p = 0; p + 3 < rgba.length; p += 4) {
    final a = rgba[p + 3] / 255;
    if (a == 0) continue;
    sum +=
        a *
        (0.2126 * lin(rgba[p]) +
            0.7152 * lin(rgba[p + 1]) +
            0.0722 * lin(rgba[p + 2]));
    weight += a;
  }
  return weight == 0 ? 0 : sum / weight;
}
