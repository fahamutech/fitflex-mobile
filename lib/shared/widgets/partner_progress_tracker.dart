// One partner progress tracker (journey audit Phase B · B4b): the four steps
// registered → approved → verified → "Ready to be paid", each drawn with its
// own state (icon + words, never colour alone), and one line saying what to
// do next. Shown on the pending screen, at the top of the Verification
// centre, and as a compact banner on vendor home.
//
// Pure UI: the host decides where a next action leads ([onAction]).

import 'package:flutter/material.dart';

import '../components/components.dart';
import '../design_tokens.dart';
import '../formatters.dart';
import '../i18n.dart';
import '../partner_progress.dart';
import '../tone_theme.dart';

/// The label of one checklist item a next action names, with the gym's name
/// for an item that belongs to one gym. Null when the app has no label for it.
String? partnerItemLabel(
  BuildContext context,
  PartnerItemRef ref, {
  String? Function(String gymId)? gymName,
}) {
  final key = 'kyc.item.${ref.field}';
  final label = context.tr(key);
  if (label == key) return null;
  final gym = ref.gymId == null ? null : gymName?.call(ref.gymId!);
  return gym == null
      ? label
      : _fill(context.tr('progress.itemAtGym'), {'item': label, 'gym': gym});
}

/// The neutral KYC reason code a partner gets instead of a sensitive one
/// (fitflex-functions#245). It is never paired with a reviewer note: the
/// partner is told the case is under review and to contact FitFlex support.
const partnerUnderReviewReason = 'under_review';

/// "Under review — please contact FitFlex support." in the active language.
String partnerUnderReviewMessage(BuildContext context) =>
    context.tr('progress.reason.under_review');

/// Whether a next action's button contacts FitFlex support rather than
/// opening a screen in the app.
bool partnerActionIsSupport(PartnerNextAction action) =>
    action.code == 'contact_support' ||
    action.code == 'payout_not_ready' ||
    (action.code == 'kyc_changes_requested' &&
        action.reasonCode == partnerUnderReviewReason);

/// Why payouts aren't ready for a gym owner (fitflex-functions#247): the
/// gym has several owners and none is named to be paid, or another owner is.
String partnerPayoutNotReadyMessage(BuildContext context, String? reason) =>
    switch (reason) {
      'payout_owner_required' => context.tr(
        'progress.payout.payout_owner_required',
      ),
      'not_payout_owner' => context.tr('progress.payout.not_payout_owner'),
      _ => context.tr('progress.next.payout_not_ready'),
    };

