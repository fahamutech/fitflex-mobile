import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/widgets/ff_photo_picker_field.dart';

class TrainerRegistrationPage extends StatefulWidget {
  const TrainerRegistrationPage({super.key});

  @override
  State<TrainerRegistrationPage> createState() =>
      _TrainerRegistrationPageState();
}

class _TrainerRegistrationPageState extends State<TrainerRegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _busy = false;

  // Step 0 — Personal
  final _nameCtrl = TextEditingController();
  String? _photoUrl;
  String? _gender;
  final _bioCtrl = TextEditingController();

  // Step 1 — Professional
  final _sessionRateCtrl = TextEditingController();
  final List<String> _specialties = [];

  static const _specialtyOptions = [
    'weight_training',
    'cardio',
    'yoga',
    'boxing',
    'pilates',
    'crossfit',
    'swimming',
    'nutrition',
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _sessionRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      await api.trainerRegister({
        'displayName': _nameCtrl.text.trim(),
        'photoUrl': _photoUrl ?? '',
        'gender': _gender,
        'bio': _bioCtrl.text.trim(),
        'hourlyRateTzs': num.tryParse(_sessionRateCtrl.text) ?? 0,
        'specialties': _specialties,
      });
      if (!mounted) return;
      // Re-hydrate auth to reflect onboarding completion
      final meRes = await api.me();
      if (!mounted) return;
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      await AppScope.of(
        context,
      ).auth.signIn(AppScope.of(context).auth.token!, user);
      if (!mounted) return;
      context.go(AppRoutes.pending);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: ${e.status}')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _next() {
    if (_step < 1) {
      setState(() => _step++);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('trainerReg.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_step > 0) {
              _back();
            } else {
              context.go(AppRoutes.role);
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                // Step indicator
                Row(
                  children: List.generate(2, (i) {
                    final active = i <= _step;
                    return Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(2),
                          color: active
                              ? FFTokens.brand600
                              : FFTokens.borderSecondary,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(child: _buildStep(context)),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_step > 0)
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _back,
                          child: Text(context.tr('onboarding.back')),
                        ),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _next,
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _step < 1
                                    ? context.tr('onboarding.next')
                                    : context.tr('trainerReg.submit'),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStep(BuildContext context) {
    switch (_step) {
      case 0:
        return _personalStep(context);
      case 1:
        return _professionalStep(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _personalStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('trainerReg.personalTitle'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('trainerReg.personalSubtitle'),
          style: const TextStyle(fontSize: 14, color: FFTokens.fgTertiary),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: context.tr('trainerReg.displayName'),
            border: const OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('trainerReg.picture'),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: FFTokens.fgPrimary),
        ),
        const SizedBox(height: 8),
        Center(
          child: FFPhotoPickerField(
            value: _photoUrl,
            onChanged: (url) => setState(() => _photoUrl = url),
            size: 100,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: InputDecoration(
            labelText: context.tr('trainerReg.gender'),
            border: const OutlineInputBorder(),
          ),
          items: ['male', 'female', 'other']
              .map(
                (g) => DropdownMenuItem(
                  value: g,
                  child: Text(context.tr('onboarding.gender_$g')),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _gender = v),
          validator: (v) =>
              v == null ? context.tr('onboarding.required') : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _bioCtrl,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: context.tr('trainerReg.bio'),
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
      ],
    );
  }

  Widget _professionalStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('trainerReg.professionalTitle'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('trainerReg.professionalSubtitle'),
          style: const TextStyle(fontSize: 14, color: FFTokens.fgTertiary),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _sessionRateCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: context.tr('trainerReg.sessionRate'),
            suffixText: 'TZS${context.tr('trainerReg.perSession')}',
            border: const OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          context.tr('trainerReg.specialties'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _specialtyOptions.map((s) {
            final selected = _specialties.contains(s);
            return FilterChip(
              label: Text(context.tr('trainerReg.specialty_$s')),
              selected: selected,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _specialties.add(s);
                  } else {
                    _specialties.remove(s);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}
