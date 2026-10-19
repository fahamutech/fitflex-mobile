import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/models.dart';
import '../../shared/pass_gyms.dart';
import 'member_shell.dart';
import 'widgets/mobile_money_pay.dart';
import 'widgets/pass_gyms_sheet.dart';

/// How long a FitFlex Pass lasts once its payment is approved. The server
/// sets 30 days at purchase and moves both dates to the approval moment
/// (subscription-service `subscribe`, `activationDates`); /subscription-tiers
/// sends no length, so the app mirrors it here.
const platformPassDays = 30;

class MemberPaymentPage extends StatelessWidget {
  const MemberPaymentPage({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final pass = data.passes
        .where((p) => p.id == data.selectedTier)
        .firstOrNull;
    final price = pass?.price ?? 0;
    final visitCap = pass?.visitCap;
    // Nothing to pay for until the chosen tier is found in the live catalogue.
    final payable = pass != null && price > 0;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => context.go(AppRoutes.memberPasses),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('member.payment')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                context.tr('member.paymentBody'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          // Order summary
          FFCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('member.orderSummary'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _Row(
                  label: context.tr('pay.product.fitflexPass'),
                  value: context.tr('pass.${data.selectedTier}'),
                ),
                _Row(
                  label: context.tr('home.visits'),
                  value: visitCap == null
                      ? context.tr('pass.unlimited')
                      : '$visitCap',
                ),
                // The pass starts when FitFlex approves the payment, not
                // today, so no calendar dates are promised here.
                _Row(
                  key: const Key('payment-pass-start'),
                  label: context.tr('member.startDate'),
                  value: context.tr('member.passStartsOnApproval'),
                ),
                _Row(
                  key: const Key('payment-pass-length'),
                  label: context.tr('member.passLength'),
                  value: context
                      .tr('member.passLastsFromApproval')
                      .replaceAll('{days}', '$platformPassDays'),
                ),
                _Row(
                  label: context.tr('member.total'),
                  value: formatCurrency(price),
                ),
              ],
            ),
          ),

          // Available gyms details
          const SizedBox(height: 16),
          _AvailableGymsSection(pass: pass, gyms: data.gyms),

          // Payment method — commented out until payment integrations are live
          // Padding(
          //   padding: const EdgeInsets.only(top: 16, bottom: 10),
          //   child: Text(
          //     context.tr('member.paymentMethod'),
          //     style: const TextStyle(
          //       fontSize: 16,
          //       fontWeight: FontWeight.w600,
          //       color: FFTokens.fgPrimary,
          //     ),
          //   ),
          // ),
          // FFActionTile(
          //   icon: Icons.phone_android,
          //   title: 'M-Pesa',
          //   onTap: () {},
          // ),
          // FFActionTile(
          //   icon: Icons.account_balance,
          //   title: 'CRDB Bank Transfer',
          //   onTap: () {},
          // ),
          // FFActionTile(
          //   icon: Icons.account_balance,
          //   title: 'NMB Bank Transfer',
          //   onTap: () {},
          // ),
          const SizedBox(height: 16),
          if (!payable)
            FFAlert(
              message: context.tr('member.passNoneAvailable'),
              tone: FFAlertTone.warning,
            ),
          _SubmitButton(tier: data.selectedTier, enabled: payable),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      // Values can be whole sentences ("Starts when payment is approved"):
      // they wrap instead of running off a narrow phone.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          const SizedBox(width: FFTokens.spacingSm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubmitButton extends StatefulWidget {
  const _SubmitButton({required this.tier, required this.enabled});

  final String tier;
  final bool enabled;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _loading = false;

  Future<void> _submit() async {
    if (_loading) return; // a second tap must not send a second request
    setState(() => _loading = true);
    try {
      final created = await AppScope.of(context).api.requestPass(widget.tier);
      if (!mounted) return;
      FFSnack.success(context, context.tr('member.paymentSubmitted'));
      // With mobile money switched on, pay straight away.
      final req = created['paymentRequest'];
      if (req is Map) {
        await offerMobileMoney(
          context,
          paymentRequestId: req['id'] as String?,
          amountTzs: (req['amountTzs'] as num?) ?? 0,
        );
        if (!mounted) return;
      }
      // Refresh QR and user data after subscription
      final shellState = context.findAncestorStateOfType<MemberShellState>();
      await shellState?.refreshQr();
      await shellState?.refreshMe();
      if (!mounted) return;
      context.go(AppRoutes.memberHome);
    } on ApiException catch (e) {
      if (!mounted) return;
      FFSnack.error(context, apiErrorMessage(FFLocaleScope.of(context), e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FFButton(
      label: context.tr('member.requestPayment'),
      onPressed: _loading || !widget.enabled ? null : _submit,
      loading: _loading,
    );
  }
}

class _AvailableGymsSection extends StatelessWidget {
  const _AvailableGymsSection({required this.pass, required this.gyms});

  final PassTier? pass;
  final List<Gym> gyms;

  @override
  Widget build(BuildContext context) {
    final accessible = gymsForPass(pass?.gymAccess, gyms);
    if (accessible.isEmpty) return const SizedBox.shrink();

    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.fitness_center,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                context.tr('member.availableGyms'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              FFBadge(label: '${accessible.length}', tone: FFBadgeTone.brand),
            ],
          ),
          const SizedBox(height: 12),
          ...accessible
              .take(5)
              .map(
                (g) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          g.name,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                      FFBadge(
                        label: g.tier.replaceAll('_', ' '),
                        tone: FFBadgeTone.gray,
                      ),
                    ],
                  ),
                ),
              ),
          if (pass != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.only(top: 4),
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () => showPassGymsSheet(
                  context,
                  tierId: pass!.id,
                  gymAccess: pass!.gymAccess,
                  gyms: gyms,
                ),
                child: Text(
                  accessible.length > 5
                      ? '${context.tr('passGyms.view')} (+${accessible.length - 5} ${context.tr('member.moreGyms')})'
                      : context.tr('passGyms.view'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
