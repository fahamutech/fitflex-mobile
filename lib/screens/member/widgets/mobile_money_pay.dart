import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../../../shared/models.dart';
import '../member_shell.dart';

/// Where a payment attempt stands, as the server reports it.
enum MomoStage { input, sending, waiting, success, failed, held, slow, ended }

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

/// The wallets AzamPay takes, as the server expects them (`network` on
/// `POST /me/payments/:id/mobile-money`), in the order they are offered.
const momoWallets = ['Mpesa', 'Tigo', 'Airtel', 'Halopesa', 'Azampesa'];

/// The wallet a Tanzanian number most likely pays from, or null.
///
/// ASSUMPTION: the prefix table follows the TCRA ranges (Vodacom M-Pesa
/// 074/075/076, Tigo/Mixx 065/067/071/077, Airtel 068/069/078, Halotel
/// 061/062) and matches the server's own guess. Numbers port between
/// networks, so this is only a starting choice the member can change.
/// AzamPesa is a wallet, not a number range: it is never guessed.
String? momoWalletGuess(String raw) {
  var d = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (d.startsWith('255')) {
    d = d.substring(3);
  } else if (d.startsWith('0')) {
    d = d.substring(1);
  }
  if (d.length < 2) return null;
  return switch (d.substring(0, 2)) {
    '74' || '75' || '76' => 'Mpesa',
    '65' || '67' || '71' || '77' => 'Tigo',
    '68' || '69' || '78' => 'Airtel',
    '61' || '62' => 'Halopesa',
    _ => null,
  };
}

/// The server's answer to "has it gone through?" as a stage.
///
/// `none` after a prompt went out means the prompt is no longer open: it
/// was declined, or nobody answered it for ten minutes and the server gave
/// it up. The request itself still waits, so the prompt can be sent again.
MomoStage momoStageFor(String? state) => switch (state) {
  'completed' => MomoStage.success,
  'failed' => MomoStage.failed,
  'held' => MomoStage.held,
  'none' => MomoStage.ended,
  _ => MomoStage.waiting,
};

/// The ways a payment request can be paid (`GET /payments/options.methods`,
/// fitflex-functions#361). All three pay the same request and are settled
/// the same way: only when the server says `completed`.
abstract final class MomoMethod {
  /// A prompt on the payer's phone (`POST …/mobile-money`).
  static const mobileMoney = 'mobile_money';

  /// Bank checkout with the bank's one-time password (`POST …/bank`).
  static const bank = 'bank';

  /// AzamPay's hosted payment page, in the browser (`POST …/checkout-page`).
  static const page = 'page';
}

/// Whether the server lists the ways to pay at all. Only such a server has
/// `POST /me/payments/:id/refresh`; an older one is asked the mobile-money
/// way, as before.
bool momoListsMethods(Map<String, dynamic>? options) =>
    options?['methods'] is List;

/// The banks bank checkout takes (`bank.providers`), as the server names them.
List<String> momoBanks(Map<String, dynamic>? options) {
  final block = options?['bank'];
  if (block is! Map || block['providers'] is! List) return const [];
  return [
    for (final b in block['providers'] as List)
      if (b is String && b.trim().isNotEmpty) b.trim(),
  ];
}

/// The ways [amountTzs] can be paid in this app, in the server's order.
///
/// Without `methods` (an older server) it is mobile money only, exactly as
/// before. Bank needs a bank to choose and an amount within
/// `bank.maxAmountTzs`; the page needs the server's `app` return target (the
/// app never sends an address, and `web` returns to the member portal).
/// Mobile money is always on while paying is, so it is what is left.
List<String> momoMethodsFor(Map<String, dynamic>? options, num amountTzs) {
  const fallback = [MomoMethod.mobileMoney];
  if (!momoListsMethods(options)) return fallback;
  final out = <String>[];
  for (final m in options!['methods'] as List) {
    switch (m) {
      case MomoMethod.mobileMoney:
        out.add(MomoMethod.mobileMoney);
      case MomoMethod.bank:
        final max = (options['bank'] as Map?)?['maxAmountTzs'];
        if (momoBanks(options).isNotEmpty &&
            (max is! num || amountTzs <= max)) {
          out.add(MomoMethod.bank);
        }
      case MomoMethod.page:
        final page = options['page'];
        if (page is Map &&
            page['returnTo'] is List &&
            (page['returnTo'] as List).contains('app')) {
          out.add(MomoMethod.page);
        }
    }
  }
  return out.isEmpty ? fallback : out;
}

