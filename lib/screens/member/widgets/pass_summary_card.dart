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
        : sub?.status ?? context.tr('home.subscribe');

    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('member.yourPass'),
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          FFBadge(
            label: status,
            tone: data.hasActivePass
                ? FFBadgeTone.success
                : pending != null
                ? FFBadgeTone.warning
                : FFBadgeTone.gray,
            dot: true,
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
                  backgroundColor: Theme.of(context).colorScheme.surface,
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
                      color: Theme.of(context).textTheme.bodySmall?.color,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  visitCap == null
                      ? '$visitsUsed / ${context.tr('pass.unlimited')}'
                      : '$visitsUsed / $visitCap',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
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
                backgroundColor: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(FFTokens.radiusFull),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () async {
                    // Refresh QR and user data before navigation
                    final shellState = context
                        .findAncestorStateOfType<MemberShellState>();
                    await shellState?.refreshQr();
                    await shellState?.refreshMe();
                    if (!context.mounted) return;
                    if (data.hasActivePass) {
                      context.go(AppRoutes.memberQr);
                    } else {
                      context.go(AppRoutes.memberPasses);
                    }
                  },
                  child: Text(
                    data.hasActivePass
                        ? context.tr('member.showQr')
                        : context.tr('member.subscribe'),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    // Refresh QR and user data before navigation
                    final shellState = context
                        .findAncestorStateOfType<MemberShellState>();
                    await shellState?.refreshQr();
                    await shellState?.refreshMe();
                    if (!context.mounted) return;
                    context.go(AppRoutes.memberPasses);
                  },
                  child: Text(context.tr('member.upgradePlan')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
