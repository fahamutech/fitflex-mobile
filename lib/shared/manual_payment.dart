// Manual Lipa Namba payments (A3, fitflex-functions#188).
//
// GET /payments/options may carry
//   manual: { enabled, lipaNamba, accountName, network|null,
//             instructions: {en, sw}|null, referenceRequired }
// A missing block, or enabled != true, means manual payment is not on and the
// app behaves as before (no transaction ID is asked for or sent). While it is
// on, the member pays the Lipa Namba first and then types the mobile-money
// transaction ID, which goes as `reference` on POST /me/subscribe (pass and
// direct_sub) and POST /me/upgrade.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'components/components.dart';
import 'design_tokens.dart';
import 'i18n.dart';

/// The Lipa Namba details the server sent, only while manual payment is on.
class ManualPayment {
  const ManualPayment({
    required this.lipaNamba,
    required this.accountName,
    this.network,
    this.instructionsEn,
    this.instructionsSw,
    this.referenceRequired = true,
    this.payerPhoneRequired = false,
  });

  final String lipaNamba;
  final String accountName;
  final String? network;
  final String? instructionsEn;
  final String? instructionsSw;
  final bool referenceRequired;

  /// The member must also say which mobile-money number they paid from.
  final bool payerPhoneRequired;

  /// The `manual` block of /payments/options, or null when it is missing,
  /// switched off, or lacks the number or account name.
  static ManualPayment? fromOptions(Map<String, dynamic>? options) {
    final m = options?['manual'];
    if (m is! Map || m['enabled'] != true) return null;
    final number = m['lipaNamba']?.toString().trim() ?? '';
    final name = m['accountName']?.toString().trim() ?? '';
    if (number.isEmpty || name.isEmpty) return null;
    String? text(Object? v) {
      final t = v?.toString().trim() ?? '';
      return t.isEmpty ? null : t;
    }

    final instructions = m['instructions'];
    return ManualPayment(
      lipaNamba: number,
      accountName: name,
      network: text(m['network']),
      instructionsEn: instructions is Map ? text(instructions['en']) : null,
      instructionsSw: instructions is Map ? text(instructions['sw']) : null,
      referenceRequired: m['referenceRequired'] != false,
      payerPhoneRequired: m['payerPhoneRequired'] == true,
    );
  }

  /// The admin's own instructions in [lang], falling back to the other
  /// language rather than showing nothing.
  String? instructionsFor(String lang) => lang == 'sw'
      ? (instructionsSw ?? instructionsEn)
      : (instructionsEn ?? instructionsSw);
}

/// How a purchase is paid, from /payments/options.
class PaymentModes {
  const PaymentModes({this.mobileMoney = false, this.manual});

  /// Tunzaa mobile money ("Pay now") is on.
  final bool mobileMoney;

  /// Manual Lipa Namba with a transaction ID, when on.
  final ManualPayment? manual;

  static const none = PaymentModes();

  factory PaymentModes.fromOptions(Map<String, dynamic>? options) =>
      PaymentModes(
        mobileMoney: options?['enabled'] == true,
        manual: ManualPayment.fromOptions(options),
      );
}

/// Reads /payments/options; when it cannot be reached, nothing extra is on
/// and the screen behaves as it did before manual payments existed.
Future<PaymentModes> loadPaymentModes(ApiClient api) async {
  try {
    return PaymentModes.fromOptions(await api.paymentOptions());
  } catch (_) {
    return PaymentModes.none;
  }
}

final _transactionIdPattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{5,39}$');

/// i18n key for what is wrong with a typed transaction ID, or null when it
/// passes the server's rule (fitflex-functions#188): 6–40 characters of
/// letters, digits, `.`, `_` or `-`, starting with a letter or digit and
/// containing at least one digit. The server upper-cases it.
String? transactionIdError(String raw) {
  final id = raw.trim();
  if (id.isEmpty) return 'manualPay.idRequired';
  if (!_transactionIdPattern.hasMatch(id) || !id.contains(RegExp(r'[0-9]'))) {
    return 'manualPay.idInvalid';
  }
  // At least six letters or digits once the punctuation is dropped.
  if (id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').length < 6) {
    return 'manualPay.idInvalid';
  }
  return null;
}

final _payerPhonePattern = RegExp(r'^(?:\+255|255|0)([67]\d{8})$');

/// i18n key for what is wrong with the number the member paid from, or null
/// when it passes the server's rule (fitflex-functions#188): 0XXXXXXXXX,
/// 255XXXXXXXXX or +255XXXXXXXXX, a 6x/7x mobile number, with spaces,
/// dashes, dots or brackets allowed.
String? payerPhoneError(String raw) {
  if (raw.trim().isEmpty) return 'manualPay.phoneRequired';
  final compact = raw.trim().replaceAll(RegExp(r'[\s().-]'), '');
  return _payerPhonePattern.hasMatch(compact) ? null : 'manualPay.phoneInvalid';
}