/// The language to ask AzamPay's page for: the app's, when the server
/// lists it (`page.languages`); otherwise none is sent (the server's default).
String? momoPageLanguage(Map<String, dynamic>? options, String appLanguage) {
  final page = options?['page'];
  if (page is! Map || page['languages'] is! List) return null;
  return (page['languages'] as List).contains(appLanguage) ? appLanguage : null;
}

/// Whether [raw] can be a bank account number as the server takes it: 5–30
/// letters, digits, `-`, `/` or spaces.
bool looksLikeBankAccount(String raw) =>
    RegExp(r'^[A-Za-z0-9\-/ ]{5,30}$').hasMatch(raw.trim());

/// Whether [raw] can be a bank's one-time password: 4–12 letters or digits.
bool looksLikeBankOtp(String raw) =>
    RegExp(r'^[A-Za-z0-9]{4,12}$').hasMatch(raw.trim());

/// A payment page address the app may open: https only.
Uri? momoCheckoutUri(Object? raw) {
  if (raw is! String) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri;
}

/// Opens AzamPay's payment page in the external browser. Tests replace it.
@visibleForTesting
Future<bool> Function(Uri uri) momoOpenExternal = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Product kinds a payment request can be for (`productType` on the server).
abstract final class MomoProduct {
  static const fitflexPass = 'FITFLEX_PASS';
  static const gymPlan = 'GYM_SUBSCRIPTION';
  static const trainerSession = 'TRAINER_SERVICE';
  static const trainerGymPass = 'TRAINER_GYM_PASS';

  /// Event tickets (events S4); offered only when the server lists it.
  static const eventOrder = 'EVENT_ORDER';

  /// A member's own shop order (AZAMPAY_SHOP_ORDERS); offered only when the
  /// server lists it.
  static const shopOrder = 'SHOP_ORDER';
}

/// What a server without the `mobileMoney` key pays by mobile money: members
/// pay passes and gym plans, everyone else nothing (fitflex-functions#240).
/// Event and shop orders are paid only when the server lists them.
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

/// Whether "Pay now" (mobile money) is switched on at all, from
/// `GET /payments/options`; false when it cannot be reached.
Future<bool> loadMobileMoneyOn(ApiClient api) async {
  try {
    return (await api.paymentOptions())['enabled'] == true;
  } catch (_) {
    return false;
  }
}

