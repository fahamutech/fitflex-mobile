import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The partner a home belongs to (spec §40.4): the picked gym for owners and
/// gym staff, the trainer's own profile, the vendor (for vendor staff too).
/// [accountId] is the signed-in persona, so a saved copy is never shown to
/// another account on the same phone.
@immutable
class PartnerMediaSubject {
  const PartnerMediaSubject._(this.side, this.accountId, this.gymId);

  /// An owner's or gym staff member's home for [gymId].
  factory PartnerMediaSubject.gym(String accountId, String gymId) =>
      PartnerMediaSubject._('gym', accountId, gymId);

  /// A trainer's own home.
  factory PartnerMediaSubject.trainer(String accountId) =>
      PartnerMediaSubject._('trainer', accountId, null);

  /// A vendor's (or vendor staff member's) Products tab.
  factory PartnerMediaSubject.vendor(String accountId) =>
      PartnerMediaSubject._('vendor', accountId, null);

  /// `gym`, `trainer` or `vendor`.
  final String side;
  final String accountId;
  final String? gymId;

  /// Where it is kept on the phone.
  String get key => [accountId, side, ?gymId].join('|');

  @override
  bool operator ==(Object other) =>
      other is PartnerMediaSubject && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => key;
}

/// The side of the app [userType] works on for partner media, or null.
String? partnerMediaSideOf(String? userType) => switch (userType) {
  'gym_operator' || 'gym_staff' => 'gym',
  'trainer' => 'trainer',
  'vendor' || 'vendor_staff' => 'vendor',
  _ => null,
};

/// The settings page address for [side] (spec §41.1).
String partnerMediaRoute(String side, {String? gymId}) => switch (side) {
  'gym' =>
    gymId == null || gymId.isEmpty
        ? '/owner/brand-media'
        : Uri(
            path: '/owner/brand-media',
            queryParameters: {'gymId': gymId},
          ).toString(),
  'trainer' => '/trainer/brand-media',
  _ => '/vendor/brand-media',
};

/// One photo or logo (`MediaItem`, fitflex-functions docs/partner-media-api.md).
@immutable
class PartnerMediaItem {
  const PartnerMediaItem({
    required this.id,
    required this.kind,
    required this.status,
    this.origin = 'partner',
    this.width = 0,
    this.height = 0,
    this.focalX = 0,
    this.focalY = 0,
    this.bright = false,
    this.plate = 'light',
    this.plateChoice = 'auto',
    this.files = const {},
    this.bytes = const {},
    this.takedownReason,
    this.takedownNote,
    this.createdAt,
    this.revision = 0,
  });

  final String id;

  /// `hero` or `logo`.
  final String kind;

  /// `live`, `replaced`, `removed` or `taken_down`.
  final String status;

  /// `partner` or `fitflex` (set by FitFlex for this partner).
  final String origin;
  final int width;
  final int height;

  /// The point that stays in view, -1..1 each (Flutter's [Alignment]).
  final double focalX;
  final double focalY;

  /// A bright photo: the scrim behind the text looks a little darker.
  final bool bright;

  /// Logos: the resolved plate, `light` or `dark`.
  final String plate;

  /// Logos: what the uploader chose, `auto`, `light` or `dark`.
  final String plateChoice;

  /// Variant → root-relative file path (live items only).
  final Map<String, String> files;

  /// Variant → byte length.
  final Map<String, int> bytes;
  final String? takedownReason;
  final String? takedownNote;
  final DateTime? createdAt;
  final int revision;

  bool get isLogo => kind == 'logo';
  bool get live => status == 'live';
  bool get setByFitflex => origin == 'fitflex';
  Alignment get focal => Alignment(focalX, focalY);

  /// Width / height; 1 when unknown.
  double get aspect => width > 0 && height > 0 ? width / height : 1;

  static PartnerMediaItem? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final kind = raw['kind'];
    final status = raw['status'];
    if (id is! String || id.isEmpty || !_safeId.hasMatch(id)) return null;
    if (kind != 'hero' && kind != 'logo') return null;
    if (status is! String) return null;
    final focal = raw['focal'];
    final takedown = raw['takedown'];
    double num01(Object? v) {
      final n = v is num ? v.toDouble() : 0.0;
      return n.isFinite ? n.clamp(-1.0, 1.0) : 0.0;
    }

