import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';

class MemberTrainerDetailPage extends StatelessWidget {
  const MemberTrainerDetailPage({super.key, required this.trainerId});

  final String trainerId;

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final trainer = data.trainers.where((t) => t.id == trainerId).firstOrNull;

    if (trainer == null) {
      return Center(child: FFEmptyState(title: context.tr('member.noData')));
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => context.go(AppRoutes.memberTrainers),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('member.findTrainerTitle')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          // Trainer header
          Row(
            children: [
              FFAvatar(
                name: trainer.displayName,
                src: trainer.photoUrl,
                size: FFAvatarSize.lg,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            trainer.displayName,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        if (trainer.approvalStatus == 'approved') ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            size: 20,
                            color: FFTokens.success600,
                          ),
                        ],
                      ],
                    ),
                    if (trainer.specialties.isNotEmpty)
                      Text(
                        trainer.specialties.join(' / '),
                        style: TextStyle(
                          color: Theme.of(context).textTheme.bodySmall?.color,
                          fontSize: 14,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FFBadge(
                label:
                    '${trainer.sessionRateCurrency} ${trainer.hourlyRateTzs}${context.tr('trainerReg.perSession')}',
                tone: FFBadgeTone.brand,
              ),
              const SizedBox(width: 6),
              // FFBadge(
              //   label: '${trainer.experienceYears ?? 0} yrs',
              //   tone: FFBadgeTone.gray,
              // ),
              // const SizedBox(width: 6),
              // FFBadge(
              //   label: '${trainer.rating ?? '-'} rating',
              //   tone: FFBadgeTone.success,
              // ),
            ],
          ),

          // About
          FFSectionTitle(context.tr('member.about')),
          FFCard(
            child: Text(
              trainer.bio ?? '',
              style: TextStyle(
                color: Theme.of(context).textTheme.bodySmall?.color,
                height: 1.4,
              ),
            ),
          ),

          // Gyms
          FFSectionTitle(context.tr('member.availableGyms')),
          if (trainer.gyms.isEmpty)
            FFEmptyState(title: context.tr('member.noData'))
          else
            ...trainer.gyms.map(
              (g) => FFActionTile(
                icon: Icons.fitness_center,
                title: g.name,
                subtitle: g.location,
                onTap: () => context.go('/member/gyms/${g.id}'),
              ),
            ),

          // Availability
          FFSectionTitle(context.tr('member.availability')),
          if (trainer.availability.isEmpty)
            FFEmptyState(title: context.tr('member.noData'))
          else
            ...trainer.availability.map(
              (a) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FFCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            a.dayLabel,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                          ),
                          if (a.gymName != null) ...[
                            const SizedBox(width: 8),
                            FFBadge(label: a.gymName!, tone: FFBadgeTone.brand),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: a.slots
                            .map(
                              (s) => FFBadge(label: s, tone: FFBadgeTone.gray),
                            )
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
