import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/activity/training_plan.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../member_shell.dart';
import 'training_widgets.dart';

/// "Monday".
String weekdayLabel(BuildContext context, int day) =>
    context.tr('training.weekday.$day');

/// A plan a trainer has made for the member: who it is from, what it is,
/// and a way to look inside before answering.
class TrainingOfferCard extends StatelessWidget {
  const TrainingOfferCard({super.key, required this.offer});

  final TrainingPlanOffer offer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = offer.trainerName ?? context.tr('training.yourTrainer');
    return FFCard(
      key: Key('training-offer-${offer.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('training.offerFrom').replaceAll('{name}', from),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            [
              offer.name,
              context
                  .tr('training.weeks')
                  .replaceAll('{n}', '${offer.durationWeeks}'),
              context
                  .tr('training.daysAWeek')
                  .replaceAll('{n}', '${offer.daysPerWeek}'),
            ].join(' · '),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: Key('training-offer-open-${offer.id}'),
              onPressed: () => showTrainingOfferSheet(context, offer),
              child: Text(context.tr('training.offerView')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the offer: its sessions, the trainer's note, and Accept / Decline.
Future<void> showTrainingOfferSheet(
  BuildContext context,
  TrainingPlanOffer offer,
) {
  // The sheet lives above the shell, so hand it what it needs from here.
  final data = MemberDataScope.of(context);
  final shell = context.findAncestorStateOfType<MemberShellState>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => TrainingOfferView(offer: offer, data: data, shell: shell),
  );
}

/// An offer in full — its sessions, the trainer's note, Accept / Decline.
/// Shown in a sheet from the Training tab, and as a page of its own when
/// reached from a notification.
class TrainingOfferView extends StatefulWidget {
  const TrainingOfferView({
    super.key,
    required this.offer,
    required this.data,
    required this.shell,
    this.header,
    this.onAnswered,
  });

  final TrainingPlanOffer offer;
  final MemberData data;
  final MemberShellState? shell;

  /// Shown above the offer (the page's way back).
  final Widget? header;

  /// Called once the member has answered; by default the sheet closes.
  final void Function(bool accepted)? onAnswered;

  @override
  State<TrainingOfferView> createState() => _TrainingOfferViewState();
}

class _TrainingOfferViewState extends State<TrainingOfferView> {
  bool _busy = false;
  String? _error;

  Future<void> _answer({required bool accept}) async {
    final offer = widget.offer;
    final data = widget.data;
    if (accept && data.trainingPlan != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(ctx.tr('training.replaceTitle')),
          content: Text(ctx.tr('training.replaceBody')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ctx.tr('training.keepPlan')),
            ),
            FilledButton(
              key: const Key('offer-replace-confirm'),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ctx.tr('training.offerAccept')),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final repo = AppScope.of(context).training;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr(
      accept ? 'training.offerAccepted' : 'training.offerDeclined',
    );
    final failed = context.tr('training.failed');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final plan = accept ? await repo.accept(offer.id) : null;
      if (!accept) await repo.decline(offer.id);
      if (widget.shell != null) {
        await widget.shell!.refreshTraining();
      } else {
        // Keep the screen right even without a shell (tests, previews).
        data.update((d) {
          d.trainingOffers = [
            for (final o in d.trainingOffers)
              if (o.id != offer.id) o,
          ];
          if (plan != null) d.trainingPlan = plan;
        });
      }
      if (widget.onAnswered case final answered?) {
        answered(accept);
      } else {
        navigator.pop();
      }
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = failed;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offer = widget.offer;
    final from = offer.trainerName ?? context.tr('training.yourTrainer');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        child: ListView(
          key: const Key('offer-sheet'),
          shrinkWrap: true,
          children: [
            ?widget.header,
            Text(offer.name, style: theme.textTheme.titleLarge),
            Text(
              [
                context.tr('training.fromTrainer').replaceAll('{name}', from),
                context
                    .tr('training.weeks')
                    .replaceAll('{n}', '${offer.durationWeeks}'),
                if (offer.startDate != null)
                  context
                      .tr('training.startsOn')
                      .replaceAll(
                        '{date}',
                        trainingDate(context, offer.startDate!),
                      ),
              ].join(' · '),
              style: theme.textTheme.bodySmall,
            ),
            if ((offer.note ?? '').isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingSm),
              FFCard(
                key: const Key('offer-note'),
                child: Text(offer.note!, style: theme.textTheme.bodyMedium),
              ),
            ],
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('training.offerEachWeek'),
              style: theme.textTheme.labelLarge,
            ),
            for (final s in offer.firstWeek)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [
                        weekdayLabel(context, s.day),
                        s.name,
                        if (s.estimatedDuration != null)
                          context
                              .tr('training.minutes')
                              .replaceAll('{n}', '${s.estimatedDuration}'),
                      ].join(' · '),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final e in s.exercises)
                      Text(e, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('training.offerNote'),
              style: theme.textTheme.bodySmall,
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                child: Text(
                  _error!,
                  key: const Key('offer-error'),
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),
            const SizedBox(height: FFTokens.spacingMd),
            FilledButton(
              key: const Key('offer-accept'),
              onPressed: _busy ? null : () => _answer(accept: true),
              child: Text(context.tr('training.offerAccept')),
            ),
            TextButton(
              key: const Key('offer-decline'),
              onPressed: _busy ? null : () => _answer(accept: false),
              child: Text(context.tr('training.offerDecline')),
            ),
          ],
        ),
      ),
    );
  }
}
