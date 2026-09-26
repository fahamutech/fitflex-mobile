import 'package:flutter/material.dart';

import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../communication_controller.dart';
import '../data/communication_models.dart';

/// Pick a preset audience, narrow it down, and see how many members match.
class AudienceSelector extends StatelessWidget {
  const AudienceSelector({super.key, required this.controller});

  final CampaignComposerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final r = c.refinements;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AudienceCountBanner(controller: c),
        const SizedBox(height: FFTokens.spacingMd),
        FFFieldLabel(context.tr('comms.audience.who')),
        Wrap(
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacingXs,
          children: [
            for (final p in kGymAudiencePresets)
              FFPill(
                key: Key('preset-$p'),
                label: context.tr('comms.preset.$p'),
                filled: c.preset == p,
                onTap: () => c.setPreset(p),
              ),
          ],
        ),
        if (c.preset != null) ...[
          const SizedBox(height: FFTokens.spacingXs),
          Text(
            context.tr('comms.preset.${c.preset}.body'),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: FFTokens.spacingLg),
        FFFieldLabel(context.tr('comms.audience.narrow')),
        if (c.hasCustomFilter)
          FFAlert(
            message: context.tr('comms.audience.customSetElsewhere'),
            tone: FFAlertTone.info,
          ),
        if (c.hasCustomFilter)
          TextButton(
            onPressed: c.clearCustomFilter,
            child: Text(context.tr('comms.audience.clearCustom')),
          )
        else ...[
          _ChoiceRow(
            keyPrefix: 'expires',
            label: context.tr('comms.audience.expiresWithin'),
            options: const [3, 7, 14, 30],
            selected: r.expiresWithinDays,
            format: (d) => context.tr('comms.days').replaceFirst('{n}', '$d'),
            onChanged: (d) =>
                c.setRefinements(r.copyWith(expiresWithinDays: () => d)),
          ),
          _ChoiceRow(
            keyPrefix: 'novisit',
            label: context.tr('comms.audience.noVisitFor'),
            options: const [7, 14, 30, 60],
            selected: r.noVisitForDays,
            format: (d) => context.tr('comms.days').replaceFirst('{n}', '$d'),
            onChanged: (d) =>
                c.setRefinements(r.copyWith(noVisitForDays: () => d)),
          ),
          _Label(context.tr('comms.audience.plan')),
          Wrap(
            spacing: FFTokens.spacingXs,
            children: [
              for (final plan in const ['daily', 'weekly', 'monthly'])
                FFPill(
                  key: Key('plan-$plan'),
                  label: context.tr('comms.plan.$plan'),
                  filled: r.plans.contains(plan),
                  onTap: () {
                    final next = {...r.plans};
                    next.contains(plan) ? next.remove(plan) : next.add(plan);
                    c.setRefinements(r.copyWith(plans: next));
                  },
                ),
            ],
          ),
          _ChoiceRow<String>(
            keyPrefix: 'gender',
            label: context.tr('comms.audience.gender'),
            options: const ['female', 'male'],
            selected: r.gender,
            format: (g) => context.tr('comms.gender.$g'),
            onChanged: (g) => c.setRefinements(r.copyWith(gender: () => g)),
          ),
          _ChoiceRow<(int, int?)>(
            keyPrefix: 'age',
            label: context.tr('comms.audience.age'),
            options: const [(18, 25), (26, 35), (36, 50), (51, null)],
            selected: r.minAge == null ? null : (r.minAge!, r.maxAge),
            format: (a) => a.$2 == null ? '${a.$1}+' : '${a.$1}–${a.$2}',
            onChanged: (a) => c.setRefinements(
              r.copyWith(minAge: () => a?.$1, maxAge: () => a?.$2),
            ),
          ),
          if (r.gender != null || r.minAge != null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              child: Text(
                context.tr('comms.audience.demographicsNote'),
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }
}

/// "84 members match this audience."
class AudienceCountBanner extends StatelessWidget {
  const AudienceCountBanner({super.key, required this.controller});

  final CampaignComposerController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final count = c.audienceCount;
    Widget child;
    if (c.countError != null) {
      child = Text(
        errorMessage(FFLocaleScope.of(context), c.countError!),
        style: theme.textTheme.bodyMedium,
      );
    } else if (count == null) {
      child = const FFSpinner();
    } else {
      final names = count.sample.take(3).join(', ');
      child = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            count.count == 0
                ? context.tr('comms.audience.none')
                : context
                      .tr(
                        count.count == 1
                            ? 'comms.audience.matchOne'
                            : 'comms.audience.match',
                      )
                      .replaceFirst('{n}', '${count.count}'),
            key: const Key('audience-count'),
            style: theme.textTheme.titleMedium,
          ),
          if (names.isNotEmpty)
            Text(
              context
                  .tr('comms.audience.forExample')
                  .replaceFirst('{names}', names),
              style: theme.textTheme.bodySmall,
            ),
        ],
      );
    }
    return FFCard(
      child: Row(
        children: [
          Icon(Icons.groups_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: FFTokens.spacingSm),
          Expanded(child: child),
          if (c.countLoading && count != null)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: FFTokens.spacingSm,
      bottom: FFTokens.spacingXs,
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

/// A row of single-choice pills that can be tapped again to clear.
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.keyPrefix,
    required this.label,
    required this.options,
    required this.selected,
    required this.format,
    required this.onChanged,
  });

  final String keyPrefix;
  final String label;
  final List<T> options;
  final T? selected;
  final String Function(T) format;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _Label(label),
      Wrap(
        spacing: FFTokens.spacingXs,
        runSpacing: FFTokens.spacingXs,
        children: [
          for (final o in options)
            FFPill(
              key: Key('$keyPrefix-${format(o)}'),
              label: format(o),
              filled: o == selected,
              onTap: () => onChanged(o == selected ? null : o),
            ),
        ],
      ),
    ],
  );
}
