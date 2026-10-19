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
    // Offline before the profile ever arrived: we don't know the pass, so
    // say we couldn't load it rather than "No pass yet".
    if (data.me == null && data.offline) {
      return FFErrorState(
        key: const Key('pass-summary-error'),
        icon: Icons.cloud_off_outlined,
        title: context.tr('home.passError.title'),
        retryLabel: context.tr('home.retry'),
        onRetry: () => _retry(context),
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

    // A working pass leads with its own name and status. A purchase still
    // waiting for approval is a different pass, so it gets its own amber
    // line below instead of borrowing this card's title or badge.
    final hasPass = state.canShowQr;
    final pendingAside = hasPass ? pending : null;

    // With no pass the title says so once; the sentence and the button
    // below carry the invitation, so the badge is left out.
    final String title;
    final String? status;
    if (hasPass || (pending == null && sub != null)) {
      title = sub!.isDirect
          ? (sub.homeGym?.name ?? context.tr('member.membership'))
          : context.tr('pass.${sub.tier}');
      status = _statusLabel(context, sub.status);
    } else if (pending != null) {
      title =
          _pendingName(context, pending) ??
          context.tr('pass.state.pendingPurchaseAny');
      status = context.tr('pass.pending');
    } else {
      title = context.tr('pass.state.noPassYet');
      status = null;
    }

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
              if (status != null) ...[
                const SizedBox(width: FFTokens.spacingSm),
                FFBadge(label: status, tone: state.badgeTone, dot: true),
              ],
            ],
          ),
          if (pendingAside != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            FFBadge(
              key: const Key('pass-pending-purchase'),
              label: switch (_pendingName(context, pendingAside)) {
                final name? =>
                  context
                      .tr('pass.state.pendingPurchase')
                      .replaceAll('{tier}', name),
                null => context.tr('pass.state.pendingPurchaseAny'),
              },
              tone: FFBadgeTone.warning,
              dot: true,
              wrap: true,
            ),
          ],
          if (sub?.isDirect == true && (hasPass || pending == null)) ...[
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
            if (passStateMessage(context, data, state) case final m?) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                m,
                key: const Key('pass-state-message'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
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
              _ => context.tr('pass.state.choose'),
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

    var message = passStateMessage(context, data, state);

    if (!state.canShowQr) {
      return Text(
        message ?? '',
        key: const Key('pass-state-message'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    // The ring already says how many are left; say what to do about it.
    if (state == PassState.lowVisits && (left ?? 0) > 0) {
      message = context.tr('pass.state.lowVisitsHint');
    }

    // Beside the ring: how many of the total they have used.
    final usedOf = left == null || cap == null
        ? null
        : context
              .tr('pass.state.usedOf')
              .replaceAll('{used}', '${(cap - left).clamp(0, cap)}')
              .replaceAll('{total}', '$cap');

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
            leftLabel: context.tr('pass.state.left'),
            ofLabel: usedOf!,
          )
        else
          Icon(Icons.all_inclusive, size: 40, color: ringColor),
        const SizedBox(width: FFTokens.spacingMd),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Beside the ring's "11 left": "7 of 18 used".
              Text(
                usedOf ?? context.tr('pass.unlimited'),
                key: const Key('pass-visits-used'),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              // The ending-soon sentence already carries the date.
              if (sub?.expiresAt != null && state != PassState.endingSoon)
                Text(
                  context.tr('pass.state.endsOn').replaceAll('{date}', ends),
                  style: theme.textTheme.bodyMedium,
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

  /// Loads the profile again (and the QR once it says there is a pass).
  Future<void> _retry(BuildContext context) async {
    final shellState = context.findAncestorStateOfType<MemberShellState>();
    await shellState?.refreshMe();
    if (data.canCheckIn) await shellState?.refreshQr();
  }

  /// The pass name for a tier, or the tier itself for one the app doesn't know.
  static String _tierLabel(BuildContext context, String tier) {
    final key = 'pass.$tier';
    final label = context.tr(key);
    return label == key ? tier : label;
  }

  /// What a waiting payment buys: the pass tier, or the gym for a gym plan.
  static String? _pendingName(BuildContext context, PaymentRequest pending) {
    if (pending.tier.isNotEmpty) return _tierLabel(context, pending.tier);
    final gym = pending.gymName?.trim() ?? '';
    return gym.isEmpty ? null : gym;
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

/// Visits left as a ring: the number in the middle with "left" under it.
/// "7 of 18 used" sits beside the ring, so no number is said twice.
class _VisitsRing extends StatelessWidget {
  const _VisitsRing({
    super.key,
    required this.left,
    required this.total,
    required this.color,
    required this.leftLabel,
    required this.ofLabel,
  });

  final int left;
  final int total;
  final Color color;
  final String leftLabel;
  final String ofLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = total <= 0 ? 0.0 : (left / total).clamp(0.0, 1.0);
    return Semantics(
      label: '$left $leftLabel $ofLabel',
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
                  leftLabel,
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
