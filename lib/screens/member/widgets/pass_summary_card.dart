import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../member_shell.dart';

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
    final sub = data.subscription;
    final pending = data.pendingPayment;
    final visitsUsed = data.me?.visitsUsed ?? 0;
    final visitCap = data.me?.visitCap;
    final visitProgress = visitCap == null || visitCap <= 0
        ? null
        : (visitsUsed / visitCap).clamp(0, 1).toDouble();
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
              FFBadge(
                label: status,
                tone: data.hasActivePass
                    ? FFBadgeTone.success
                    : pending != null
                    ? FFBadgeTone.warning
                    : FFBadgeTone.gray,
                dot: true,
              ),
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
              value: _formatDate(sub.startedAt),
            ),
            _DirectDateRow(
              key: const Key('direct-membership-expiry'),
              label: context.tr('member.membershipExpiry'),
              value: _formatDate(sub.expiresAt),
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
          ] else if (sub != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('home.visits'),
                    style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  visitCap == null
                      ? '$visitsUsed / ${context.tr('pass.unlimited')}'
                      : '$visitsUsed / $visitCap',
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (visitProgress != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: visitProgress,
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(FFTokens.radiusFull),
              ),
            ],
          ],
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            key: const Key('pass-primary-action'),
            fullWidth: true,
            label: data.hasActivePass
                ? context.tr('member.showQr')
                : context.tr('member.subscribe'),
            icon: data.hasActivePass ? Icons.qr_code_2 : null,
            onPressed: () => _go(
              context,
              data.hasActivePass ? AppRoutes.memberQr : AppRoutes.memberPasses,
            ),
          ),
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
      ),
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

  static String _formatDate(String? iso) {
    final date = DateTime.tryParse(iso ?? '')?.toLocal();
    if (date == null) return '-';
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year}';
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
