import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/shop_home.dart';
import '../../../shared/widgets/shop_home/shop_banner_carousel.dart';
import 'banner_models.dart';

/// Picks a banner photo. Replaced in tests.
typedef BannerImagePicker = Future<PickedBannerImage?> Function();

@visibleForTesting
BannerImagePicker? debugBannerImagePicker;

/// The gallery, at full size (banners need at least 1600 × 1000, so the
/// photo is not shrunk), with its pixel size read from the file.
Future<PickedBannerImage?> pickBannerImageFromGallery() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  int? width;
  int? height;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    width = frame.image.width;
    height = frame.image.height;
    frame.image.dispose();
    codec.dispose();
  } catch (_) {
    // Not an image the device can read: reported as the wrong type.
  }
  return PickedBannerImage(
    bytes: bytes,
    filename: file.name,
    mimeType: file.mimeType,
    width: width,
    height: height,
  );
}

/// Propose or change a banner (shop-home-phase2.md §5.2.3). Every text is
/// required in English AND Swahili (the subline is optional, but then in
/// both). No prices, percentages, links or phone numbers in any text. The
/// banner links to one of the vendor's own products or to their store.
///
/// "Send for approval" saves (POST or PATCH), uploads a newly picked photo
/// (POST /:id/image) and sends it (POST /:id/submit) unless the server says
/// it is already waiting for approval. Pops `true` once sent.
class VendorBannerFormPage extends StatefulWidget {
  const VendorBannerFormPage({
    super.key,
    this.banner,
    this.copyFrom,
    required this.products,
    required this.vendorId,
    required this.businessName,
    this.confirmation,
    this.now,
  });

  /// The banner being edited; null for a new one.
  final VendorBanner? banner;

  /// A past banner whose text and target start a new one ("Copy to new").
  final VendorBanner? copyFrom;

  /// The vendor's products (GET /vendor/products), for the product picker.
  final List<Map<String, dynamic>> products;

  /// The store a "My store" banner links to.
  final String vendorId;
  final String businessName;

  /// The confirmation texts and version from the list answer. Null from
  /// an older server: the app's own texts, and no version is sent.
  final BannerConfirmation? confirmation;

  /// The clock (tests).
  final DateTime Function()? now;

  @override
  State<VendorBannerFormPage> createState() => _VendorBannerFormPageState();
}

class _VendorBannerFormPageState extends State<VendorBannerFormPage> {
  static const _langs = ['en', 'sw'];

  /// The texts the vendor writes (the button is fixed by the target).
  static const _formFields = [
    'imageAlt',
    'headlineLead',
    'headlineAccent',
    'subline',
  ];

  final Map<String, Map<String, TextEditingController>> _text = {
    for (final f in bannerTextFields)
      f: {for (final l in _langs) l: TextEditingController()},
  };
  final Map<String, FocusNode> _focus = {};
  final Map<String, GlobalKey> _anchors = {};

  PickedBannerImage? _image;

  /// Why the last picked photo was not kept (type, size, pixels).
  String? _pickError;

  /// The banner's photo already on the server (published files, or the
  /// private preview that needs the session).
  ShopBannerImage _existingPublic = const ShopBannerImage();
  String _existingPreview = '';
  bool _hasExistingImage = false;
  Set<String> _audience = {...bannerAudiences};

  /// The model release and licence references for a newly picked photo.
  final _consentRef = TextEditingController();
  final _licenceRef = TextEditingController();
  late BannerConfirmation? _confirmation = widget.confirmation;

  /// The button is the one for the target (vendors may send no other).
  String get _ctaKey => defaultCtaKey(_targetType);
  String? _people;
  bool _rights = false;
  bool _models = false;
  String _targetType = 'product';
  String? _productId;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _bannerId;
  String _status = 'draft';
  bool _submitted = false;
  bool _busy = false;
  bool _dirty = false;
  bool _filling = false;
  String _previewLang = 'en';
  bool _previewDark = false;
  final Map<String, String> _serverErrors = {};

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  FocusNode _node(String key) => _focus[key] ??= FocusNode(debugLabel: key);
  GlobalKey _anchor(String key) =>
      _anchors[key] ??= GlobalKey(debugLabel: 'merch-anchor-$key');

  @override
  void initState() {
    super.initState();
    final source = widget.banner ?? widget.copyFrom;
    _filling = true;
    if (source != null) {
      for (final f in bannerTextFields) {
        final t = source.text[f];
        _text[f]!['en']!.text = t?.en ?? '';
        _text[f]!['sw']!.text = t?.sw ?? '';
      }
      _targetType = source.targetType == 'vendor_store'
          ? 'vendor_store'
          : 'product';
      _productId = _targetType == 'product' && source.targetValue.isNotEmpty
          ? source.targetValue
          : null;
      _audience = {...source.audienceRoles};
    }
    if (widget.banner != null) {
      final b = widget.banner!;
      _bannerId = b.id;
      _status = b.status;
      _existingPublic = b.publicImage;
      _existingPreview = b.previewUrl;
      _hasExistingImage = b.hasImage;
      _startsAt = b.startsAt;
      _endsAt = b.endsAt;
    }
    _filling = false;
    for (final f in bannerTextFields) {
      for (final l in _langs) {
        final c = _text[f]![l]!;
        var last = c.text;
        // Only a change of text counts (focus and selection notify too).
        c.addListener(() {
          if (c.text == last) return;
          last = c.text;
          _changed(f, l);
        });
      }
    }
  }

