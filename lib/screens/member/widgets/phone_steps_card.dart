import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/activity.dart';
import '../../../shared/activity/phone_steps.dart';
import '../../../shared/activity/step_ledger.dart' show dayKey;
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'activity_widgets.dart' show formatSteps;

/// Turn on counting steps with this phone, or — once on — a quiet line
/// saying it's counting. Hidden where the feature isn't offered.
class PhoneStepsCard extends StatelessWidget {
  const PhoneStepsCard({super.key, this.dismissible = false});

  /// Home offers "Not now"; the Activity tab doesn't.
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final steps = context.getInheritedWidgetOfExactType<AppScope>()?.phoneSteps;
    if (steps == null || !steps.supported) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: steps,
      builder: (context, _) {
        if (!steps.loaded) return const SizedBox.shrink();
        if (steps.enabled) return _Counting(steps: steps);
        if (dismissible && steps.promptDismissed) {
          return const SizedBox.shrink();
        }
        return _Prompt(steps: steps, dismissible: dismissible);
      },
    );
  }
}

/// Turns counting on and says what happened. Shared with the Privacy switch.
Future<bool> turnOnPhoneSteps(BuildContext context, PhoneSteps steps) async {
  final messenger = ScaffoldMessenger.of(context);
  final shell = context.findAncestorStateOfType<MemberShellState>();
  final on = context.tr('phoneSteps.onToast');
  final denied = context.tr('phoneSteps.deniedToast');
  // Carry on from what this phone already sent (turned off and on again).
  final known = <String, int>{};
  final data = context
      .getInheritedWidgetOfExactType<MemberDataScope>()
      ?.notifier;
  for (final a in data?.activities ?? const <Activity>[]) {
    if (a.devicePlatform == DevicePlatform.phoneSensor && a.steps != null) {
      final k = dayKey(a.startedAt);
      if (a.steps! > (known[k] ?? 0)) known[k] = a.steps!;
    }
  }
  final ok = await steps.enable(known: known);
  messenger.showSnackBar(SnackBar(content: Text(ok ? on : denied)));
  if (ok) await shell?.syncPhoneSteps();
  return ok;
}

class _Prompt extends StatefulWidget {
  const _Prompt({required this.steps, required this.dismissible});

  final PhoneSteps steps;
  final bool dismissible;

  @override
  State<_Prompt> createState() => _PromptState();
}

class _PromptState extends State<_Prompt> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.steps;
    return FFCard(
      key: const Key('phone-steps-prompt'),
      margin: const EdgeInsets.only(top: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.directions_walk, color: theme.colorScheme.primary),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: Text(
                  context.tr('phoneSteps.title'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr(
              s.needsSettings ? 'phoneSteps.needsSettings' : 'phoneSteps.body',
            ),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingSm,
            children: [
              if (s.needsSettings)
                FilledButton.tonal(
                  key: const Key('phone-steps-settings'),
                  onPressed: s.openSettings,
                  child: Text(context.tr('phoneSteps.openSettings')),
                )
              else
                FilledButton(
                  key: const Key('phone-steps-enable'),
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await turnOnPhoneSteps(context, s);
                          if (mounted) setState(() => _busy = false);
                        },
                  child: Text(context.tr('phoneSteps.enable')),
                ),
              if (widget.dismissible)
                TextButton(
                  key: const Key('phone-steps-dismiss'),
                  onPressed: s.dismissPrompt,
                  child: Text(context.tr('phoneSteps.notNow')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Counting extends StatelessWidget {
  const _Counting({required this.steps});

  final PhoneSteps steps;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      key: const Key('phone-steps-counting'),
      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
      child: Row(
        children: [
          Icon(Icons.sensors, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: FFTokens.spacingXs),
          Expanded(
            child: Text(
              context
                  .tr('phoneSteps.counting')
                  .replaceAll('{n}', formatSteps(steps.countedToday)),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Settings → Privacy & data: the on/off switch.
class PhoneStepsSwitch extends StatelessWidget {
  const PhoneStepsSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    final steps = context.getInheritedWidgetOfExactType<AppScope>()?.phoneSteps;
    if (steps == null || !steps.supported) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: steps,
      builder: (context, _) => FFCard(
        margin: const EdgeInsets.only(top: FFTokens.spacingMd),
        child: SwitchListTile(
          key: const Key('phone-steps-switch'),
          contentPadding: EdgeInsets.zero,
          value: steps.enabled,
          title: Text(context.tr('phoneSteps.switchTitle')),
          subtitle: Text(
            context.tr(
              steps.needsSettings
                  ? 'phoneSteps.needsSettings'
                  : 'phoneSteps.switchBody',
            ),
          ),
          onChanged: (on) async {
            if (on) {
              if (steps.needsSettings) {
                await steps.openSettings();
              } else {
                await turnOnPhoneSteps(context, steps);
              }
            } else {
              await steps.disable();
            }
          },
        ),
      ),
    );
  }
}
