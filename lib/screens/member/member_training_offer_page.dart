import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/i18n.dart';
import 'member_shell.dart';
import 'widgets/training_offer.dart';

/// A trainer's plan offer on a page of its own — where the "your trainer
/// made you a plan" notification leads. If the offer is no longer waiting
/// (answered already, or taken back), it says so and points to the plan.
class MemberTrainingOfferPage extends StatefulWidget {
  const MemberTrainingOfferPage({super.key, required this.offerId});

  final String offerId;

  @override
  State<MemberTrainingOfferPage> createState() =>
      _MemberTrainingOfferPageState();
}

class _MemberTrainingOfferPageState extends State<MemberTrainingOfferPage> {
  bool _checked = false;
  bool _checking = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final data = MemberDataScope.of(context);
    final shell = context.findAncestorStateOfType<MemberShellState>();
    // The notification can arrive after the app last loaded its offers:
    // look once more before saying it isn't there.
    if (!_checked &&
        shell != null &&
        data.trainingLoaded &&
        !data.trainingOffers.any((o) => o.id == widget.offerId)) {
      _checked = true;
      _checking = true;
      shell.refreshTraining().whenComplete(() {
        if (mounted) setState(() => _checking = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final shell = context.findAncestorStateOfType<MemberShellState>();
    final back = Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: const Key('training-back'),
        onPressed: () => context.go(AppRoutes.memberActivity),
        icon: const Icon(Icons.arrow_back, size: 18),
        label: Text(context.tr('activity.title')),
      ),
    );
    if (!data.trainingLoaded || _checking) {
      return const Center(child: CircularProgressIndicator());
    }
    final offer = data.trainingOffers
        .where((o) => o.id == widget.offerId)
        .firstOrNull;
    if (offer == null) {
      final onIt = data.trainingPlan?.id == widget.offerId;
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          back,
          FFEmptyState(
            key: const Key('offer-gone'),
            title: context.tr(
              onIt ? 'training.offerAlreadyYours' : 'training.offerGone',
            ),
            body: onIt ? null : context.tr('training.offerGoneBody'),
            action: FilledButton.tonal(
              key: const Key('offer-gone-plan'),
              onPressed: () => context.go(AppRoutes.memberTrainingPlan),
              child: Text(context.tr('training.viewPlan')),
            ),
          ),
        ],
      );
    }
    final router = GoRouter.maybeOf(context);
    return TrainingOfferView(
      key: ValueKey(offer.id),
      offer: offer,
      data: data,
      shell: shell,
      header: back,
      // Accepted: straight to the plan. Declined: back to Activity.
      onAnswered: (accepted) => router?.go(
        accepted ? AppRoutes.memberTrainingPlan : AppRoutes.memberActivity,
      ),
    );
  }
}
