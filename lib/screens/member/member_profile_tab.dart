import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/pass_summary_card.dart';
import 'widgets/checkin_list.dart';

class MemberProfileTab extends StatelessWidget {
  const MemberProfileTab({super.key});

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('home.signout')),
        content: Text(context.tr('confirm.signout')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.tr('member.cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FFTokens.error500),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('home.signout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await AppScope.of(context).auth.signOut();
    if (!context.mounted) return;
    context.go(AppRoutes.language);
  }

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
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () => _confirmSignOut(context),
          icon: const Icon(Icons.logout, color: FFTokens.fgTertiary),
          label: Text(
            context.tr('home.signout'),
            style: const TextStyle(color: FFTokens.fgTertiary),
          ),
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