/// The number as the server stores it (+255…), for showing back; null when
/// it is not a valid number.
String? normalizedPayerPhone(String raw) {
  final m = _payerPhonePattern.firstMatch(
    raw.trim().replaceAll(RegExp(r'[\s().-]'), ''),
  );
  return m == null ? null : '+255${m.group(1)}';
}

/// [text] kept on one line: spaces become no-break spaces and hyphens are
/// held to their neighbours with word joiners, so "TSh 60,000", "M-Pesa" or
/// "0712 345 678" never break in the middle at 360px.
String keepTogether(String text) =>
    text.replaceAll(' ', '\u00A0').replaceAll('-', '\u2060-\u2060');

/// Test hook: copies [text] to the clipboard; tests make it fail.
@visibleForTesting
Future<void> Function(String text) manualPayCopier = (text) =>
    Clipboard.setData(ClipboardData(text: text));

/// Step-by-step instructions for paying the Lipa Namba, with a copy button.
class ManualPaymentSteps extends StatelessWidget {
  const ManualPaymentSteps({
    super.key,
    required this.manual,
    required this.amountLabel,
    this.upgrade = false,
  });

  final ManualPayment manual;

  /// The amount to pay, already formatted ("TZS 120,000").
  final String amountLabel;

  /// Paying the difference for an upgrade: once approved it applies to the
  /// pass the member already has, rather than starting a new plan.
  final bool upgrade;

