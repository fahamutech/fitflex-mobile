import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/partner_media/partner_media_image_check.dart';
import '../../shared/partner_media/partner_media_models.dart';
import '../../shared/partner_media/partner_media_store.dart';
import 'partner_media_band.dart';

/// What one upload try came to.
enum PartnerUploadStatus {
  ok,
  cancelled,
  noAccess,
  versionMismatch,
  offline,
  failed,
}

@immutable
class PartnerUploadResult {
  const PartnerUploadResult(this.status, {this.code, this.values = const {}});

  final PartnerUploadStatus status;

  /// The server's error code (failed).
  final String? code;
  final Map<String, Object?> values;
}

/// What the sheet sends: the original file, the focus point (photo) or the
/// plate (logo), with the confirmation version the boxes were ticked for.
@immutable
class PartnerUploadRequest {
  const PartnerUploadRequest({
    required this.kind,
    required this.picked,
    required this.confirmationVersion,
    this.focal = Alignment.center,
    this.plate = 'auto',
  });

  final String kind;
  final PickedPartnerImage picked;
  final String confirmationVersion;
  final Alignment focal;
  final String plate;
}

/// Progress of the upload the sheet started: bytes sent (0..1), then
/// "preparing" (the server cleans the file; it can't be cancelled then).
class PartnerUploadProgress extends ChangeNotifier {
  double sent = 0;
  bool preparing = false;

  void update(double v) {
    sent = v.clamp(0, 1);
    notifyListeners();
  }

  void setPreparing() {
    preparing = true;
    notifyListeners();
  }
}

typedef PartnerUploadFn =
    Future<PartnerUploadResult> Function(
      PartnerUploadRequest request,
      PartnerUploadProgress progress,
      Future<void> abort,
    );

/// The text for a partner media error [code] (spec §44.1) for a [kind]
/// (`hero` / `logo`), or "Something went wrong (code)." when there is none.
String partnerMediaErrorText(
  BuildContext context,
  String kind,
  String code, {
  Map<String, Object?> values = const {},
  PartnerMediaLimits limits = const PartnerMediaLimits(),
}) {
  final logo = kind == 'logo';
  // A logo's size is its short side; a day limit (person or partner,
  // functions#277 review M3) waits until tomorrow, a minute limit a minute.
  final key = switch (code) {
    'image_too_small' when logo => 'image_too_small_logo',
    // 60 tries a day per partner, whatever their outcome (functions#277).
    'rate_limited' when values['scope'] == 'partner_attempts' =>
      'rate_limited_attempts',
    // 40 a day per person, or 20 successful uploads a day per partner.
    'rate_limited' when values['limit'] == 'day' => 'rate_limited_day',
    _ => code,
  };
  String fill(String s) {
    final maxBytes =
        (values['maxBytes'] as num?)?.toInt() ??
        (logo ? limits.logoMaxBytes : limits.heroMaxBytes);
    final mb = maxBytes / (1024 * 1024);
    return s
        .replaceAll(
          '{minWidth}',
          '${values['minWidth'] ?? limits.heroMinWidth}',
        )
        .replaceAll('{minSide}', '${values['minSide'] ?? limits.logoMinSide}')
        .replaceAll(
          '{maxMb}',
          '${values['maxMb'] ?? (mb == mb.roundToDouble() ? mb.round() : mb.toStringAsFixed(1))}',
        );
  }

  final full = 'partnerMedia.error.$key';
  final text = context.tr(full);
  if (text == full) {
    return context.tr('partnerMedia.error.unknown').replaceAll('{code}', code);
  }
  return fill(text);
}

/// Opens the upload sheet (spec §42): full screen on phones, a centred
/// dialog at most 720 wide from 840. Resolves with the last status (ok when
/// the new photo or logo is live).
Future<PartnerUploadStatus?> showPartnerMediaUploadSheet(
  BuildContext context, {
  required String kind,
  required String side,
  required PickedPartnerImage picked,
  required PartnerMediaConfirmation confirmation,
  required PartnerMediaLimits limits,
  required PartnerUploadFn upload,
  required Future<PickedPartnerImage?> Function() pickAnother,
  required Future<PartnerMediaConfirmation?> Function() reloadConfirmation,
  String? name,
  bool replacing = false,
  FFHeroOwnPhoto? livePhoto,
  PartnerLogoImage? liveLogo,
}) {
  final sheet = PartnerMediaUploadSheet(
    kind: kind,
    side: side,
    picked: picked,
    confirmation: confirmation,
    limits: limits,
    upload: upload,
    pickAnother: pickAnother,
    reloadConfirmation: reloadConfirmation,
    name: name,
    replacing: replacing,
    livePhoto: livePhoto,
    liveLogo: liveLogo,
  );
  if (MediaQuery.sizeOf(context).width >= 840) {
    return showDialog<PartnerUploadStatus>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(FFTokens.spacingLg),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 720,
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
          ),
          child: sheet,
        ),
      ),
    );
  }
  return Navigator.of(context).push<PartnerUploadStatus>(
    MaterialPageRoute(fullscreenDialog: true, builder: (_) => sheet),
  );
}