/// The message for a next action, in the active language.
String partnerActionMessage(
  BuildContext context,
  PartnerNextAction action, {
  String? Function(String gymId)? gymName,
}) {
  String items() {
    final labels = <String>[
      for (final m in action.missing)
        ?partnerItemLabel(context, m, gymName: gymName),
    ];
    final unknown = action.missing.length - labels.length;
    const shown = 3;
    final more = labels.length > shown ? labels.length - shown : 0;
    final parts = labels.take(shown).toList();
    if (more + unknown > 0) {
      parts.add(_fill(context.tr('progress.more'), {'n': more + unknown}));
    }
    return parts.join(', ');
  }

  String stillNeeded() => action.missing.isEmpty
      ? context.tr('progress.next.complete_kyc_items.none')
      : _fill(context.tr('progress.next.complete_kyc_items'), {
          'items': items(),
        });

  switch (action.code) {
    case 'wait_for_approval':
      return context.tr('progress.next.wait_for_approval');
    case 'complete_kyc_items':
      return stillNeeded();
    case 'submit_kyc':
      return context.tr('progress.next.submit_kyc');
    case 'kyc_under_review':
      return context.tr('kyc.status.inReview');
    case 'kyc_changes_requested':
      if (action.reasonCode == partnerUnderReviewReason) {
        // No reason is given: say it is under review, nothing more.
        final review = partnerUnderReviewMessage(context);
        return action.missing.isEmpty ? review : '$review\n${stillNeeded()}';
      }
      final reasonKey = 'progress.changeReason.${action.reasonCode}';
      final reason = context.tr(reasonKey);
      final asked = reason == reasonKey
          ? context.tr('progress.next.kyc_changes_requested')
          : _fill(context.tr('progress.next.kyc_changes_requested.reason'), {
              'reason': reason,
            });
      return action.missing.isEmpty ? asked : '$asked\n${stillNeeded()}';
    case 'add_payout_account':
      return context.tr(
        action.reason == 'payout_account_rejected'
            ? 'progress.next.add_payout_account.rejected'
            : 'progress.next.add_payout_account',
      );
    case 'payout_account_under_review':
      return context.tr('progress.next.payout_account_under_review');
    case 'payout_account_cooling_off':
      final until = action.until == null
          ? null
          : context.localDateTimeText(action.until, fallback: '');
      return until == null || until.isEmpty
          ? context.tr('progress.next.payout_account_cooling_off.soon')
          : _fill(context.tr('progress.next.payout_account_cooling_off'), {
              'date': until,
            });
    case 'payout_not_ready':
      return partnerPayoutNotReadyMessage(context, action.reason);
    case 'add_gym':
      return context.tr('progress.next.add_gym');
    case 'contact_support':
      return partnerBlockedReason(context, action.reason);
    case 'none':
      return context.tr('progress.next.none');
    default:
      // A code from a newer server: say plainly that FitFlex is on it.
      return context.tr('progress.next.unknown');
  }
}

/// Why a step is blocked, in words.
String partnerBlockedReason(BuildContext context, String? reason) =>
    switch (reason) {
      'account_suspended' => context.tr('progress.blocked.account_suspended'),
      'role_rejected' => context.tr('progress.blocked.role_rejected'),
      'kyc_rejected' => context.tr('kyc.status.rejected'),
      'kyc_suspended' => context.tr('kyc.status.suspended'),
      partnerUnderReviewReason => partnerUnderReviewMessage(context),
      _ => context.tr('progress.blocked.other'),
    };

/// The button label for a next action the partner can act on, or null when
/// there is nothing to press (FitFlex is reviewing, or all done).
String? partnerActionLabel(BuildContext context, PartnerNextAction action) =>
    partnerActionIsSupport(action)
    ? context.tr('member.contactSupport')
    : switch (action.code) {
        'complete_kyc_items' => context.tr('kyc.pending.cta'),
        'submit_kyc' => context.tr('kyc.submit.action'),
        'kyc_changes_requested' => context.tr('progress.cta.changes'),
        'add_payout_account' => context.tr('progress.cta.payout'),
        'add_gym' => context.tr('progress.cta.addGym'),
        _ => null,
      };

String _stepLabel(BuildContext context, String key) =>
    context.tr('progress.step.$key');

String _stateLabel(BuildContext context, PartnerStepState s) =>
    context.tr('progress.state.${s.name}');

/// "Step 2 of 4, Approved, current" — what a screen reader says for a step.
String partnerStepSemantics(
  BuildContext context,
  int number,
  int total,
  PartnerStep step,
) => _fill(context.tr('progress.a11y.step'), {
  'n': number,
  'total': total,
  'label': _stepLabel(context, step.key),
  'state': context.tr('progress.a11y.state.${step.state.name}'),
});

String _fill(String template, Map<String, Object?> values) {
  var out = template;
  values.forEach((k, v) => out = out.replaceAll('{$k}', '${v ?? ''}'));
  return out;
}

class _StateVisual {
  const _StateVisual(this.icon, this.color);
  final IconData icon;
  final Color color;

