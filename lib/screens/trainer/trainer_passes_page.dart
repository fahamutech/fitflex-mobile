import 'dart:async';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app_scope.dart';
import '../../shared/components/components.dart';
import '../../shared/design_tokens.dart';
import '../../shared/formatters.dart';
import '../../shared/i18n.dart';
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('trainerPass.cancelled'))),
      );
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
                FilledButton.icon(
                  key: const Key('trainer-passes-show-qr'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const TrainerQrPage(),
                    ),
                  ),
                  icon: const Icon(Icons.qr_code_2),
                  label: Text(context.tr('trainerPass.showQr')),
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
                    trailing: TextButton(
                      key: Key('trainer-pass-cancel-${p['id']}'),
                      onPressed: _busyId == null ? () => _cancel(p) : null,
                      child: Text(context.tr('trainer.cancel')),
                    ),
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
  const _PassTile({required this.pass, this.trailing});

  final Map<String, dynamic> pass;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final gym = pass['gym'] as Map?;
    final status = pass['status']?.toString() ?? '';
    final kind = pass['kind'] == 'member_plan'
        ? context.tr('trainerPass.kindPlan')
        : context.tr('trainerPass.kindPass');
    final period = context.tr('trainerPass.period.${pass['plan']}');
    final amount = (pass['paymentRequest'] as Map?)?['amountTzs'] as num?;
    final until = pass['expiresAt']?.toString().split('T').first ?? '';
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
        child: Row(
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
    final primary = Theme.of(context).colorScheme.primary;
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
                  QrImageView(
                    key: const Key('trainer-qr'),
                    data: _token!,
                    size: 240,
                    backgroundColor: Colors.white,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: primary,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: primary,
                    ),
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
        ],
      ),
    );
  }
}
