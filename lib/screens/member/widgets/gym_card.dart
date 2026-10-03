import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/models.dart';
import '../../../shared/widgets/partner_not_verified.dart';

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
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (gymIsVerified(gym)) ...[
                        const SizedBox(width: 4),
                        const GymVerifiedIcon(size: 14),
                      ] else ...[
                        const SizedBox(width: 6),
                        const NotVerifiedLabel(),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    gym.location,
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodySmall?.color,
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
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.outline,
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

/// Portrait card used inside a responsive grid.
/// Uses a surface-shade background instead of elevation for separation.
class GymGridCard extends StatelessWidget {
  const GymGridCard({
    super.key,
    required this.gym,
    this.distanceKm,
    this.onTap,
    this.extraBadge,
  });

  final Gym gym;
  final double? distanceKm;

  /// Defaults to the member gym page.
  final VoidCallback? onTap;

  /// An extra badge under the tier (e.g. how a trainer gets in).
  final Widget? extraBadge;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: onTap ?? () => context.go('/member/gyms/${gym.id}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Image / thumbnail ──────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(FFTokens.radiusLg),
              ),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: gym.coverThumbnail == null
                    ? Container(
                        color: cs.primary.withValues(alpha: 0.1),
                        child: Icon(
                          Icons.fitness_center,
                          size: 36,
                          color: cs.primary,
                        ),
                      )
                    : FFRemoteImage(
                        src: gym.coverThumbnail!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        fallback: Container(
                          color: cs.primary.withValues(alpha: 0.1),
                          child: Icon(
                            Icons.fitness_center,
                            size: 36,
                            color: cs.primary,
                          ),
                        ),
                      ),
              ),
            ),
            // ── Content ────────────────────────────────────────────────
            Flexible(
              child: ClipRect(
                child: Padding(
                  // Keep the compact two-column card within the Pixel 7 grid's
                  // 241.3 px extent, including the verified and distance badges.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              gym.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (gymIsVerified(gym)) ...[
                            const SizedBox(width: 4),
                            const GymVerifiedIcon(size: 13),
                          ] else ...[
                            const SizedBox(width: 6),
                            const NotVerifiedLabel(),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        gym.location,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodySmall?.copyWith(fontSize: 11),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          FFBadge(
                            label: gym.tier.replaceAll('_', ' '),
                            tone: FFBadgeTone.brand,
                          ),
                          if (distanceKm != null)
                            FFBadge(
                              label: _formatDistance(distanceKm!),
                              tone: FFBadgeTone.gray,
                            ),
                          ?extraBadge,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
    final thumb = gym.coverThumbnail;
    if (thumb == null) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(FFTokens.radiusMd),
        ),
        child: Icon(
          Icons.fitness_center,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(FFTokens.radiusMd),
      child: FFRemoteImage(
        src: thumb,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        fallback: Container(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
          child: Icon(
            Icons.fitness_center,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