  static _StateVisual of(BuildContext context, PartnerStepState s) {
    final scheme = Theme.of(context).colorScheme;
    final tones = FFToneTheme.of(context);
    return switch (s) {
      PartnerStepState.done => _StateVisual(
        Icons.check_circle,
        tones.success.fg,
      ),
      PartnerStepState.current => _StateVisual(
        Icons.radio_button_checked,
        scheme.primary,
      ),
      PartnerStepState.todo => _StateVisual(
        Icons.radio_button_unchecked,
        scheme.onSurfaceVariant,
      ),
      PartnerStepState.blocked => _StateVisual(Icons.block, tones.danger.fg),
    };
  }
}

/// The partner's progress: four steps and one next action. [compact] draws
/// one summary line (for a banner); the full form lists each step.
class PartnerProgressTracker extends StatelessWidget {
  const PartnerProgressTracker({
    super.key,
    required this.progress,
    this.onAction,
    this.compact = false,
    this.busy = false,
  });

  final PartnerProgress progress;

  /// Called with the next action when its button is pressed. No button is
  /// drawn without it.
  final void Function(PartnerNextAction action)? onAction;
  final bool compact;
  final bool busy;

  bool get _multiGym => progress.gyms.length > 1;

  /// With several gyms, a payout action names one gym, and that gym's row
  /// already says it: the overall line is left out so it is said once.
  bool get _showOverallAction =>
      !(_multiGym && progress.nextAction.gymId != null);

  String? _gymName(String gymId) => progress.gymName(gymId);

  @override
  Widget build(BuildContext context) {
    return FFCard(
      key: Key(compact ? 'partner-progress-compact' : 'partner-progress'),
      child: compact ? _compact(context) : _full(context),
    );
  }

  Widget _full(BuildContext context) {
    final theme = Theme.of(context);
    final total = progress.steps.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('progress.title'),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        for (var i = 0; i < total; i++)
          _StepRow(
            step: progress.steps[i],
            number: i + 1,
            total: total,
            // The current step's reason is said in the next-action line.
            showReason: progress.steps[i].key != progress.current,
          ),
        if (_showOverallAction) ...[
          const SizedBox(height: FFTokens.spacingSm),
          _ActionLine(
            key: const Key('partner-progress-next'),
            action: progress.nextAction,
            gymName: _gymName,
            onAction: onAction,
            busy: busy,
          ),
        ],
        if (_multiGym) ...[
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('kyc.section.operational'),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          for (final g in progress.gyms)
            _GymRow(
              gym: g,
              overall: progress.nextAction,
              onAction: onAction,
              busy: busy,
            ),
        ],
      ],
    );
  }

  Widget _compact(BuildContext context) {
    final theme = Theme.of(context);
    final current = progress.currentStep ?? progress.steps.last;
    final total = progress.steps.length;
    final number = progress.currentNumber;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: partnerStepSemantics(context, number, total, current),
          excludeSemantics: true,
          child: Row(
            children: [
              for (final s in progress.steps)
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                    end: FFTokens.spacingXs,
                  ),
                  child: Icon(
                    _StateVisual.of(context, s.state).icon,
                    size: FFTokens.iconSm,
                    color: _StateVisual.of(context, s.state).color,
                  ),
                ),
              const SizedBox(width: FFTokens.spacingXs),
              Expanded(
                child: Text(
                  _fill(context.tr('progress.summary'), {
                    'n': number,
                    'total': total,
                    'label': _stepLabel(context, current.key),
                  }),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_showOverallAction) ...[
          const SizedBox(height: FFTokens.spacingSm),
          _ActionLine(
            key: const Key('partner-progress-next'),
            action: progress.nextAction,
            gymName: _gymName,
            onAction: onAction,
            busy: busy,
            small: true,
          ),
        ],
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.number,
    required this.total,
    required this.showReason,
  });

  final PartnerStep step;
  final int number;
  final int total;
  final bool showReason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visual = _StateVisual.of(context, step.state);
    final date = step.state == PartnerStepState.done && step.at != null
        ? context.localDate(step.at, fallback: '')
        : '';
    final detail = [
      _stateLabel(context, step.state),
      if (date.isNotEmpty) date,
      if (showReason &&
          step.state == PartnerStepState.blocked &&
          step.reason != null)
        partnerBlockedReason(context, step.reason),
    ].join(' · ');
    final emphasised =
        step.state == PartnerStepState.current ||
        step.state == PartnerStepState.blocked;
    return Semantics(
      key: Key('partner-step-${step.key}'),
      label: [
        partnerStepSemantics(context, number, total, step),
        if (date.isNotEmpty) date,
      ].join(', '),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: FFTokens.spacingXs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(visual.icon, size: FFTokens.iconMd, color: visual.color),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _stepLabel(context, step.key),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: emphasised
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                  Text(
                    detail,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: step.state == PartnerStepState.blocked
                          ? visual.color
                          : theme.colorScheme.onSurfaceVariant,
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

class _ActionLine extends StatelessWidget {
  const _ActionLine({
    super.key,
    required this.action,
    required this.gymName,
    required this.onAction,
    required this.busy,
    this.small = false,
    this.buttonKey = const Key('partner-progress-action'),
  });

  final Key buttonKey;
  final PartnerNextAction action;
  final String? Function(String gymId) gymName;
  final void Function(PartnerNextAction action)? onAction;
  final bool busy;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final label = onAction == null ? null : partnerActionLabel(context, action);
    final support = partnerActionIsSupport(action);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          partnerActionMessage(context, action, gymName: gymName),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        if (label != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FFButton(
              key: buttonKey,
              label: label,
              maxLines: 2,
              size: small ? FFButtonSize.sm : FFButtonSize.md,
              variant: support || small
                  ? FFButtonVariant.secondary
                  : FFButtonVariant.primary,
              icon: support ? Icons.support_agent_outlined : null,
              onPressed: busy ? null : () => onAction!(action),
            ),
          ),
        ],
      ],
    );
  }
}

