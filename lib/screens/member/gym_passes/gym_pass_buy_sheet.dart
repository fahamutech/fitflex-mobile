import 'package:flutter/material.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/gym_passes/gym_pass.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../widgets/mobile_money_pay.dart';

/// Custom Gym Passes: the buy flow for one plan. Pick the people (couples and
/// group), see the price the server set, accept the terms when the plan has
/// them, and pay through the same payment step a direct plan uses. Resolves
/// true when the purchase was created.
Future<bool?> showGymPassBuySheet(
  BuildContext context, {
  required Gym gym,
  required GymPassPlan plan,
  @visibleForTesting
  Future<bool> Function(BuildContext context, String? id, num amount)?
  payOverride,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Never closed by a swipe or a tap outside: a purchase may be in flight.
    // The sheet has its own Close button, off while it is busy.
    isDismissible: false,
    enableDrag: false,
    builder: (ctx) =>
        GymPassBuySheet(gym: gym, plan: plan, payOverride: payOverride),
  );
}

class GymPassBuySheet extends StatefulWidget {
  const GymPassBuySheet({
    super.key,
    required this.gym,
    required this.plan,
    this.payOverride,
  });

  /// Tests replace the mobile-money step (to make it fail).
  @visibleForTesting
  final Future<bool> Function(BuildContext context, String? id, num amount)?
  payOverride;

  final Gym gym;
  final GymPassPlan plan;

  @override
  State<GymPassBuySheet> createState() => _GymPassBuySheetState();
}

class _GymPassBuySheetState extends State<GymPassBuySheet> {
  final _others = <TextEditingController>[];
  bool _busy = false;

  /// One purchase per sheet: once the server has taken it, a second tap must
  /// not send another (the route has no idempotency key; a repeat while the
  /// first payment is open is refused with 409 payment_already_pending).
  bool _submitted = false;
  bool _termsAccepted = false;
  String? _error;
  bool _showFieldErrors = false;

