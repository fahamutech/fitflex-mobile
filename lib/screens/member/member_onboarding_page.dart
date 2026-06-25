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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          ),
          title: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: FFTokens.danger,
                size: FFTokens.iconXl,
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Text(
                context.tr('onboarding.error'),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(message, style: Theme.of(context).textTheme.bodyMedium),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                context.tr('onboarding.ok'),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: FFTokens.brandVibrant,
                  fontWeight: FontWeight.w600,
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
                          size: FFTokens.iconLg,
                        ),
                        const SizedBox(width: FFTokens.spacingSm),
                        Text(
                          context.tr('member.setupTitle'),
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
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
                        backgroundColor: Theme.of(context).colorScheme.outline,
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
                            duration: FFTokens.motionMedium,
                            opacity: _controller.canProceed ? 1.0 : 0.5,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              onPressed:
                                  (_controller.canProceed && !_controller.busy)
                                  ? _next
                                  : null,
                              child: _controller.busy
                                  ? SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimary,
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
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          context.tr('onboarding.fitnessSubtitle'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
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
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('onboarding.personalSubtitle'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
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
          style: Theme.of(context).textTheme.labelLarge,
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
          suffixIcon: Icon(
            Icons.calendar_today,
            color: Theme.of(context).colorScheme.outline,
            size: FFTokens.iconSm,
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
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 10),
        Text(
          context.tr('onboarding.levelSubtitle'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).textTheme.bodySmall?.color,
          ),
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
        duration: FFTokens.motionMedium,
        curve: FFTokens.motionCurve,
        height: 84,
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
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
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface,
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
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: suffixIcon,
        suffixText: suffixText,
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
        duration: FFTokens.motionMedium,
        curve: FFTokens.motionCurve,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: FFTokens.iconSm,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).textTheme.bodySmall?.color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurface,
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
        duration: FFTokens.motionMedium,
        curve: FFTokens.motionCurve,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color,
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
