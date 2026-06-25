import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import 'ff_photo_picker_field.dart';

/// Fullscreen form for adding/editing a trainer (used by gym owners).
/// Returns the payload Map on save, or null on cancel.
class TrainerFormPage extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final String title;
  final List<String> defaultGymIds;

  const TrainerFormPage({
    super.key,
    this.initial,
    required this.title,
    this.defaultGymIds = const [],
  });

  @override
  State<TrainerFormPage> createState() => _TrainerFormPageState();
}

class _TrainerFormPageState extends State<TrainerFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _rate;
  late final TextEditingController _bio;
  String _photo = '';
  String _currency = 'TZS';
  List<String> _selectedSpecialties = [];
  List<String> _availableSpecialties = [];
  bool _specialtiesLoaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final t = widget.initial ?? const {};
    _name = TextEditingController(text: t['displayName']?.toString() ?? '');
    _email = TextEditingController(text: t['email']?.toString() ?? '');
    _phone = TextEditingController(text: t['phone']?.toString() ?? '');
    _rate = TextEditingController(
      text: (t['hourlyRateTzs'] as num?)?.toString() ?? '',
    );
    _bio = TextEditingController(text: t['bio']?.toString() ?? '');
    _photo = t['photoUrl']?.toString() ?? '';
    _currency = t['sessionRateCurrency']?.toString() ?? 'TZS';
    _selectedSpecialties =
        (t['specialties'] as List?)?.whereType<String>().toList() ?? [];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_specialtiesLoaded) _loadSpecialties();
  }

  Future<void> _loadSpecialties() async {
    try {
      final api = AppScope.of(context).api;
      final result = await api.getSpecialties();
      if (!mounted) return;
      setState(() {
        _availableSpecialties = result.whereType<String>().toList();
        _specialtiesLoaded = true;
      });
    } on ApiException {
      if (mounted) setState(() => _specialtiesLoaded = true);
    }
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? context.tr('onboarding.required')
      : null;

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('onboarding.required');
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
    return ok ? null : context.tr('onboarding.invalidEmail');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'displayName': _name.text.trim(),
        'email': _email.text.trim(),
        'phone': _phone.text.trim(),
        'specialties': _selectedSpecialties,
        'hourlyRateTzs': num.tryParse(_rate.text.trim()) ?? 0,
        'sessionRateCurrency': _currency,
        'bio': _bio.text.trim(),
        'photoUrl': _photo,
        if (widget.initial == null && widget.defaultGymIds.isNotEmpty)
          'gymIds': widget.defaultGymIds,
        'status': 'active',
      };
      Navigator.of(context).pop(payload);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton(
            key: const Key('trainerFormSave'),
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('member.save')),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              // Photo
              Center(
                child: FFPhotoPickerField(
                  value: _photo.isEmpty ? null : _photo,
                  onChanged: (url) => setState(() => _photo = url),
                  size: 96,
                ),
              ),
              const SizedBox(height: 16),
              // Name
              FFTextField(
                key: const Key('trainerFormName'),
                controller: _name,
                label: context.tr('ownerReg.trainerName'),
                validator: _required,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              // Email
              FFTextField(
                key: const Key('trainerFormEmail'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                enabled: !isEdit,
                label: context.tr('ownerReg.trainerEmail'),
                validator: isEdit ? null : _emailValidator,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              // Phone
              FFTextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                label: context.tr('member.phone'),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              // Rate + currency row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: FFTextField(
                      key: const Key('trainerFormRate'),
                      controller: _rate,
                      keyboardType: TextInputType.number,
                      label: context.tr('ownerReg.trainerRate'),
                      validator: (v) {
                        final n = num.tryParse((v ?? '').trim());
                        if (n == null || n < 0) {
                          return context.tr('onboarding.required');
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: FFTokens.spacingSm),
                  FFDropdownField<String>(
                    width: 100,
                    value: _currency,
                    label: 'Currency',
                    items: const [
                      DropdownMenuItem(value: 'TZS', child: Text('TZS')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                    ],
                    onChanged: (v) => setState(() => _currency = v ?? 'TZS'),
                  ),
                ],
              ),
              const SizedBox(height: FFTokens.spacingSm),
              // Specialties chips
              FFFieldLabel(context.tr('ownerReg.trainerSpecialties')),
              if (!_specialtiesLoaded)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_availableSpecialties.isEmpty)
                Text(
                  context.tr('onboarding.required'),
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableSpecialties.map((s) {
                    final selected = _selectedSpecialties.contains(s);
                    return FilterChip(
                      label: Text(s),
                      selected: selected,
                      onSelected: (v) => setState(() {
                        if (v) {
                          _selectedSpecialties = [..._selectedSpecialties, s];
                        } else {
                          _selectedSpecialties = _selectedSpecialties
                              .where((x) => x != s)
                              .toList();
                        }
                      }),
                    );
                  }).toList(),
                ),
              const SizedBox(height: FFTokens.spacingSm),
              // Bio
              FFTextField(
                controller: _bio,
                maxLines: 3,
                label: context.tr('trainerReg.bio'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<Map<String, dynamic>?> openTrainerForm(
  BuildContext context, {
  Map<String, dynamic>? initial,
  required String title,
  List<String> defaultGymIds = const [],
}) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TrainerFormPage(
        initial: initial,
        title: title,
        defaultGymIds: defaultGymIds,
      ),
    ),
  );
}
