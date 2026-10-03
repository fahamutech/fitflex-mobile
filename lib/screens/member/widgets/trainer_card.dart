import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../../../shared/widgets/partner_not_verified.dart';

/// Portrait card used inside a responsive grid.
/// Uses a surface-shade background instead of elevation for separation.
class TrainerGridCard extends StatelessWidget {
  const TrainerGridCard({super.key, required this.trainer});

  final TrainerProfile trainer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final specialties = trainer.specialties.take(2).join(' · ');

    return GestureDetector(
      onTap: () => context.go('/member/trainers/${trainer.id}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar / photo ─────────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(FFTokens.radiusLg),
              ),
              child: AspectRatio(
                aspectRatio: 1,
                child: trainer.photoUrl != null && trainer.photoUrl!.isNotEmpty
                    ? FFRemoteImage(
                        src: trainer.photoUrl!,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.cover,
                        fallback: _AvatarPlaceholder(name: trainer.displayName),
                      )
                    : _AvatarPlaceholder(name: trainer.displayName),
              ),
            ),
            // ── Content ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          trainer.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (trainer.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          size: 13,
                          color: FFTokens.success600,
                        ),
                      ] else ...[
                        const SizedBox(width: 6),
                        const NotVerifiedLabel(),
                      ],
                    ],
                  ),
                  if (specialties.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      specialties,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    formatCurrency(
                      trainer.hourlyRateTzs,
                      currency: trainer.sessionRateCurrency,
                    ),
                    style: tt.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final initials = name
        .split(' ')
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return Container(
      color: cs.primary.withValues(alpha: 0.12),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

class TrainerCard extends StatelessWidget {
  const TrainerCard({super.key, required this.trainer});

  final TrainerProfile trainer;

  @override
  Widget build(BuildContext context) {
    final specialties = trainer.specialties.join(' / ');
    return FFCard(
      child: InkWell(
        onTap: () => context.go('/member/trainers/${trainer.id}'),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        child: Row(
          children: [
            FFAvatar(
              name: trainer.displayName,
              src: trainer.photoUrl,
              size: FFAvatarSize.lg,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          trainer.displayName,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (trainer.isVerified) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          size: 14,
                          color: FFTokens.success600,
                        ),
                      ] else ...[
                        const SizedBox(width: 6),
                        const NotVerifiedLabel(),
                      ],
                    ],
                  ),
                  if (specialties.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      specialties,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodySmall?.color,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '${formatCurrency(trainer.hourlyRateTzs, currency: trainer.sessionRateCurrency)}${context.tr('trainerReg.perSession')}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
