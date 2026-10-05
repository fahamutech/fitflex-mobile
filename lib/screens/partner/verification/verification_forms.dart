// Partner verification forms: identity, business details, one document (its
// details and file), and payout accounts. Each form saves to the API and
// returns the refreshed overview to the verification centre.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'verification_models.dart';
import 'verification_repository.dart';

const _maxFileBytes = 10 * 1024 * 1024;

String _errorText(BuildContext context, Object e) {
  if (e is ApiException) {
    final key = switch (e.code) {
      'case_locked' => 'kyc.locked',
      'file_too_large' => 'kyc.error.fileTooLarge',
      'unsupported_file_type' => 'kyc.error.fileType',
      'encrypted_pdf' => 'kyc.error.encryptedPdf',
      'pdf_with_active_content' => 'kyc.error.pdfContent',
      'unreadable_image' => 'kyc.error.unreadableImage',
      'storage_service_unavailable' ||
      'storage_upload_failed' => 'kyc.error.storage',
      'account_already_added' => 'kyc.error.accountExists',
      'too_many_accounts' => 'kyc.error.tooManyAccounts',
      'invalid_mobile_number' => 'kyc.error.mobileNumber',
      'expiresOn_before_issuedOn' => 'kyc.error.dates',
      'invalid_email' => 'kyc.error.email',
      _ => null,
    };
    if (key != null) return context.tr(key);
  }
  return errorMessage(FFLocaleScope.of(context), e);
}

// Replace any message still showing rather than queueing behind it.
void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));

String? _blankToNull(String v) => v.trim().isEmpty ? null : v.trim();

/// A form page scaffold with a save button that shows progress.
class _FormScaffold extends StatelessWidget {
  const _FormScaffold({
    required this.title,
    required this.formKey,
    required this.busy,
    required this.onSave,
    required this.children,
  });
  final String title;
  final GlobalKey<FormState> formKey;
  final bool busy;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: children,
      ),
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(FFTokens.spacingLg),
      child: FilledButton(
        key: const Key('kyc-form-save'),
        onPressed: busy ? null : onSave,
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(context.tr('kyc.save')),
      ),
    ),
  );
}

Widget _gap() => const SizedBox(height: FFTokens.spacingMd);

Widget _text(
  BuildContext context,
  String key,
  TextEditingController c, {
  bool required = false,
  TextInputType? keyboard,
  String? hintKey,
  String? Function(String)? check,
}) => Padding(
  padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
  child: TextFormField(
    key: Key('kyc-field-$key'),
    controller: c,
    keyboardType: keyboard,
    decoration: InputDecoration(
      labelText: context.tr('kyc.field.$key') + (required ? ' *' : ''),
      helperText: hintKey == null ? null : context.tr(hintKey),
      border: const OutlineInputBorder(),
    ),
    validator: (v) {
      final value = v ?? '';
      if (required && value.trim().isEmpty) return context.tr('kyc.required');
      return check?.call(value);
    },
  ),
);

Widget _choice(
  BuildContext context,
  String key,
  String? value,
  List<String> options,
  ValueChanged<String?> onChanged, {
  bool required = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
  child: DropdownButtonFormField<String>(
    key: Key('kyc-field-$key'),
    initialValue: options.contains(value) ? value : null,
    isExpanded: true,
    decoration: InputDecoration(
      labelText: context.tr('kyc.field.$key') + (required ? ' *' : ''),
      border: const OutlineInputBorder(),
    ),
    items: [
      for (final o in options)
        DropdownMenuItem(value: o, child: Text(context.tr('kyc.option.$o'))),
    ],
    onChanged: onChanged,
    validator: (v) => required && v == null ? context.tr('kyc.required') : null,
  ),
);

/// A YYYY-MM-DD date field with a date picker.
class _DateField extends StatelessWidget {
  const _DateField({
    required this.fieldKey,
    required this.value,
    required this.onChanged,
    this.required = false,
  });
  final String fieldKey;
  final String? value;
  final ValueChanged<String?> onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
    child: FormField<String>(
      initialValue: value,
      validator: (v) => required && (v == null || v.isEmpty)
          ? context.tr('kyc.required')
          : null,
      builder: (state) => InkWell(
        key: Key('kyc-field-$fieldKey'),
        onTap: () async {
          final now = DateTime.now();
          final initial = DateTime.tryParse(state.value ?? '') ?? now;
          final picked = await showDatePicker(
            context: context,
            initialDate: initial,
            firstDate: DateTime(now.year - 80),
            lastDate: DateTime(now.year + 30),
          );
          if (picked == null) return;
          final day = picked.toIso8601String().substring(0, 10);
          state.didChange(day);
          onChanged(day);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText:
                context.tr('kyc.field.$fieldKey') + (required ? ' *' : ''),
            border: const OutlineInputBorder(),
            errorText: state.errorText,
            suffixIcon: const Icon(Icons.calendar_today_outlined),
          ),
          child: Text(state.value ?? ''),
        ),
      ),
    ),
  );
}

