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

/// The fixed buttons a vendor picks from (`ctaKey`), and the app's words
/// for each. A typed button text is refused (422 cta_label_not_allowed).
const bannerCtaKeys = {
  'view_product': 'shop.banner.cta.viewProduct',
  'visit_store': 'shop.banner.cta.visitStore',
  'shop_now': 'shop.banner.cta.shopNow',
  'view_all': 'shop.banner.cta.viewAll',
};

/// The button for a target: vendors may only send this one (else
/// 422 invalid_cta_key); shop_now / view_all are FitFlex's.
String defaultCtaKey(String targetType) =>
    targetType == 'vendor_store' ? 'visit_store' : 'view_product';

/// Rejection codes staff choose from (the vendor sees the label + note).
const bannerRejectCodes = {'image', 'people', 'text', 'claim', 'link', 'other'};

/// The confirmation texts the uploader accepts (`confirmation` in the list
/// answer): shown exactly as sent, in the user's language. [version] goes
/// with the photo (`confirmationVersion`).
class BannerConfirmation {
  const BannerConfirmation({
    required this.version,
    this.draft = false,
    this.rights,
    this.models,
  });

  final String version;

  /// `status: draft_pending_counsel`: wording not final.
  final bool draft;
  final ShopText? rights;
  final ShopText? models;

  static BannerConfirmation? fromJson(Object? json) {
    if (json is! Map) return null;
    final version = json['version']?.toString() ?? '';
    if (version.isEmpty) return null;
    return BannerConfirmation(
      version: version,
      draft: json['status']?.toString() == 'draft_pending_counsel',
      rights: ShopText.fromJson(json['rights']),
      models: ShopText.fromJson(json['models']),
    );
  }
}

/// Max length of the model release and licence references.
const bannerRefMax = 200;

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
    this.reasonCode,
    this.reasonNote,
    this.ctaKey,
    this.endedByFitflex = false,
    this.allowedActions,
    this.endedAt,
  });

  /// When it actually ended (early or at its end time).
  final DateTime? endedAt;

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

  /// Why it was rejected, ended or expired: `statusReason` (a code: a
  /// rejection code, ended_by_fitflex, window_passed, ...) and
  /// `statusReasonNote` (staff's words, shown as written).
  final String? reasonCode;
  final String? reasonNote;

  /// The chosen button (`ctaKey`), when the server sends it.
  final String? ctaKey;

  /// The words for a rejection code, or null for another code.
  String? get rejectLabelKey => bannerRejectCodes.contains(reasonCode)
      ? 'merch.reject.$reasonCode'
      : null;
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
      // statusReason is the code; an older server sent the code in
      // statusReasonCode and the words in statusReason.
      reasonCode: _str(json['statusReasonCode']) ?? _str(json['statusReason']),
      reasonNote:
          _str(json['statusReasonNote']) ??
          (json['statusReasonCode'] != null
              ? _str(json['statusReason'])
              : null),
      ctaKey: bannerCtaKeys.containsKey(json['ctaKey'])
          ? json['ctaKey'] as String
          : null,
      endedByFitflex: json['endedByFitflex'] == true,
      endedAt: _date(json['endedAt']),
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

// The text rules, copied pattern for pattern from the server's
// src/shared/shop-banner-rules.mjs (functions#227 at 5ff99b1), so the form
// refuses what the server refuses. The server decides: anything this
// misses still comes back as price_claim_in_text / contact_in_text {field}
// and is shown under that field.
//
// Normalisation: the server uses NFKC, then removes format characters
// (\p{Cf}) and collapses whitespace. Dart has no NFKC; [normaliseBannerText]
// maps the forms that matter here the same way (fullwidth ASCII U+FF01–FF5E
// and the ideographic space), then does the same \p{Cf} and whitespace
// steps. Arabic-Indic and other digits are matched by \p{Nd}, as on the
// server.
String normaliseBannerText(String v) {
  final mapped = String.fromCharCodes(
    v.runes.map(
      (r) => r >= 0xFF01 && r <= 0xFF5E
          ? r - 0xFEE0
          : r == 0x3000
          ? 0x20
          : r,
    ),
  );
  return mapped
      .replaceAll(RegExp(r'\p{Cf}', unicode: true), '')
      .replaceAll(RegExp(r'\s+', unicode: true), ' ')
      .trim();
}

