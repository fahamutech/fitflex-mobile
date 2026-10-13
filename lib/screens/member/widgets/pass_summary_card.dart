import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../../../shared/tone_theme.dart';
import '../member_shell.dart';
import 'pass_state.dart';

class PassSummaryCard extends StatelessWidget {
  const PassSummaryCard({super.key, required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    // Until the profile arrives we don't know the pass, so don't flash
    // "Choose a pass" at a member who already has one.
    if (data.me == null && !data.offline) {
      return const FFCard(
        key: Key('pass-summary-loading'),
        child: SizedBox(height: 120, child: Center(child: FFSpinner(size: 32))),
      );
    }
    final theme = Theme.of(context);
    final state = passStateFor(data);
    final sub = data.subscription;
    final pending = data.pendingPayment;
    final directDaysLeft = sub?.isDirect == true ? sub?.daysLeft : null;
    final directDurationDays = _durationDays(sub);
    final directProgress = directDaysLeft == null || directDurationDays == null
        ? null
        : (directDaysLeft / directDurationDays).clamp(0, 1).toDouble();

    final title = sub == null
        ? context.tr('home.subscribe')
        : sub.isDirect
        ? (sub.homeGym?.name ?? context.tr('member.membership'))
        : context.tr('pass.${sub.tier}');
    final status = pending != null
        ? context.tr('pass.pending')
        : sub == null
        ? context.tr('home.subscribe')
        : _statusLabel(context, sub.status);

    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('member.yourPass'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              FFBadge(label: status, tone: state.badgeTone, dot: true),
            ],
          ),
          if (sub?.isDirect == true) ...[
            const SizedBox(height: 10),
            Text(
              context.tr('member.plan_${sub!.plan ?? 'monthly'}'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _DirectDateRow(
              key: const Key('direct-membership-start'),
              label: context.tr('member.membershipStart'),
              value: passDate(sub.startedAt),
            ),
            _DirectDateRow(
              key: const Key('direct-membership-expiry'),
              label: context.tr('member.membershipExpiry'),
              value: passDate(sub.expiresAt),
            ),
            if (directDaysLeft != null) ...[
              _DirectDateRow(
                key: const Key('direct-membership-days-left'),
                label: context.tr('member.membershipDaysLeft'),
                value: '${directDaysLeft < 0 ? 0 : directDaysLeft}',
              ),
              if (directProgress != null) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: directProgress,
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                ),
              ],
            ],
          ] else ...[
            const SizedBox(height: FFTokens.spacingMd),
            _stateBody(context, state),
          ],
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            key: const Key('pass-primary-action'),
            fullWidth: true,
            label: switch (state) {
              PassState.pending => context.tr('pass.state.viewPayment'),
              PassState.ended => context.tr('pass.state.payAgain'),
              _ when state.canShowQr => context.tr('member.showQr'),
              _ => context.tr('member.subscribe'),
            },
            icon: state.canShowQr ? Icons.qr_code_2 : null,
            onPressed: () => _go(
              context,
              state.canShowQr ? AppRoutes.memberQr : AppRoutes.memberPasses,
            ),
          ),
          if (state.canShowQr) ...[
            const SizedBox(height: FFTokens.spacingXs),
            FFButton(
              key: const Key('pass-upgrade-action'),
              fullWidth: true,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              label: context.tr('member.upgradePlan'),
              onPressed: () => _go(context, AppRoutes.memberPasses),
            ),
          ],
        ],
      ),
    );
  }

  /// The platform-pass body: the ring and what's next while the pass works,
  /// a plain sentence otherwise.
  Widget _stateBody(BuildContext context, PassState state) {
    final theme = Theme.of(context);
    final sub = data.subscription;
    final left = visitsLeft(data);
    final cap = data.me?.visitCap;
    final ends = passDate(sub?.expiresAt);

    final message = passStateMessage(context, data, state);

    if (!state.canShowQr) {
      return Text(
        message ?? '',
        key: const Key('pass-state-message'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final tone = FFToneTheme.of(context);
    final ringColor = state.tone == PassTone.warning
        ? tone.warning.dot
        : theme.colorScheme.primary;
    return Row(
      children: [
        if (left != null && cap != null)
          _VisitsRing(
            key: const Key('pass-visits-ring'),
            left: left,
            total: cap,
            color: ringColor,
            ofLabel: context
                .tr('pass.state.visitsOf')
                .replaceAll('{total}', '$cap'),
          )
        else
          Icon(Icons.all_inclusive, size: 40, color: ringColor),
        const SizedBox(width: FFTokens.spacingMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (left == null)
                Text(
                  context.tr('pass.unlimited'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              // The ending-soon sentence already carries the date.
              if (sub?.expiresAt != null && state != PassState.endingSoon)
                Text(
                  context.tr('pass.state.endsOn').replaceAll('{date}', ends),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.only(top: FFTokens.spacing2xs),
                  child: Text(
                    message,
                    key: const Key('pass-state-message'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// Refreshes the QR and profile first so the next screen is current.
  static Future<void> _go(BuildContext context, String route) async {
    final shellState = context.findAncestorStateOfType<MemberShellState>();
    await shellState?.refreshQr();
    await shellState?.refreshMe();
    if (!context.mounted) return;
    context.go(route);
  }

  /// Translated status, falling back to the raw value for new ones.
  static String _statusLabel(BuildContext context, String status) {
    final key = 'member.status_$status';
    final label = context.tr(key);
    return label == key ? status : label;
  }

  static int? _durationDays(Subscription? sub) {
    final start = DateTime.tryParse(sub?.startedAt ?? '');
    final end = DateTime.tryParse(sub?.expiresAt ?? '');
    if (start == null || end == null) return null;
    final days = end.difference(start).inHours ~/ 24;
    return days <= 0 ? null : days;
  }
}

class _DirectDateRow extends StatelessWidget {
  const _DirectDateRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

/// Visits left as a ring: the number in the middle, "of N visits" under it.
class _VisitsRing extends StatelessWidget {
  const _VisitsRing({
    super.key,
    required this.left,
    required this.total,
    required this.color,
    required this.ofLabel,
  });

  final int left;
  final int total;
  final Color color;
  final String ofLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total <= 0 ? 0.0 : (left / total).clamp(0.0, 1.0);
    return Semantics(
      label: '$left $ofLabel',
      child: SizedBox(
        width: 96,
        height: 96,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: fraction,
                strokeWidth: 9,
                strokeCap: StrokeCap.round,
                color: color,
                backgroundColor: theme.colorScheme.outlineVariant,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$left',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                Text(
                  ofLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
