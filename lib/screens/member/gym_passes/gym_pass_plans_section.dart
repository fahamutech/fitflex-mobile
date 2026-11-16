import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/gym_passes/gym_pass.dart';
import '../../../shared/gym_passes/gym_passes_flag.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import 'gym_pass_buy_sheet.dart';

/// Custom Gym Passes: the "Gym Membership Plans" section of a gym's page. A
/// gym's published custom plans, kept apart from the FitFlex Pass tiers and
/// the daily / weekly / monthly plans above it.
///
/// Nothing shows (and nothing is requested) while the build flag is off, the
/// server answers 404 `feature_disabled`, the request fails, or the gym has
/// no custom plans: the page is then exactly what it was.
class GymPassPlansSection extends StatefulWidget {
  const GymPassPlansSection({super.key, required this.gym, this.onBought});

  final Gym gym;

  /// A purchase was created (the member's profile and payments reload).
  final VoidCallback? onBought;

  @override
  State<GymPassPlansSection> createState() => _GymPassPlansSectionState();
}

class _GymPassPlansSectionState extends State<GymPassPlansSection> {
  List<GymPassPlan> _plans = const [];
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started || !gymCustomPassesEnabled) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await AppScope.of(context).api.gymPassPlans(widget.gym.id);
      if (!mounted) return;
      setState(() => _plans = [for (final p in raw) ?GymPassPlan.fromJson(p)]);
    } catch (_) {
      // 404 feature_disabled (off on the server) or a failed request: no
      // section. Custom passes are an extra, never a blocker for the page.
    }
  }

  Future<void> _buy(GymPassPlan plan) async {
    final bought = await showGymPassBuySheet(
      context,
      gym: widget.gym,
      plan: plan,
    );
    if (bought == true && mounted) widget.onBought?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (!gymCustomPassesEnabled || _plans.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      key: const Key('gym-section-pass-plans'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FFSectionTitle(context.tr('gymPass.sectionTitle')),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.tr('gymPass.sectionNote'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
        for (final plan in _plans)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: GymPassPlanTile(
              key: Key('gym-pass-plan-${plan.id}'),
              plan: plan,
              onTap: () => _buy(plan),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

/// One custom plan: name, who it covers, how long, price.
class GymPassPlanTile extends StatelessWidget {
  const GymPassPlanTile({super.key, required this.plan, required this.onTap});

  final GymPassPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = FFLocaleScope.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FFTokens.radiusXl),
      child: FFCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      FFBadge(
                        label: gymPassCategoryLabel(locale, plan),
                        tone: FFBadgeTone.brand,
                      ),
                      FFBadge(
                        label: gymPassDurationLabel(locale, plan),
                        tone: FFBadgeTone.gray,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatCurrency(plan.priceTzs),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
