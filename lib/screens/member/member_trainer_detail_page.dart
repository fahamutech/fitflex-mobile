import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/trainer_actions_sheet.dart';
import 'widgets/trainer_sharing.dart';

class MemberTrainerDetailPage extends StatefulWidget {
  const MemberTrainerDetailPage({super.key, required this.trainerId});

  final String trainerId;

  @override
  State<MemberTrainerDetailPage> createState() =>
      _MemberTrainerDetailPageState();
}

class _MemberTrainerDetailPageState extends State<MemberTrainerDetailPage> {
  bool _interestBusy = false;

  String get trainerId => widget.trainerId;

  Future<void> _book() async {
    final data = MemberDataScope.of(context);
    final trainer = data.trainers.where((t) => t.id == trainerId).firstOrNull;
    if (trainer == null) return;
    final booked = await showTrainerBookingSheet(context, trainer);
    if (booked == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.bookingRequested'))),
      );
    }
  }

  Future<void> _enquire() async {
    final data = MemberDataScope.of(context);
    final trainer = data.trainers.where((t) => t.id == trainerId).firstOrNull;
    if (trainer == null) return;
    final sent = await showTrainerEnquiryDialog(context, trainer);
    if (sent == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.tr('member.enquirySent'))));
    }
  }

  Future<void> _showInterest() async {
    setState(() => _interestBusy = true);
    try {
      await AppScope.of(context).api.engageTrainer(trainerId, type: 'interest');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.interestSent'))),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.enquiryFailed'))),
      );
    } finally {
      if (mounted) setState(() => _interestBusy = false);
    }
  }

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
          key: const Key('trainer-detail-back'),
          onPressed: () => context.go(AppRoutes.memberTrainers),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('member.findTrainerTitle')),
      ),
      // A4 — pinned action bar: Book / Enquire / Show interest.
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: Row(
            key: const Key('trainer-actions'),
            children: [
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  key: const Key('trainer-action-book'),
                  onPressed: _book,
                  icon: const Icon(Icons.event_available, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.tr('member.bookSession')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  key: const Key('trainer-action-enquire'),
                  onPressed: _enquire,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.tr('member.enquire')),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: const Key('trainer-action-interest'),
                  onPressed: _interestBusy ? null : _showInterest,
                  icon: const Icon(Icons.favorite_border, size: 18),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(context.tr('member.showInterest')),
                  ),
                ),
              ),
            ],
          ),
        ),
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
                        if (trainer.isVerified) ...[
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
          // A5 — standardized profile facts: rate, experience, rating.
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              FFBadge(
                label:
                    '${trainer.sessionRateCurrency} ${trainer.hourlyRateTzs}${context.tr('trainerReg.perSession')}',
                tone: FFBadgeTone.brand,
              ),
              if ((trainer.experienceYears ?? 0) > 0)
                FFBadge(
                  label:
                      '${trainer.experienceYears} ${context.tr('member.yearsExp')}',
                  tone: FFBadgeTone.gray,
                ),
              if ((trainer.rating ?? 0) > 0)
                FFBadge(
                  label: '★ ${trainer.rating}',
                  tone: FFBadgeTone.success,
                ),
            ],
          ),

          // Connect for a trainer plan — the member chooses what's shared.
          TrainerConnectCard(
            trainerId: trainer.id,
            trainerName: trainer.displayName,
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
