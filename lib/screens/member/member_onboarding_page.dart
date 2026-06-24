import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/theme_toggle_button.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_onboarding_controller.dart';

class MemberOnboardingPage extends StatefulWidget {
  const MemberOnboardingPage({super.key});

  @override
  State<MemberOnboardingPage> createState() => _MemberOnboardingPageState();
}

class _MemberOnboardingPageState extends State<MemberOnboardingPage> {
  final _formKey = GlobalKey<FormState>();
  late final MemberOnboardingController _controller;

  static const _goals = [
    'lose_weight',
    'gain_muscle',
    'stay_fit',
    'improve_endurance',
    'learn_new_skill',
  ];

  static const _goalEmojis = {
    'lose_weight': '🏃‍♂️',
    'gain_muscle': '💪',
    'stay_fit': '🧘',
    'improve_endurance': '⚡',
    'learn_new_skill': '🥊',
  };

  static const _genders = ['male', 'female', 'other'];
  static const _levels = ['beginner', 'intermediate', 'advanced'];

  static const _levelEmojis = {
    'beginner': '🌱',
    'intermediate': '⚡',
    'advanced': '🏆',
  };

  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final scope = AppScope.of(context);
      _controller = MemberOnboardingController(
        api: scope.api,
        auth: scope.auth,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    _controller.submit(
      onSuccess: () {
        if (!mounted) return;
        context.go(AppRoutes.memberHome);
      },
      onError: (msg) {
        if (!mounted) return;
        _showErrorDialog(context, msg);
      },
    );
  }