/// Offers mobile-money payment for a request that was just created, when the
/// server has it switched on for this [productType] and [role]. Resolves true
/// when the payment completed. Safe to call anywhere: with it off (or
/// unreachable) it does nothing. [onCompleted] runs as soon as the server says
/// the payment completed, so the list behind the sheet can be re-fetched.
/// [options] is `GET /payments/options` when the caller already asked.
Future<bool> offerMobileMoney(
  BuildContext context, {
  required String? paymentRequestId,
  required num amountTzs,
  required String productType,
  String role = 'member',
  String? defaultPhone,
  VoidCallback? onCompleted,
  Map<String, dynamic>? options,
}) async {
  if (paymentRequestId == null || paymentRequestId.isEmpty) return false;
  if (options == null) {
    final api = AppScope.of(context).api;
    try {
      options = await api.paymentOptions();
    } catch (_) {
      return false;
    }
  }
  if (!momoOffers(options, productType, role: role) || !context.mounted) {
    return false;
  }
  // Only what can be paid in this app counts towards "more than one way".
  final several = momoMethodsFor(options, amountTzs).length > 1;
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
    title: context.tr(several ? 'member.payment' : 'momo.title'),
    isDismissible: false,
    child: MobileMoneyPayPanel(
      paymentRequestId: paymentRequestId,
      amountTzs: amountTzs,
      defaultPhone: phone,
      testMode: options['environment'] == 'sandbox',
      productType: productType,
      onCompleted: onCompleted,
      provider: options['provider']?.toString(),
      options: options,
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
  'no_open_attempt': 'momo.held.noOpenAttempt',
};

/// The body text key for a completed payment of [productType].
String momoSuccessBodyKey(String? productType) => switch (productType) {
  MomoProduct.trainerSession => 'momo.successBody.session',
  MomoProduct.trainerGymPass => 'momo.successBody.trainerPass',
  MomoProduct.eventOrder => 'momo.successBody.eventOrder',
  MomoProduct.shopOrder => 'shop.paymentConfirmed',
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
    this.provider,
    this.options,
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

  /// `GET /payments/options.provider`. 'azampay' (the only payment method)
  /// asks which wallet pays; without it the request is just `{phone}`.
  final String? provider;

  /// `GET /payments/options`. With `methods` listing more than one way that
  /// can be used here, the member chooses how to pay (mobile money, bank,
  /// AzamPay's page). Null, no `methods`, or mobile money only: the panel is
  /// the mobile-money one, exactly as before.
  final Map<String, dynamic>? options;

  @override
  State<MobileMoneyPayPanel> createState() => _MobileMoneyPayPanelState();
}

class _MobileMoneyPayPanelState extends State<MobileMoneyPayPanel>
    with WidgetsBindingObserver {
  late final TextEditingController _phone = TextEditingController(
    text: widget.defaultPhone ?? '',
  );
  MomoStage _stage = MomoStage.input;
  String? _error;

  /// The ways this amount can be paid here, and the one chosen.
  late final List<String> _methods = momoMethodsFor(
    widget.options,
    widget.amountTzs,
  );
  late String _method = _methods.first;

  // Bank checkout. The one-time password lives only in [_otp] while it is
  // typed: it is cleared as soon as it has been sent, and never stored.
  late final List<String> _banks = momoBanks(widget.options);
  late String? _bank = _banks.length == 1 ? _banks.single : null;
  final _account = TextEditingController();
  final _otp = TextEditingController();
  String? _bankError;
  String? _accountError;
  String? _otpError;

  /// A refusal that belongs to no field (bank and page).
  String? _formError;

  /// AzamPay's page for this request while it is open, to open it again.
  Uri? _checkoutUri;
  Timer? _timer;
  int _polls = 0;
  bool _checking = false;
  String? _heldReason;

  /// AzamPay only: the wallet that pays, guessed from the number until the
  /// member picks one themselves.
  late String? _wallet = _picksWallet
      ? momoWalletGuess(widget.defaultPhone ?? '')
      : null;
  bool _walletPicked = false;
  String? _walletError;

  bool get _picksWallet => widget.provider == 'azampay';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _phone.dispose();
    _account.dispose();
    _otp.dispose();
    super.dispose();
  }

  /// Back from the browser: ask the server where the payment stands. Coming
  /// back proves nothing; only its answer `completed` is a payment.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _method == MomoMethod.page &&
        _stage == MomoStage.waiting) {
      _check();
    }
  }

  void _choose(String method) {
    if (_stage != MomoStage.input || method == _method) return;
    setState(() {
      _method = method;
      _error = null;
      _walletError = null;
      _bankError = null;
      _accountError = null;
      _otpError = null;
      _formError = null;
      // A code typed for the bank does not wait behind another choice.
      _otp.clear();
    });
  }

  void _follow() {
    _polls = 0;
    setState(() => _stage = MomoStage.waiting);
    _timer?.cancel();
    _timer = Timer.periodic(widget.pollEvery, (_) => _check());
  }

  Future<void> _sendBank() async {
    if (_stage == MomoStage.sending) return; // one request per tap
    final bank = _bank;
    final account = _account.text.trim();
    final otp = _otp.text.trim();
    setState(() {
      _formError = null;
      _bankError = bank == null ? context.tr('momo.bank.chooseBank') : null;
      _accountError = looksLikeBankAccount(account)
          ? null
          : context.tr('error.reason.invalidAccountNumber');
      _error = looksLikeTzMobile(_phone.text)
          ? null
          : context.tr('error.reason.invalidPhone');
      _otpError = looksLikeBankOtp(otp)
          ? null
          : context.tr('error.reason.invalidOtp');
    });
    if (bank == null ||
        _accountError != null ||
        _error != null ||
        _otpError != null) {
      return;
    }
    // Let go of the focused field before it is disabled for the request.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _stage = MomoStage.sending);
    final api = AppScope.of(context).api;
    final locale = FFLocaleScope.of(context);
    try {
      try {
        await api.payByBank(
          widget.paymentRequestId,
          bank: bank,
          accountNumber: account,
          phone: _phone.text.trim(),
          otp: otp,
        );
      } finally {
        // Sent (or refused): the code is used up either way. A new attempt
        // needs a new one from the bank.
        _otp.clear();
      }
      if (!mounted) return;
      _follow();
    } catch (e) {
      if (!mounted) return;
      final code = e is ApiException ? e.code : null;
      setState(() {
        _stage = MomoStage.input;
        switch (code) {
          case 'invalid_bank':
            _bankError = errorMessage(locale, e);
          case 'invalid_account_number':
            _accountError = errorMessage(locale, e);
          case 'invalid_phone':
            _error = errorMessage(locale, e);
          case 'invalid_otp':
            _otpError = errorMessage(locale, e);
          case 'provider_rejected':
            // AzamPay refused it, e.g. a wrong code: say what to check.
            _formError = locale.t('momo.bank.rejected');
          default:
            _formError = errorMessage(locale, e);
        }
      });
    }
  }

  Future<void> _openPage() async {
    if (_stage == MomoStage.sending) return; // one request per tap
    setState(() {
      _stage = MomoStage.sending;
      _formError = null;
    });
    final api = AppScope.of(context).api;
    final locale = FFLocaleScope.of(context);
    try {
      final out = await api.openCheckoutPage(
        widget.paymentRequestId,
        // A name the server listed, never an address.
        returnTo: 'app',
        language: momoPageLanguage(widget.options, locale.locale.languageCode),
      );
      if (!mounted) return;
      final uri = momoCheckoutUri(out['checkoutUrl']);
      if (uri == null) {
        setState(() {
          _stage = MomoStage.input;
          _formError = locale.t('momo.page.openFailed');
        });
        return;
      }
      // No timer: the page stays open for up to 30 minutes. The payment is
      // looked at when the app comes back, and by "check now".
      _timer?.cancel();
      setState(() {
        _checkoutUri = uri;
        _stage = MomoStage.waiting;
      });
      await _launchPage();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = MomoStage.input;
        _formError = errorMessage(locale, e);
      });
    }
  }

  /// Opens (or opens again) the same payment page in the external browser.
  Future<void> _launchPage() async {
    final uri = _checkoutUri;
    if (uri == null) return;
    var ok = false;
    try {
      ok = await momoOpenExternal(uri);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() => _formError = ok ? null : context.tr('momo.page.openFailed'));
  }

  Future<void> _send() async {
    if (_stage == MomoStage.sending) return; // one prompt per tap
    if (!looksLikeTzMobile(_phone.text)) {
      setState(() => _error = context.tr('error.reason.invalidPhone'));
      return;
    }
    if (_picksWallet && _wallet == null) {
      setState(() => _walletError = context.tr('error.reason.networkRequired'));
      return;
    }
    setState(() {
      _stage = MomoStage.sending;
      _error = null;
      _walletError = null;
    });
    try {
      await AppScope.of(context).api.payByMobileMoney(
        widget.paymentRequestId,
        _phone.text.trim(),
        network: _picksWallet ? _wallet : null,
      );
      if (!mounted) return;
      _polls = 0;
      setState(() => _stage = MomoStage.waiting);
      _timer?.cancel();
      _timer = Timer.periodic(widget.pollEvery, (_) => _check());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = MomoStage.input;
        // The server could not tell the wallet from the number: ask for it
        // beside the wallet choice, not under the number.
        if (_picksWallet && e is ApiException && e.code == 'network_required') {
          _walletError = context.tr('error.reason.networkRequired');
        } else {
          _error = errorMessage(FFLocaleScope.of(context), e);
        }
      });
    }
  }

  void _phoneChanged(String text) {
    setState(() {
      _error = null;
      if (_picksWallet && !_walletPicked) _wallet = momoWalletGuess(text);
    });
  }

  Future<void> _check() async {
    if (_checking || !mounted) return;
    _checking = true;
    try {
      final api = AppScope.of(context).api;
      // One rule: a server that lists `methods` has the refresh for every
      // method, and is asked that way for all three; an older server only
      // has the mobile-money one.
      final out = momoListsMethods(widget.options)
          ? await api.refreshPayment(widget.paymentRequestId)
          : await api.refreshMobileMoney(widget.paymentRequestId);
      if (!mounted) return;
      // The same page, to open again while it is open.
      final again = momoCheckoutUri(out['checkoutUrl']);
      if (again != null) _checkoutUri = again;
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
      // The page has no timer and no "still waiting": it is simply open.
      if (_method == MomoMethod.page) return;
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

  /// AzamPay: which wallet pays. Preselected from the number; a tap wins
  /// and is never changed by later typing.
  Widget _walletChoice(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.tr('momo.wallet'), style: theme.textTheme.labelMedium),
      const SizedBox(height: FFTokens.spacingXs),
      Wrap(
        spacing: FFTokens.spacingSm,
        children: [
          for (final w in momoWallets)
            FFFilterChip(
              key: Key('momo-wallet-$w'),
              label: context.tr('momo.wallet.$w'),
              selected: _wallet == w,
              tone: FFFilterChipTone.tint,
              selection: FFChipSelection.radio,
              onSelected: _stage == MomoStage.sending
                  ? () {}
                  : () => setState(() {
                      _wallet = w;
                      _walletPicked = true;
                      _walletError = null;
                    }),
            ),
        ],
      ),
      if (_walletError != null) ...[
        const SizedBox(height: FFTokens.spacingXs),
        Text(
          _walletError!,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
        ),
      ],
    ],
  );

  /// How to pay, when the server offers more than one way usable here.
  Widget _methodChoice(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(context.tr('momo.method'), style: theme.textTheme.labelMedium),
      const SizedBox(height: FFTokens.spacingXs),
      Wrap(
        spacing: FFTokens.spacingSm,
        children: [
          for (final m in _methods)
            FFFilterChip(
              key: Key('momo-method-$m'),
              label: context.tr('momo.method.$m'),
              selected: _method == m,
              tone: FFFilterChipTone.tint,
              selection: FFChipSelection.radio,
              onSelected: () => _choose(m),
            ),
        ],
      ),
    ],
  );

  Widget _fieldError(ThemeData theme, String text) => Padding(
    padding: const EdgeInsets.only(top: FFTokens.spacingXs),
    child: Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.error,
      ),
    ),
  );

  /// Bank checkout: the bank, how to get its one-time code, the account,
  /// the number registered with the bank, and the code.
  List<Widget> _bankForm(ThemeData theme, String amount) {
    final editable = _stage == MomoStage.input;
    final stepsKey = 'momo.bank.steps.$_bank';
    final steps = _bank == null ? stepsKey : context.tr(stepsKey);
    return [
      Text(
        '$amount · ${context.tr('momo.bank.intro')}',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: FFTokens.spacingMd),
      Text(context.tr('momo.bank.bank'), style: theme.textTheme.labelMedium),
      const SizedBox(height: FFTokens.spacingXs),
      Wrap(
        spacing: FFTokens.spacingSm,
        children: [
          for (final b in _banks)
            FFFilterChip(
              key: Key('momo-bank-$b'),
              // Bank names are brand names, the same in both languages.
              label: b,
              selected: _bank == b,
              tone: FFFilterChipTone.tint,
              selection: FFChipSelection.radio,
              onSelected: editable
                  ? () => setState(() {
                      _bank = b;
                      _bankError = null;
                    })
                  : () {},
            ),
        ],
      ),
      if (_bankError != null) _fieldError(theme, _bankError!),
      // The steps are the bank's own; shown only for a bank we have them for.
      if (_bank != null && steps != stepsKey) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFAlert(
          key: const Key('momo-bank-steps'),
          message: '${context.tr('momo.bank.stepsTitle')}\n$steps',
          tone: FFAlertTone.info,
        ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      FFTextField(
        key: const Key('momo-bank-account'),
        controller: _account,
        label: context.tr('momo.bank.account'),
        enabled: editable,
        errorText: _accountError,
        autofillHints: const [],
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-/ ]')),
          LengthLimitingTextInputFormatter(30),
        ],
        onChanged: (_) {
          if (_accountError != null) setState(() => _accountError = null);
        },
      ),
      const SizedBox(height: FFTokens.spacingMd),
      FFTextField(
        key: const Key('momo-bank-phone'),
        controller: _phone,
        label: context.tr('momo.bank.phone'),
        hint: context.tr('momo.phoneHint'),
        keyboardType: TextInputType.phone,
        enabled: editable,
        errorText: _error,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
        ],
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
      ),
      const SizedBox(height: FFTokens.spacingMd),
      FFTextField(
        key: const Key('momo-bank-otp'),
        controller: _otp,
        label: context.tr('momo.bank.otp'),
        helperText: context.tr('momo.bank.otpHelp'),
        enabled: editable,
        errorText: _otpError,
        // Never offered back by the keyboard or a password manager.
        obscureText: true,
        autofillHints: const [],
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
          LengthLimitingTextInputFormatter(12),
        ],
        onChanged: (_) {
          if (_otpError != null) setState(() => _otpError = null);
        },
      ),
      if (_formError != null) ...[
        const SizedBox(height: FFTokens.spacingMd),
        FFAlert(
          key: const Key('momo-form-error'),
          message: _formError!,
          tone: FFAlertTone.error,
        ),
      ],
      const SizedBox(height: FFTokens.spacingMd),
      FFButton(
        key: const Key('momo-bank-pay'),
        label: context.tr('momo.bank.pay').replaceFirst('{amount}', amount),
        loading: _stage == MomoStage.sending,
        fullWidth: true,
        maxLines: 2,
        onPressed: _stage == MomoStage.sending ? null : _sendBank,
      ),
    ];
  }

  /// AzamPay's hosted page: what will happen, and the button that opens it.
  List<Widget> _pageIntro(ThemeData theme, String amount) => [
    Text(
      '$amount · ${context.tr('momo.page.intro')}',
      style: theme.textTheme.bodyMedium,
    ),
    if (_formError != null) ...[
      const SizedBox(height: FFTokens.spacingMd),
      FFAlert(
        key: const Key('momo-form-error'),
        message: _formError!,
        tone: FFAlertTone.error,
      ),
    ],
    const SizedBox(height: FFTokens.spacingMd),
    FFButton(
      key: const Key('momo-page-open'),
      label: context.tr('momo.page.open'),
      icon: Icons.open_in_new,
      loading: _stage == MomoStage.sending,
      fullWidth: true,
      maxLines: 2,
      onPressed: _stage == MomoStage.sending ? null : _openPage,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = formatCurrency(widget.amountTzs);
    final byBank = _method == MomoMethod.bank;
    final byPage = _method == MomoMethod.page;
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
        if (_methods.length > 1) {
          children.addAll([
            _methodChoice(theme),
            const SizedBox(height: FFTokens.spacingMd),
          ]);
        }
        if (byBank) {
          children.addAll(_bankForm(theme, amount));
          break;
        }
        if (byPage) {
          children.addAll(_pageIntro(theme, amount));
          break;
        }
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
            onChanged: _picksWallet
                ? _phoneChanged
                : (_) {
                    if (_error != null) setState(() => _error = null);
                  },
          ),
          if (_picksWallet) ...[
            const SizedBox(height: FFTokens.spacingMd),
            _walletChoice(theme),
          ],
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
            context.tr(
              byPage
                  ? 'momo.page.waitingTitle'
                  : byBank
                  ? 'momo.bank.waitingTitle'
                  : 'momo.waitingTitle',
            ),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            context
                .tr(
                  byPage
                      ? 'momo.page.waitingBody'
                      : byBank
                      ? 'momo.bank.waitingBody'
                      : 'momo.waitingBody',
                )
                .replaceFirst('{amount}', amount),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          if (byPage && _formError != null) ...[
            const SizedBox(height: FFTokens.spacingMd),
            FFAlert(
              key: const Key('momo-form-error'),
              message: _formError!,
              tone: FFAlertTone.error,
            ),
          ],
          const SizedBox(height: FFTokens.spacingMd),
          FFButton(
            key: const Key('momo-check-now'),
            // "I have approved" is about a prompt on the phone.
            label: context.tr(
              byPage || byBank ? 'momo.checkNowPlain' : 'momo.checkNow',
            ),
            variant: FFButtonVariant.secondary,
            fullWidth: true,
            onPressed: _check,
          ),
          if (byPage) ...[
            const SizedBox(height: FFTokens.spacingSm),
            // The same page while it is open: no second attempt is made.
            FFButton(
              key: const Key('momo-page-reopen'),
              label: context.tr('momo.page.reopen'),
              icon: Icons.open_in_new,
              variant: FFButtonVariant.secondary,
              fullWidth: true,
              maxLines: 2,
              onPressed: _checkoutUri == null ? null : _launchPage,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            // The page stays open for a while: the sheet can be closed and
            // the payment looked at later. Closing is never "paid".
            FFButton(
              key: const Key('momo-page-close'),
              label: context.tr('common.close'),
              variant: FFButtonVariant.ghost,
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ]);
      case MomoStage.success:
      case MomoStage.failed:
      case MomoStage.held:
      case MomoStage.slow:
      case MomoStage.ended:
        final key = switch (_stage) {
          MomoStage.success => 'success',
          MomoStage.failed => 'failed',
          MomoStage.held => 'held',
          MomoStage.ended => 'ended',
          _ => 'slow',
        };
        // The prompt can be sent again: after a failure, or once the last
        // prompt is no longer open.
        final again = _stage == MomoStage.failed || _stage == MomoStage.ended;
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
              // An ended prompt is about the phone; a bank attempt and a
              // payment page end in their own words.
              MomoStage.ended when byBank => 'momo.bank.endedBody',
              MomoStage.ended when byPage => 'momo.page.endedBody',
              _ => 'momo.${key}Body',
            }),
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FFTokens.spacingMd),
          if (again) ...[
            FFButton(
              key: const Key('momo-send-again'),
              label: context.tr(
                _stage == MomoStage.ended && !byBank && !byPage
                    ? 'momo.sendAgain'
                    : 'momo.tryAgain',
              ),
              fullWidth: true,
              onPressed: () => setState(() {
                _stage = MomoStage.input;
                _formError = null;
                _checkoutUri = null;
              }),
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          if (_stage == MomoStage.slow) ...[
            // Still unanswered after the wait: look again by hand, so a
            // prompt the server has given up can be sent again.
            FFButton(
              key: const Key('momo-check-again'),
              label: context.tr(
                byBank ? 'momo.checkNowPlain' : 'momo.checkNow',
              ),
              variant: FFButtonVariant.secondary,
              fullWidth: true,
              onPressed: _check,
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          FFButton(
            key: const Key('momo-done'),
            label: context.tr('momo.done'),
            variant: again
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
