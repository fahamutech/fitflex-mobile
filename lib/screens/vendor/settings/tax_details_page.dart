// Vendor tools · S5: Tax details (design spec §6). The vendor says they are
// VAT-registered and proves it with their VAT certificate, so VAT and their
// TIN/VRN appear on their documents once a FitFlex KYC reviewer verifies it
// (O-12). Prices always include VAT (Q-11); app prices and commission never
// change (O-10).
//
// Only the vendor account edits (Q-16; the server answers 403 owner_only to
// staff). Staff with `payments` see it read-only; other staff cannot open
// it. Shown only while the server reports `vat: true`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/network/browser_online.dart';
import '../../partner/verification/verification_forms.dart'
    show DocumentSource, PickDocument, pickDocumentFromDevice;
import '../../partner/verification/verification_models.dart' show KycOverview;
import '../documents/document_models.dart';
import '../stock/stock_options.dart';

const vendorTaxRoute = '/vendor/settings/tax';

/// The KYC requirement the certificate is uploaded under.
const vatCertificateRequirement = 'vat_certificate';

const _maxFileBytes = 10 * 1024 * 1024;

class TaxDetailsPage extends StatefulWidget {
  const TaxDetailsPage({super.key, this.pickDocument});

  /// The device's camera, gallery or file picker; tests replace it.
  final PickDocument? pickDocument;

  @override
  State<TaxDetailsPage> createState() => _TaxDetailsPageState();
}

class _TaxDetailsPageState extends State<TaxDetailsPage> {
  TaxProfile? _profile;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  bool _uploadFailed = false;
  String? _uploadError;
  bool _registered = false;
  String? _uploadedId;
  bool _dirty = false;
  String? _tinError;
  String? _vrnError;
  String? _certError;
  String? _saveError;
  final _tin = TextEditingController();
  final _vrn = TextEditingController();
  final _vrnFocus = FocusNode();