  @override
  void dispose() {
    _consentRef.dispose();
    _licenceRef.dispose();
    for (final m in _text.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  void _changed(String field, String lang) {
    if (_filling || !mounted) return;
    setState(() {
      _dirty = true;
      _serverErrors.remove('$field.$lang');
      _serverErrors.remove(field);
    });
  }

  String _v(String field, String lang) => _text[field]![lang]!.text.trim();

  String _langName(String lang) => context.tr('merch.lang.$lang');

  /// Products a banner may link to: active, approved and in stock.
  List<Map<String, dynamic>> get _eligible => widget.products.where((p) {
    final status = p['status']?.toString() ?? 'active';
    final approval = p['approvalStatus']?.toString() ?? 'approved';
    final stock = p['stock'] is num ? p['stock'] as num : 0;
    return status == 'active' && approval == 'approved' && stock > 0;
  }).toList();

  /// Every client-side problem, in focus order (key → message).
  Map<String, String> _errors() {
    final out = <String, String>{};
    final image = _image;
    if (image == null && !_hasExistingImage) {
      out['image'] = _pickError ?? context.tr('merch.banner.imageRequired');
    } else if (image != null) {
      final problem = image.problemKey;
      if (problem != null) out['image'] = context.tr(problem);
      if (_people == null) out['people'] = context.tr('merch.pickOne');
      if (!_rights) out['rights'] = context.tr('merch.confirmRequired');
      if (_people == 'product_models' && !_models) {
        out['models'] = context.tr('merch.confirmRequired');
      }
      if (_people == 'product_models' && _consentRef.text.trim().isEmpty) {
        out['consentRef'] = context.tr('merch.banner.consentRequired');
      }
      for (final (key, c) in [
        ('consentRef', _consentRef),
        ('licenceRef', _licenceRef),
      ]) {
        if (c.text.trim().length > bannerRefMax) {
          out[key] = context
              .tr('merch.field.tooLong')
              .replaceAll('{n}', '$bannerRefMax');
        }
      }
    }
    for (final f in _formFields) {
      final optional = f == 'subline';
      final anyFilled = _langs.any((l) => _v(f, l).isNotEmpty);
      for (final l in _langs) {
        final key = '$f.$l';
        final value = _v(f, l);
        if (value.isEmpty) {
          if (!optional) {
            out[key] = context
                .tr('merch.field.required')
                .replaceAll('{language}', _langName(l));
          } else if (anyFilled) {
            out[key] = context
                .tr('merch.banner.otherLanguage')
                .replaceAll('{language}', _langName(l));
          }
          continue;
        }
        final problem = bannerTextProblem(value);
        if (problem == 'price') {
          out[key] = context.tr('merch.banner.noPrices');
          continue;
        }
        if (problem == 'contact') {
          out[key] = context.tr('merch.banner.noLinks');
          continue;
        }
        final max = switch (f) {
          'subline' => bannerSublineMax[l]!,
          'ctaLabel' => bannerCtaMax[l]!,
          'imageAlt' => bannerAltMax[l]!,
          _ => null,
        };
        if (max != null && value.length > max) {
          out[key] = context
              .tr('merch.field.tooLong')
              .replaceAll('{n}', '$max');
        }
        if (f == 'headlineLead') {
          final total = [
            value,
            _v('headlineAccent', l),
          ].where((s) => s.isNotEmpty).join(' ').length;
          final limit = bannerHeadlineMax[l]!;
          if (total > limit) {
            out[key] = context
                .tr('merch.banner.tooLong')
                .replaceAll('{n}', '$limit');
          }
        }
      }
    }
    if (_targetType == 'product' &&
        (_productId == null || !_eligible.any((p) => p['id'] == _productId))) {
      out['target'] = context.tr(
        _eligible.isEmpty
            ? 'merch.banner.noProducts'
            : 'merch.banner.productRequired',
      );
    }
    if (_audience.isEmpty) {
      out['audience'] = context.tr('merch.banner.pickAudience');
    }
    final start = _startsAt;
    final end = _endsAt;
    // Sending (and sending back an approved or live banner) needs a start
    // at least an hour ahead; a pending edit keeps its time. No maximum
    // length (owner decision).
    final sends =
        widget.banner == null ||
        const {'draft', 'rejected', 'approved', 'live'}.contains(_status);
    if (start == null) {
      out['startsAt'] = context.tr('merch.dates.required');
    } else if (sends && start.isBefore(_now.add(const Duration(hours: 1)))) {
      out['startsAt'] = context.tr('merch.dates.startSoon');
    }
    if (end == null) {
      out['endsAt'] = context.tr('merch.dates.required');
    } else if (start != null && !end.isAfter(start)) {
      out['endsAt'] = context.tr('merch.dates.endAfter');
    }
    return out;
  }

  String? _errorFor(String key) =>
      (key == 'image' ? _serverErrors[key] ?? _pickError : null) ??
      _serverErrors[key] ?? (_submitted ? _errors()[key] : null);

  Map<String, dynamic> _body() {
    ShopText? pair(String f) {
      final en = _v(f, 'en');
      final sw = _v(f, 'sw');
      if (en.isEmpty && sw.isEmpty) return null;
      return ShopText(en, sw);
    }

    Map<String, String>? json(String f) {
      final t = pair(f);
      return t == null ? null : {'en': t.en, 'sw': t.sw};
    }

    final patch = _bannerId != null;
    return {
      'imageAlt': json('imageAlt'),
      'headlineLead': json('headlineLead'),
      'headlineAccent': json('headlineAccent'),
      // An emptied subline is cleared on the server (null); a new banner
      // without one leaves it out.
      if (json('subline') != null || patch) 'subline': json('subline'),
      // A button from the fixed list (spec DD-P2-1); never typed text.
      'ctaKey': _ctaKey,
      'target': {
        'type': _targetType,
        'value': _targetType == 'vendor_store' ? widget.vendorId : _productId,
      },
      'audienceRoles': [
        for (final a in bannerAudiences)
          if (_audience.contains(a)) a,
      ],
      'startsAt': _startsAt?.toUtc().toIso8601String(),
      'endsAt': _endsAt?.toUtc().toIso8601String(),
    };
  }

  /// Moves to the first field with a problem and focuses it.
  void _focusFirst(Iterable<String> keys) {
    const order = [
      'image',
      'people',
      'rights',
      'models',
      'consentRef',
      'licenceRef',
      'imageAlt.en',
      'imageAlt.sw',
      'headlineLead.en',
      'headlineLead.sw',
      'headlineAccent.en',
      'headlineAccent.sw',
      'subline.en',
      'subline.sw',
      'target',
      'cta',
      'audience',
      'startsAt',
      'endsAt',
    ];
    final set = keys.toSet();
    final first = order.firstWhere(set.contains, orElse: () => '');
    if (first.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _anchors[first]?.currentContext;
      if (anchor != null && anchor.mounted) {
        Scrollable.ensureVisible(
          anchor,
          alignment: 0.2,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : FFTokens.motionMedium,
        );
      }
      _focus[first]?.requestFocus();
    });
  }

  /// A server refusal on one field (docs/shop-banners-api.md), shown under
  /// that field. False when it is not about a field.
  bool _serverFieldError(ApiException e) {
    final body = e.body is Map ? e.body as Map : const {};
    final parts = (body['field']?.toString() ?? '').split('.');
    final name = parts.first;
    final lang = parts.length > 1 && _langs.contains(parts[1])
        ? parts[1]
        : null;
    final isText = bannerTextFields.contains(name);
    void put(String key, String message) => _serverErrors[key] = message;
    String max(int fallback) =>
        '${body['max'] is num ? (body['max'] as num).toInt() : fallback}';
    switch (e.code) {
      case 'price_claim_in_text' || 'contact_in_text':
        if (!isText) return false;
        put(
          '$name.${lang ?? 'en'}',
          context.tr(
            e.code == 'price_claim_in_text'
                ? 'merch.banner.noPrices'
                : 'merch.banner.noLinks',
          ),
        );
      case 'missing_translation':
        if (!isText) return false;
        final listed = body['missing'] is List
            ? (body['missing'] as List).map((m) => '$m').where(_langs.contains)
            : const <String>[];
        final missing =
            lang ??
            (listed.isNotEmpty
                ? listed.first
                : (_v(name, 'sw').isEmpty ? 'sw' : 'en'));
        put(
          '$name.$missing',
          context
              .tr('merch.banner.otherLanguage')
              .replaceAll('{language}', _langName(missing)),
        );
      case 'headline_too_long':
        final l = lang ?? 'en';
        // Under the field the server names (headlineAccent), else the lead.
        put(
          isText ? '$name.$l' : 'headlineLead.$l',
          context
              .tr('merch.banner.tooLong')
              .replaceAll('{n}', max(bannerHeadlineMax[l]!)),
        );
      case 'text_too_long':
        if (!isText) return false;
        put(
          '$name.${lang ?? 'en'}',
          context.tr('merch.field.tooLong').replaceAll('{n}', max(0)),
        );
      case 'start_too_soon':
        put('startsAt', context.tr('merch.dates.startSoon'));
      case 'start_required':
        put('startsAt', context.tr('merch.dates.required'));
      case 'end_before_start':
        put('endsAt', context.tr('merch.dates.endAfter'));
      case 'end_required':
        put('endsAt', context.tr('merch.dates.required'));
      case 'target_required':
        put('target', context.tr('merch.banner.productRequired'));
      case 'target_not_eligible':
        put('target', context.tr(targetIneligibleKey(body)));
      case 'target_not_owned' || 'target_type_not_allowed':
        put('target', context.tr('merch.banner.targetNotOwned'));
      case 'cta_label_not_allowed' || 'invalid_cta_key':
        put('cta', context.tr('merch.banner.ctaNotAllowed'));
      case 'consent_reference_required':
        put('consentRef', context.tr('merch.banner.consentRequired'));
      case 'invalid_reference':
        put(
          name == 'licenceRef' ? 'licenceRef' : 'consentRef',
          context.tr('merch.field.tooLong').replaceAll('{n}', '$bannerRefMax'),
        );
      case 'audience_required':
        put('audience', context.tr('merch.banner.pickAudience'));
      case 'image_required':
        put('image', context.tr('merch.banner.imageRequired'));
      case 'image_too_small':
        put('image', context.tr('merch.banner.imageSize'));
      case 'file_too_large':
        put('image', context.tr('merch.banner.imageWeight'));
      case 'unsupported_file_type':
        put('image', context.tr('merch.banner.imageType'));
      case 'rights_confirmation_required':
        if (_image != null) {
          put('rights', context.tr('merch.confirmRequired'));
        } else {
          put('image', context.tr('merch.banner.reconfirm'));
        }
      case 'people_confirmation_required' || 'image_people_unconfirmed':
        if (_image == null) {
          put('image', context.tr('merch.banner.reconfirm'));
        } else if (_people == null) {
          put('people', context.tr('merch.pickOne'));
        } else {
          put('models', context.tr('merch.confirmRequired'));
        }
      default:
        return false;
    }
    return true;
  }

  /// Refusals that end the edit (the banner moved on, or the tool is off):
  /// the message key, or null.
  static String? _closingError(ApiException e) => switch (e.code) {
    'not_editable' ||
    'invalid_transition' ||
    'proposal_expired' => 'merch.notEditable',
    'feature_disabled' => 'merch.unavailable',
    'banner_not_found' => 'merch.notYours',
    'vendor_permission_forbidden' => 'vendor.noAccess',
    _ => null,
  };

  /// Refusals about the business, not the banner: the message key.
  static String? _accountError(ApiException e) => switch (e.code) {
    'vendor_suspended' => 'merch.suspended',
    'vendor_not_approved' => 'merch.pendingBody',
    'rate_limited' => 'merch.rateLimited',
    'too_many_open_proposals' => 'merch.tooManyOpen',
    _ => null,
  };

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _submitted = true;
      _serverErrors.clear();
    });
    final errors = _errors();
    if (errors.isNotEmpty) {
      _focusFirst(errors.keys);
      return;
    }
    // Changing a scheduled or live banner sends it back for approval.
    if (_bannerId != null && (_status == 'approved' || _status == 'live')) {
      final ok = await showFFConfirmDialog(
        context,
        title: context.tr('merch.resend.title'),
        message: context.tr('merch.resend.body'),
        confirmLabel: context.tr('merch.resend.confirm'),
        cancelLabel: context.tr('merch.resend.keep'),
        confirmKey: const Key('merch-resend-confirm'),
      );
      if (!ok || !mounted) return;
    }
    final api = AppScope.of(context).api;
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    var step = 'save';
    try {
      Map<String, dynamic> saved;
      if (_bannerId == null) {
        saved = await api.vendorCreateShopBanner(_body());
        _bannerId = saved['id']?.toString();
        if (_bannerId == null || _bannerId!.isEmpty) {
          throw ApiException(500, null);
        }
      } else {
        saved = await api.vendorUpdateShopBanner(_bannerId!, _body());
      }
      _status = _statusOf(saved) ?? _status;
      final image = _image;
      if (image != null) {
        step = 'image';
        final out = await api.vendorUploadShopBannerImage(
          _bannerId!,
          bytes: image.bytes,
          filename: image.filename,
          people: _people ?? 'none',
          rightsConfirmed: _rights,
          peopleConfirmed: _people == 'product_models' && _models,
          confirmationVersion: _confirmation?.version,
          consentRef: _people == 'product_models'
              ? _consentRef.text.trim()
              : null,
          licenceRef: _licenceRef.text.trim(),
        );
        _status = _statusOf(out) ?? _status;
        final view = VendorBanner.fromJson(out);
        _image = null;
        _hasExistingImage = true;
        _existingPublic = view.publicImage;
        _existingPreview = view.previewUrl;
      }
      // A draft (new, or a rejected one that was edited) is sent; a pending
      // one stays pending; an approved one went back to pending by itself.
      if (_status == 'draft') {
        step = 'submit';
        final out = await api.vendorSubmitShopBanner(_bannerId!);
        _status = _statusOf(out) ?? 'pending_approval';
      }
      if (!mounted) return;
      messenger.success(locale.t('merch.sent'));
      _dirty = false;
      _leave(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final closing = _closingError(e);
      if (closing != null) {
        messenger.error(locale.t(closing));
        _dirty = false;
        _leave(true);
        return;
      }
      final account = _accountError(e);
      if (account != null) {
        messenger.error(locale.t(account));
        return;
      }
      if (e.code == 'confirmation_version_mismatch') {
        // The wording changed: fetch it, untick, ask again.
        await _reloadConfirmation();
        if (!mounted) return;
        setState(() {
          _rights = false;
          _models = false;
          _serverErrors['rights'] = locale.t('merch.banner.confirmChanged');
        });
        _focusFirst(const ['rights']);
        return;
      }
      if (_serverFieldError(e)) {
        setState(() {});
        _focusFirst(_serverErrors.keys);
        return;
      }
      if (step == 'image') {
        setState(
          () => _serverErrors['image'] = locale.t('merch.banner.uploadFailed'),
        );
        _focusFirst(const ['image']);
        return;
      }
      messenger.error(locale.t('merch.saveFailed'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      if (isNetworkError(e) || e is TimeoutException) {
        messenger.error(locale.t('merch.notSentOffline'));
      } else if (step == 'image') {
        setState(
          () => _serverErrors['image'] = locale.t('merch.banner.uploadFailed'),
        );
      } else {
        messenger.error(locale.t('merch.saveFailed'));
      }
    }
  }

  /// The current confirmation texts (one list item is enough).
  Future<void> _reloadConfirmation() async {
    try {
      final out = await AppScope.of(context).api.vendorShopBanners(limit: 1);
      final fresh = BannerConfirmation.fromJson(out['confirmation']);
      if (fresh != null && mounted) setState(() => _confirmation = fresh);
    } catch (_) {
      // Kept as it was; the next send says so again.
    }
  }

  static String? _statusOf(Map<String, dynamic> banner) =>
      (banner['effectiveStatus'] ?? banner['status'])?.toString();

  Future<void> _pickImage() async {
    final picker = debugBannerImagePicker ?? pickBannerImageFromGallery;
    final picked = await picker();
    if (picked == null || !mounted) return;
    // Checked at once (type, 5 MB, 1600 × 1000): a photo that cannot be
    // used is not kept, and says why under the field.
    final problem = picked.problemKey;
    setState(() {
      _pickError = problem == null ? null : context.tr(problem);
      _serverErrors.remove('image');
      if (problem != null) return;
      _image = picked;
      _dirty = true;
    });
  }

  Future<void> _pickDate(bool start) async {
    final current = start ? _startsAt : _endsAt;
    final base = toEatWallClock(
      current ??
          (start
              ? _now.add(const Duration(days: 1))
              : (_startsAt ?? _now).add(const Duration(days: 7))),
    );
    final today = toEatWallClock(_now);
    final day = await showDatePicker(
      context: context,
      initialDate: base.isBefore(today) ? today : base,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: context.tr(start ? 'merch.dates.starts' : 'merch.dates.ends'),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      helpText: context.tr('merch.dates.tzNote'),
    );
    if (time == null || !mounted) return;
    final at = fromEatWallClock(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    setState(() {
      _dirty = true;
      if (start) {
        _startsAt = at;
        _serverErrors.remove('startsAt');
      } else {
        _endsAt = at;
        _serverErrors.remove('endsAt');
      }
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty || _busy) return !_busy;
    return showFFConfirmDialog(
      context,
      title: context.tr('merch.discard.title'),
      confirmLabel: context.tr('merch.discard.confirm'),
      cancelLabel: context.tr('merch.discard.keep'),
      destructive: true,
      confirmKey: const Key('merch-discard-confirm'),
    );
  }

  Future<void> _cancel() async {
    if (await _confirmDiscard() && mounted) {
      _dirty = false;
      _leave(false);
    }
  }

  /// Back to the list: the page that opened the form, or (when the form was
  /// opened from its own address, e.g. after a refresh) /vendor/merch.
  void _leave(bool sent) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(sent);
    } else {
      context.go(AppRoutes.vendorMerch);
    }
  }

  // ── Building blocks ────────────────────────────────────────────────────

  Widget _label(BuildContext context, String text, {String? help}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: FFTokens.spacingMd,
        bottom: FFTokens.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (help != null) ...[
            const SizedBox(height: FFTokens.spacing2xs),
            Text(help, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _error(String key) {
    final message = _errorFor(key);
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          key: Key('merch-error-$key'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }

  /// One text in both languages, English above Swahili (they stack at any
  /// width and text size).
  Widget _pair(String field, String label, {String? help}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _label(context, label, help: help),
      for (final l in _langs) ...[
        KeyedSubtree(
          key: _anchor('$field.$l'),
          child: FFTextField(
            key: Key('merch-field-$field-$l'),
            controller: _text[field]![l],
            focusNode: _node('$field.$l'),
            label: context.tr('merch.field.$l'),
            // "Headline: first part, English": the field and the language.
            semanticsLabel: '$label, ${context.tr('merch.field.$l')}',
            errorText: _errorFor('$field.$l'),
            enabled: !_busy,
            maxLines: field == 'subline' || field == 'imageAlt' ? 2 : 1,
            textInputAction: TextInputAction.next,
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
      ],
    ],
  );

  Widget _imageField(BuildContext context) {
    final theme = Theme.of(context);
    final image = _image;
    final Widget preview;
    if (image != null) {
      preview = Image.memory(
        image.bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const SizedBox.expand(),
      );
    } else if (_hasExistingImage) {
      preview = _existingPhoto(context, 480);
    } else {
      preview = Center(
        child: Icon(
          Icons.image_outlined,
          size: 40,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final hasImage = image != null || _hasExistingImage;
    return KeyedSubtree(
      key: _anchor('image'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(
            context,
            context.tr('merch.banner.image'),
            help: context.tr('merch.banner.imageHelp'),
          ),
          Semantics(
            image: true,
            label: context.tr('merch.banner.imagePreview'),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FFTokens.radiusMd),
              child: AspectRatio(
                aspectRatio: 16 / 10,
                child: ColoredBox(
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: ExcludeSemantics(child: preview),
                ),
              ),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Focus(
            focusNode: _node('image'),
            skipTraversal: true,
            child: FFButton(
              key: const Key('merch-pick-image'),
              label: context.tr(
                hasImage
                    ? 'merch.banner.changeImage'
                    : 'merch.banner.chooseImage',
              ),
              icon: Icons.photo_library_outlined,
              variant: FFButtonVariant.secondary,
              visualDensity: VisualDensity.standard,
              maxLines: 2,
              onPressed: _busy ? null : _pickImage,
            ),
          ),
          _error('image'),
          if (image != null) ..._confirmations(context),
        ],
      ),
    );
  }

  /// The photo already on the server: the published file, else the private
  /// preview (with the session), [w] px wide.
  Widget _existingPhoto(BuildContext context, int w) {
    final scope = AppScope.of(context);
    final base = scope.api.baseUrl;
    final public = _existingPublic.resolved(base).pick(w.toDouble(), 1);
    final token = scope.auth.token;
    final src =
        public ??
        (_existingPreview.isEmpty ? '' : '$base$_existingPreview?w=$w');
    if (src.isEmpty) return const SizedBox.expand();
    return FFRemoteImage(
      src: src,
      fit: BoxFit.cover,
      headers: public == null && token != null
          ? {'authorization': 'Bearer $token'}
          : null,
      fallback: const SizedBox.expand(),
    );
  }

  /// People in the photo and the rights confirmations (O-3), for a newly
  /// picked photo.
  List<Widget> _confirmations(BuildContext context) => [
    KeyedSubtree(
      key: _anchor('people'),
      child: _label(context, context.tr('merch.banner.people')),
    ),
    for (final (id, key) in const [
      ('none', 'merch.banner.peopleNone'),
      ('product_models', 'merch.banner.peopleModels'),
    ]) ...[
      FFChoiceTile(
        key: Key('merch-people-$id'),
        title: context.tr(key),
        selected: _people == id,
        minHeight: 48,
        onSelected: _busy
            ? () {}
            : () => setState(() {
                _people = id;
                _dirty = true;
              }),
      ),
      const SizedBox(height: FFTokens.spacingSm),
    ],
    _error('people'),
    if (_confirmation?.draft == true)
      Padding(
        padding: const EdgeInsets.only(top: FFTokens.spacingSm),
        child: Text(
          context.tr('merch.banner.confirmDraft'),
          key: const Key('merch-confirm-draft'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    KeyedSubtree(
      key: _anchor('rights'),
      child: _check(
        'rights',
        _serverText(_confirmation?.rights, 'merch.banner.rights'),
        _rights,
        (v) => setState(() {
          _rights = v;
          _serverErrors.remove('rights');
        }),
      ),
    ),
    _error('rights'),
    if (_people == 'product_models') ...[
      KeyedSubtree(
        key: _anchor('models'),
        child: _check(
          'models',
          _serverText(_confirmation?.models, 'merch.banner.modelsConfirm'),
          _models,
          (v) => setState(() => _models = v),
        ),
      ),
      _error('models'),
      KeyedSubtree(
        key: _anchor('consentRef'),
        child: FFTextField(
          key: const Key('merch-consent-ref'),
          controller: _consentRef,
          focusNode: _node('consentRef'),
          label: context.tr('merch.banner.consentRef'),
          helperText: context.tr('merch.banner.consentRefHelp'),
          errorText: _errorFor('consentRef'),
          enabled: !_busy,
          onChanged: (_) => setState(() {
            _dirty = true;
            _serverErrors.remove('consentRef');
          }),
        ),
      ),
      const SizedBox(height: FFTokens.spacingSm),
    ],
    KeyedSubtree(
      key: _anchor('licenceRef'),
      child: FFTextField(
        key: const Key('merch-licence-ref'),
        controller: _licenceRef,
        focusNode: _node('licenceRef'),
        label: context.tr('merch.banner.licenceRef'),
        helperText: context.tr('merch.banner.licenceRefHelp'),
        errorText: _errorFor('licenceRef'),
        enabled: !_busy,
        onChanged: (_) => setState(() {
          _dirty = true;
          _serverErrors.remove('licenceRef');
        }),
      ),
    ),
  ];

  /// A text the server sent (in the user's language), else the app's own.
  String _serverText(ShopText? text, String fallbackKey) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final v = text?.of(lang).trim() ?? '';
    return v.isEmpty ? context.tr(fallbackKey) : v;
  }

  Widget _check(
    String key,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) => CheckboxListTile(
    key: Key('merch-check-$key'),
    focusNode: _node(key),
    value: value,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    title: Text(label),
    onChanged: _busy
        ? null
        : (v) {
            _dirty = true;
            onChanged(v ?? false);
          },
  );

  Widget _targetField(BuildContext context) {
    final eligible = _eligible;
    return KeyedSubtree(
      key: _anchor('target'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, context.tr('merch.banner.target')),
          for (final (id, key) in const [
            ('product', 'merch.banner.targetProduct'),
            ('vendor_store', 'merch.banner.targetStore'),
          ]) ...[
            FFChoiceTile(
              key: Key('merch-target-$id'),
              title: context.tr(key),
              selected: _targetType == id,
              minHeight: 48,
              onSelected: () {
                if (_busy || _targetType == id) return;
                setState(() {
                  _targetType = id;
                  _dirty = true;
                  _serverErrors.remove('target');
                });
              },
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          if (_targetType == 'product')
            Focus(
              focusNode: _node('target'),
              skipTraversal: true,
              child: eligible.isEmpty
                  ? Text(
                      context.tr('merch.banner.noProducts'),
                      key: const Key('merch-no-products'),
                    )
                  : FFDropdownField<String>(
                      key: const Key('merch-product'),
                      value: eligible.any((p) => p['id'] == _productId)
                          ? _productId
                          : null,
                      label: context.tr('merch.banner.pickProduct'),
                      isExpanded: true,
                      items: [
                        for (final p in eligible)
                          DropdownMenuItem(
                            value: p['id']?.toString(),
                            child: Text(
                              p['name']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _productId = v;
                        _dirty = true;
                        _serverErrors.remove('target');
                      }),
                    ),
            ),
          if (_targetType == 'product' || _serverErrors.containsKey('target'))
            _error('target'),
        ],
      ),
    );
  }

  /// The button, from the fixed list; the target's own is picked until the
  /// vendor chooses another. Shows the chosen words.
  Widget _ctaField(BuildContext context) => KeyedSubtree(
    key: _anchor('cta'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, context.tr('merch.banner.ctaTitle')),
        Text(
          context
              .tr('merch.banner.button')
              .replaceAll('{label}', context.tr(bannerCtaKeys[_ctaKey]!)),
          key: const Key('merch-button-label'),
        ),
        _error('cta'),
      ],
    ),
  );

  /// Who sees it: Members, Trainers, Gym owners (at least one).
  Widget _audienceField(BuildContext context) => KeyedSubtree(
    key: _anchor('audience'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, context.tr('merch.banner.showTo')),
        for (final (i, a) in bannerAudiences.indexed)
          CheckboxListTile(
            key: Key('merch-audience-$a'),
            focusNode: i == 0 ? _node('audience') : null,
            value: _audience.contains(a),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(context.tr('merch.audience.$a')),
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _dirty = true;
                    _serverErrors.remove('audience');
                    if (v == true) {
                      _audience.add(a);
                    } else {
                      _audience.remove(a);
                    }
                  }),
          ),
        _error('audience'),
      ],
    ),
  );

  Widget _dateField(BuildContext context, bool start) {
    final key = start ? 'startsAt' : 'endsAt';
    final at = start ? _startsAt : _endsAt;
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final text = at == null
        ? context.tr('merch.dates.pick')
        : formatDateTime(toEatWallClock(at), locale: lang);
    return KeyedSubtree(
      key: _anchor(key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(
            context,
            context.tr(start ? 'merch.dates.starts' : 'merch.dates.ends'),
            help: context.tr('merch.dates.tzNote'),
          ),
          Focus(
            focusNode: _node(key),
            skipTraversal: true,
            child: FFButton(
              key: Key('merch-$key'),
              label: text,
              icon: Icons.event_outlined,
              variant: FFButtonVariant.secondary,
              fullWidth: true,
              visualDensity: VisualDensity.standard,
              maxLines: 2,
              semanticLabel:
                  '${context.tr(start ? 'merch.dates.starts' : 'merch.dates.ends')}, '
                  '$text, ${context.tr('merch.dates.tzNote')}',
              onPressed: _busy ? null : () => _pickDate(start),
            ),
          ),
          _error(key),
        ],
      ),
    );
  }

  /// The slide as members would see it, in either language and theme.
  Widget _preview(BuildContext context) {
    final lang = _previewLang;
    ShopText? one(String f) {
      final v = _v(f, lang);
      return v.isEmpty ? null : ShopText(v, v);
    }

    final lead = one('headlineLead');
    final banner = ShopBanner(
      id: 'preview',
      image: _existingPublic.resolved(AppScope.of(context).api.baseUrl),
      headlineLead: lead ?? ShopText(' ', ' '),
      headlineAccent: one('headlineAccent'),
      subline: one('subline'),
      ctaLabel: ShopText(
        FFLocale().tIn(lang, bannerCtaKeys[_ctaKey]!),
        FFLocale().tIn(lang, bannerCtaKeys[_ctaKey]!),
      ),
      target: ShopBannerTarget(_targetType, ''),
      origin: 'vendor',
      vendorName: widget.businessName.isEmpty ? ' ' : widget.businessName,
    );
    final theme = _previewDark ? buildDarkTheme() : buildTheme();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label(context, context.tr('merch.banner.preview')),
        Wrap(
          spacing: FFTokens.spacingSm,
          runSpacing: FFTokens.spacingSm,
          children: [
            FFSegmented(
              key: const Key('merch-preview-lang'),
              value: _previewLang,
              options: [
                ('en', context.tr('merch.field.en')),
                ('sw', context.tr('merch.field.sw')),
              ],
              onChanged: (v) => setState(() => _previewLang = v),
            ),
            FFSegmented(
              key: const Key('merch-preview-theme'),
              value: _previewDark ? 'dark' : 'light',
              options: [
                ('light', context.tr('merch.preview.light')),
                ('dark', context.tr('merch.preview.dark')),
              ],
              onChanged: (v) => setState(() => _previewDark = v == 'dark'),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Semantics(
          container: true,
          label: context.tr('merch.banner.previewA11y'),
          child: ExcludeSemantics(
            child: Theme(
              data: theme,
              child: Container(
                key: const Key('merch-preview'),
                padding: const EdgeInsets.all(FFTokens.spacingSm),
                decoration: BoxDecoration(
                  color: theme.scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: IgnorePointer(
                    child: ShopBannerCarousel(
                      banners: [banner],
                      onOpen: (_) {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Every field is built (not lazily), so a failed send can scroll to and
    // focus the first problem wherever it is.
    final form = SingleChildScrollView(
      key: const Key('merch-banner-form'),
      padding: const EdgeInsets.fromLTRB(
        FFTokens.spacingLg,
        FFTokens.spacingSm,
        FFTokens.spacingLg,
        FFTokens.spacingXl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _imageField(context),
          _pair(
            'imageAlt',
            context.tr('merch.banner.imageAlt'),
            help: context.tr('merch.banner.imageAltHelp'),
          ),
          FFAlert(message: context.tr('merch.banner.textRule')),
          _pair('headlineLead', context.tr('merch.banner.lead')),
          _pair(
            'headlineAccent',
            context.tr('merch.banner.accent'),
            help: context.tr('merch.banner.accentHelp'),
          ),
          _pair('subline', context.tr('merch.banner.subline')),
          _targetField(context),
          _ctaField(context),
          _audienceField(context),
          _dateField(context, true),
          _dateField(context, false),
          const SizedBox(height: FFTokens.spacingMd),
          _preview(context),
          const SizedBox(height: FFTokens.spacingLg),
          FFAlert(message: context.tr('merch.reviewNote')),
          const SizedBox(height: FFTokens.spacingLg),
          FFButton(
            key: const Key('merch-send'),
            label: context.tr('merch.send'),
            fullWidth: true,
            visualDensity: VisualDensity.standard,
            maxLines: 2,
            loading: _busy,
            onPressed: _busy ? null : _send,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: const Key('merch-cancel'),
            label: context.tr('common.cancel'),
            variant: FFButtonVariant.ghost,
            fullWidth: true,
            visualDensity: VisualDensity.standard,
            onPressed: _busy ? null : _cancel,
          ),
        ],
      ),
    );
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          _dirty = false;
          setState(() {});
          if (context.mounted) _leave(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.tr(
              widget.banner == null
                  ? 'merch.banner.newTitle'
                  : 'merch.banner.editTitle',
            ),
          ),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: form,
          ),
        ),
      ),
    );
  }
}
