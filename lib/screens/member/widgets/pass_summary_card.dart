import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../router.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
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
    final progress = visitCap == null || visitCap <= 0
        ? null
        : (visitsUsed / visitCap).clamp(0, 1).toDouble();

    final title = sub == null
        ? context.tr('home.subscribe')
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
            style: const TextStyle(color: FFTokens.fgQuaternary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
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
          if (sub != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('home.visits'),
                    style: const TextStyle(
                      color: FFTokens.fgQuaternary,
                      fontSize: 12,
                    ),
                  ),
                ),
                Text(
                  visitCap == null
                      ? '$visitsUsed / ${context.tr('pass.unlimited')}'
                      : '$visitsUsed / $visitCap',
                  style: const TextStyle(
                    color: FFTokens.fgSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (progress != null) ...[
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: progress,
                color: FFTokens.brand500,
                backgroundColor: FFTokens.bgTertiary,
                borderRadius: BorderRadius.circular(FFTokens.radiusFull),
              ),
            ],
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: data.hasActivePass
                      ? () => context.go(AppRoutes.memberQr)
                      : () => context.go(AppRoutes.memberPasses),
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
                  onPressed: () => context.go(AppRoutes.memberPasses),
                  child: Text(context.tr('member.upgradePlan')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
