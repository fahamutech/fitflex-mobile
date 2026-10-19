import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../shared/payment_labels.dart';
import '../../shared/models.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import 'member_scan_gym_page.dart';
import 'member_shell.dart';
import 'widgets/checkin_list.dart';
import 'widgets/pass_state.dart';

class MemberQrTab extends StatelessWidget {
  const MemberQrTab({super.key});

  @override
  Widget build(BuildContext context) {
    final data = MemberDataScope.of(context);
    final state = passStateFor(data);
    final notice = state == PassState.lowVisits || state == PassState.endingSoon
        ? passStateMessage(context, data, state)
        : null;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          onPressed: () => context.go(AppRoutes.memberHome),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(context.tr('member.qr')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          if (data.pendingPayment != null) _PendingPaymentCard(data: data),
          // Amber heads-up while the QR still works: running low or ending.
          if (notice != null && data.canCheckIn) ...[
            FFAlert(
              key: const Key('qr-state-notice'),
              message: notice,
              tone: FFAlertTone.warning,
            ),
            const SizedBox(height: 12),
          ],
          if (data.canCheckIn)
            _QrCard(data: data)
          else
            _QrLockedCard(data: data, state: state),
          if (data.canCheckIn) ...[
            const SizedBox(height: 12),
            // Tech Brief §5: self check-in by scanning the gym's entrance QR.
            FFButton(
              key: const Key('member-scan-gym-qr'),
              label: context.tr('member.scanGymQr'),
              onPressed: () => _scanGym(context, data),
              variant: FFButtonVariant.secondary,
              icon: Icons.qr_code_scanner,
            ),
          ],
          const SizedBox(height: 12),

          // Recent checkins
          FFSectionTitle(context.tr('member.recentCheckins')),
          CheckinList(checkins: data.checkins, limit: 5),
        ],
      ),
    );
  }
}

Future<void> _scanGym(BuildContext context, MemberData data) async {
  final api = AppScope.of(context).api;
  final checkedIn = await Navigator.of(
    context,
  ).push<bool>(MaterialPageRoute(builder: (_) => const MemberScanGymPage()));
  if (checkedIn != true) return;
  try {
    final res = await api.myCheckins();
    data.update(
      (d) => d.checkins = res
          .whereType<Map<String, dynamic>>()
          .map(CheckIn.fromJson)
          .toList(),
    );
  } catch (_) {
    // The list refreshes on the next app resume anyway.
  }
}

class _QrCard extends StatelessWidget {
  const _QrCard({required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    return FFCard(
      child: Column(
        children: [
          Text(
            context.tr('home.qr'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (data.qrToken != null)
            FFQrCode(
              key: const Key('member-qr'),
              data: data.qrToken!,
              size: 220,
            )
          else
            const SizedBox(
              height: 220,
              child: Center(child: FFSpinner(size: 32)),
            ),
          const SizedBox(height: 8),
          Text(
            context.tr('home.qr.refreshes'),
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _QrLockedCard extends StatelessWidget {
  const _QrLockedCard({required this.data, required this.state});

  final MemberData data;
  final PassState state;

  @override
  Widget build(BuildContext context) {
    final isPending = data.pendingPayment != null;
    final title = isPending
        ? context.tr('home.qr.pendingTitle')
        : context.tr('home.qr.lockedTitle');
    // An ended pass says so (and when) instead of the generic locked copy.
    final ended = state == PassState.ended;
    final body = isPending
        ? context.tr('home.qr.pendingBody')
        : ended
        ? passStateMessage(context, data, state)!
        : context.tr('home.qr.lockedBody');

    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  borderRadius: BorderRadius.circular(FFTokens.radiusXl),
                ),
                child: Icon(
                  Icons.qr_code_2,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isPending) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FFButton(
                label: ended
                    ? context.tr('pass.state.payAgain')
                    : context.tr('member.subscribe'),
                onPressed: () => context.go(AppRoutes.memberPasses),
                icon: Icons.card_membership,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PendingPaymentCard extends StatelessWidget {
  const _PendingPaymentCard({required this.data});

  final MemberData data;

  @override
  Widget build(BuildContext context) {
    final pending = data.pendingPayment!;
    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FFBadge(
            label: context.tr('pass.pending'),
            tone: FFBadgeTone.warning,
            dot: true,
          ),
          const SizedBox(height: 8),
          Text(
            '${paymentProductLabel(context, pending)} - ${formatCurrency(pending.amountTzs)}',
            style: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color,
              fontSize: 14,
            ),
          ),
          if (pending.memberReference case final ref?) ...[
            const SizedBox(height: 4),
            Text(
              context.tr('manualPay.idShown').replaceAll('{id}', ref),
              key: const Key('qr-pending-transaction-id'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (pending.payerPhone case final phone?) ...[
            const SizedBox(height: 2),
            Text(
              context
                  .tr('manualPay.paidFromShown')
                  .replaceAll('{phone}', phone),
              key: const Key('qr-pending-payer-phone'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
