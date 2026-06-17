import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/models.dart';

class GymCard extends StatelessWidget {
  const GymCard({super.key, required this.gym, this.distanceKm});

  final Gym gym;
  final double? distanceKm;

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
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          gym.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: FFTokens.fgPrimary,
                          ),
                        ),
                      ),
                      if (gymIsVerified(gym)) ...[
                        const SizedBox(width: 4),
                        const GymVerifiedIcon(size: 14),
                      ],
                    ],
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
                      if (distanceKm != null) ...[
                        const SizedBox(width: 6),
                        FFBadge(
                          label: _formatDistance(distanceKm!),
                          tone: FFBadgeTone.gray,
                        ),
                      ],
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

bool gymIsVerified(Gym gym) =>
    gym.isVerified ||
    gym.verificationStatus == 'verified' ||
    gym.verificationStatus == 'approved';

String _formatDistance(double km) {
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.round()} km';
}

class GymVerifiedIcon extends StatelessWidget {
  const GymVerifiedIcon({super.key, this.size = 16});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Icon(Icons.verified, size: size, color: FFTokens.success600);
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
      child: FFRemoteImage(
        src: gym.images.first,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        fallback: Container(
          color: FFTokens.brand50,
          child: const Icon(Icons.fitness_center, color: FFTokens.brand700),
        ),
      ),
    );
  }
}
