import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';

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
  final _picker = ImagePicker();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _rate;
  late final TextEditingController _specialties;
  late final TextEditingController _bio;
  String _photo = '';
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
    _specialties = TextEditingController(
      text: (t['specialties'] as List? ?? const []).join(', '),
    );
    _bio = TextEditingController(text: t['bio']?.toString() ?? '');
    _photo = t['photoUrl']?.toString() ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _rate.dispose();
    _specialties.dispose();
    _bio.dispose();
    super.dispose();
  }

  String? _required(String? v) => (v == null || v.trim().isEmpty)
      ? context.tr('onboarding.required')
      : null;

  String? _emailValidator(String? v) {
    if (v == null || v.trim().isEmpty) return context.tr('onboarding.required');
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());
    return ok ? null : context.tr('onboarding.invalidEmail');
  }

  Future<void> _pickPhoto() async {
    final file = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      imageQuality: 80,
    );
    if (!mounted) return;
    if (file != null) setState(() => _photo = file.path);
  }

  Future<String> _encodedPhoto() async {
    if (_photo.isEmpty ||
        _photo.startsWith('http') ||
        _photo.startsWith('data:')) {
      return _photo;
    }
    final f = File(_photo);
    if (!await f.exists()) return '';
    final bytes = await f.readAsBytes();
    final ext = _photo.split('.').last.toLowerCase();
    final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
    return 'data:$mime;base64,${base64Encode(bytes)}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    final photoUrl = await _encodedPhoto();
    if (!mounted) return;
    final specialties = _specialties.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final payload = <String, dynamic>{
      'displayName': _name.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'specialties': specialties,
      'hourlyRateTzs': num.tryParse(_rate.text.trim()) ?? 0,
      'bio': _bio.text.trim(),
      'photoUrl': photoUrl,
      if (widget.initial == null && widget.defaultGymIds.isNotEmpty)
        'gymIds': widget.defaultGymIds,
      'status': 'active',
    };
    Navigator.of(context).pop(payload);
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
            onPressed: _busy ? null : _save,
            child: Text(context.tr('member.save')),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.trainerName'),
                  border: const OutlineInputBorder(),
                ),
                validator: _required,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                enabled: !isEdit,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.trainerEmail'),
                  border: const OutlineInputBorder(),
                ),
                validator: isEdit ? null : _emailValidator,
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('trainerReg.picture'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: FFTokens.fgSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                    child: SizedBox(
                      width: 72,
                      height: 72,
                      child: _photo.isEmpty
                          ? Container(
                              color: FFTokens.brand50,
                              child: const Icon(
                                Icons.person,
                                color: FFTokens.brand700,
                              ),
                            )
                          : _photo.startsWith('http') ||
                                _photo.startsWith('data:')
                          ? FFRemoteImage(
                              src: _photo,
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                              fallback: const Icon(Icons.person),
                            )
                          : Image.file(
                              File(_photo),
                              width: 72,
                              height: 72,
                              fit: BoxFit.cover,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: _pickPhoto,
                    icon: const Icon(Icons.add_a_photo, size: 18),
                    label: Text(context.tr('ownerReg.pickImage')),
                  ),
                  if (_photo.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => _photo = ''),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: context.tr('member.phone'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _specialties,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.trainerSpecialties'),
                  hintText: 'e.g. Yoga, Cardio',
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rate,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('ownerReg.trainerRate'),
                  suffixText: 'TZS',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = num.tryParse((v ?? '').trim());
                  if (n == null || n < 0) {
                    return context.tr('onboarding.required');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bio,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Bio',
                  border: OutlineInputBorder(),
                ),
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