const _notLetterBefore = r'(?<![\p{L}])';
const _notLetterAfter = r'(?![\p{L}])';

RegExp _u(String source, {bool ci = false}) =>
    RegExp(source, unicode: true, caseSensitive: !ci);

final _pricePatterns = [
  _u(r'[%٪﹪]'),
  _u(r'/='),
  _u(r'\p{Nd}\s*/-'),
  _u(
    '$_notLetterBefore(?:tsh|tshs|tzs|ksh|kshs|shs?|sh)\\.?\\s*\\p{Nd}',
    ci: true,
  ),
  _u(
    '\\p{Nd}[\\p{Nd},.\\s]*\\s*(?:tsh|tshs|tzs|ksh|shs?|shilingi|bob)$_notLetterAfter',
    ci: true,
  ),
  _u(
    '$_notLetterBefore(?:shilingi|asilimia|percent|per\\s*cent|pct|elfu|laki|milioni|million|punguzo|bure|nusu\\s*bei|half\\s*price|discount)$_notLetterAfter',
    ci: true,
  ),
  _u('$_notLetterBefore(?:bei|price)\\s*:?\\s*\\p{Nd}', ci: true),
  _u(r'\p{Nd}{1,3}(?:[,.]\p{Nd}{3})+'),
  _u(r'\p{Nd}{4,}'),
];

const _tlds =
    'com|net|org|info|biz|shop|store|app|io|me|co|tz|ke|ug|rw|bi|africa|online|site|website|xyz|link|ly|tv|club|fit|fitness';

final _contactPatterns = [
  _u(r'https?://', ci: true),
  _u(r'www\.', ci: true),
  _u('[\\p{L}\\p{Nd}-]+\\.(?:$_tlds)(?![\\p{L}\\p{Nd}-])', ci: true),
  _u('$_notLetterBefore(?:dot|nukta)\\s*(?:$_tlds)$_notLetterAfter', ci: true),
  _u(r'(?:^|[^\p{L}\p{Nd}])@[\p{L}\p{Nd}_.]{2,}'),
  _u(r'\+?\s*25[45][\s-]?\p{Nd}{2,3}[\s-]?\p{Nd}{3}[\s-]?\p{Nd}{3}'),
  _u(r'(?<!\p{Nd})0[167]\p{Nd}{2}[\s-]?\p{Nd}{3}[\s-]?\p{Nd}{3}(?!\p{Nd})'),
  _u(r'\p{Nd}(?:[\s-]?\p{Nd}){8,}'),
];

/// What is wrong with a banner [text] under the server's text rules:
/// `contact` (checked first, as the server does), `price`, or null.
String? bannerTextProblem(String text) {
  final t = normaliseBannerText(text);
  if (t.isEmpty) return null;
  // Links and phone numbers first, as the server checks them (so a phone
  // number gets "Remove links and phone numbers", not the price message).
  if (_contactPatterns.any((re) => re.hasMatch(t))) return 'contact';
  if (_pricePatterns.any((re) => re.hasMatch(t))) return 'price';
  return null;
}

/// The message for `422 target_not_eligible {reason}`.
String targetIneligibleKey(Object? body) {
  final reason = body is Map ? body['reason']?.toString() : null;
  return switch (reason) {
    'product_not_listed' => 'merch.ineligible.productNotListed',
    'vendor_suspended' => 'merch.suspended',
    'vendor_not_approved' => 'merch.pendingBody',
    'vendor_not_found' => 'merch.notYours',
    _ => 'merch.ineligible.generic',
  };
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
