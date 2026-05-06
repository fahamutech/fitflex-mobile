import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import 'widgets/trainer_card.dart';

class MemberGymDetailPage extends StatelessWidget {
  const MemberGymDetailPage({super.key, required this.gymId});

  final String gymId;

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final gym = data.gyms.where((g) => g.id == gymId).firstOrNull;

    if (gym == null) {
      return Center(child: FFEmptyState(title: context.tr('member.noData')));
    }

    final trainersAtGym = data.trainers
        .where((t) {
          return t.gymIds.contains(gymId) || t.gyms.any((g) => g.id == gymId);
        })
        .take(2)
        .toList();

    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        // Back + title
        Row(
          children: [
            IconButton(
              onPressed: () => context.go(AppRoutes.memberGyms),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                context.tr('member.gymDetail'),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: FFTokens.fgPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Hero image
        _GymHero(gym: gym),

        // Name + location
        Text(
          gym.name,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: FFTokens.fgPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          gym.location,
          style: const TextStyle(color: FFTokens.fgQuaternary, fontSize: 14),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FFBadge(
              label: gym.tier.replaceAll('_', ' '),
              tone: FFBadgeTone.brand,
            ),
            const SizedBox(width: 6),
            FFBadge(
              label: gym.isFreeOnline
                  ? context.tr('gym.free')
                  : context.tr('gym.paid'),
              tone: gym.isFreeOnline ? FFBadgeTone.success : FFBadgeTone.gray,
            ),
          ],
        ),

        // About
        _SectionTitle(context.tr('member.about')),
        FFCard(
          child: Text(
            gym.venueType == 'online'
                ? context.tr('member.planBody')
                : '${context.tr('member.openNow')} - QR Check-in - ${gym.perVisitRate} TZS',
            style: const TextStyle(color: FFTokens.fgQuaternary, height: 1.4),
          ),
        ),

        // Amenities & Equipment
        if (gym.amenities.isNotEmpty || gym.equipment.isNotEmpty) ...[
          _SectionTitle(context.tr('gym.amenities')),
          if (gym.amenities.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: gym.amenities
                  .map((a) => FFBadge(label: a, tone: FFBadgeTone.brand))
                  .toList(),
            ),
          if (gym.equipment.isNotEmpty) ...[
            if (gym.amenities.isNotEmpty) const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: gym.equipment
                  .map((e) => FFBadge(label: e, tone: FFBadgeTone.gray))
                  .toList(),
            ),
          ],
        ],

        // Trainers
        _SectionTitle(context.tr('member.trainersAtGym')),
        if (trainersAtGym.isEmpty)
          FFEmptyState(title: context.tr('member.noData'))
        else
          ...trainersAtGym.map((t) => TrainerCard(trainer: t)),

        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: () => context.go(AppRoutes.memberPasses),
                child: Text(context.tr('member.subscribe')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.go(AppRoutes.memberQr),
                child: Text(context.tr('member.visitWithPass')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GymHero extends StatelessWidget {
  const _GymHero({required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      margin: const EdgeInsets.only(bottom: 14),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: FFTokens.brand50,
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      ),
      child: gym.images.isNotEmpty
          ? FFRemoteImage(
              src: gym.images.first,
              width: double.infinity,
              height: 180,
              fit: BoxFit.cover,
              fallback: const Center(
                child: Icon(
                  Icons.fitness_center,
                  color: FFTokens.brand700,
                  size: 48,
                ),
              ),
            )
          : const Center(
              child: Icon(
                Icons.fitness_center,
                color: FFTokens.brand700,
                size: 48,
              ),
            ),
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