  bool get _owner =>
      AppScope.of(context).auth.user?['userType']?.toString() == 'vendor';

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_onOnline);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_onOnline);
    _tin.dispose();
    _vrn.dispose();
    _vrnFocus.dispose();
    super.dispose();
  }

  void _onOnline() {
    if (mounted) setState(() {});
  }

  Future<void> _start() async {
    final tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    if (!tools.vat) {
      context.go('/vendor/home');
      return;
    }
    if (!_owner && !canVendor(context, 'payments')) {
      FFSnack.error(context, context.tr('vendor.tax.noAccess'));
      context.go('/vendor/home');
      return;
    }
    await _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await AppScope.of(context).api.vendorTaxProfile();
      if (!mounted) return;
      _apply(TaxProfile.fromJson(res));
      setState(() => _loading = false);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 403) {
        FFSnack.error(context, context.tr('vendor.tax.noAccess'));
        context.go('/vendor/home');
        return;
      }
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _apply(TaxProfile p) {
    _profile = p;
    _registered = p.vatRegistered;
    _tin.text = p.tin ?? '';
    _vrn.text = p.vrn ?? '';
    _uploadedId = null;
    _dirty = false;
    _tinError = _vrnError = _certError = _saveError = null;
  }

  bool get _hasCertificate =>
      _uploadedId != null || _profile?.certificateDocumentId != null;

  void _changed() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _toggle(bool on) async {
    final p = _profile;
    if (!on && p != null && p.vatRegistered && p.everVerified) {
      final ok = await showFFConfirmDialog(
        context,
        message: context.tr('vendor.tax.stopConfirm'),
        confirmLabel: context.tr('vendor.tax.stop'),
        destructive: true,
        confirmKey: const Key('tax-stop-confirm'),
      );
      if (!ok || !mounted) return;
      setState(() => _registered = false);
      // It applies to new sales at once (§6.1).
      await _save();
      return;
    }
    setState(() {
      _registered = on;
      _dirty = true;
    });
  }

  Future<void> _upload(DocumentSource source) async {
    final pick = widget.pickDocument ?? pickDocumentFromDevice;
    final picked = await pick(source);
    if (picked == null || !mounted) return;
    if (picked.bytes.length > _maxFileBytes) {
      setState(() {
        _uploadFailed = true;
        _uploadError = context.tr('kyc.error.fileTooLarge');
      });
      return;
    }
    setState(() {
      _uploading = true;
      _uploadFailed = false;
      _uploadError = null;
      _certError = null;
    });
    try {
      final res = await AppScope.of(context).api.uploadMyKycDocumentFile(
        vatCertificateRequirement,
        bytes: picked.bytes,
        filename: picked.name,
        docType: vatCertificateRequirement,
      );
      final doc = KycOverview.fromJson(
        res,
      ).currentDocument(vatCertificateRequirement);
      if (!mounted) return;
      setState(() {
        _uploadedId = doc?.id;
        _dirty = true;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _uploadFailed = true;
        _uploadError = context.tr(
          e.code == 'case_locked'
              ? 'vendor.tax.caseLocked'
              : e.code == 'file_too_large'
              ? 'kyc.error.fileTooLarge'
              : 'vendor.tax.uploadFailed',
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _uploadFailed = true;
          _uploadError = context.tr('vendor.tax.uploadFailed');
        });
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// The body to save, or null (with field errors) when something is wrong.
  Map<String, dynamic>? _body() {
    final p = _profile;
    String? tinError;
    String? vrnError;
    String? certError;
    String? tin;
    String? vrn;
    if (_registered) {
      vrn = normaliseVrn(_vrn.text);
      if (vrn == null) vrnError = context.tr('vendor.tax.vrnInvalid');
      if (!(p?.tinFromKyc ?? false)) {
        final raw = _tin.text.trim();
        if (raw.isEmpty) {
          tinError = context.tr('vendor.tax.tinRequired');
        } else {
          tin = normaliseTin(raw);
          if (tin == null) tinError = context.tr('vendor.tax.tinInvalid');
        }
      }
      if (!_hasCertificate) certError = context.tr('vendor.tax.certRequired');
    }
    setState(() {
      _tinError = tinError;
      _vrnError = vrnError;
      _certError = certError;
      _saveError = null;
    });
    if (tinError != null || vrnError != null || certError != null) return null;
    return {
      'vatRegistered': _registered,
      if (_registered) ...{
        'tin': ?tin,
        'vrn': vrn,
        'certificateDocumentId': ?_uploadedId,
      },
      'updatedAt': ?p?.updatedAt,
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    final body = _body();
    if (body == null) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      final res = await AppScope.of(context).api.vendorSaveTaxProfile(body);
      if (!mounted) return;
      setState(() => _apply(TaxProfile.fromJson(res)));
      FFSnack.success(context, context.tr('vendor.tax.saved'));
    } on ApiException catch (e) {
      if (!mounted) return;
      switch (e.code) {
        case 'tax_profile_changed':
          FFSnack.info(context, context.tr('vendor.tax.changedElsewhere'));
          await _load();
        case 'vrn_invalid':
          setState(() => _vrnError = context.tr('vendor.tax.vrnInvalid'));
        case 'tin_invalid':
          setState(() => _tinError = context.tr('vendor.tax.tinInvalid'));
        case 'kyc_tin_invalid':
          // The TIN comes from the verification case and is not 9 digits.
          setState(() => _tinError = context.tr('vendor.tax.kycTinInvalid'));
        case 'tin_required':
          setState(() => _tinError = context.tr('vendor.tax.tinRequired'));
        case 'certificate_required':
          setState(() => _certError = context.tr('vendor.tax.certRequired'));
        case 'owner_only':
          setState(() => _saveError = context.tr('vendor.tax.ownerOnly'));
        default:
          setState(() => _saveError = context.tr('vendor.tax.saveFailed'));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saveError = context.tr('error.network'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _leave() async {
    if (_dirty && _owner) {
      final discard = await showFFConfirmDialog(
        context,
        message: context.tr('vendor.tax.discardBody'),
        confirmLabel: context.tr('vendor.tax.discard'),
        destructive: true,
        confirmKey: const Key('tax-discard-confirm'),
      );
      if (!discard || !mounted) return;
    }
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/vendor/home?open=business');
    }
  }

  String _reason(TaxProfile p) {
    final r = p.rejectReason;
    final text = r != null && taxRejectReasons.contains(r)
        ? context.tr('vendor.tax.reason.$r')
        : context.tr('vendor.tax.reason.other');
    final note = p.rejectNote;
    return note == null ? text : '$text. $note';
  }

  Widget _status(TaxProfile p) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final (String message, FFAlertTone tone) = switch (p.status) {
      _ when p.everVerified && !p.certificateStands => (
        context.tr('vendor.tax.certNotStanding'),
        FFAlertTone.warning,
      ),
      _ when p.changePending => (
        context.tr('vendor.tax.changePending'),
        FFAlertTone.info,
      ),
      'pending' => (context.tr('vendor.tax.statusPending'), FFAlertTone.info),
      'verified' => (
        fillIn(context.tr('vendor.tax.statusVerified'), {
          'date': p.verifiedAt == null
              ? ''
              : formatDate(
                  DateTime.parse(
                    p.verifiedAt!,
                  ).toUtc().add(const Duration(hours: 3)),
                  locale: lang,
                ),
        }),
        FFAlertTone.success,
      ),
      'rejected' => (
        fillIn(context.tr('vendor.tax.statusRejected'), {'reason': _reason(p)}),
        FFAlertTone.warning,
      ),
      _ => (context.tr('vendor.tax.statusNone'), FFAlertTone.info),
    };
    final again =
        _owner &&
        (p.status == 'rejected' || (p.everVerified && !p.certificateStands));
    return Semantics(
      container: true,
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FFAlert(key: const Key('tax-status'), message: message, tone: tone),
          if (again)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FFButton(
                key: const Key('tax-send-again'),
                label: context.tr('vendor.tax.sendAgain'),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: () {
                  setState(() => _registered = true);
                  _vrnFocus.requestFocus();
                },
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final p = _profile;
    final editable = _owner && !_saving && !_uploading;
    final offline = !BrowserOnline.instance.value;
    return PopScope(
      canPop: !_dirty || !_owner,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: _leave),
          title: Text(context.tr('vendor.tax.title')),
        ),
        body: _loading
            ? FFSkeletonList(semanticLabel: context.tr('common.loading'))
            : p == null
            ? ListView(
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                children: [
                  FFErrorState(
                    key: const Key('tax-failed'),
                    message: context.tr('vendor.tax.failed'),
                    onRetry: _load,
                  ),
                ],
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: ListView(
                    padding: const EdgeInsets.all(FFTokens.spacingLg),
                    children: [
                      _status(p),
                      if (!_owner) ...[
                        const SizedBox(height: FFTokens.spacingSm),
                        FFAlert(
                          key: const Key('tax-owner-only'),
                          message: context.tr('vendor.tax.ownerOnly'),
                        ),
                      ],
                      const SizedBox(height: FFTokens.spacingMd),
                      SwitchListTile(
                        key: const Key('tax-registered'),
                        contentPadding: EdgeInsets.zero,
                        value: _registered,
                        onChanged: editable ? _toggle : null,
                        title: Text(context.tr('vendor.tax.registered')),
                      ),
                      if (_registered) ...[
                        const SizedBox(height: FFTokens.spacingSm),
                        // UAT D5: a TIN taken from KYC is said to be
                        // read-only, not only shown that way.
                        Semantics(
                          readOnly: p.tinFromKyc || !editable,
                          label: p.tinFromKyc || !editable
                              ? context.tr('vendor.tax.tinReadOnlyA11y')
                              : null,
                          child: FFTextField(
                            key: const Key('tax-tin'),
                            controller: _tin,
                            label: context.tr('vendor.tax.tin'),
                            readOnly: p.tinFromKyc || !editable,
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[\d\s-]'),
                              ),
                            ],
                            helperText: p.tinFromKyc
                                ? context.tr('vendor.tax.tinFromKyc')
                                : context.tr('vendor.tax.tinHint'),
                            errorText: _tinError,
                            onChanged: (_) => _changed(),
                          ),
                        ),
                        const SizedBox(height: FFTokens.spacingSm),
                        FFTextField(
                          key: const Key('tax-vrn'),
                          controller: _vrn,
                          focusNode: _vrnFocus,
                          label: context.tr('vendor.tax.vrn'),
                          readOnly: !editable,
                          textCapitalization: TextCapitalization.characters,
                          errorText: _vrnError,
                          onChanged: (_) => _changed(),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _certificate(muted, editable),
                      ],
                      const SizedBox(height: FFTokens.spacingMd),
                      for (final k in const [
                        'vendor.tax.howItWorks',
                        'vendor.tax.pastUnchanged',
                        'vendor.tax.appUnchanged',
                        'vendor.tax.pricesInclude',
                      ])
                        Padding(
                          padding: const EdgeInsets.only(
                            bottom: FFTokens.spacingXs,
                          ),
                          child: Text(context.tr(k), style: muted),
                        ),
                      if (_saveError != null) ...[
                        const SizedBox(height: FFTokens.spacingSm),
                        Semantics(
                          liveRegion: true,
                          child: FFAlert(
                            key: const Key('tax-save-error'),
                            message: _saveError!,
                            tone: FFAlertTone.error,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
        bottomNavigationBar: p == null || !_owner
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (offline)
                        Text(
                          context.tr('error.network'),
                          key: const Key('tax-offline'),
                          style: muted,
                        ),
                      FFButton(
                        key: const Key('tax-save'),
                        label: context.tr('vendor.tax.save'),
                        fullWidth: true,
                        visualDensity: VisualDensity.standard,
                        loading: _saving,
                        onPressed: _saving || _uploading || offline
                            ? null
                            : _save,
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _certificate(TextStyle? muted, bool editable) => Column(
    key: const Key('tax-certificate'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        context.tr('vendor.tax.cert'),
        style: Theme.of(context).textTheme.labelLarge,
      ),
      // Told here, not in a snack: one would cover the sticky Save.
      Semantics(
        container: true,
        liveRegion: true,
        child: Text(
          context.tr(
            _uploadedId != null
                ? 'vendor.tax.certUploaded'
                : _hasCertificate
                ? 'kyc.doc.fileAttached'
                : 'kyc.doc.noFile',
          ),
          key: const Key('tax-cert-state'),
        ),
      ),
      Text(context.tr('kyc.doc.fileHint'), style: muted),
      if (_certError != null)
        Text(
          _certError!,
          key: const Key('tax-cert-error'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (_uploadFailed) ...[
        const SizedBox(height: FFTokens.spacingXs),
        Semantics(
          liveRegion: true,
          child: FFAlert(
            key: const Key('tax-upload-failed'),
            message: _uploadError ?? context.tr('vendor.tax.uploadFailed'),
            tone: FFAlertTone.error,
          ),
        ),
      ],
      if (_owner) ...[
        const SizedBox(height: FFTokens.spacingSm),
        if (_uploading)
          Row(
            children: [
              const FFSpinner(),
              const SizedBox(width: FFTokens.spacingSm),
              Text(context.tr('vendor.tax.uploading')),
            ],
          )
        else
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingSm,
            children: [
              FFButton(
                key: const Key('tax-cert-camera'),
                label: context.tr('photo.camera'),
                icon: Icons.photo_camera_outlined,
                variant: FFButtonVariant.secondary,
                visualDensity: VisualDensity.standard,
                onPressed: editable
                    ? () => _upload(DocumentSource.camera)
                    : null,
              ),
              FFButton(
                key: const Key('tax-cert-gallery'),
                label: context.tr('photo.gallery'),
                icon: Icons.photo_library_outlined,
                variant: FFButtonVariant.secondary,
                visualDensity: VisualDensity.standard,
                onPressed: editable
                    ? () => _upload(DocumentSource.gallery)
                    : null,
              ),
              FFButton(
                key: const Key('tax-cert-file'),
                label: context.tr('kyc.doc.choosePdf'),
                icon: Icons.picture_as_pdf_outlined,
                variant: FFButtonVariant.secondary,
                visualDensity: VisualDensity.standard,
                onPressed: editable ? () => _upload(DocumentSource.file) : null,
              ),
            ],
          ),
      ],
    ],
  );
}
