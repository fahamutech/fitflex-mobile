import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/pass_summary_card.dart';
import 'widgets/checkin_list.dart';

class MemberProfileTab extends StatelessWidget {
  const MemberProfileTab({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final me = data.me;
    final displayName = me?.user.resolvedName ?? 'Member';
    final visitsUsed = me?.visitsUsed ?? 0;
    final visitCap = me?.visitCap;

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        // Profile header
        FFCard(
          child: Row(
            children: [
              FFAvatar(
                name: displayName,
                src: me?.user.photoUrl,
                size: FFAvatarSize.lg,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: FFTokens.fgPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FFBadge(
                      label:
                          data.subscription?.tier ?? context.tr('pass.pending'),
                      tone: data.hasActivePass
                          ? FFBadgeTone.success
                          : FFBadgeTone.gray,
                      dot: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Stats
        Row(
          children: [
            Expanded(
              child: FFMetricCard(
                label: context.tr('home.visits'),
                value: '$visitsUsed',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FFMetricCard(
                label: context.tr('pass.visits'),
                value: visitCap == null ? '-' : '$visitCap',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Subscription
        _SectionTitle(context.tr('member.mySubscription')),
        PassSummaryCard(data: data),

        // Visit history
        _SectionTitle(context.tr('member.visitHistory')),
        CheckinList(checkins: data.checkins, limit: 8),

        // Settings
        _SectionTitle(context.tr('member.accountSettings')),
        FFActionTile(
          icon: Icons.edit,
          title: context.tr('member.editDetails'),
          onTap: () {},
        ),
        FFActionTile(
          icon: Icons.payment,
          title: context.tr('member.paymentMethods'),
          onTap: () {},
        ),
        FFActionTile(
          icon: Icons.notifications,
          title: context.tr('member.notifications'),
          onTap: () {},
        ),
        FFActionTile(
          icon: Icons.help_outline,
          title: context.tr('member.help'),
          onTap: () {},
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: FFTokens.fgPrimary,
        ),
      ),
    );
  }
}
