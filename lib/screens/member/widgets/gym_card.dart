import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';

class GymCard extends StatelessWidget {
  const GymCard({super.key, required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: InkWell(
        onTap: () => context.go('/member/gyms/${gym.id}'),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Row(
          children: [
            SizedBox(width: 72, height: 72, child: _GymThumb(gym: gym)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    gym.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: FFTokens.fgPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gym.location,
                    style: const TextStyle(
                      color: FFTokens.fgQuaternary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
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
                        tone: gym.isFreeOnline
                            ? FFBadgeTone.success
                            : FFBadgeTone.gray,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: FFTokens.fgDisabled,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _GymThumb extends StatelessWidget {
  const _GymThumb({required this.gym});

  final Gym gym;

  @override
  Widget build(BuildContext context) {
    if (gym.images.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: FFTokens.brand50,
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        child: const Icon(Icons.fitness_center, color: FFTokens.brand700),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      child: Image.network(
        gym.images.first,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stack) => Container(
          color: FFTokens.brand50,
          child: const Icon(Icons.fitness_center, color: FFTokens.brand700),
        ),
      ),
    );
  }
}
