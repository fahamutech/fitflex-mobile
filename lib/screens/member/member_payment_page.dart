import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/api_client.dart';
import '../../shared/api_error_message.dart';
import '../../shared/models.dart';
import 'member_shell.dart';
import '../../shared/wire_labels.dart';

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

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
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
                  label: context.tr('member.choosePlan'),
                  value: context.tr('pass.${data.selectedTier}'),
                ),
                _Row(
                  label: context.tr('home.visits'),
                  value: visitCap == null
                      ? context.tr('pass.unlimited')
                      : '$visitCap',
                ),
                _Row(
                  label: context.tr('member.startDate'),
                  value: DateFormat('dd MMM yyyy').format(DateTime.now()),
                ),
                _Row(
                  label: context.tr('member.endDate'),
                  value: DateFormat(
                    'dd MMM yyyy',
                  ).format(DateTime.now().add(const Duration(days: 30))),
                ),
                _Row(
                  label: context.tr('shop.total'),
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
          _SubmitButton(tier: data.selectedTier),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _SubmitButton extends StatefulWidget {
  const _SubmitButton({required this.tier});

  final String tier;

  @override
  State<_SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<_SubmitButton> {
  bool _loading = false;

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await AppScope.of(context).api.requestPass(widget.tier);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('member.paymentSubmitted'))),
      );
      // Refresh QR and user data after subscription
      final shellState = context.findAncestorStateOfType<MemberShellState>();
      await shellState?.refreshQr();
      await shellState?.refreshMe();
      if (!mounted) return;
      context.go(AppRoutes.memberHome);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(apiErrorMessage(FFLocaleScope.of(context), e))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _loading ? null : _submit,
      child: _loading
          ? FFSpinner(size: 18, color: Theme.of(context).colorScheme.onPrimary)
          : Text(context.tr('member.requestPayment')),
    );
  }
}

class _AvailableGymsSection extends StatelessWidget {
  const _AvailableGymsSection({required this.pass, required this.gyms});

  final PassTier? pass;
  final List<Gym> gyms;

  List<Gym> _getAccessibleGyms() {
    if (pass == null || pass!.gymAccess == null || pass!.gymAccess!.isEmpty) {
      return gyms;
    }
    return gyms.where((g) {
      final tier = g.tier
          .toLowerCase()
          .replaceAll('-', '_')
          .replaceAll(' ', '_');
      switch (pass!.gymAccess) {
        case 'standard':
          return tier == 'standard';
        case 'midtier':
          return tier == 'standard' || tier == 'mid_tier' || tier == 'midtier';
        case 'premium':
          return tier == 'standard' ||
              tier == 'mid_tier' ||
              tier == 'midtier' ||
              tier == 'premium';
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final accessible = _getAccessibleGyms();
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
                        label: gymTierLabel(FFLocaleScope.of(context), g.tier),
                        tone: FFBadgeTone.gray,
                      ),
                    ],
                  ),
                ),
              ),
          if (accessible.length > 5)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '+${accessible.length - 5} ${context.tr('member.moreGyms')}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