  /// The plan as the server lists it now (re-read when the sheet opens, so a
  /// price or terms change since the list was loaded is never missed).
  late GymPassPlan _plan = widget.plan;
  bool _refreshing = true;
  bool _planGone = false;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _plan.minOthers; i++) {
      _others.add(TextEditingController());
    }
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    if (scope == null) return;
    _refreshPlan(scope.api);
  }

  Future<void> _refreshPlan(ApiClient api, {bool keepError = false}) async {
    GymPassPlan? fresh;
    var answered = false;
    try {
      final raw = await api.gymPassPlans(widget.gym.id);
      answered = true;
      for (final p in raw) {
        final plan = GymPassPlan.fromJson(p);
        if (plan?.id == widget.plan.id) fresh = plan;
      }
    } catch (_) {
      // Could not re-read: the listed plan stays. The server still decides
      // the price when the purchase is made.
    }
    if (!mounted) return;
    setState(() {
      _refreshing = false;
      // The server's own price (just refused) is kept if the re-read fails.
      if (answered && fresh == null) {
        _planGone = true;
        _error = context.tr('gymPass.error.planUnavailable');
        return;
      }
      if (fresh != null) {
        if (fresh.termsVersion != _plan.termsVersion || fresh.terms == null) {
          _termsAccepted = false;
        }
        _plan = fresh;
        if (keepError) {
          _error = context
              .tr('gymPass.error.priceChanged')
              .replaceFirst('{amount}', formatCurrency(_plan.priceTzs));
        }
        // The people boxes follow the fresh headcount rule.
        while (_others.length < _plan.minOthers) {
          _others.add(TextEditingController());
        }
        while (_others.length > _plan.maxOthers && _others.isNotEmpty) {
          _others.removeLast().dispose();
        }
      }
    });
  }

  @override
  void dispose() {
    for (final c in _others) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _canAddField => _others.length < _plan.maxOthers;

  /// Why the typed people cannot be sent yet, or null. The server makes the
  /// final call (and hides who has an account); this only saves a round trip.
  String? _peopleProblem() => gymPassPeopleProblem(_plan, [
    for (final c in _others) c.text,
  ], (key) => context.tr(key));

  Future<void> _buy() async {
    if (_busy || _submitted || _refreshing || _planGone) return;
    final problem = _peopleProblem();
    if (problem != null || (_plan.terms != null && !_termsAccepted)) {
      setState(() {
        _showFieldErrors = true;
        _error = problem;
      });
      return;
    }
    final others = <Map<String, String>>[
      for (final c in _others) ?gymPassContactBody(c.text),
    ];
    // A focused field is released before it is disabled for the request (L4).
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final created = await AppScope.of(context).api.buyGymPass(
        planId: _plan.id,
        others: others,
        termsVersion: _plan.terms != null ? _plan.termsVersion : null,
        // The price the member is looking at; a change is refused (409).
        expectedPriceTzs: _plan.priceTzs,
      );
      _submitted = true;
      if (!mounted) return;
      final req = created['paymentRequest'];
      if (req is Map) {
        try {
          final id = req['id'] as String?;
          // The amount is the server's, taken from its payment request.
          final amount = (req['amountTzs'] as num?) ?? 0;
          final pay = widget.payOverride;
          if (pay != null) {
            await pay(context, id, amount);
          } else {
            await offerMobileMoney(
              context,
              paymentRequestId: id,
              amountTzs: amount,
              productType: MomoProduct.gymPlan,
            );
          }
        } catch (_) {
          // The purchase exists; only the payment step failed. Say so, and
          // end as a purchase (the payment can be finished from My passes).
          if (mounted) FFSnack.warning(context, context.tr('gymPass.payLater'));
        }
      }
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.status == 409 && e.code == 'price_changed') {
        // Nothing was created. Take the server's new price, show it, and
        // ask again (the next tap confirms the new price).
        final body = e.body is Map ? e.body as Map : const {};
        final now = body['priceTzs'];
        final api = AppScope.of(context).api;
        setState(() {
          _busy = false;
          if (now is num) _plan = _plan.withPrice(now);
          _error = (now is num)
              ? context
                    .tr('gymPass.error.priceChanged')
                    .replaceFirst('{amount}', formatCurrency(now))
              : context.tr('gymPass.error.priceChangedGeneric');
        });
        await _refreshPlan(api, keepError: true);
        return;
      }
      setState(() {
        _busy = false;
        _error = gymPassErrorMessage(
          FFLocaleScope.of(context),
          e,
          errorMessage,
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = isNetworkError(e)
            ? context.tr('error.network')
            : context.tr('gymPass.buyFailed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = FFLocaleScope.of(context);
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: FFTokens.spacingLg,
            right: FFTokens.spacingLg,
            bottom:
                MediaQuery.of(context).viewInsets.bottom + FFTokens.spacingLg,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.tr('gymPass.buyTitle'),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('gym-pass-close'),
                      tooltip: context.tr('gymPass.closeSheet'),
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(widget.gym.name, style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                FFCard(
                  key: const Key('gym-pass-buy-summary'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _plan.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${gymPassCategoryLabel(locale, _plan)} · ${gymPassDurationLabel(locale, _plan)}',
                        style: theme.textTheme.labelMedium,
                      ),
                      if (_plan.description != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _plan.description!,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.tr('gymPass.price'),
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          Text(
                            formatCurrency(_plan.priceTzs),
                            key: const Key('gym-pass-buy-price'),
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr('gymPass.priceNote'),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.tr('gymPass.coversYou'),
                  key: const Key('gym-pass-covers-you'),
                  style: theme.textTheme.bodyMedium,
                ),
                if (_plan.takesOthers) ...[
                  const SizedBox(height: 10),
                  Text(
                    context
                        .tr('gymPass.othersHint')
                        .replaceFirst('{max}', '${_plan.maxOthers}'),
                    style: theme.textTheme.labelMedium,
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < _others.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: FFTextField(
                              key: Key('gym-pass-person-$i'),
                              controller: _others[i],
                              label: context
                                  .tr('gymPass.personLabel')
                                  .replaceFirst('{n}', '${i + 2}'),
                              hint: context.tr('gymPass.personHint'),
                              keyboardType: TextInputType.emailAddress,
                              enabled: !_busy,
                              errorText:
                                  _showFieldErrors &&
                                      gymPassContactBody(_others[i].text) ==
                                          null
                                  ? context.tr('gymPass.error.contactProblem')
                                  : null,
                              onChanged: (_) => setState(() => _error = null),
                            ),
                          ),
                          if (i >= _plan.minOthers)
                            IconButton(
                              key: Key('gym-pass-person-remove-$i'),
                              tooltip: context.tr('gymPass.removeField'),
                              onPressed: _busy
                                  ? null
                                  : () => setState(() {
                                      _others.removeAt(i).dispose();
                                    }),
                              icon: const Icon(Icons.close),
                            ),
                        ],
                      ),
                    ),
                  if (_canAddField)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FFButton(
                        key: const Key('gym-pass-add-person'),
                        label: context.tr('gymPass.addAnother'),
                        variant: FFButtonVariant.ghost,
                        onPressed: _busy
                            ? null
                            : () => setState(
                                () => _others.add(TextEditingController()),
                              ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    context.tr('gymPass.notifyNote'),
                    key: const Key('gym-pass-notify-note'),
                    style: theme.textTheme.labelSmall,
                  ),
                ],
                if (_plan.terms != null) ...[
                  const SizedBox(height: 12),
                  FFCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('gymPass.terms'),
                          style: theme.textTheme.labelLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(_plan.terms!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  CheckboxListTile(
                    key: const Key('gym-pass-terms'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _termsAccepted,
                    onChanged: _busy
                        ? null
                        : (v) => setState(() => _termsAccepted = v ?? false),
                    title: Text(context.tr('gymPass.acceptTerms')),
                  ),
                  if (_showFieldErrors && !_termsAccepted)
                    Text(
                      context.tr('gymPass.error.termsNeeded'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  FFAlert(
                    key: const Key('gym-pass-error'),
                    message: _error!,
                    tone: FFAlertTone.error,
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FFButton(
                    key: const Key('gym-pass-buy'),
                    label: context.tr('gymPass.buyAction'),
                    onPressed: _busy || _submitted || _refreshing || _planGone
                        ? null
                        : _buy,
                    loading: _busy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Why the people typed for [plan] cannot be sent yet, as translated text, or
/// null when they can. Checks only what the server's headcount rule and
/// "the same contact twice" need: whether a contact belongs to a FitFlex
/// member is never known here.
String? gymPassPeopleProblem(
  GymPassPlan plan,
  List<String> typed,
  String Function(String key) tr,
) {
  final filled = [
    for (final t in typed)
      if (t.trim().isNotEmpty) t,
  ];
  if (!plan.takesOthers) {
    return filled.isEmpty ? null : tr('gymPass.error.headcount');
  }
  if (filled.length < plan.minOthers || filled.length > plan.maxOthers) {
    return tr('gymPass.error.headcount');
  }
  if (filled.length != typed.length) return tr('gymPass.error.contactProblem');
  final seen = <String>{};
  for (final t in filled) {
    if (gymPassContactBody(t) == null) {
      return tr('gymPass.error.contactProblem');
    }
    if (!seen.add(gymPassContactKey(t))) {
      return tr('gymPass.error.contactProblem');
    }
  }
  return null;
}
