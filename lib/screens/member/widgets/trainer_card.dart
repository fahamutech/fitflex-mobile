import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';

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
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: FFTokens.fgPrimary,
                          ),
                        ),
                      ),
                      if (trainer.approvalStatus == 'approved') ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.verified,
                          size: 14,
                          color: FFTokens.success600,
                        ),
                      ],
                    ],
                  ),
                  if (specialties.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      specialties,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: FFTokens.fgQuaternary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Text(
              '${trainer.sessionRateCurrency} ${trainer.hourlyRateTzs}${context.tr('trainerReg.perSession')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: FFTokens.fgSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
