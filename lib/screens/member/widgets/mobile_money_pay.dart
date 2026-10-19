import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../member_shell.dart';

/// Where a payment attempt stands, as the server reports it.
enum MomoStage { input, sending, waiting, success, failed, held, slow }

/// A Tanzanian number as typed, reduced to digits (and a leading +) for display.
String momoDisplayPhone(String raw) => raw.replaceAll(RegExp(r'[^0-9+]'), '');

/// Whether [raw] looks like a Tanzanian mobile number (07…, 06…, 255…, +255…).
/// The server makes the final call; this only avoids a pointless round trip.
bool looksLikeTzMobile(String raw) {
  var d = raw.replaceAll(RegExp(r'[\s\-().]'), '');
  if (d.startsWith('+')) d = d.substring(1);
  if (RegExp(r'^0[67]\d{8}$').hasMatch(d)) return true;
  if (RegExp(r'^[67]\d{8}$').hasMatch(d)) return true;
  return RegExp(r'^255[67]\d{8}$').hasMatch(d);
}

/// The server's answer to "has it gone through?" as a stage.
MomoStage momoStageFor(String? state) => switch (state) {
  'completed' => MomoStage.success,
  'failed' => MomoStage.failed,
  'held' => MomoStage.held,
  _ => MomoStage.waiting,
};

/// Offers mobile-money payment for a request that was just created, when the
/// server has it switched on. Resolves true when the payment completed.
/// Safe to call anywhere: with it off (or unreachable) it does nothing.
Future<bool> offerMobileMoney(
  BuildContext context, {
  required String? paymentRequestId,
  required num amountTzs,
}) async {
  if (paymentRequestId == null || paymentRequestId.isEmpty) return false;
  final api = AppScope.of(context).api;
  Map<String, dynamic> options;
  try {
    options = await api.paymentOptions();
  } catch (_) {
    return false;
  }
  if (options['enabled'] != true || !context.mounted) return false;
  final phone = context
      .dependOnInheritedWidgetOfExactType<MemberDataScope>()
      ?.notifier
      ?.me
      ?.user
      .phone;
  final done = await showFFSheet<bool>(
    context,
    title: context.tr('momo.title'),
    isDismissible: false,
    child: MobileMoneyPayPanel(
      paymentRequestId: paymentRequestId,
      amountTzs: amountTzs,
      defaultPhone: phone,
      testMode: options['environment'] == 'sandbox',
    ),
  );
  return done == true;
}

/// Collects the number, asks the phone to approve, then follows the payment
/// until it completes, fails or takes too long.
class MobileMoneyPayPanel extends StatefulWidget {
  const MobileMoneyPayPanel({
    super.key,
    required this.paymentRequestId,
    required this.amountTzs,
    this.defaultPhone,
    this.testMode = false,
    this.pollEvery = const Duration(seconds: 4),
    this.giveUpAfter = const Duration(minutes: 2),
  });

  final String paymentRequestId;
  final num amountTzs;
  final String? defaultPhone;
  final bool testMode;
  final Duration pollEvery;
  final Duration giveUpAfter;

  @override
  State<MobileMoneyPayPanel> createState() => _MobileMoneyPayPanelState();
}

