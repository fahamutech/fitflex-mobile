// Vendor tools · S3: the payment sheet (spec §3) — how the customer paid,
// possibly with several methods, and the change to give back. The sheet
// mirrors the server's rules; the POS sends the sale and tells the sheet
// whether to close or to show a problem.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart';
import 'sale_models.dart';
import 'sales_widgets.dart';

/// What the POS made of one Complete.
class PayAttempt {
  const PayAttempt._(
    this.kind, {
    this.messageKey,
    this.values,
    this.index,
    this.action,
  });

  /// The sheet closes; the POS carries on (receipt, cart, snack).
  const PayAttempt.close() : this._(PayAttemptKind.close);

  /// The sheet stays with an inline problem ([index]: that payment row).
  const PayAttempt.stay(
    String messageKey, {
    Map<String, Object?>? values,
    int? index,
    String? action,
  }) : this._(
         PayAttemptKind.stay,
         messageKey: messageKey,
         values: values,
         index: index,
         action: action,
       );

  /// 5xx: the sheet stays with Try again and "Save and sync later".
  const PayAttempt.server() : this._(PayAttemptKind.server);

  final PayAttemptKind kind;
  final String? messageKey;
  final Map<String, Object?>? values;
  final int? index;

  /// A fix the seller can choose in the sheet, e.g. `recordToday` (a sale
  /// too old to keep its date is recorded with today's date).
  final String? action;
}

enum PayAttemptKind { close, stay, server }

typedef PaySubmit =
    Future<PayAttempt> Function(
      List<Map<String, dynamic>> payments, {
      bool queue,
    });

class _Row {
  _Row(PaymentRow row)
    : row = row,
      amount = TextEditingController(
        text: row.amountTzs > 0 ? '${row.amountTzs}' : '',
      ),
      reference = TextEditingController(text: row.reference);
  final PaymentRow row;
  final TextEditingController amount;
  final TextEditingController reference;
  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}

class PaymentSheet extends StatefulWidget {
  const PaymentSheet({
    super.key,
    required this.totalTzs,
    required this.submit,
    this.onAction,
  });

  final int totalTzs;
  final PaySubmit submit;

  /// Applies a [PayAttempt.action] before Complete is tried again.
  final void Function(String action)? onAction;