  Future<void> _copy(BuildContext context) async {
    final copied = context.tr('manualPay.copied');
    final failed = context
        .tr('manualPay.copyFailed')
        .replaceAll('{number}', manual.lipaNamba);
    try {
      await manualPayCopier(manual.lipaNamba);
    } catch (_) {
      // The browser can refuse the clipboard; the number is still on screen.
      if (context.mounted) FFSnack.error(context, failed);
      return;
    }
    if (!context.mounted) return;
    FFSnack.success(context, copied);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    // The number itself is said once, large, below this sentence.
    final payTo = context
        .tr(
          manual.network == null ? 'manualPay.step1' : 'manualPay.step1Network',
        )
        .replaceAll('{amount}', keepTogether(amountLabel))
        .replaceAll('{name}', manual.accountName)
        .replaceAll('{network}', keepTogether(manual.network ?? ''));
    final instructions = manual.instructionsFor(lang);

    Widget step(int n, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$n.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );

    return FFCard(
      key: const Key('manual-pay-steps'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('manualPay.title'),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          step(
            1,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(payTo, style: theme.textTheme.bodyMedium),
                const SizedBox(height: FFTokens.spacingXs),
                Row(
                  children: [
                    // Never wraps: a long number shrinks to fit instead.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          manual.lipaNamba,
                          key: const Key('manual-pay-number'),
                          maxLines: 1,
                          softWrap: false,
                          semanticsLabel: context
                              .tr('manualPay.numberA11y')
                              .replaceAll(
                                '{number}',
                                manual.lipaNamba.split('').join(' '),
                              ),
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: FFTokens.spacingXs),
                    IconButton.outlined(
                      key: const Key('manual-pay-copy'),
                      tooltip: context.tr('manualPay.copy'),
                      icon: const Icon(Icons.copy, size: FFTokens.iconMd),
                      // 48dp on phones and on the web alike.
                      constraints: const BoxConstraints(
                        minWidth: 48,
                        minHeight: 48,
                      ),
                      visualDensity: VisualDensity.standard,
                      onPressed: () => _copy(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
          step(
            2,
            Text(
              context.tr('manualPay.step2'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          step(
            3,
            Text(
              context.tr(
                upgrade ? 'manualPay.step3Upgrade' : 'manualPay.step3',
              ),
              key: const Key('manual-pay-step3'),
              style: theme.textTheme.bodyMedium,
            ),
          ),
          if (instructions != null) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Text(
              instructions,
              key: const Key('manual-pay-instructions'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Room kept below a focused payment field when the keyboard opens, so the
/// next field and the submit button scroll into view with it.
const manualPayScrollPadding = EdgeInsets.fromLTRB(20, 20, 20, 160);

/// The required "Transaction ID" field. [errorText] is shown under it.
class TransactionIdField extends StatelessWidget {
  const TransactionIdField({
    super.key,
    required this.controller,
    this.errorText,
    this.enabled = true,
    this.onChanged,
  });

  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => FFTextField(
    key: const Key('manual-pay-transaction-id'),
    controller: controller,
    label: context.tr('manualPay.idLabel'),
    hint: context.tr('manualPay.idHint'),
    errorText: errorText,
    enabled: enabled,
    textCapitalization: TextCapitalization.characters,
    scrollPadding: manualPayScrollPadding,
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._\- ]')),
      LengthLimitingTextInputFormatter(48),
    ],
    onChanged: onChanged,
  );
}

/// i18n key for a refused paying number, to show under its field, or null.
String? payerPhoneServerErrorKey(Object error) {
  if (error is! ApiException) return null;
  return switch (error.code) {
    'payer_phone_required' => 'manualPay.phoneRequired',
    'payer_phone_invalid' => 'manualPay.phoneInvalid',
    _ => null,
  };
}

/// What the member types for a manual payment: the transaction ID and the
/// number they paid from, with the problems found (as i18n keys). One per
/// purchase screen; dispose it with the screen.
class ManualPaymentInput {
  final transactionId = TextEditingController();
  final payerPhone = TextEditingController();
  String? idError;
  String? phoneError;
  bool _prefilled = false;

  /// Puts the member's own number in the paying-number field once, if it is
  /// still empty. They can change it.
  void prefillPhone(String? phone) {
    if (_prefilled) return;
    _prefilled = true;
    final p = phone?.trim() ?? '';
    if (p.isNotEmpty && payerPhone.text.isEmpty) payerPhone.text = p;
  }

  /// Checks what was typed. Returns what to send, or null (with [idError] /
  /// [phoneError] set) when something needs fixing first.
  ({String reference, String? payerPhone})? check(ManualPayment manual) {
    idError = transactionIdError(transactionId.text);
    phoneError = manual.payerPhoneRequired
        ? payerPhoneError(payerPhone.text)
        : null;
    if (idError != null || phoneError != null) return null;
    return (
      reference: transactionId.text.trim(),
      payerPhone: manual.payerPhoneRequired ? payerPhone.text.trim() : null,
    );
  }

  /// Puts a server refusal of the ID or the number under its field. True
  /// when it was one of those; other errors are shown the usual way.
  bool takeServerError(Object error) {
    final id = transactionIdServerErrorKey(error);
    final phone = payerPhoneServerErrorKey(error);
    if (id == null && phone == null) return false;
    idError = id ?? idError;
    phoneError = phone ?? phoneError;
    return true;
  }

  /// Clears the shown problems (as the member edits). True if any were shown.
  bool clearErrors() {
    final had = idError != null || phoneError != null;
    idError = null;
    phoneError = null;
    return had;
  }

  void dispose() {
    transactionId.dispose();
    payerPhone.dispose();
  }
}

/// i18n key for a refused transaction ID, to show under the field, or null
/// for any other error (shown the usual way).
String? transactionIdServerErrorKey(Object error) {
  if (error is! ApiException) return null;
  return switch (error.code) {
    'payment_reference_required' => 'manualPay.idRequired',
    'payment_reference_invalid' => 'manualPay.idInvalid',
    'payment_reference_duplicate' => 'manualPay.idDuplicate',
    _ => null,
  };
}

/// The instructions and the transaction ID field together, as each purchase
/// screen shows them while manual payment is on.
class ManualPaymentFields extends StatelessWidget {
  const ManualPaymentFields({
    super.key,
    required this.manual,
    required this.amountLabel,
    required this.input,
    this.enabled = true,
    this.onChanged,
    this.upgrade = false,
  });

  final ManualPayment manual;
  final String amountLabel;
  final ManualPaymentInput input;
  final bool enabled;

  /// See [ManualPaymentSteps.upgrade].
  final bool upgrade;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    String? tr(String? key) => key == null ? null : context.tr(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ManualPaymentSteps(
          manual: manual,
          amountLabel: amountLabel,
          upgrade: upgrade,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        TransactionIdField(
          controller: input.transactionId,
          errorText: tr(input.idError),
          enabled: enabled,
          onChanged: onChanged,
        ),
        if (manual.payerPhoneRequired) ...[
          const SizedBox(height: FFTokens.spacingMd),
          FFTextField(
            key: const Key('manual-pay-payer-phone'),
            controller: input.payerPhone,
            label: context.tr('manualPay.phoneLabel'),
            hint: context.tr('manualPay.phoneHint'),
            helperText: context.tr('manualPay.phoneHelp'),
            errorText: tr(input.phoneError),
            enabled: enabled,
            keyboardType: TextInputType.phone,
            scrollPadding: manualPayScrollPadding,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s().-]')),
              LengthLimitingTextInputFormatter(20),
            ],
            onChanged: onChanged,
          ),
        ],
      ],
    );
  }
}