/// One gym of an owner with several: its name, its current step and, when it
/// is about this gym alone, what to do next.
class _GymRow extends StatelessWidget {
  const _GymRow({
    required this.gym,
    required this.overall,
    required this.onAction,
    required this.busy,
  });

  final PartnerGymProgress gym;
  final PartnerNextAction overall;
  final void Function(PartnerNextAction action)? onAction;
  final bool busy;

  /// The gym's own next action: its payout step. Verification is one case
  /// for the owner, so its action (with each gym item named with its gym)
  /// is said once, above, not again per gym.
  PartnerNextAction? get _own {
    final p = gym.progress;
    final a = p.nextAction;
    if (a.isNone || p.current != 'payoutReady') return null;
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = gym.progress;
    final step = p.currentStep ?? p.steps.last;
    final total = p.steps.length;
    final visual = _StateVisual.of(context, step.state);
    final own = _own;
    final name = gym.name ?? context.tr('progress.gymUnnamed');
    return Padding(
      key: Key('partner-progress-gym-${gym.gymId}'),
      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          Semantics(
            label: partnerStepSemantics(context, p.currentNumber, total, step),
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(visual.icon, size: FFTokens.iconSm, color: visual.color),
                const SizedBox(width: FFTokens.spacingXs),
                Expanded(
                  child: Text(
                    p.finished
                        ? _stepLabel(context, 'payoutReady')
                        : [
                            _fill(context.tr('progress.summary'), {
                              'n': p.currentNumber,
                              'total': total,
                              'label': _stepLabel(context, step.key),
                            }),
                            _stateLabel(context, step.state),
                          ].join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (own != null) ...[
            const SizedBox(height: FFTokens.spacingXs),
            _ActionLine(
              action: own,
              gymName: (_) => null,
              onAction: onAction,
              busy: busy,
              small: true,
              buttonKey: Key('partner-progress-gym-action-${gym.gymId}'),
            ),
          ],
        ],
      ),
    );
  }
}
