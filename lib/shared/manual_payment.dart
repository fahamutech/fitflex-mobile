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
  });

  final String lipaNamba;
  final String accountName;
  final String? network;
  final String? instructionsEn;
  final String? instructionsSw;
  final bool referenceRequired;

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
  return null;
}

/// Step-by-step instructions for paying the Lipa Namba, with a copy button.
class ManualPaymentSteps extends StatelessWidget {
  const ManualPaymentSteps({
    super.key,
    required this.manual,
    required this.amountLabel,
  });

  final ManualPayment manual;

  /// The amount to pay, already formatted ("TZS 120,000").
  final String amountLabel;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: manual.lipaNamba));
    if (!context.mounted) return;
    FFSnack.success(context, context.tr('manualPay.copied'));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final payTo = context
        .tr(
          manual.network == null ? 'manualPay.step1' : 'manualPay.step1Network',
        )
        .replaceAll('{amount}', amountLabel)
        .replaceAll('{number}', manual.lipaNamba)
        .replaceAll('{name}', manual.accountName)
        .replaceAll('{network}', manual.network ?? '');
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
                    Expanded(
                      child: SelectableText(
                        manual.lipaNamba,
                        key: const Key('manual-pay-number'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                    FFButton(
                      key: const Key('manual-pay-copy'),
                      label: context.tr('manualPay.copy'),
                      icon: Icons.copy,
                      size: FFButtonSize.sm,
                      variant: FFButtonVariant.secondary,
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
              context.tr('manualPay.step3'),
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
    inputFormatters: [
      FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._\- ]')),
      LengthLimitingTextInputFormatter(48),
    ],
    onChanged: onChanged,
  );
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
    required this.controller,
    this.errorText,
    this.enabled = true,
    this.onChanged,
  });

  final ManualPayment manual;
  final String amountLabel;
  final TextEditingController controller;
  final String? errorText;
  final bool enabled;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      ManualPaymentSteps(manual: manual, amountLabel: amountLabel),
      const SizedBox(height: FFTokens.spacingMd),
      TransactionIdField(
        controller: controller,
        errorText: errorText,
        enabled: enabled,
        onChanged: onChanged,
      ),
    ],
  );
}
