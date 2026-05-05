import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/gym_card.dart';
import 'widgets/trainer_card.dart';
import 'widgets/pass_summary_card.dart';
import 'widgets/checkin_list.dart';

class MemberHomeTab extends StatelessWidget {
  const MemberHomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final me = data.me;
    final displayName = me?.user.resolvedName ?? context.tr('home.welcome');
    final gyms = data.gyms.take(2).toList();
    final trainers = data.trainers.take(2).toList();

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Text(
          context.tr('member.goodMorning'),
          style: const TextStyle(color: FFTokens.fgQuaternary, fontSize: 14),
        ),
        FFPageHeader(title: displayName),

        // Pass summary
        PassSummaryCard(data: data),

        // Near gyms
        _SectionRow(
          title: context.tr('member.nearGyms'),
          onSeeAll: () => context.go(AppRoutes.memberGyms),
        ),
        ...gyms.map((g) => GymCard(gym: g)),

        // Featured trainers
        _SectionRow(
          title: context.tr('member.featuredTrainers'),
          onSeeAll: () => context.go(AppRoutes.memberTrainers),
        ),
        ...trainers.map((t) => TrainerCard(trainer: t)),

        // Activity
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Text(
            context.tr('member.activity'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
          ),
        ),
        CheckinList(checkins: data.checkins, limit: 3),
      ],
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.title, required this.onSeeAll});

  final String title;
  final VoidCallback onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: FFTokens.fgPrimary,
              ),
            ),
          ),
          TextButton(
            onPressed: onSeeAll,
            child: Text(context.tr('home.seeAll')),
          ),
        ],
      ),
    );
  }
}