class _AddressFields {
  _AddressFields(KycAddress a)
    : line1 = TextEditingController(text: a.line1),
      city = TextEditingController(text: a.city),
      region = TextEditingController(text: a.region);
  final TextEditingController line1;
  final TextEditingController city;
  final TextEditingController region;

  List<Widget> build(
    BuildContext context,
    String prefix, {
    bool required = true,
  }) => [
    _text(context, '${prefix}Line1', line1, required: required),
    _text(context, '${prefix}City', city, required: required),
    _text(context, '${prefix}Region', region),
  ];

  Map<String, dynamic> toJson() => {
    'line1': line1.text.trim(),
    'city': city.text.trim(),
    'region': region.text.trim(),
    'country': 'TZ',
  };

  void dispose() {
    line1.dispose();
    city.dispose();
    region.dispose();
  }
}

String? _checkEmail(BuildContext context, String v) =>
    v.trim().isEmpty || RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim())
    ? null
    : context.tr('kyc.error.email');

// ── Identity ────────────────────────────────────────────────────────────────

class PersonFormPage extends StatefulWidget {
  const PersonFormPage({
    super.key,
    required this.repository,
    required this.overview,
  });
  final VerificationRepository repository;
  final KycOverview overview;

  @override
  State<PersonFormPage> createState() => _PersonFormPageState();
}

