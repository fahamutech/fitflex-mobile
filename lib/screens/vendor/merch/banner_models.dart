// Shop home Phase 2 · S1 (banners): a vendor's banner proposals, the text
// rules the form checks before the server does, and Tanzania-time helpers.
//
// Contract: fitflex-functions docs/shop-banners-api.md (feat/shop-banners,
// flag SHOP_BANNERS):
//   GET /vendor/shop-banners → {items, vendor: {canPropose, reason}, ...}
//   POST /vendor/shop-banners, PATCH /:id → {banner}
//   POST /:id/image (multipart: file, people, rightsConfirmed,
//   peopleConfirmed), POST /:id/submit | withdraw | end → {banner}
//   GET /vendor/tools/options → merch: {banners: bool}
//   Field errors carry {field: "<name>.<en|sw>"}.
import 'dart:typed_data';

import '../../../shared/shop_home.dart';

/// The bilingual text fields of a banner, in the form's order.
const bannerTextFields = [
  'imageAlt',
  'headlineLead',
  'headlineAccent',
  'subline',
  'ctaLabel',
];

/// Who a banner is shown to (`audienceRoles`); at least one.
const bannerAudiences = ['member', 'trainer', 'owner'];

/// Limits (docs/shop-banners-api.md). No maximum run length (owner).
const bannerHeadlineMax = {'en': 32, 'sw': 42};
const bannerSublineMax = {'en': 70, 'sw': 90};
const bannerCtaMax = {'en': 24, 'sw': 30};
const bannerAltMax = {'en': 160, 'sw': 200};
const bannerImageMaxBytes = 5 * 1024 * 1024;
const bannerImageMinWidth = 1600;
const bannerImageMinHeight = 1000;

/// One of the vendor's banners (the vendor view).
class VendorBanner {
  const VendorBanner({
    required this.id,
    required this.status,
    required this.text,
    this.publicImage = const ShopBannerImage(),
    this.previewUrl = '',
    this.hasImage = false,
    this.targetType = 'product',
    this.targetValue = '',
    this.targetName,
    this.audienceRoles = bannerAudiences,
    this.ctaLabelCustom = true,
    this.startsAt,
    this.endsAt,
    this.expiresAt,
    this.reason,
    this.reasonCode,
    this.endedByFitflex = false,
    this.allowedActions,
  });

  final String id;

  /// `effectiveStatus` (worked out by the server from the clock): draft,
  /// pending_approval, approved, live, ended, rejected, expired, withdrawn.
  final String status;

  /// field → {en, sw} for [bannerTextFields].
  final Map<String, ShopText> text;

  /// The published files (after approval), root-relative.
  final ShopBannerImage publicImage;

  /// The private preview (`/vendor/shop-banners/:id/image`, needs the
  /// session), root-relative; empty without a photo.
  final String previewUrl;
  final bool hasImage;
  final String targetType;
  final String targetValue;

  /// The linked product's name, when the server sends it.
  final String? targetName;
  final List<String> audienceRoles;

  /// Whether the button text was written by the vendor (else the default
  /// for the target).
  final bool ctaLabelCustom;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// When a pending proposal lapses (only while pending).
  final DateTime? expiresAt;

  /// `statusReason`: why it was rejected or ended (the vendor sees it).
  final String? reason;
  final String? reasonCode;
  final bool endedByFitflex;

  /// What the vendor may do now (edit, image, submit, withdraw, end). Null
  /// from a server that does not send it: worked out from [status].
  final List<String>? allowedActions;