class _MobileMoneyPayPanelState extends State<MobileMoneyPayPanel> {
  late final TextEditingController _phone = TextEditingController(
    text: widget.defaultPhone ?? '',
  );
  MomoStage _stage = MomoStage.input;
  String? _error;
  Timer? _timer;
  int _polls = 0;
  bool _checking = false;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_stage == MomoStage.sending) return; // one prompt per tap
    if (!looksLikeTzMobile(_phone.text)) {
      setState(() => _error = context.tr('error.reason.invalidPhone'));
      return;
    }
    setState(() {
      _stage = MomoStage.sending;
      _error = null;
    });
    try {
      await AppScope.of(
        context,
      ).api.payByMobileMoney(widget.paymentRequestId, _phone.text.trim());
      if (!mounted) return;
      _polls = 0;
      setState(() => _stage = MomoStage.waiting);
      _timer?.cancel();
      _timer = Timer.periodic(widget.pollEvery, (_) => _check());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = MomoStage.input;
        _error = errorMessage(FFLocaleScope.of(context), e);
      });
    }
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final out = await AppScope.of(
        context,
      ).api.refreshMobileMoney(widget.paymentRequestId);
      if (!mounted) return;
      final stage = momoStageFor(out['state'] as String?);
      if (stage != MomoStage.waiting) {
        _timer?.cancel();
        setState(() => _stage = stage);
        if (stage == MomoStage.success) {
          // Pick up the activated plan (QR, status) behind the sheet.
          final shell = context.findAncestorStateOfType<MemberShellState>();
          unawaited(shell?.refreshQr());
          unawaited(shell?.refreshMe());
        }
        return;
      }
      // Counted in polls, not wall time: a phone that slept does not give up early.
      _polls += 1;
      if (widget.pollEvery * _polls >= widget.giveUpAfter) {
        _timer?.cancel();
        setState(() => _stage = MomoStage.slow);
      }
    } catch (_) {
      // A dropped connection while waiting is not a failed payment: keep going.
    } finally {
      _checking = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = formatCurrency(widget.amountTzs);
    final children = <Widget>[
      if (widget.testMode) ...[
        FFAlert(
          message: context.tr('momo.testMode'),
          tone: FFAlertTone.warning,
        ),
        const SizedBox(height: FFTokens.spacingMd),
      ],
    ];
    switch (_stage) {
      case MomoStage.input:
      case MomoStage.sending:
        children.addAll([
          Text(
            '$amount · ${context.tr('momo.intro')}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          FFTextField(
            controller: _phone,
            label: context.tr('momo.phone'),
            hint: context.tr('momo.phoneHint'),
            keyboardType: TextInputType.phone,
            enabled: _stage == MomoStage.input,
            errorText: _error,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
            ],
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            label: context
                .tr('momo.send')
                .replaceFirst('{phone}', momoDisplayPhone(_phone.text)),
            loading: _stage == MomoStage.sending,
            fullWidth: true,
            onPressed: _stage == MomoStage.sending ? null : _send,
          ),
        ]);
      case MomoStage.waiting:
        children.addAll([
          const Center(child: FFSpinner(size: 28)),
          const SizedBox(height: FFTokens.spacingMd),
          Text(
            context.tr('momo.waitingTitle'),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('momo.waitingBody').replaceFirst('{amount}', amount),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            label: context.tr('momo.checkNow'),
            variant: FFButtonVariant.secondary,
            fullWidth: true,
            onPressed: _check,
          ),
        ]);
      case MomoStage.success:
      case MomoStage.failed:
      case MomoStage.held:
      case MomoStage.slow:
        final key = switch (_stage) {
          MomoStage.success => 'success',
          MomoStage.failed => 'failed',
          MomoStage.held => 'held',
          _ => 'slow',
        };
        children.addAll([
          Icon(
            _stage == MomoStage.success
                ? Icons.check_circle
                : _stage == MomoStage.failed
                ? Icons.error_outline
                : Icons.hourglass_top_rounded,
            size: 40,
            color: _stage == MomoStage.success
                ? theme.colorScheme.primary
                : theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('momo.${key}Title'),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('momo.${key}Body'),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          if (_stage == MomoStage.failed) ...[
            FFButton(
              label: context.tr('momo.tryAgain'),
              fullWidth: true,
              onPressed: () => setState(() => _stage = MomoStage.input),
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          FFButton(
            label: context.tr('momo.done'),
            variant: _stage == MomoStage.failed
                ? FFButtonVariant.secondary
                : FFButtonVariant.primary,
            fullWidth: true,
            onPressed: () =>
                Navigator.of(context).pop(_stage == MomoStage.success),
          ),
        ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

/// "Pay now" under a pending payment, shown only while mobile money is on and
/// the payment is one it can settle (a pass, an upgrade or a gym plan).
class PayNowButton extends StatefulWidget {
  const PayNowButton({super.key, required this.request});

  final PaymentRequest request;

  @override
  State<PayNowButton> createState() => _PayNowButtonState();
}

class _PayNowButtonState extends State<PayNowButton> {
  Future<bool>? _available;

  static const _payable = {'FITFLEX_PASS', 'GYM_SUBSCRIPTION'};

  @override
  void initState() {
    super.initState();
    final type = widget.request.productType;
    // An older server sends no product type: a tier means a pass.
    // Paid by hand with a transaction ID: the server refuses a second
    // payment (409 manual_payment_submitted), so "Pay now" is not offered.
    final isPayable =
        widget.request.memberReference == null &&
        (type != null
            ? _payable.contains(type)
            : widget.request.tier.isNotEmpty);
    if (isPayable) {
      // Read without depending on it: initState may not register dependencies.
      _available = context
          .getInheritedWidgetOfExactType<AppScope>()!
          .api
          .paymentOptions()
          .then((o) => o['enabled'] == true)
          .catchError((_) => false);
    }
  }

  Future<void> _pay() async {
    final done = await offerMobileMoney(
      context,
      paymentRequestId: widget.request.id,
      amountTzs: widget.request.amountTzs,
    );
    if (done && mounted) {
      final shell = context.findAncestorStateOfType<MemberShellState>();
      await shell?.refreshMe();
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _available;
    if (available == null) return const SizedBox.shrink();
    return FutureBuilder<bool>(
      future: available,
      builder: (context, snap) {
        if (snap.data != true) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: SizedBox(
            width: double.infinity,
            child: FFButton(
              label: context.tr('momo.payNow'),
              icon: Icons.phone_android,
              onPressed: _pay,
            ),
          ),
        );
      },
    );
  }
}