class _PersonFormPageState extends State<PersonFormPage> {
  final _form = GlobalKey<FormState>();
  late final String _role = personRoleFor(widget.overview.partnerType);
  late final List<String> _fields = personFieldsFor(
    widget.overview.partnerType,
  );
  late final KycPerson _p =
      widget.overview.personFor(_role) ?? KycPerson(role: _role);
  late final _name = TextEditingController(text: _p.fullName);
  late final _idNumber = TextEditingController(text: _p.idNumber);
  late final _phone = TextEditingController(text: _p.phone);
  late final _email = TextEditingController(text: _p.email);
  late final _position = TextEditingController(text: _p.position);
  late final _address = _AddressFields(_p.address);
  late String _nationality = _p.nationality ?? 'TZ';
  late String? _idType = _p.idType ?? 'nida';
  late String? _relationship = _p.relationship;
  late String? _authority = _p.authority;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_name, _idNumber, _phone, _email, _position]) {
      c.dispose();
    }
    _address.dispose();
    super.dispose();
  }

  bool get _isTrainer => widget.overview.partnerType == 'trainer';

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'fullName': _name.text.trim(),
        'nationality': _nationality,
        'idType': _idType,
        'idNumber': _blankToNull(_idNumber.text),
        if (_fields.contains('phone')) 'phone': _blankToNull(_phone.text),
        if (_fields.contains('email')) 'email': _blankToNull(_email.text),
        if (_fields.contains('address')) 'address': _address.toJson(),
        if (_fields.contains('position'))
          'position': _blankToNull(_position.text),
        if (_fields.contains('relationship')) 'relationship': _relationship,
        if (_fields.contains('authority')) 'authority': _authority,
      };
      final updated = await widget.repository.updatePerson(_role, body);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendor = widget.overview.partnerType == 'vendor';
    // Tanzanian trainers identify with NIDA; everyone else may use a passport.
    final idTypes = _isTrainer
        ? (_nationality == 'TZ' ? const ['nida'] : const ['passport'])
        : const ['nida', 'passport'];
    if (!idTypes.contains(_idType)) _idType = idTypes.first;
    return _FormScaffold(
      title: context.tr(
        vendor ? 'kyc.form.representative' : 'kyc.form.identity',
      ),
      formKey: _form,
      busy: _busy,
      onSave: _save,
      children: [
        Text(
          context.tr(
            vendor ? 'kyc.form.representativeIntro' : 'kyc.form.identityIntro',
          ),
        ),
        _gap(),
        _text(context, 'fullName', _name, required: true),
        Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
          child: DropdownButtonFormField<String>(
            key: const Key('kyc-field-nationality'),
            initialValue: countries.containsKey(_nationality)
                ? _nationality
                : 'TZ',
            isExpanded: true,
            decoration: InputDecoration(
              labelText: context.tr('kyc.field.nationality'),
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final e in countries.entries)
                DropdownMenuItem(
                  value: e.key,
                  child: Text(context.tr('kyc.country.${e.key}')),
                ),
            ],
            onChanged: (v) => setState(() => _nationality = v ?? 'TZ'),
          ),
        ),
        _choice(
          context,
          'idType',
          _idType,
          idTypes,
          (v) => setState(() => _idType = v),
          required: true,
        ),
        _text(
          context,
          'idNumber',
          _idNumber,
          required: true,
          hintKey: _idType == 'nida' ? 'kyc.hint.nida' : null,
        ),
        if (_fields.contains('position')) _text(context, 'position', _position),
        if (_fields.contains('relationship'))
          _choice(
            context,
            'relationship',
            _relationship,
            relationships,
            (v) => setState(() => _relationship = v),
            required: true,
          ),
        if (_fields.contains('authority'))
          _choice(
            context,
            'authority',
            _authority,
            authorities,
            (v) => setState(() => _authority = v),
          ),
        if (_fields.contains('phone'))
          _text(
            context,
            'phone',
            _phone,
            required: !vendor,
            keyboard: TextInputType.phone,
          ),
        if (_fields.contains('email'))
          _text(
            context,
            'email',
            _email,
            required: !vendor,
            keyboard: TextInputType.emailAddress,
            check: (v) => _checkEmail(context, v),
          ),
        if (_fields.contains('address')) ...[
          FFSectionTitle(context.tr('kyc.field.address')),
          ..._address.build(context, 'address'),
        ],
      ],
    );
  }
}

// ── Business ────────────────────────────────────────────────────────────────

class BusinessFormPage extends StatefulWidget {
  const BusinessFormPage({
    super.key,
    required this.repository,
    required this.overview,
  });
  final VerificationRepository repository;
  final KycOverview overview;

  @override
  State<BusinessFormPage> createState() => _BusinessFormPageState();
}

class _BusinessFormPageState extends State<BusinessFormPage> {
  final _form = GlobalKey<FormState>();
  late final KycCaseInfo? _c = widget.overview.kycCase;
  late final _legalName = TextEditingController(text: _c?.legalName);
  late final _tradingName = TextEditingController(text: _c?.tradingName);
  late final _registration = TextEditingController(
    text: _c?.registrationNumber,
  );
  late final _tin = TextEditingController(text: _c?.tin);
  late final _address = _AddressFields(
    _c?.registeredAddress ?? const KycAddress(),
  );
  late String? _entityType = _c?.entityType;
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_legalName, _tradingName, _registration, _tin]) {
      c.dispose();
    }
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.updateBusiness({
        'legalName': _legalName.text.trim(),
        'tradingName': _tradingName.text.trim(),
        'entityType': _entityType,
        'registrationNumber': _registration.text.trim(),
        'registrationAuthority': 'BRELA',
        'tin': _tin.text.trim(),
        'registeredAddress': _address.toJson(),
      });
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Vendors only have to give the TIN; the rest is collected if they have it.
  bool get _strict => widget.overview.partnerType != 'vendor';

  @override
  Widget build(BuildContext context) => _FormScaffold(
    title: context.tr('kyc.form.business'),
    formKey: _form,
    busy: _busy,
    onSave: _save,
    children: [
      Text(context.tr('kyc.form.businessIntro')),
      _gap(),
      _text(context, 'legalName', _legalName, required: _strict),
      _text(context, 'tradingName', _tradingName, required: _strict),
      _choice(
        context,
        'entityType',
        _entityType,
        entityTypes,
        (v) => setState(() => _entityType = v),
        required: _strict,
      ),
      _text(
        context,
        'registrationNumber',
        _registration,
        required: _strict,
        hintKey: 'kyc.hint.brela',
      ),
      _text(
        context,
        'tin',
        _tin,
        required: true,
        keyboard: TextInputType.number,
      ),
      FFSectionTitle(context.tr('kyc.field.registeredAddress')),
      ..._address.build(context, 'address', required: _strict),
    ],
  );
}