  static DateTime? _date(Object? v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toUtc();

  static String? _str(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  factory VendorBanner.fromJson(Map<String, dynamic> json) {
    final target = json['target'] is Map ? json['target'] as Map : const {};
    final image = json['image'] is Map ? json['image'] as Map : null;
    final roles = json['audienceRoles'] is List
        ? [
            for (final r in json['audienceRoles'] as List)
              if (bannerAudiences.contains(r)) r.toString(),
          ]
        : bannerAudiences;
    final actions = json['allowedActions'];
    return VendorBanner(
      id: json['id']?.toString() ?? '',
      status:
          (json['effectiveStatus'] ?? json['status'])?.toString() ?? 'draft',
      text: {
        for (final f in bannerTextFields)
          if (ShopText.fromJson(json[f]) != null)
            f: ShopText.fromJson(json[f])!,
      },
      publicImage: ShopBannerImage.fromJson(image?['public']),
      previewUrl: _str(image?['previewUrl']) ?? '',
      hasImage: image != null,
      targetType: target['type']?.toString() ?? 'product',
      targetValue: target['value'] is String ? target['value'] as String : '',
      targetName: _str(json['targetName']),
      audienceRoles: roles.isEmpty ? bannerAudiences : roles,
      ctaLabelCustom: json['ctaLabelCustom'] != false,
      startsAt: _date(json['startsAt']),
      endsAt: _date(json['endsAt']),
      expiresAt: _date(json['expiresAt']),
      reason: _str(json['statusReason']),
      reasonCode: _str(json['statusReasonCode']),
      endedByFitflex: json['endedByFitflex'] == true,
      allowedActions: actions is List
          ? [for (final a in actions) a.toString()]
          : null,
    );
  }

  bool _may(String action, Set<String> fallback) =>
      allowedActions?.contains(action) ?? fallback.contains(status);

  /// Edit (an approved or live one goes back for approval).
  bool get canEdit => _may('edit', const {
    'draft',
    'pending_approval',
    'approved',
    'live',
    'rejected',
  });
  bool get canSubmit => _may('submit', const {'draft'});
  bool get canWithdraw =>
      _may('withdraw', const {'draft', 'pending_approval', 'approved'});
  bool get canEnd => _may('end', const {'live'});

  /// Editing sends it back for approval (it leaves the shop meanwhile).
  bool get editResends => status == 'approved' || status == 'live';

  String headline(String lang) {
    String of(String f) => text[f]?.of(lang).trim() ?? '';
    return [
      of('headlineLead'),
      of('headlineAccent'),
    ].where((s) => s.isNotEmpty).join(' ');
  }
}

/// The list group a status falls in.
String bannerGroup(String status) => switch (status) {
  'live' => 'live',
  'approved' => 'scheduled',
  'pending_approval' => 'waiting',
  'draft' => 'drafts',
  _ => 'past',
};

const bannerGroups = ['live', 'scheduled', 'waiting', 'drafts', 'past'];

/// The i18n key for a status label.
String bannerStatusKey(String status) => switch (status) {
  'pending_approval' => 'merch.status.pending',
  'approved' ||
  'live' ||
  'ended' ||
  'rejected' ||
  'expired' ||
  'withdrawn' ||
  'draft' => 'merch.status.$status',
  _ => 'merch.status.draft',
};

// Prices, discounts and amounts (DD-P2-2): a percent sign, "/=", a currency
// word or sign, an amount with thousands separators ("50,000"), "20 off",
// the words for percent. ("5K run" is allowed: it is a distance.)
final _priceRule = RegExp(
  r'%|/=|\$|€|£'
  r'|\b(tsh|tshs|tzs|ksh|kshs|usd|shs?|shilingi|sh\.)\b'
  r'|\b(percent|per\s?cent|asilimia)\b'
  r'|\b\d{1,3}([,.]\d{3})+\b'
  r'|\b\d+\s?(off|punguzo)\b'
  r'|\b(bei|price)\s*[:=]?\s*\d',
  caseSensitive: false,
);

// Links (a scheme, www., or a web address) and phone numbers (9+ digits).
final _linkRule = RegExp(
  r'(https?://|www\.)|\b[a-z0-9-]+\.(com|co\.tz|tz|net|org|shop|store)\b',
  caseSensitive: false,
);
final _phoneRule = RegExp(r'\+?\d[\d\s().-]{7,}\d');

/// What is wrong with a banner [text] under the text rule: `price`,
/// `contact`, or null when it is fine. The server checks it again
/// (`price_claim_in_text`).
String? bannerTextProblem(String text) {
  final t = text.trim();
  if (t.isEmpty) return null;
  if (_priceRule.hasMatch(t)) return 'price';
  if (_linkRule.hasMatch(t)) return 'contact';
  for (final m in _phoneRule.allMatches(t)) {
    if (m.group(0)!.replaceAll(RegExp(r'\D'), '').length >= 9) {
      return 'contact';
    }
  }
  return null;
}

/// A photo picked for a banner, with its size when it could be decoded.
class PickedBannerImage {
  const PickedBannerImage({
    required this.bytes,
    required this.filename,
    this.mimeType,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String filename;
  final String? mimeType;
  final int? width;
  final int? height;

  static const _types = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
  };

  bool get allowedType {
    final mime = (mimeType ?? '').toLowerCase();
    if (_types.values.contains(mime)) return true;
    if (mime.isNotEmpty && mime != 'application/octet-stream') return false;
    final ext = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    return _types.containsKey(ext);
  }

  /// The form's message key for what is wrong, or null.
  String? get problemKey {
    if (!allowedType) return 'merch.banner.imageType';
    if (bytes.length > bannerImageMaxBytes) return 'merch.banner.imageWeight';
    if (width == null || height == null) return 'merch.banner.imageType';
    if (width! < bannerImageMinWidth || height! < bannerImageMinHeight) {
      return 'merch.banner.imageSize';
    }
    return null;
  }
}

/// Tanzania is UTC+3 all year.
const eatOffset = Duration(hours: 3);

/// [utc] as a Tanzania wall-clock time (a non-UTC DateTime, which the app's
/// formatters print as it is).
DateTime toEatWallClock(DateTime utc) {
  final e = utc.toUtc().add(eatOffset);
  return DateTime(e.year, e.month, e.day, e.hour, e.minute);
}

/// A Tanzania wall-clock date and time as the UTC instant it is.
DateTime fromEatWallClock(int year, int month, int day, int hour, int minute) =>
    DateTime.utc(year, month, day, hour, minute).subtract(eatOffset);
