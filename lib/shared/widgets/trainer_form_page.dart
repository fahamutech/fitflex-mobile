import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../models.dart';
import 'ff_photo_picker_field.dart';
import 'social_links.dart';

/// Fullscreen form for adding/editing a trainer (used by gym owners).
/// Returns the payload Map on save, or null on cancel.
class TrainerFormPage extends StatefulWidget {
  final Map<String, dynamic>? initial;
  final String title;
  final List<String> defaultGymIds;
  final bool requireInitialPin;

  const TrainerFormPage({
    super.key,
    this.initial,
    required this.title,
    this.defaultGymIds = const [],
    this.requireInitialPin = false,
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
  late final TextEditingController _initialPin;
  late final Map<String, TextEditingController> _socials;
  String _photo = '';
  String _currency = 'TZS';
  List<String> _selectedSpecialties = [];
  List<Map<String, dynamic>> _availability = [];
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
    _initialPin = TextEditingController();
    _socials = SocialHandleFields.controllersFor(
      SocialLinks.fromJson(t['socialLinks']),
    );
    _photo = t['photoUrl']?.toString() ?? '';
    _currency = t['sessionRateCurrency']?.toString() ?? 'TZS';
    _selectedSpecialties =
        (t['specialties'] as List?)?.whereType<String>().toList() ?? [];
    _availability =
        (t['availability'] as List?)
            ?.whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList() ??
        [];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_specialtiesLoaded) _loadSpecialties();
  }

  @override
  void dispose() {
    for (final c in _socials.values) {
      c.dispose();
    }
    super.dispose();
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

  String? _pinValidator(String? v) =>
      RegExp(r'^\d{4}$').hasMatch((v ?? '').trim())
      ? null
      : context.tr('onboarding.required');

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
        'availability': _availability,
        'socialLinks': SocialHandleFields.valuesOf(_socials),
        if (widget.requireInitialPin) 'initialPin': _initialPin.text.trim(),
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
              if (widget.requireInitialPin) ...[
                FFTextField(
                  key: const Key('trainerFormPin'),
                  controller: _initialPin,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  label: context.tr('owner.initialPin'),
                  validator: _pinValidator,
                ),
                const SizedBox(height: FFTokens.spacingSm),
              ],
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
                    label: context.tr('common.currency'),
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
              const SizedBox(height: FFTokens.spacingMd),
              FFFieldLabel(context.tr('social.title')),
              SocialHandleFields(controllers: _socials),
              const SizedBox(height: FFTokens.spacingSm),
              FFFieldLabel(context.tr('trainer.availability')),
              Text(
                context.tr('trainer.availabilityHint'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              ..._availability.asMap().entries.map((entry) {
                final value = entry.value;
                final day =
                    value['day']?.toString() ??
                    value['date']?.toString() ??
                    context.tr('trainer.availability');
                final slots =
                    (value['slots'] as List?)
                        ?.map((slot) => slot.toString())
                        .join(', ') ??
                    '';
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(day),
                  subtitle: Text(slots),
                  trailing: IconButton(
                    tooltip: context.tr('member.delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () =>
                        setState(() => _availability.removeAt(entry.key)),
                  ),
                );
              }),
              OutlinedButton.icon(
                key: const Key('trainer-availability-add'),
                onPressed: _addAvailability,
                icon: const Icon(Icons.add),
                label: Text(context.tr('trainer.addAvailability')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addAvailability() async {
    final day = TextEditingController();
    final slots = TextEditingController();
    final entry = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dialogContext.tr('trainer.addAvailability')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const Key('trainer-availability-day'),
              controller: day,
              decoration: InputDecoration(
                labelText: dialogContext.tr('trainer.availabilityDay'),
              ),
            ),
            TextField(
              key: const Key('trainer-availability-slots'),
              controller: slots,
              decoration: InputDecoration(
                labelText: dialogContext.tr('trainer.availabilitySlots'),
                hintText: '09:00, 10:00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dialogContext.tr('member.cancel')),
          ),
          FilledButton(
            key: const Key('trainer-availability-save'),
            onPressed: () {
              final selectedSlots = slots.text
                  .split(',')
                  .map((slot) => slot.trim())
                  .where((slot) => slot.isNotEmpty)
                  .toList();
              if (day.text.trim().isEmpty || selectedSlots.isEmpty) return;
              Navigator.pop(dialogContext, {
                'day': day.text.trim().toLowerCase(),
                'slots': selectedSlots,
              });
            },
            child: Text(dialogContext.tr('member.save')),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 300), () {
      day.dispose();
      slots.dispose();
    });
    if (entry != null && mounted) setState(() => _availability.add(entry));
  }
}

Future<Map<String, dynamic>?> openTrainerForm(
  BuildContext context, {
  Map<String, dynamic>? initial,
  required String title,
  List<String> defaultGymIds = const [],
  bool requireInitialPin = false,
}) {
  return Navigator.of(context).push<Map<String, dynamic>>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TrainerFormPage(
        initial: initial,
        title: title,
        defaultGymIds: defaultGymIds,
        requireInitialPin: requireInitialPin,
      ),
    ),
  );
}
