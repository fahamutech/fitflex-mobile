import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/api_client.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';

class MemberOnboardingPage extends StatefulWidget {
  const MemberOnboardingPage({super.key});

  @override
  State<MemberOnboardingPage> createState() => _MemberOnboardingPageState();
}

class _MemberOnboardingPageState extends State<MemberOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  int _step = 0;
  bool _busy = false;

  // Step 0 — Personal info
  final _nameCtrl = TextEditingController();
  String? _gender;
  final _dobCtrl = TextEditingController();

  // Step 1 — Fitness info
  String? _fitnessGoal;
  String? _fitnessLevel;
  final _heightCtrl = TextEditingController();
  final _weightCtrl = TextEditingController();

  // Step 2 — Preferences
  final List<String> _workoutTimes = [];

  static const _genders = ['male', 'female', 'other'];
  static const _goals = [
    'lose_weight',
    'build_muscle',
    'stay_fit',
    'improve_flexibility',
    'stress_relief',
  ];
  static const _levels = ['beginner', 'intermediate', 'advanced'];
  static const _timeOptions = ['morning', 'afternoon', 'evening'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final api = AppScope.of(context).api;
      await api.updateProfile({
        'displayName': _nameCtrl.text.trim(),
        'gender': _gender,
        'dateOfBirth': _dobCtrl.text.trim(),
        'fitnessGoal': _fitnessGoal,
        'fitnessLevel': _fitnessLevel,
        'heightCm': _heightCtrl.text.isNotEmpty
            ? num.tryParse(_heightCtrl.text)
            : null,
        'weightKg': _weightCtrl.text.isNotEmpty
            ? num.tryParse(_weightCtrl.text)
            : null,
        'preferredWorkoutTimes': _workoutTimes,
        'onboardingCompleted': true,
      });
      if (!mounted) return;
      // Re-hydrate auth user to reflect onboarding completion
      final meRes = await api.me();
      if (!mounted) return;
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      await AppScope.of(
        context,
      ).auth.signIn(AppScope.of(context).auth.token!, user);
      if (!mounted) return;
      context.go(AppRoutes.memberHome);
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
    if (_step < 2) {
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
        title: Text(context.tr('onboarding.title')),
        automaticallyImplyLeading: false,
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
                  children: List.generate(3, (i) {
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

                // Content
                Expanded(
                  child: SingleChildScrollView(child: _buildStep(context)),
                ),

                // Navigation buttons
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
                                _step < 2
                                    ? context.tr('onboarding.next')
                                    : context.tr('onboarding.finish'),
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
        return _buildPersonalStep(context);
      case 1:
        return _buildFitnessStep(context);
      case 2:
        return _buildPreferencesStep(context);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildPersonalStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('onboarding.personalTitle'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('onboarding.personalSubtitle'),
          style: const TextStyle(fontSize: 14, color: FFTokens.fgTertiary),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _nameCtrl,
          decoration: InputDecoration(
            labelText: context.tr('onboarding.displayName'),
            border: const OutlineInputBorder(),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _gender,
          decoration: InputDecoration(
            labelText: context.tr('onboarding.gender'),
            border: const OutlineInputBorder(),
          ),
          items: _genders
              .map(
                (g) => DropdownMenuItem(
                  value: g,
                  child: Text(context.tr('onboarding.gender_$g')),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _gender = v),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _dobCtrl,
          readOnly: true,
          decoration: InputDecoration(
            labelText: context.tr('onboarding.dob'),
            border: const OutlineInputBorder(),
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime(1995),
              firstDate: DateTime(1940),
              lastDate: DateTime.now(),
            );
            if (date != null) {
              _dobCtrl.text = date.toIso8601String().split('T').first;
            }
          },
        ),
      ],
    );
  }

  Widget _buildFitnessStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('onboarding.fitnessTitle'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('onboarding.fitnessSubtitle'),
          style: const TextStyle(fontSize: 14, color: FFTokens.fgTertiary),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField<String>(
          initialValue: _fitnessGoal,
          decoration: InputDecoration(
            labelText: context.tr('onboarding.fitnessGoal'),
            border: const OutlineInputBorder(),
          ),
          items: _goals
              .map(
                (g) => DropdownMenuItem(
                  value: g,
                  child: Text(context.tr('onboarding.goal_$g')),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _fitnessGoal = v),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: _fitnessLevel,
          decoration: InputDecoration(
            labelText: context.tr('onboarding.fitnessLevel'),
            border: const OutlineInputBorder(),
          ),
          items: _levels
              .map(
                (l) => DropdownMenuItem(
                  value: l,
                  child: Text(context.tr('onboarding.level_$l')),
                ),
              )
              .toList(),
          onChanged: (v) => setState(() => _fitnessLevel = v),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _heightCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('onboarding.height'),
                  suffixText: 'cm',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _weightCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('onboarding.weight'),
                  suffixText: 'kg',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreferencesStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('onboarding.preferencesTitle'),
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          context.tr('onboarding.preferencesSubtitle'),
          style: const TextStyle(fontSize: 14, color: FFTokens.fgTertiary),
        ),
        const SizedBox(height: 20),
        ..._timeOptions.map(
          (t) => CheckboxListTile(
            title: Text(context.tr('onboarding.time_$t')),
            value: _workoutTimes.contains(t),
            onChanged: (v) {
              setState(() {
                if (v == true) {
                  _workoutTimes.add(t);
                } else {
                  _workoutTimes.remove(t);
                }
              });
            },
          ),
        ),
      ],
    );
  }
}