  void _next() {
    if (_controller.step == 1) {
      if (!_formKey.currentState!.validate()) return;
    }
    _controller.next(() {
      _submit();
    });
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: FFTokens.darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: FFTokens.danger,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                context.tr('onboarding.error'),
                style: const TextStyle(
                  color: FFTokens.darkFgPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            message,
            style: const TextStyle(
              color: FFTokens.darkFgSecondary,
              fontSize: 15,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                context.tr('onboarding.ok'),
                style: const TextStyle(
                  color: FFTokens.brandVibrant,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final progress = (_controller.step + 1) / 3;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            actions: const [ThemeToggleButton()],
          ),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FFTokens.spacingLg,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    // MEMBER SETUP header
                    Row(
                      children: [
                        const Icon(
                          Icons.fitness_center_rounded,
                          color: FFTokens.brandVibrant,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          context.tr('member.setupTitle'),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: FFTokens.darkFgPrimary,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: FFTokens.darkBorder,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          FFTokens.brandVibrant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Step content with smooth slide transition
                    Expanded(
                      child: PageView(
                        controller: _controller.pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (index) {
                          _controller.setStep(index);
                        },
                        children: [
                          SingleChildScrollView(
                            child: _buildGoalsStep(context),
                          ),
                          SingleChildScrollView(
                            child: _buildPersonalStep(context),
                          ),
                          SingleChildScrollView(
                            child: _buildFitnessLevelStep(context),
                          ),
                        ],
                      ),
                    ),

                    // Navigation actions with smooth fade animations
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (_controller.step > 0) ...[
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: FFTokens.darkFgSecondary,
                                side: const BorderSide(
                                  color: FFTokens.darkBorder,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    FFTokens.radiusFull,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              onPressed: _controller.busy
                                  ? null
                                  : _controller.back,
                              child: Text(context.tr('onboarding.back')),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        Expanded(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 250),
                            opacity: _controller.canProceed ? 1.0 : 0.5,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: FFTokens.brandVibrant,
                                foregroundColor: Colors.black,
                                disabledBackgroundColor: FFTokens.darkSurface,
                                disabledForegroundColor: FFTokens.darkFgMuted,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    FFTokens.radiusFull,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              onPressed:
                                  (_controller.canProceed && !_controller.busy)
                                  ? _next
                                  : null,
                              child: _controller.busy
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.black,
                                      ),
                                    )
                                  : Text(
                                      _controller.step < 2
                                          ? context.tr('onboarding.next')
                                          : context.tr('onboarding.finish'),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Step 0: Fitness Goals ────────────────────────────────────────────────────

  Widget _buildGoalsStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('onboarding.fitnessTitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: FFTokens.darkFgPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.tr('onboarding.fitnessSubtitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: FFTokens.darkFgMuted),
        ),
        const SizedBox(height: 24),
        // 2-column goal grid
        for (int row = 0; row < (_goals.length / 2).ceil(); row++) ...[
          if (row > 0) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _GoalTile(
                  label: context.tr('onboarding.goal_${_goals[row * 2]}'),
                  emoji: _goalEmojis[_goals[row * 2]] ?? '',
                  selected: _controller.fitnessGoals.contains(_goals[row * 2]),
                  onTap: () => _controller.toggleGoal(_goals[row * 2]),
                ),
              ),
              const SizedBox(width: 12),
              if (row * 2 + 1 < _goals.length)
                Expanded(
                  child: _GoalTile(
                    label: context.tr('onboarding.goal_${_goals[row * 2 + 1]}'),
                    emoji: _goalEmojis[_goals[row * 2 + 1]] ?? '',
                    selected: _controller.fitnessGoals.contains(
                      _goals[row * 2 + 1],
                    ),
                    onTap: () => _controller.toggleGoal(_goals[row * 2 + 1]),
                  ),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  // ── Step 1: Personal info ──────────────────────────────────

  Widget _buildPersonalStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('onboarding.personalTitle'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: FFTokens.darkFgPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('onboarding.personalSubtitle'),
          style: const TextStyle(fontSize: 14, color: FFTokens.darkFgMuted),
        ),
        const SizedBox(height: 24),
        _DarkTextField(
          controller: _controller.nameCtrl,
          label: context.tr('onboarding.displayName'),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
        const SizedBox(height: 16),
        // Gender radio choice group
        Text(
          context.tr('onboarding.gender'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: FFTokens.darkFgSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: _genders.map((g) {
            final selected = _controller.gender == g;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: g != _genders.last ? 10 : 0),
                child: _GenderRadioTile(
                  label: context.tr('onboarding.gender_$g'),
                  selected: selected,
                  onTap: () => _controller.setGender(g),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        _DarkTextField(
          controller: _controller.dobCtrl,
          label: context.tr('onboarding.dob'),
          readOnly: true,
          suffixIcon: const Icon(
            Icons.calendar_today,
            color: FFTokens.darkFgMuted,
            size: 18,
          ),
          onTap: () async {
            final date = await showDatePicker(
              context: context,
              initialDate: DateTime(1995),
              firstDate: DateTime(1940),
              lastDate: DateTime.now(),
            );
            if (date != null) {
              _controller.dobCtrl.text = date
                  .toIso8601String()
                  .split('T')
                  .first;
            }
          },
          validator: (v) => (v == null || v.trim().isEmpty)
              ? context.tr('onboarding.required')
              : null,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _DarkTextField(
                controller: _controller.heightCtrl,
                label: context.tr('onboarding.height'),
                keyboardType: TextInputType.number,
                suffixText: 'cm',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _DarkTextField(
                controller: _controller.weightCtrl,
                label: context.tr('onboarding.weight'),
                keyboardType: TextInputType.number,
                suffixText: 'kg',
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 2: Fitness level ─────────────────────────────────────────────────────

  Widget _buildFitnessLevelStep(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('onboarding.levelTitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: FFTokens.darkFgPrimary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          context.tr('onboarding.levelSubtitle'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: FFTokens.darkFgMuted),
        ),
        const SizedBox(height: 28),
        ..._levels.map(
          (l) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _DarkLevelTile(
              label: context.tr('onboarding.level_$l'),
              description: context.tr('onboarding.level_${l}_desc'),
              emoji: _levelEmojis[l] ?? '',
              selected: _controller.fitnessLevel == l,
              onTap: () => _controller.setFitnessLevel(l),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared dark-themed input widgets ────────────────────────────────────────────

class _GoalTile extends StatelessWidget {
  const _GoalTile({
    required this.label,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 84,
        decoration: BoxDecoration(
          color: selected
              ? FFTokens.brandVibrant.withValues(alpha: 0.12)
              : FFTokens.darkSurface,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          border: Border.all(
            color: selected ? FFTokens.brandVibrant : FFTokens.darkBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? FFTokens.brandVibrant
                      : FFTokens.darkFgSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  const _DarkTextField({
    required this.controller,
    required this.label,
    this.readOnly = false,
    this.keyboardType,
    this.validator,
    this.onTap,
    this.suffixIcon,
    this.suffixText,
  });

  final TextEditingController controller;
  final String label;
  final bool readOnly;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final VoidCallback? onTap;
  final Widget? suffixIcon;
  final String? suffixText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      validator: validator,
      onTap: onTap,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      style: const TextStyle(color: FFTokens.darkFgPrimary),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: FFTokens.darkFgMuted),
        suffixIcon: suffixIcon,
        suffixText: suffixText,
        suffixStyle: const TextStyle(color: FFTokens.darkFgMuted),
        filled: true,
        fillColor: FFTokens.darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          borderSide: const BorderSide(color: FFTokens.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          borderSide: const BorderSide(color: FFTokens.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          borderSide: const BorderSide(color: FFTokens.brandVibrant, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          borderSide: const BorderSide(color: FFTokens.danger),
        ),
      ),
    );
  }
}

class _GenderRadioTile extends StatelessWidget {
  const _GenderRadioTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? FFTokens.brandVibrant.withValues(alpha: 0.1)
              : FFTokens.darkSurface,
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          border: Border.all(
            color: selected ? FFTokens.brandVibrant : FFTokens.darkBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 18,
              color: selected ? FFTokens.brandVibrant : FFTokens.darkFgMuted,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected
                    ? FFTokens.brandVibrant
                    : FFTokens.darkFgSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DarkLevelTile extends StatelessWidget {
  const _DarkLevelTile({
    required this.label,
    required this.description,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? FFTokens.brandVibrant.withValues(alpha: 0.1)
              : FFTokens.darkSurface,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          border: Border.all(
            color: selected ? FFTokens.brandVibrant : FFTokens.darkBorder,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: selected
                          ? FFTokens.brandVibrant
                          : FFTokens.darkFgPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      color: FFTokens.darkFgMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
