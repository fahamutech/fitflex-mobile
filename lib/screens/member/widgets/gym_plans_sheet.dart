import 'package:flutter/material.dart';
import 'mobile_money_pay.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../../../shared/manual_payment.dart';

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
  PaymentModes _modes = PaymentModes.none;
  final _transactionId = TextEditingController();
  String? _idError;

  @override
  void initState() {
    super.initState();
    // Read without depending on it: initState may not register dependencies.
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    if (scope == null) return;
    loadPaymentModes(scope.api).then((m) {
      if (mounted) setState(() => _modes = m);
    });
  }

  @override
  void dispose() {
    _transactionId.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    final plan = _selectedPlan;
    if (plan == null || _busy) return;
    final manual = _modes.manual;
    String? reference;
    if (manual != null) {
      final problem = transactionIdError(_transactionId.text);
      if (problem != null) {
        setState(() => _idError = context.tr(problem));
        return;
      }
      reference = _transactionId.text.trim();
    }
    setState(() {
      _busy = true;
      _error = null;
      _idError = null;
    });
    try {
      final created = await AppScope.of(context).api.subscribeDirect(
        gymId: widget.gym.id,
        plan: plan,
        reference: reference,
      );
      if (!mounted) return;
      // With mobile money switched on, pay straight away; a transaction ID
      // means it was already paid by hand.
      final req = created['paymentRequest'];
      if (manual == null && req is Map) {
        await offerMobileMoney(
          context,
          paymentRequestId: req['id'] as String?,
          amountTzs: (req['amountTzs'] as num?) ?? 0,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      final idProblem = transactionIdServerErrorKey(e);
      setState(() {
        _busy = false;
        if (manual != null && idProblem != null) {
          _idError = context.tr(idProblem);
        } else {
          _error = apiErrorMessage(FFLocaleScope.of(context), e);
        }
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
        // Scrolls when the Lipa Namba steps and the keyboard need the room.
        child: SingleChildScrollView(
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
              Text(
                widget.gym.name,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 4),
              Text(
                context.tr('member.gymPlansNote'),
                style: Theme.of(context).textTheme.labelSmall,
              ),
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
              if (_modes.manual != null && _selectedPlan != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 6),
                  child: ManualPaymentFields(
                    key: const Key('gym-plan-manual-pay'),
                    manual: _modes.manual!,
                    amountLabel: formatCurrency(
                      plans
                              .where((p) => p.id == _selectedPlan)
                              .firstOrNull
                              ?.price ??
                          0,
                    ),
                    controller: _transactionId,
                    errorText: _idError,
                    enabled: !_busy,
                    onChanged: (_) {
                      if (_idError != null) setState(() => _idError = null);
                    },
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
                  child: FFButton(
                    key: const Key('gym-plan-subscribe'),
                    label: context.tr(
                      _modes.manual != null
                          ? 'manualPay.submit'
                          : 'member.subscribe',
                    ),
                    onPressed: _selectedPlan == null || _busy
                        ? null
                        : _subscribe,
                    loading: _busy,
                  ),
                ),
            ],
          ),
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