// ── Documents ───────────────────────────────────────────────────────────────

enum DocumentSource { camera, gallery, file }

class PickedDocument {
  const PickedDocument(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

typedef PickDocument = Future<PickedDocument?> Function(DocumentSource source);

/// The device's camera, gallery or file picker.
Future<PickedDocument?> pickDocumentFromDevice(DocumentSource source) async {
  if (source == DocumentSource.file) {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (file == null) return null;
    return PickedDocument(await file.readAsBytes(), file.name);
  }
  final image = await ImagePicker().pickImage(
    source: source == DocumentSource.camera
        ? ImageSource.camera
        : ImageSource.gallery,
    maxWidth: 2400,
    maxHeight: 2400,
    imageQuality: 85,
  );
  if (image == null) return null;
  return PickedDocument(await image.readAsBytes(), image.name);
}

class DocumentPage extends StatefulWidget {
  const DocumentPage({
    super.key,
    required this.repository,
    required this.overview,
    required this.requirementKey,
    required this.pickDocument,
  });
  final VerificationRepository repository;
  final KycOverview overview;
  final String requirementKey;
  final PickDocument pickDocument;

  @override
  State<DocumentPage> createState() => _DocumentPageState();
}

class _DocumentPageState extends State<DocumentPage> {
  final _form = GlobalKey<FormState>();
  late KycOverview _overview = widget.overview;
  late final DocumentSpec _spec =
      documentSpecs[widget.requirementKey] ?? const DocumentSpec(['other'], []);
  late final KycDocument? _doc = widget.overview.currentDocument(
    widget.requirementKey,
  );
  // A reviewed document starts over: its details aren't carried into the new one.
  late final bool _fresh = _doc == null || _doc.status != 'pending';
  late final _number = TextEditingController(
    text: _fresh ? null : _doc?.documentNumber,
  );
  late final _issuer = TextEditingController(
    text: _fresh ? null : _doc?.issuer,
  );
  late String? _issuedOn = _fresh ? null : _doc?.issuedOn;
  late String? _expiresOn = _fresh ? null : _doc?.expiresOn;
  late String _docType = (_doc != null && _spec.types.contains(_doc.docType))
      ? _doc.docType
      : _spec.types.first;
  bool _busy = false;

  @override
  void dispose() {
    _number.dispose();
    _issuer.dispose();
    super.dispose();
  }

  KycDocument? get _current => _overview.currentDocument(widget.requirementKey);

  Future<void> _upload(DocumentSource source) async {
    final picked = await widget.pickDocument(source);
    if (picked == null || !mounted) return;
    if (picked.bytes.length > _maxFileBytes) {
      return _snack(context, context.tr('kyc.error.fileTooLarge'));
    }
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.uploadDocumentFile(
        widget.requirementKey,
        bytes: picked.bytes,
        filename: picked.name,
        docType: _docType,
      );
      if (!mounted) return;
      setState(() => _overview = updated);
      _snack(context, context.tr('kyc.doc.uploaded'));
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final updated = await widget.repository
          .updateDocument(widget.requirementKey, {
            'docType': _docType,
            if (_spec.fields.contains('documentNumber'))
              'documentNumber': _blankToNull(_number.text),
            if (_spec.fields.contains('issuer'))
              'issuer': _blankToNull(_issuer.text),
            if (_spec.fields.contains('issuedOn')) 'issuedOn': _issuedOn,
            if (_spec.fields.contains('expiresOn')) 'expiresOn': _expiresOn,
          });
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final hasFile =
        current != null && current.status == 'pending' && current.hasFile;
    final rejected = current != null && current.status == 'rejected';
    return _FormScaffold(
      title: context.tr('kyc.item.${_titleKey(widget.requirementKey)}'),
      formKey: _form,
      busy: _busy,
      onSave: _save,
      children: [
        if (rejected)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
            child: FFAlert(
              message: [
                context.tr('kyc.doc.rejected'),
                if (current.reviewNote != null) current.reviewNote!,
              ].join('\n\n'),
              tone: FFAlertTone.error,
            ),
          ),
        Text(context.tr('kyc.doc.intro.${widget.requirementKey}')),
        _gap(),
        if (_spec.types.length > 1)
          _choice(
            context,
            'docType',
            _docType,
            _spec.types,
            (v) => setState(() => _docType = v ?? _docType),
            required: true,
          ),
        if (_spec.fields.contains('issuer'))
          _text(
            context,
            _issuerLabel(widget.requirementKey),
            _issuer,
            required: true,
          ),
        if (_spec.fields.contains('documentNumber'))
          _text(
            context,
            _numberLabel(widget.requirementKey),
            _number,
            required: true,
          ),
        if (_spec.fields.contains('issuedOn'))
          _DateField(
            fieldKey: 'issuedOn',
            value: _issuedOn,
            required: true,
            onChanged: (v) => setState(() => _issuedOn = v),
          ),
        if (_spec.fields.contains('expiresOn'))
          _DateField(
            fieldKey: 'expiresOn',
            value: _expiresOn,
            required: true,
            onChanged: (v) => setState(() => _expiresOn = v),
          ),
        FFSectionTitle(context.tr('kyc.doc.file')),
        FFCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasFile
                        ? Icons.check_circle_outline
                        : Icons.upload_file_outlined,
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  Expanded(
                    child: Text(
                      hasFile
                          ? (current.fileName ??
                                context.tr('kyc.doc.fileAttached'))
                          : context.tr('kyc.doc.noFile'),
                      key: const Key('kyc-doc-file-name'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                context.tr('kyc.doc.fileHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              Wrap(
                spacing: FFTokens.spacingSm,
                runSpacing: FFTokens.spacingSm,
                children: [
                  OutlinedButton.icon(
                    key: const Key('kyc-doc-camera'),
                    onPressed: _busy
                        ? null
                        : () => _upload(DocumentSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(context.tr('photo.camera')),
                  ),
                  OutlinedButton.icon(
                    key: const Key('kyc-doc-gallery'),
                    onPressed: _busy
                        ? null
                        : () => _upload(DocumentSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(context.tr('photo.gallery')),
                  ),
                  OutlinedButton.icon(
                    key: const Key('kyc-doc-pdf'),
                    onPressed: _busy
                        ? null
                        : () => _upload(DocumentSource.file),
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(context.tr('kyc.doc.choosePdf')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _issuerLabel(String requirementKey) => switch (requirementKey) {
    'certification' => 'certificationBody',
    'liability_insurance' => 'insurer',
    _ => 'issuingAuthority',
  };

  static String _numberLabel(String requirementKey) => switch (requirementKey) {
    'owner_id' || 'trainer_id' || 'representative_id' => 'idNumber',
    'business_registration' => 'registrationNumber',
    'tin_certificate' => 'tin',
    'business_licence' => 'licenceNumber',
    'certification' => 'certificateNumber',
    'liability_insurance' => 'policyNumber',
    _ => 'documentNumber',
  };

  /// The checklist label that matches this document.
  static String _titleKey(String requirementKey) => switch (requirementKey) {
    'owner_id' || 'trainer_id' || 'representative_id' => 'id_document',
    'business_registration' => 'registration_certificate',
    'tin_certificate' => 'tin_certificate',
    'business_licence' => 'licence',
    'certification' => 'certification',
    'liability_insurance' => 'liability_cover',
    'representative_authority' => 'authority_document',
    _ => requirementKey,
  };
}

// ── Payout accounts ─────────────────────────────────────────────────────────

class PayoutAccountsPage extends StatefulWidget {
  const PayoutAccountsPage({
    super.key,
    required this.repository,
    required this.overview,
  });
  final VerificationRepository repository;
  final KycOverview overview;

  @override
  State<PayoutAccountsPage> createState() => _PayoutAccountsPageState();
}

class _PayoutAccountsPageState extends State<PayoutAccountsPage> {
  late List<PayoutAccount> _accounts = widget.overview.accounts;
  bool _busy = false;

  Future<void> _reload() async {
    final data = await widget.repository.overview();
    if (mounted) setState(() => _accounts = data.accounts);
  }

  Future<void> _add() async {
    final added = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _AddAccountPage(repository: widget.repository),
      ),
    );
    if (added == true) await _reload();
  }

  Future<void> _remove(PayoutAccount a) async {
    setState(() => _busy = true);
    try {
      await widget.repository.removePayoutAccount(a.id);
      await _reload();
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('kyc.accounts.title'))),
    body: ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(context.tr('kyc.accounts.intro')),
        _gap(),
        if (_accounts.isEmpty)
          FFEmptyState(title: context.tr('kyc.accounts.empty'))
        else
          for (final a in _accounts)
            FFCard(
              key: Key('kyc-account-${a.id}'),
              margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
              child: Row(
                children: [
                  Icon(
                    a.method == 'bank'
                        ? Icons.account_balance_outlined
                        : Icons.phone_android_outlined,
                  ),
                  const SizedBox(width: FFTokens.spacingMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${a.method == 'bank' ? a.provider : context.tr('kyc.option.${a.provider}')} · ${a.accountNumber}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(a.accountName),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          children: [
                            FFBadge(
                              label: context.tr('kyc.account.${a.status}'),
                              tone: switch (a.status) {
                                'verified' => FFBadgeTone.success,
                                'rejected' || 'disabled' => FFBadgeTone.danger,
                                _ => FFBadgeTone.warning,
                              },
                            ),
                            if (a.isPrimary)
                              FFBadge(
                                label: context.tr('kyc.account.primary'),
                                tone: FFBadgeTone.brand,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (a.status == 'pending_verification')
                    IconButton(
                      tooltip: context.tr('kyc.remove'),
                      onPressed: _busy ? null : () => _remove(a),
                      icon: const Icon(Icons.delete_outline),
                    ),
                ],
              ),
            ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.all(FFTokens.spacingLg),
      child: FilledButton.icon(
        key: const Key('kyc-account-add'),
        onPressed: _busy ? null : _add,
        icon: const Icon(Icons.add),
        label: Text(context.tr('kyc.accounts.add')),
      ),
    ),
  );
}

class _AddAccountPage extends StatefulWidget {
  const _AddAccountPage({required this.repository});
  final VerificationRepository repository;

  @override
  State<_AddAccountPage> createState() => _AddAccountPageState();
}

class _AddAccountPageState extends State<_AddAccountPage> {
  final _form = GlobalKey<FormState>();
  String _method = 'mobile_money';
  String? _mobileProvider = 'mpesa';
  final _bank = TextEditingController();
  final _name = TextEditingController();
  final _number = TextEditingController();
  final _branch = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_bank, _name, _number, _branch]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await widget.repository.addPayoutAccount({
        'method': _method,
        'provider': _method == 'bank' ? _bank.text.trim() : _mobileProvider,
        'accountName': _name.text.trim(),
        'accountNumber': _number.text.trim(),
        if (_method == 'bank' && _branch.text.trim().isNotEmpty)
          'branch': _branch.text.trim(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FormScaffold(
    title: context.tr('kyc.accounts.add'),
    formKey: _form,
    busy: _busy,
    onSave: _save,
    children: [
      SegmentedButton<String>(
        key: const Key('kyc-account-method'),
        segments: [
          ButtonSegment(
            value: 'mobile_money',
            label: Text(context.tr('kyc.option.mobile_money')),
          ),
          ButtonSegment(
            value: 'bank',
            label: Text(context.tr('kyc.option.bank')),
          ),
        ],
        selected: {_method},
        onSelectionChanged: (s) => setState(() => _method = s.first),
      ),
      _gap(),
      if (_method == 'mobile_money')
        _choice(
          context,
          'provider',
          _mobileProvider,
          mobileMoneyProviders,
          (v) => setState(() => _mobileProvider = v),
          required: true,
        )
      else
        _text(context, 'bank', _bank, required: true),
      _text(
        context,
        'accountName',
        _name,
        required: true,
        hintKey: 'kyc.hint.accountName',
      ),
      _text(
        context,
        _method == 'bank' ? 'accountNumber' : 'mobileNumber',
        _number,
        required: true,
        keyboard: _method == 'bank'
            ? TextInputType.number
            : TextInputType.phone,
      ),
      if (_method == 'bank') _text(context, 'branch', _branch),
      Text(
        context.tr('kyc.accounts.verifyNote'),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

/// One agreement (partner terms or verification consent) to read and accept.
/// Returns the refreshed overview once accepted.
class AgreementPage extends StatefulWidget {
  const AgreementPage({
    super.key,
    required this.repository,
    required this.agreementType,
  });

  final VerificationRepository repository;
  final String agreementType;

  @override
  State<AgreementPage> createState() => _AgreementPageState();
}

class _AgreementPageState extends State<AgreementPage> {
  KycAgreement? _agreement;
  Object? _loadError;
  bool _agreed = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_agreement == null && _loadError == null) _load();
  }

  Future<void> _load() async {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    try {
      final list = await widget.repository.agreements(lang);
      final match = list.where((a) => a.agreementType == widget.agreementType);
      if (!mounted) return;
      setState(() {
        _agreement = match.isEmpty ? null : match.first;
        _loadError = match.isEmpty ? StateError('not_found') : null;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final updated = await widget.repository.acceptAgreement(_agreement!);
      if (!mounted) return;
      _snack(context, context.tr('kyc.agreement.done'));
      Navigator.of(context).pop(updated);
    } catch (e) {
      if (mounted) _snack(context, _errorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _agreement;
    return Scaffold(
      appBar: AppBar(
        title: Text(a?.title ?? context.tr('kyc.agreement.title')),
      ),
      body: a == null
          ? Center(
              child: _loadError == null
                  ? const CircularProgressIndicator()
                  : Padding(
                      padding: const EdgeInsets.all(FFTokens.spacingLg),
                      child: Text(context.tr('kyc.agreement.loadFailed')),
                    ),
            )
          : ListView(
              key: const Key('kyc-agreement-text'),
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                Text(
                  [
                    ?a.reference,
                    context
                        .tr('kyc.agreement.version')
                        .replaceFirst('{v}', a.version),
                  ].join(' · '),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                for (final s in a.sections) ...[
                  _gap(),
                  Text(
                    s.heading,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(s.text),
                ],
                _gap(),
                if (a.accepted)
                  FFAlert(
                    key: const Key('kyc-agreement-accepted'),
                    tone: FFAlertTone.success,
                    message: context
                        .tr('kyc.agreement.accepted')
                        .replaceFirst(
                          '{date}',
                          a.acceptedAt!.toLocal().toIso8601String().substring(
                            0,
                            10,
                          ),
                        ),
                  )
                else
                  CheckboxListTile(
                    key: const Key('kyc-agreement-check'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _agreed,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _agreed = v ?? false),
                    title: Text(context.tr('kyc.agreement.confirm')),
                  ),
              ],
            ),
      bottomNavigationBar: a == null || a.accepted
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(FFTokens.spacingLg),
              child: FilledButton(
                key: const Key('kyc-agreement-accept'),
                onPressed: _busy || !_agreed ? null : _accept,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(context.tr('kyc.agreement.accept')),
              ),
            ),
    );
  }
}