class PartnerMediaUploadSheet extends StatefulWidget {
  const PartnerMediaUploadSheet({
    super.key,
    required this.kind,
    required this.side,
    required this.picked,
    required this.confirmation,
    required this.limits,
    required this.upload,
    required this.pickAnother,
    required this.reloadConfirmation,
    this.name,
    this.replacing = false,
    this.livePhoto,
    this.liveLogo,
  });

  final String kind;
  final String side;
  final PickedPartnerImage picked;
  final PartnerMediaConfirmation confirmation;
  final PartnerMediaLimits limits;
  final PartnerUploadFn upload;
  final Future<PickedPartnerImage?> Function() pickAnother;
  final Future<PartnerMediaConfirmation?> Function() reloadConfirmation;
  final String? name;
  final bool replacing;
  final FFHeroOwnPhoto? livePhoto;
  final PartnerLogoImage? liveLogo;

  @override
  State<PartnerMediaUploadSheet> createState() =>
      _PartnerMediaUploadSheetState();
}

class _PartnerMediaUploadSheetState extends State<PartnerMediaUploadSheet> {
  late PickedPartnerImage _picked = widget.picked;
  late PartnerMediaConfirmation _confirmation = widget.confirmation;
  Alignment _focal = Alignment.center;
  String _plate = 'auto';
  bool? _autoDark;
  bool _rights = false;
  bool _ownLogo = false;
  bool _wordingChanged = false;
  String? _error;
  bool _retry = false;
  PartnerUploadProgress? _progress;
  Completer<void>? _abort;
  PartnerUploadStatus? _last;
  static final _idle = ChangeNotifier();

  bool get _logo => widget.kind == 'logo';
  bool get _busy => _progress != null;
  PartnerMediaProblem? get _problem =>
      partnerMediaProblem(widget.kind, _picked, widget.limits);
  bool get _ticked => _rights && (!_logo || _ownLogo);

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<void> _measure() async {
    if (!_logo) return;
    final dark = await logoWantsDarkPlate(_picked.bytes);
    if (mounted) setState(() => _autoDark = dark);
  }

  String get _lang => FFLocaleScope.of(context).locale.languageCode;

  bool get _darkPlate =>
      _plate == 'dark' || (_plate == 'auto' && (_autoDark ?? false));

  Future<void> _chooseAnother() async {
    final next = await widget.pickAnother();
    if (next == null || !mounted) return;
    setState(() {
      _picked = next;
      _error = null;
      _retry = false;
      _focal = Alignment.center;
      _autoDark = null;
    });
    unawaited(_measure());
  }

  Future<void> _send() async {
    if (_busy || !_ticked || _problem != null) return;
    final progress = PartnerUploadProgress();
    final abort = Completer<void>();
    setState(() {
      _progress = progress;
      _abort = abort;
      _error = null;
      _retry = false;
    });
    final result = await widget.upload(
      PartnerUploadRequest(
        kind: widget.kind,
        picked: _picked,
        confirmationVersion: _confirmation.version,
        focal: _focal,
        plate: _plate,
      ),
      progress,
      abort.future,
    );
    if (!mounted) return;
    _last = result.status;
    switch (result.status) {
      case PartnerUploadStatus.ok:
      case PartnerUploadStatus.noAccess:
        Navigator.of(context).pop(result.status);
        return;
      case PartnerUploadStatus.cancelled:
        setState(() => _progress = null);
      case PartnerUploadStatus.versionMismatch:
        final fresh = await widget.reloadConfirmation();
        if (!mounted) return;
        setState(() {
          _progress = null;
          if (fresh != null) _confirmation = fresh;
          _rights = false;
          _ownLogo = false;
          _wordingChanged = true;
        });
      case PartnerUploadStatus.offline:
        setState(() {
          _progress = null;
          _error = context.tr('partnerMedia.offline');
          _retry = true;
        });
      case PartnerUploadStatus.failed:
        final code = result.code ?? 'unknown';
        setState(() {
          _progress = null;
          _error = partnerMediaErrorText(
            context,
            widget.kind,
            code,
            values: result.values,
            limits: widget.limits,
          );
          // The partner was deleted mid-upload (subject_not_found) or a
          // limit was reached: trying again now would not help.
          _retry =
              code == 'image_save_failed' ||
              !_fileCodes.contains(code) &&
                  code != 'rate_limited' &&
                  code != 'subject_not_found';
        });
    }
  }