  @override
  State<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<PaymentSheet> {
  late final List<_Row> _rows = [
    _Row(PaymentRow(method: 'cash', amountTzs: widget.totalTzs)),
  ];
  bool _saving = false;
  bool _server = false;
  String? _problem;
  int? _problemIndex;
  String? _action;

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  PaymentCheck get _check =>
      PaymentCheck(widget.totalTzs, [for (final r in _rows) r.row]);

  int _dueBefore(int index) {
    var paid = 0;
    for (var i = 0; i < _rows.length; i++) {
      if (i != index) paid += _rows[i].row.amountTzs;
    }
    return widget.totalTzs - paid;
  }

  void _edited() => setState(() {
    _problem = null;
    _problemIndex = null;
    _action = null;
    _server = false;
  });

  void _setAmount(_Row r, int amount) {
    r.row.amountTzs = amount;
    r.amount.text = '$amount';
    _edited();
  }

  Future<void> _complete({bool queue = false}) async {
    final check = _check;
    if (!check.canComplete || _saving) return;
    // D8: let go of the focused field BEFORE it is disabled. Disabling a
    // focused text field throws in Flutter web's semantics text editing
    // (with accessibility on).
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _problem = null;
      _server = false;
    });
    final out = await widget.submit(check.toRequest(), queue: queue);
    if (!mounted) return;
    switch (out.kind) {
      case PayAttemptKind.close:
        FocusManager.instance.primaryFocus?.unfocus();
        Navigator.of(context).pop(true);
        return;
      case PayAttemptKind.stay:
        setState(() {
          _saving = false;
          _problem = fillIn(
            context.tr(out.messageKey ?? 'vendor.pos.err.payment'),
            out.values ?? const {},
          );
          _problemIndex = out.index;
          _action = out.action;
        });
      case PayAttemptKind.server:
        setState(() {
          _saving = false;
          _server = true;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final check = _check;
    final status = _statusLine(context, check);
    return PopScope(
      canPop: !_saving,
      // D8: let go of the amount / reference field before the sheet goes
      // (a field still focused while its route closes can throw on web).
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) FocusManager.instance.primaryFocus?.unfocus();
      },
      // Escape closes the sheet on web / desktop (not while saving).
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_saving) Navigator.of(context).maybePop();
          },
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('vendor.pos.amountDue'),
                style: theme.textTheme.labelLarge,
              ),
              Text(
                formatCurrency(widget.totalTzs),
                key: const Key('pos-pay-total'),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              if (check.nothingToPay)
                Text(
                  context.tr('vendor.pos.nothingToPay'),
                  key: const Key('pos-nothing-to-pay'),
                )
              else ...[
                for (var i = 0; i < _rows.length; i++) _rowEditor(context, i),
                if (check.remainingTzs > 0 && _rows.length < maxSalePayments)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FFButton(
                      key: const Key('pos-add-payment'),
                      label: context.tr('vendor.pos.addPayment'),
                      icon: Icons.add,
                      variant: FFButtonVariant.ghost,
                      visualDensity: VisualDensity.standard,
                      onPressed: _saving
                          ? null
                          : () {
                              setState(
                                () => _rows.add(
                                  _Row(
                                    PaymentRow(amountTzs: check.remainingTzs),
                                  ),
                                ),
                              );
                              _edited();
                            },
                    ),
                  ),
              ],
              if (status != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(liveRegion: true, child: status),
              ],
              if (_problem != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('pos-pay-problem'),
                    message: _problem!,
                    tone: FFAlertTone.error,
                  ),
                ),
                if (_action == 'recordToday' && widget.onAction != null) ...[
                  const SizedBox(height: FFTokens.spacingSm),
                  FFButton(
                    key: const Key('pos-record-today'),
                    label: context.tr('vendor.sync.recordToday'),
                    variant: FFButtonVariant.secondary,
                    fullWidth: true,
                    visualDensity: VisualDensity.standard,
                    onPressed: _saving
                        ? null
                        : () {
                            widget.onAction!('recordToday');
                            _edited();
                            _complete();
                          },
                  ),
                ],
              ],
              const SizedBox(height: FFTokens.spacingMd),
              FFAlert(
                key: const Key('pos-money-notice'),
                message: context.tr('vendor.pos.moneyNotice'),
              ),
              const SizedBox(height: FFTokens.spacingMd),
              if (_server) ...[
                FFAlert(
                  key: const Key('pos-server-error'),
                  message: context.tr('vendor.pos.err.server'),
                  tone: FFAlertTone.error,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFButton(
                  key: const Key('pos-retry'),
                  label: context.tr('common.retry'),
                  fullWidth: true,
                  visualDensity: VisualDensity.standard,
                  loading: _saving,
                  onPressed: () => _complete(),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFButton(
                  key: const Key('pos-sync-later'),
                  label: context.tr('vendor.pos.syncLater'),
                  variant: FFButtonVariant.secondary,
                  fullWidth: true,
                  visualDensity: VisualDensity.standard,
                  onPressed: _saving ? null : () => _complete(queue: true),
                ),
              ] else
                FFButton(
                  key: const Key('pos-complete'),
                  label: context.tr(
                    _saving ? 'vendor.pos.completing' : 'vendor.pos.complete',
                  ),
                  fullWidth: true,
                  maxLines: 2,
                  visualDensity: VisualDensity.standard,
                  loading: _saving,
                  onPressed: check.canComplete ? () => _complete() : null,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _statusLine(BuildContext context, PaymentCheck check) {
    final theme = Theme.of(context);
    if (check.nothingToPay) return null;
    if (check.remainingTzs > 0) {
      return Text(
        fillIn(context.tr('vendor.pos.remaining'), {
          'amount': formatCurrency(check.remainingTzs),
        }),
        key: const Key('pos-remaining'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: warningText(context),
        ),
      );
    }
    if (check.nonCashOver) {
      return Text(
        fillIn(context.tr('vendor.pos.overNonCash'), {
          'method': context.tr(paymentMethodKey(check.overMethod)),
        }),
        key: const Key('pos-over-non-cash'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: warningText(context),
        ),
      );
    }
    // Caught here, before sending (the server refuses the same).
    if (check.paidTooLarge) {
      return Text(
        context.tr('vendor.pos.err.paidTooLargeLocal'),
        key: const Key('pos-paid-too-large'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: warningText(context),
        ),
      );
    }
    if (check.changeTooLarge) {
      return Text(
        fillIn(context.tr('vendor.pos.err.changeTooLargeLocal'), {
          'amount': formatCurrency(check.totalTzs + maxChangeOverTotalTzs),
        }),
        key: const Key('pos-change-too-large'),
        style: theme.textTheme.titleSmall?.copyWith(
          color: warningText(context),
        ),
      );
    }
    if (check.changeTzs > 0) {
      return Text(
        fillIn(context.tr('vendor.pos.changeDue'), {
          'amount': formatCurrency(check.changeTzs),
        }),
        key: const Key('pos-change-due'),
        style: theme.textTheme.titleMedium?.copyWith(
          color: successText(context),
        ),
      );
    }
    return null;
  }

  Widget _rowEditor(BuildContext context, int index) {
    final r = _rows[index];
    final method = r.row.method;
    final cash = method == 'cash';
    final due = _dueBefore(index);
    // Complete stays disabled while it is missing, so say why at once.
    final showRefError = r.row.referenceMissing;
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingMd),
      child: FFCard(
        key: Key('pos-payment-$index'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.tr('vendor.pos.method'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ),
                if (_rows.length >= 2)
                  IconButton(
                    key: Key('pos-remove-payment-$index'),
                    style: IconButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      visualDensity: VisualDensity.standard,
                    ),
                    tooltip: fillIn(context.tr('vendor.pos.removePayment'), {
                      'method': context.tr(paymentMethodKey(method)),
                    }),
                    icon: const Icon(Icons.close),
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() => _rows.removeAt(index).dispose());
                            _edited();
                          },
                  ),
              ],
            ),
            Wrap(
              spacing: FFTokens.spacingXs,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final m in salePaymentMethods)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    child: FFPill(
                      key: Key('pos-method-$index-$m'),
                      label: context.tr(paymentMethodKey(m)),
                      filled: method == m,
                      onTap: () {
                        if (_saving) return;
                        r.row.method = m;
                        if (m == 'cash') r.row.reference = '';
                        _edited();
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              key: Key('pos-amount-$index'),
              controller: r.amount,
              label: context.tr(
                cash ? 'vendor.pos.cashReceived' : 'vendor.pos.amount',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              enabled: !_saving,
              // A refusal about this row (e.g. its reference) shows on it too.
              errorText: _problemIndex == index ? _problem : null,
              onChanged: (v) {
                r.row.amountTzs = int.tryParse(v) ?? 0;
                _edited();
              },
            ),
            if (cash && due > 0) ...[
              const SizedBox(height: FFTokens.spacingXs),
              Wrap(
                spacing: FFTokens.spacingXs,
                runSpacing: FFTokens.spacingXs,
                children: [
                  for (final (i, amount) in quickCashAmounts(due).indexed)
                    FFPill(
                      key: Key('pos-quick-$index-$amount'),
                      label: i == 0
                          ? context.tr('vendor.pos.exact')
                          : formatMoney(amount),
                      filled: r.row.amountTzs == amount,
                      onTap: () {
                        if (!_saving) _setAmount(r, amount);
                      },
                    ),
                ],
              ),
            ],
            if (method != null && !cash) ...[
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: Key('pos-reference-$index'),
                controller: r.reference,
                label: context.tr(
                  r.row.needsReference
                      ? 'vendor.pos.reference'
                      : 'vendor.pos.referenceOptional',
                ),
                helperText: context.tr('vendor.pos.referenceHint'),
                errorText: showRefError
                    ? context.tr('vendor.pos.referenceRequired')
                    : null,
                maxLength: maxPaymentReference,
                textCapitalization: TextCapitalization.characters,
                enabled: !_saving,
                onChanged: (v) {
                  r.row.reference = v;
                  _edited();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
