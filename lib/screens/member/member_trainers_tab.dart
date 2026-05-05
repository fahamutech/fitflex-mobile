import 'package:flutter/material.dart';

import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/trainer_card.dart';

class MemberTrainersTab extends StatelessWidget {
  const MemberTrainersTab({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final trainers = data.trainers;

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        FFPageHeader(title: context.tr('member.findTrainerTitle')),
        TextField(
          decoration: InputDecoration(
            hintText: context.tr('member.searchTrainers'),
            prefixIcon: const Icon(Icons.search, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        FFSegmented(
          value: 'all',
          options: [
            ('all', context.tr('member.all')),
            ('weights', 'Weights'),
            ('cardio', 'Cardio'),
            ('yoga', 'Yoga'),
          ],
          onChanged: (_) {},
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 10),
          child: Text(
            context.tr('member.topRated'),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: FFTokens.fgPrimary,
            ),
          ),
        ),
        if (trainers.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...trainers.map((t) => TrainerCard(trainer: t)),
      ],
    );
  }
}