  static const _fileCodes = {
    'image_too_small',
    'unsupported_file_type',
    'svg_not_allowed',
    'file_too_large',
    'variant_over_budget',
    'image_taken_down_before',
  };

  void _cancel() {
    final a = _abort;
    if (a != null && !a.isCompleted) a.complete();
  }

  @override
  Widget build(BuildContext context) {
    final preparing = _progress?.preparing ?? false;
    final title = context.tr(
      _logo ? 'partnerMedia.sheet.titleLogo' : 'partnerMedia.sheet.titleHero',
    );
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            key: const Key('partner-media-sheet-close'),
            tooltip: context.tr('common.close'),
            icon: const Icon(Icons.close),
            onPressed: _busy ? null : () => Navigator.of(context).pop(_last),
          ),
          title: Semantics(header: true, child: Text(title)),
        ),
        body: ListenableBuilder(
          listenable: _progress ?? _idle,
          builder: (context, _) => ListView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              if (widget.replacing) ...[
                Text(context.tr('partnerMedia.replaceNote')),
                const SizedBox(height: FFTokens.spacingMd),
              ],
              if (_problem case final p?) ...[
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('partner-media-sheet-problem'),
                    tone: FFAlertTone.error,
                    message: partnerMediaErrorText(
                      context,
                      widget.kind,
                      p.code,
                      values: p.values,
                      limits: widget.limits,
                    ),
                  ),
                ),
                const SizedBox(height: FFTokens.spacingMd),
                FFButton(
                  key: const Key('partner-media-choose-another'),
                  label: context.tr('partnerMedia.sheet.chooseAnother'),
                  variant: FFButtonVariant.secondary,
                  fullWidth: true,
                  onPressed: _chooseAnother,
                ),
              ] else
                ..._form(context, preparing),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _form(BuildContext context, bool preparing) {
    final memory = MemoryImage(_picked.bytes);
    final ownPhoto = _logo
        ? widget.livePhoto
        : FFHeroOwnPhoto(
            id: 'picked',
            provider: memory,
            focal: _focal,
            aspect: _picked.aspect,
          );
    Widget? plate({double scale = 1}) => _logo
        ? FFLogoPlate(
            image: memory,
            aspect: _picked.aspect,
            dark: _darkPlate,
            scale: scale,
          )
        : widget.liveLogo == null
        ? null
        : FFLogoPlate(
            image: widget.liveLogo!.provider,
            aspect: widget.liveLogo!.aspect,
            dark: widget.liveLogo!.dark,
          );
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final phone = LayoutBuilder(
      builder: (context, c) {
        final w = wide ? 342.0 : (c.maxWidth).clamp(0.0, 600.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FFSectionTitle(context.tr('partnerMedia.sheet.onPhone')),
            SizedBox(
              width: w,
              child: PartnerBandPreview(
                key: const Key('partner-media-preview-phone'),
                side: widget.side,
                name: widget.name,
                label: context.tr('partnerMedia.a11y.previewPhone'),
                ownPhoto: ownPhoto,
                logo: plate(),
                forceSize: Size(w + 48, 844),
              ),
            ),
          ],
        );
      },
    );
    final wideBand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('partnerMedia.sheet.onWide')),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 792,
            child: PartnerBandPreview(
              key: const Key('partner-media-preview-wide'),
              side: widget.side,
              name: widget.name,
              label: context.tr('partnerMedia.a11y.previewWide'),
              ownPhoto: ownPhoto,
              logo: plate(),
              forceSize: const Size(1280, 800),
            ),
          ),
        ),
      ],
    );
    final disabled = _busy;
    return [
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 342, child: phone),
            const SizedBox(width: FFTokens.spacingMd),
            Expanded(child: wideBand),
          ],
        )
      else ...[
        phone,
        const SizedBox(height: FFTokens.spacingLg),
        wideBand,
      ],
      const SizedBox(height: FFTokens.spacingLg),
      if (!_logo) ...[
        FFSectionTitle(context.tr('partnerMedia.sheet.focal')),
        FFFocalPointPicker(
          image: memory,
          aspect: _picked.aspect,
          value: _focal,
          enabled: !disabled,
          onChanged: (a) => setState(() => _focal = a),
        ),
      ] else ...[
        // Wraps onto two lines on narrow phones (a wide logo at 2x).
        Wrap(
          spacing: FFTokens.spacingSm,
          runSpacing: FFTokens.spacingSm,
          children: [
            Container(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              color: Colors.white,
              child: plate(scale: 2),
            ),
            Container(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              color: FFTokens.heroPlaceholder,
              child: plate(scale: 2),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FFSectionTitle(context.tr('partnerMedia.sheet.plate')),
        IgnorePointer(
          ignoring: disabled,
          child: FFSegmented(
            key: const Key('partner-media-plate'),
            value: _plate,
            options: [
              (
                'auto',
                _autoDark == null
                    ? context.tr('partnerMedia.sheet.plateAuto')
                    : context
                          .tr('partnerMedia.sheet.plateAutoIs')
                          .replaceAll(
                            '{tone}',
                            context
                                .tr(
                                  _autoDark!
                                      ? 'partnerMedia.sheet.plateDark'
                                      : 'partnerMedia.sheet.plateLight',
                                )
                                .toLowerCase(),
                          ),
              ),
              ('light', context.tr('partnerMedia.sheet.plateLight')),
              ('dark', context.tr('partnerMedia.sheet.plateDark')),
            ],
            onChanged: (v) => setState(() => _plate = v),
          ),
        ),
      ],
      const SizedBox(height: FFTokens.spacingLg),
      if (_wordingChanged) ...[
        FFAlert(
          key: const Key('partner-media-wording-changed'),
          tone: FFAlertTone.warning,
          message: context.tr('partnerMedia.sheet.confirmChanged'),
        ),
        const SizedBox(height: FFTokens.spacingSm),
      ],
      _box(
        const Key('partner-media-confirm-rights'),
        _confirmation.rightsIn(_lang),
        _rights,
        disabled ? null : (v) => setState(() => _rights = v),
      ),
      if (_logo)
        _box(
          const Key('partner-media-confirm-own-logo'),
          _confirmation.ownLogoIn(_lang),
          _ownLogo,
          disabled ? null : (v) => setState(() => _ownLogo = v),
        ),
      const SizedBox(height: FFTokens.spacingMd),
      if (_error != null) ...[
        Semantics(
          liveRegion: true,
          child: FFAlert(
            key: const Key('partner-media-sheet-error'),
            tone: FFAlertTone.error,
            message: _error!,
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
      ],
      if (_progress case final p?)
        _progressRow(context, p)
      else ...[
        FFButton(
          key: const Key('partner-media-use'),
          label: _retry
              ? context.tr('common.retry')
              : context.tr(
                  _logo
                      ? 'partnerMedia.sheet.useLogo'
                      : 'partnerMedia.sheet.useHero',
                ),
          fullWidth: true,
          maxLines: 3,
          onPressed: _ticked ? _send : null,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFButton(
          key: const Key('partner-media-choose-another'),
          label: context.tr('partnerMedia.sheet.chooseAnother'),
          variant: FFButtonVariant.secondary,
          fullWidth: true,
          maxLines: 3,
          onPressed: _chooseAnother,
        ),
      ],
    ];
  }

  Widget _box(
    Key key,
    String text,
    bool value,
    ValueChanged<bool>? onChanged,
  ) => CheckboxListTile(
    key: key,
    value: value,
    contentPadding: EdgeInsets.zero,
    controlAffinity: ListTileControlAffinity.leading,
    // The server's words, as sent (no trimming or reformatting).
    title: Text(text),
    onChanged: onChanged == null ? null : (v) => onChanged(v ?? false),
  );

  Widget _progressRow(BuildContext context, PartnerUploadProgress p) {
    final pct = (p.sent * 100).round();
    final label = p.preparing
        ? context.tr('partnerMedia.sheet.preparing')
        : context.tr('partnerMedia.sheet.uploading').replaceAll('{n}', '$pct');
    return Column(
      key: const Key('partner-media-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          liveRegion: true,
          value: p.preparing ? null : '$pct%',
          child: Text(label),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        LinearProgressIndicator(value: p.preparing ? null : p.sent),
        if (!p.preparing) ...[
          const SizedBox(height: FFTokens.spacingSm),
          FFButton(
            key: const Key('partner-media-cancel'),
            label: context.tr('common.cancel'),
            variant: FFButtonVariant.secondary,
            onPressed: _cancel,
          ),
        ],
      ],
    );
  }
}