    return PartnerMediaItem(
      id: id,
      kind: kind as String,
      status: status,
      origin: raw['origin'] == 'fitflex' ? 'fitflex' : 'partner',
      width: (raw['width'] as num?)?.toInt() ?? 0,
      height: (raw['height'] as num?)?.toInt() ?? 0,
      focalX: focal is Map ? num01(focal['x']) : 0,
      focalY: focal is Map ? num01(focal['y']) : 0,
      bright: raw['bright'] == true,
      plate: raw['plate'] == 'dark' ? 'dark' : 'light',
      plateChoice: switch (raw['plateChoice']) {
        'light' => 'light',
        'dark' => 'dark',
        _ => 'auto',
      },
      files: {
        if (raw['files'] case final Map f)
          for (final e in f.entries)
            if (e.key is String && e.value is String)
              e.key as String: e.value as String,
      },
      bytes: {
        if (raw['bytes'] case final Map b)
          for (final e in b.entries)
            if (e.key is String && e.value is num)
              e.key as String: (e.value as num).toInt(),
      },
      takedownReason: takedown is Map ? takedown['reason']?.toString() : null,
      takedownNote: takedown is Map
          ? (takedown['note']?.toString().trim().isEmpty ?? true)
                ? null
                : takedown['note'].toString()
          : null,
      createdAt: DateTime.tryParse(raw['createdAt']?.toString() ?? ''),
      revision: (raw['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The file rules from `GET /partner/media` → `limits` (never constants in
/// the app, spec §42.1).
@immutable
class PartnerMediaLimits {
  const PartnerMediaLimits({
    this.heroMinWidth = 1080,
    this.heroMaxBytes = 15 * 1024 * 1024,
    this.heroMaxPixels,
    this.heroTypes = const [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif',
    ],
    this.logoMinSide = 256,
    this.logoMaxBytes = 2 * 1024 * 1024,
    this.logoMaxSide,
    this.logoTypes = const ['image/png', 'image/jpeg', 'image/webp'],
  });

  final int heroMinWidth;
  final int heroMaxBytes;

  /// The most pixels (width x height) a photo may have; null when the
  /// server does not send it.
  final int? heroMaxPixels;
  final List<String> heroTypes;
  final int logoMinSide;
  final int logoMaxBytes;

  /// The longest side a logo may have, in pixels (`limits.logo.maxSide`);
  /// null when the server does not send it.
  final int? logoMaxSide;
  final List<String> logoTypes;

  static PartnerMediaLimits parse(Object? raw) {
    const d = PartnerMediaLimits();
    if (raw is! Map) return d;
    final h = raw['hero'] is Map ? raw['hero'] as Map : const {};
    final l = raw['logo'] is Map ? raw['logo'] as Map : const {};
    int n(Map m, String k, int fallback) =>
        (m[k] is num) ? (m[k] as num).toInt() : fallback;
    List<String> types(Map m, List<String> fallback) => m['types'] is List
        ? [
            for (final t in m['types'] as List)
              if (t is String) t.toLowerCase(),
          ]
        : fallback;
    return PartnerMediaLimits(
      heroMinWidth: n(h, 'minWidth', d.heroMinWidth),
      heroMaxBytes: n(h, 'maxBytes', d.heroMaxBytes),
      heroMaxPixels: h['maxPixels'] is num
          ? (h['maxPixels'] as num).toInt()
          : null,
      heroTypes: types(h, d.heroTypes),
      logoMinSide: n(l, 'minSide', d.logoMinSide),
      logoMaxBytes: n(l, 'maxBytes', d.logoMaxBytes),
      logoMaxSide: l['maxSide'] is num ? (l['maxSide'] as num).toInt() : null,
      logoTypes: types(l, d.logoTypes),
    );
  }
}

/// The confirmation texts the uploader ticks, exactly as the server sends
/// them (spec §42.5). [version] goes back with the upload.
@immutable
class PartnerMediaConfirmation {
  const PartnerMediaConfirmation({
    required this.version,
    required this.rights,
    required this.ownLogo,
  });

  final String version;
  final Map<String, String> rights;
  final Map<String, String> ownLogo;

  /// The text in [lang], verbatim; the other language when it is missing.
  String rightsIn(String lang) => _in(rights, lang);
  String ownLogoIn(String lang) => _in(ownLogo, lang);

  static String _in(Map<String, String> m, String lang) =>
      m[lang] ?? m[lang == 'sw' ? 'en' : 'sw'] ?? '';

  static PartnerMediaConfirmation? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final v = raw['version'];
    if (v == null || v.toString().isEmpty) return null;
    Map<String, String> texts(Object? m) => {
      if (m is Map)
        for (final e in m.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
    };
    return PartnerMediaConfirmation(
      version: v.toString(),
      rights: texts(raw['rights']),
      ownLogo: texts(raw['ownLogo']),
    );
  }
}

/// `GET /partner/media` for the caller's own home.
@immutable
class PartnerMediaOverview {
  const PartnerMediaOverview({
    required this.subjectType,
    required this.subjectId,
    this.subjectName,
    required this.canEdit,
    this.hero,
    this.heroTakedown,
    this.logo,
    this.logoTakedown,
    this.confirmation,
    this.limits = const PartnerMediaLimits(),
  });

  final String subjectType;
  final String subjectId;
  final String? subjectName;
  final bool canEdit;

  /// The live photo, or null.
  final PartnerMediaItem? hero;

  /// The latest FitFlex takedown of the photo, when nothing is live and
  /// nothing was uploaded after it.
  final PartnerMediaItem? heroTakedown;
  final PartnerMediaItem? logo;
  final PartnerMediaItem? logoTakedown;
  final PartnerMediaConfirmation? confirmation;
  final PartnerMediaLimits limits;

  PartnerMediaItem? live(String kind) => kind == 'logo' ? logo : hero;
  PartnerMediaItem? takedown(String kind) =>
      kind == 'logo' ? logoTakedown : heroTakedown;

  static PartnerMediaOverview? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final subject = raw['subject'];
    if (subject is! Map) return null;
    final type = subject['type']?.toString();
    final id = subject['id']?.toString();
    if (type == null || id == null || id.isEmpty) return null;
    PartnerMediaItem? pick(String kind, String field, {bool live = false}) {
      final slot = raw[kind];
      if (slot is! Map) return null;
      final item = PartnerMediaItem.tryParse(slot[field]);
      if (item == null || item.kind != kind) return null;
      if (live && !item.live) return null;
      if (!live && item.status != 'taken_down') return null;
      return item;
    }

    final name = subject['name']?.toString().trim();
    return PartnerMediaOverview(
      subjectType: type,
      subjectId: id,
      subjectName: name == null || name.isEmpty ? null : name,
      canEdit: raw['canEdit'] == true,
      hero: pick('hero', 'live', live: true),
      heroTakedown: pick('hero', 'lastTakedown'),
      logo: pick('logo', 'live', live: true),
      logoTakedown: pick('logo', 'lastTakedown'),
      confirmation: PartnerMediaConfirmation.tryParse(raw['confirmation']),
      limits: PartnerMediaLimits.parse(raw['limits']),
    );
  }
}

final _safeId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

/// The address of a partner photo or logo file, or null when the server
/// sent anything but `/partner/media/{id}/file?variant=` with `x2`, `x1`, `logo256` or
/// `logo128`: no other host, no escapes, no `..`. Resolved against the API
/// base only, and the result must still be on that host (the session header
/// is sent to it, so it must never leave the API host).
Uri? partnerMediaFileUri(Object? path, String apiBase) {
  if (path is! String) return null;
  final m = _filePath.firstMatch(path);
  if (m == null) return null;
  final base = Uri.tryParse(apiBase.trim().replaceAll(RegExp(r'/+$'), ''));
  if (base == null ||
      !(base.isScheme('https') || base.isScheme('http')) ||
      base.host.isEmpty ||
      base.hasQuery ||
      base.hasFragment) {
    return null;
  }
  final out = Uri.tryParse('$base$path');
  if (out == null ||
      out.scheme != base.scheme ||
      out.host != base.host ||
      out.port != base.port ||
      out.path != '${base.path}/partner/media/${m.group(1)}/file' ||
      out.query != 'variant=${m.group(2)}') {
    return null;
  }
  return out;
}

final _filePath = RegExp(
  r'^/partner/media/([A-Za-z0-9_-]{1,64})/file\?variant=(x2|x1|logo256|logo128)$',
);
