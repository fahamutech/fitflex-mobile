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

/// Product kinds a payment request can be for (`productType` on the server).
abstract final class MomoProduct {
  static const fitflexPass = 'FITFLEX_PASS';
  static const gymPlan = 'GYM_SUBSCRIPTION';
  static const trainerSession = 'TRAINER_SERVICE';
  static const trainerGymPass = 'TRAINER_GYM_PASS';

  /// Event tickets (events S4); offered only when the server lists it.
  static const eventOrder = 'EVENT_ORDER';
}

/// What a server without the `mobileMoney` key pays by mobile money: members
/// pay passes and gym plans, everyone else nothing (fitflex-functions#240).
const _legacyMemberProducts = {MomoProduct.fitflexPass, MomoProduct.gymPlan};

/// Whether "Pay now" may be offered for a [productType] request paid by
/// someone signed in as [role], given `GET /payments/options`.
///
/// Mobile money must be `enabled`, and the product must be in
/// `mobileMoney.products`. Without that key (an older server, or the
/// trainer-products flag off) the old rule applies.
bool momoOffers(
  Map<String, dynamic> options,
  String? productType, {
  required String role,
}) {
  if (options['enabled'] != true || productType == null) return false;
  // The server's role rule: a trainer pays only their trainer gym pass, and
  // a member never pays one (403 not_payable_by_role otherwise).
  if ((role == 'trainer') != (productType == MomoProduct.trainerGymPass)) {
    return false;
  }
  final block = options['mobileMoney'];
  if (block is Map && block['products'] is List) {
    return (block['products'] as List).contains(productType);
  }
  return role == 'member' && _legacyMemberProducts.contains(productType);
}

/// Offers mobile-money payment for a request that was just created, when the
/// server has it switched on for this [productType] and [role]. Resolves true
/// when the payment completed. Safe to call anywhere: with it off (or
/// unreachable) it does nothing. [onCompleted] runs as soon as the server says
/// the payment completed, so the list behind the sheet can be re-fetched.
Future<bool> offerMobileMoney(
  BuildContext context, {
  required String? paymentRequestId,
  required num amountTzs,
  required String productType,
  String role = 'member',
  String? defaultPhone,
  VoidCallback? onCompleted,
}) async {
  if (paymentRequestId == null || paymentRequestId.isEmpty) return false;
  final api = AppScope.of(context).api;
  Map<String, dynamic> options;
  try {
    options = await api.paymentOptions();
  } catch (_) {
    return false;
  }
  if (!momoOffers(options, productType, role: role) || !context.mounted) {
    return false;
  }
  final phone =
      defaultPhone ??
      context
          .dependOnInheritedWidgetOfExactType<MemberDataScope>()
          ?.notifier
          ?.me
          ?.user
          .phone ??
      AppScope.of(context).auth.user?['phone']?.toString();
  final done = await showFFSheet<bool>(
    context,
    title: context.tr('momo.title'),
    isDismissible: false,
    child: MobileMoneyPayPanel(
      paymentRequestId: paymentRequestId,
      amountTzs: amountTzs,
      defaultPhone: phone,
      testMode: options['environment'] == 'sandbox',
      productType: productType,
      onCompleted: onCompleted,
    ),
  );
  return done == true;
}

/// Held reasons the server names on `/refresh` that get their own wording.
const momoHeldReasons = {
  'group_slot_rebooked': 'momo.held.groupSlotRebooked',
  'reference_already_used': 'momo.held.referenceAlreadyUsed',
  'amount_mismatch': 'momo.held.amountMismatch',
  'transaction_mismatch': 'momo.held.transactionMismatch',
};

/// The body text key for a completed payment of [productType].
String momoSuccessBodyKey(String? productType) => switch (productType) {
  MomoProduct.trainerSession => 'momo.successBody.session',
  MomoProduct.trainerGymPass => 'momo.successBody.trainerPass',
  MomoProduct.eventOrder => 'momo.successBody.eventOrder',
  _ => 'momo.successBody',
};

/// The body text key for a held payment: the reason's own, or the general one.
String momoHeldBodyKey(String? reason) =>
    momoHeldReasons[reason] ?? 'momo.heldBody';

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
    this.onCompleted,
    this.productType,
  });

  final String paymentRequestId;
  final num amountTzs;
  final String? defaultPhone;
  final bool testMode;
  final Duration pollEvery;
  final Duration giveUpAfter;

  /// Runs once when the server says the payment completed.
  final VoidCallback? onCompleted;

  /// What is being paid for, so "payment received" says what happens next.
  final String? productType;

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
  String? _heldReason;

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
        setState(() {
          _stage = stage;
          _heldReason = out['reason']?.toString();
        });
        if (stage == MomoStage.success) {
          // Pick up the activated plan (QR, status) behind the sheet.
          final shell = context.findAncestorStateOfType<MemberShellState>();
          unawaited(shell?.refreshQr());
          unawaited(shell?.refreshMe());
          widget.onCompleted?.call();
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
            context.tr(switch (_stage) {
              MomoStage.held => momoHeldBodyKey(_heldReason),
              MomoStage.success => momoSuccessBodyKey(widget.productType),
              _ => 'momo.${key}Body',
            }),
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
/// the server takes this payment's product from this [role] (see [momoOffers]).
class PayNowButton extends StatefulWidget {
  const PayNowButton({
    super.key,
    required this.request,
    this.role = 'member',
    this.onPaid,
    this.options,
  });

  final PaymentRequest request;

  /// Who is paying: 'member' or 'trainer' (the signed-in role).
  final String role;

  /// Runs when the payment completed, to re-fetch what it paid for.
  final VoidCallback? onPaid;

  /// `GET /payments/options`, when the page already asked (one call for
  /// many buttons). Asked here otherwise.
  final Future<Map<String, dynamic>>? options;

  @override
  State<PayNowButton> createState() => _PayNowButtonState();
}

class _PayNowButtonState extends State<PayNowButton> {
  Future<bool>? _available;

  /// The product kind; an older server sends none, and a tier means a pass.
  String? get _product =>
      widget.request.productType ??
      (widget.request.tier.isNotEmpty ? MomoProduct.fitflexPass : null);

  @override
  void initState() {
    super.initState();
    // Paid by hand with a transaction ID: the server refuses a second
    // payment (409 manual_payment_submitted), so "Pay now" is not offered.
    if (widget.request.memberReference == null && _product != null) {
      // Read without depending on it: initState may not register dependencies.
      final options =
          widget.options ??
          context
              .getInheritedWidgetOfExactType<AppScope>()!
              .api
              .paymentOptions();
      _available = options
          .then((o) => momoOffers(o, _product, role: widget.role))
          .catchError((_) => false);
    }
  }

  Future<void> _pay() async {
    final done = await offerMobileMoney(
      context,
      paymentRequestId: widget.request.id,
      amountTzs: widget.request.amountTzs,
      productType: _product!,
      role: widget.role,
      // The completed payment is re-fetched behind the sheet.
      onCompleted: widget.onPaid,
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
              key: Key('pay-now-${widget.request.id}'),
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
