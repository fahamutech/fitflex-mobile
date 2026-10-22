import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
import '../../shared/models.dart';
import '../member/member_scan_gym_page.dart';
import '../member/widgets/mobile_money_pay.dart';
import 'trainer_gyms_tab.dart';

/// Trainer › My passes: trainer passes and gym member plans — active ones
/// with the check-in QR, pending ones (awaiting admin payment approval) with
/// cancel, and history.
class TrainerPassesPage extends StatefulWidget {
  const TrainerPassesPage({super.key});

  @override
  State<TrainerPassesPage> createState() => _TrainerPassesPageState();
}

class _TrainerPassesPageState extends State<TrainerPassesPage> {
  List<Map<String, dynamic>> _passes = [];
  bool _loading = true;
  bool _started = false;
  String? _busyId;

  /// `GET /payments/options`, asked once for every "Pay now" on the page.
  Future<Map<String, dynamic>>? _payOptions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Unreachable or refused: no "Pay now", nothing else changes.
    _payOptions = AppScope.of(
      context,
    ).api.paymentOptions().catchError((_) => <String, dynamic>{});
    _load();
  }

  /// The pending payment behind [pass], with its product kind: a trainer
  /// pass (payable by the trainer once the server allows it) or a gym member
  /// plan (not payable by mobile money from a trainer account).
  static PaymentRequest? _pendingPayment(Map<String, dynamic> pass) {
    final req = pass['paymentRequest'];
    if (req is! Map || (req['id']?.toString() ?? '').isEmpty) return null;
    return PaymentRequest.fromJson({
      ...req.cast<String, dynamic>(),
      'productType': pass['kind'] == 'trainer_pass'
          ? MomoProduct.trainerGymPass
          : MomoProduct.gymPlan,
    });
  }

  Future<void> _load() async {
    try {
      final rows = await AppScope.of(context).api.trainerPasses();
      if (!mounted) return;
      setState(() {
        _passes = rows.whereType<Map<String, dynamic>>().toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> pass) async {
    setState(() => _busyId = pass['id']?.toString());
    try {
      await AppScope.of(context).api.trainerCancelPass(pass['id'].toString());
      if (!mounted) return;
      FFSnack.info(context, context.tr('trainerPass.cancelled'));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(trainerPassErrorText(context, e))));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _passes.where((p) => p['status'] == 'active').toList();
    final pending = _passes
        .where((p) => p['status'] == 'payment_pending')
        .toList();
    final history = _passes
        .where((p) => !['active', 'payment_pending'].contains(p['status']))
        .toList();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('trainerPass.myPasses'))),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: FFSpinner(size: 28)),
              )
            else if (_passes.isEmpty)
              FFEmptyState(title: context.tr('trainerPass.none'))
            else ...[
              if (active.isNotEmpty) ...[
                FFButton(
                  key: const Key('trainer-passes-show-qr'),
                  label: context.tr('trainerPass.showQr'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TrainerQrPage(),
                    ),
                  ),
                  icon: Icons.qr_code_2,
                ),
                FFSectionTitle(context.tr('trainerPass.active')),
                ...active.map((p) => _PassTile(pass: p)),
              ],
              if (pending.isNotEmpty) ...[
                FFSectionTitle(context.tr('trainerPass.pending')),
                Text(
                  context.tr('trainerPass.pendingBody'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                ...pending.map(
                  (p) => _PassTile(
                    pass: p,
                    trailing: FFButton(
                      key: Key('trainer-pass-cancel-${p['id']}'),
                      label: context.tr('trainer.cancel'),
                      onPressed: _busyId == null ? () => _cancel(p) : null,
                      variant: FFButtonVariant.ghost,
                      size: FFButtonSize.sm,
                    ),
                    footer: switch (_pendingPayment(p)) {
                      final request? => PayNowButton(
                        key: ValueKey('pay-${request.id}'),
                        request: request,
                        role: 'trainer',
                        options: _payOptions,
                        onPaid: _load,
                      ),
                      null => null,
                    },
                  ),
                ),
              ],
              if (history.isNotEmpty) ...[
                FFSectionTitle(context.tr('trainerPass.history')),
                ...history.map((p) => _PassTile(pass: p)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _PassTile extends StatelessWidget {
  const _PassTile({required this.pass, this.trailing, this.footer});

  final Map<String, dynamic> pass;
  final Widget? trailing;

  /// Under the row: "Pay now" on a pass awaiting payment.
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final gym = pass['gym'] as Map?;
    final status = pass['status']?.toString() ?? '';
    final kind = pass['kind'] == 'member_plan'
        ? context.tr('trainerPass.kindPlan')
        : context.tr('trainerPass.kindPass');
    final period = context.tr('trainerPass.period.${pass['plan']}');
    final amount = (pass['paymentRequest'] as Map?)?['amountTzs'] as num?;
    final until = context.localDate(pass['expiresAt'], fallback: '');
    final (statusLabel, tone) = switch (status) {
      'active' => (
        context.tr('trainerPass.activeUntil').replaceAll('{date}', until),
        FFBadgeTone.success,
      ),
      'payment_pending' => (
        context.tr('trainerPass.statusPending'),
        FFBadgeTone.warning,
      ),
      'expired' => (context.tr('trainerPass.statusExpired'), FFBadgeTone.gray),
      'payment_rejected' => (
        context.tr('trainerPass.statusRejected'),
        FFBadgeTone.danger,
      ),
      _ => (context.tr('trainerPass.statusCancelled'), FFBadgeTone.gray),
    };
    return Padding(
      key: Key('trainer-pass-${pass['id']}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        gym?['name']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          '$kind · $period',
                          if (amount != null) formatCurrency(amount),
                        ].join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 6),
                      FFBadge(label: statusLabel, tone: tone),
                    ],
                  ),
                ),
                ?trailing,
              ],
            ),
            if (footer != null)
              Padding(
                padding: const EdgeInsets.only(top: FFTokens.spacingSm),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// The trainer's rotating check-in QR, shown at reception. Works for trainer
/// passes, gym member plans and (free) linked gyms alike.
class TrainerQrPage extends StatefulWidget {
  const TrainerQrPage({super.key});

  @override
  State<TrainerQrPage> createState() => _TrainerQrPageState();
}

class _TrainerQrPageState extends State<TrainerQrPage> {
  String? _token;
  bool _locked = false;
  bool _started = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refresh();
    // Tokens live 60 seconds; refresh well before that, like the member QR.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final res = await AppScope.of(context).api.myQr();
      if (mounted) {
        setState(() {
          _token = res['token'] as String?;
          _locked = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('trainerPass.qrTitle'))),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFCard(
            child: Column(
              children: [
                if (_locked)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      context.tr('trainerPass.qrLocked'),
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (_token != null)
                  FFQrCode(
                    key: const Key('trainer-qr'),
                    data: _token!,
                    size: 240,
                  )
                else
                  const SizedBox(
                    height: 240,
                    child: Center(child: FFSpinner(size: 32)),
                  ),
                const SizedBox(height: 12),
                Text(
                  context.tr('trainerPass.qrHint'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // No reception scanner? Scan the QR posted at the entrance instead.
          FFButton(
            key: const Key('trainer-qr-scan-gym'),
            label: context.tr('checkin.scanInstead'),
            onPressed: () async {
              final checkedIn = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const MemberScanGymPage()),
              );
              if (checkedIn == true && context.mounted) {
                FFSnack.success(context, context.tr('checkin.done'));
              }
            },
            variant: FFButtonVariant.secondary,
            icon: Icons.qr_code_scanner,
          ),
        ],
      ),
    );
  }
}
