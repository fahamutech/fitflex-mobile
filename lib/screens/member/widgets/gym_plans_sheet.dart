import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';

/// A7 — Gym direct plan model derived from the gym's own rates.
class GymPlan {
  const GymPlan({required this.id, required this.price, required this.days});

  final String id; // daily | weekly | monthly
  final num price;
  final int days;
}

/// Builds the sellable Daily/Weekly/Monthly plans for a gym.
/// Plans with no configured price are omitted.
List<GymPlan> gymPlansFor(Gym gym) {
  final plans = <GymPlan>[
    if ((gym.ratePerDay ?? 0) > 0)
      GymPlan(id: 'daily', price: gym.ratePerDay!, days: 1),
    if ((gym.ratePerWeek ?? 0) > 0)
      GymPlan(id: 'weekly', price: gym.ratePerWeek!, days: 7),
    if ((gym.ratePerMonth ?? 0) > 0)
      GymPlan(id: 'monthly', price: gym.ratePerMonth!, days: 30),
  ];
  return plans;
}

/// A7 — bottom sheet listing a gym's Daily/Weekly/Monthly plans.
/// Confirming a plan creates a direct subscription (payment pending).
Future<bool?> showGymPlansSheet(BuildContext context, Gym gym) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => GymPlansSheet(gym: gym),
  );
}

class GymPlansSheet extends StatefulWidget {
  const GymPlansSheet({super.key, required this.gym});

  final Gym gym;

  @override
  State<GymPlansSheet> createState() => _GymPlansSheetState();
}

class _GymPlansSheetState extends State<GymPlansSheet> {
  String? _selectedPlan;
  bool _busy = false;
  String? _error;

  Future<void> _subscribe() async {
    final plan = _selectedPlan;
    if (plan == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.of(
        context,
      ).api.subscribeDirect(gymId: widget.gym.id, plan: plan);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '${context.tr('member.subscribeFailed')} (${e.status})';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('member.subscribeFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plans = gymPlansFor(widget.gym);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: FFTokens.spacingLg,
          right: FFTokens.spacingLg,
          bottom: MediaQuery.of(context).viewInsets.bottom + FFTokens.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('member.gymPlansTitle'),
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(widget.gym.name, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            if (plans.isEmpty)
              FFEmptyState(title: context.tr('member.noGymPlans'))
            else
              ...plans.map(
                (p) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _PlanTile(
                    key: Key('gym-plan-${p.id}'),
                    plan: p,
                    selected: _selectedPlan == p.id,
                    onTap: _busy
                        ? null
                        : () => setState(() => _selectedPlan = p.id),
                  ),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              FFAlert(message: _error!, tone: FFAlertTone.error),
            ],
            const SizedBox(height: 10),
            if (plans.isNotEmpty)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('gym-plan-subscribe'),
                  onPressed: _selectedPlan == null || _busy ? null : _subscribe,
                  child: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(context.tr('member.subscribe')),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    super.key,
    required this.plan,
    required this.selected,
    required this.onTap,
  });

  final GymPlan plan;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      child: AnimatedContainer(
        duration: FFTokens.motionFast,
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        decoration: BoxDecoration(
          color: selected ? cs.primary.withValues(alpha: 0.1) : cs.surface,
          border: Border.all(
            color: selected ? cs.primary : cs.outline,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('member.plan_${plan.id}'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context
                        .tr('member.planDuration')
                        .replaceFirst('{days}', '${plan.days}'),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            Text(
              formatCurrency(plan.price),
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (selected) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_circle, color: cs.primary, size: 20),
            ],
          ],
        ),
      ),
    );
  }
}
