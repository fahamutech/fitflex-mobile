// Vendor tools · S4: recording a customer payment (spec §6.1–6.2), the
// payment receipt (§7.2) and voiding a payment (§6.4). Online only: a
// payment is never queued (the over-payment check needs the live balance).
// Only `customers` records and voids payments (Q-3).
import '../../../shared/network/browser_online.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../sales/offline_sale_queue.dart';
import '../sales/receipt_data.dart' show eatDateTime;
import '../sales/receipt_page.dart' show shareReceipt;
import '../sales/sale_models.dart';
import '../sales/sales_widgets.dart';
import '../stock/stock_history_page.dart' show stockRangePickerTheme;
import '../stock/stock_options.dart';
import 'customer_models.dart';
import 'customers_widgets.dart';

/// The business name for document headers: the profile, else the header
/// this device kept for receipts (staff may not read the profile).
Future<String?> loadBusinessName(BuildContext context) async {
  final session = SalesSession.of(context);
  try {
    final p = await AppScope.of(context).api.vendorProfile();
    await session?.saveBusiness(p);
    final name = p['businessName']?.toString().trim() ?? '';
    return name.isEmpty ? null : name;
  } catch (_) {
    final kept = await session?.loadBusiness() ?? const {};
    final name = kept['businessName']?.toString().trim() ?? '';
    return name.isEmpty ? null : name;
  }
}

/// Opens "Record payment" for [customer] (a profile). Answers the server's
/// `{payment, customer}` once saved, else null. Then shows the saved snack
/// and the payment receipt.
Future<Map<String, dynamic>?> recordCustomerPayment(
  BuildContext context, {
  required Map<String, dynamic> customer,
}) async {
  final name = customerDisplayName(customer, context.tr);
  final out = await showFFSheet<Map<String, dynamic>>(
    context,
    title: fillIn(context.tr('vendor.pay.title'), {'name': name}),
    isDismissible: false,
    child: RecordPaymentSheet(customer: customer),
  );
  if (out == null || !context.mounted) return null;
  final payment = out['payment'] is Map
      ? Map<String, dynamic>.from(out['payment'] as Map)
      : null;
  if (payment == null) return out;
  FFSnack.success(
    context,
    fillIn(context.tr('vendor.pay.saved'), {'number': payment['number']}),
  );
  final after = out['customer'] is Map ? out['customer'] as Map : const {};
  await showPaymentReceipt(
    context,
    customerId: customer['id'].toString(),
    customerName: name,
    payment: payment,
    stillOwedTzs: intOf(after['owedTzs']),
    customerArchived: customer['archived'] == true,
  );
  return out;
}

class _SaleField {
  _SaleField(this.sale) : controller = TextEditingController();
  final OpenSale sale;
  final TextEditingController controller;
}

class RecordPaymentSheet extends StatefulWidget {
  const RecordPaymentSheet({super.key, required this.customer, this.now});

  /// The customer's profile (owedTzs, openSales, id).
  final Map<String, dynamic> customer;

  /// Test hook for "today".
  final DateTime Function()? now;

  @override
  State<RecordPaymentSheet> createState() => _RecordPaymentSheetState();
}

class _RecordPaymentSheetState extends State<RecordPaymentSheet> {
  late Map<String, dynamic> _customer = widget.customer;
  final _amount = TextEditingController();
  final _reference = TextEditingController();
  final _note = TextEditingController();
  String _method = 'cash';
  String? _receivedOn;
  List<_SaleField>? _manual;
  bool _saving = false;
  String? _problem;
  String? _refError;
  String? _dateError;
  late final String _clientRef = newCustomerClientRef('pay');

  String get _today => eatTodayString(widget.now?.call());
  String get _id => _customer['id'].toString();
  int get _owed => intOf(_customer['owedTzs']);
  List<OpenSale> get _open => openSalesOf(_customer);

  @override
  void initState() {
    super.initState();
    BrowserOnline.instance.addListener(_onBrowserOnline);
  }

  void _onBrowserOnline() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    BrowserOnline.instance.removeListener(_onBrowserOnline);
    _amount.dispose();
    _reference.dispose();
    _note.dispose();
    for (final f in _manual ?? const <_SaleField>[]) {
      f.controller.dispose();
    }
    super.dispose();
  }

  CustomerPaymentCheck get _check => CustomerPaymentCheck(
    online: BrowserOnline.instance.value,
    owedTzs: _owed,
    amountTzs: int.tryParse(_amount.text) ?? 0,
    method: _method,
    reference: _reference.text,
    openSales: _open,
    manual: _manual == null
        ? null
        : {
            for (final f in _manual!)
              f.sale.id: int.tryParse(f.controller.text) ?? 0,
          },
  );

  void _edited() => setState(() {
    _problem = null;
    _refError = null;
    _dateError = null;
  });

  void _setAmount(int v) {
    _amount.text = '$v';
    _edited();
  }

  void _toggleManual() {
    setState(() {
      if (_manual == null) {
        // Start from the oldest-first split, then the vendor changes it.
        final preview = {
          for (final l in _check.preview) l.sale.id: l.amountTzs,
        };
        _manual = [
          for (final s in _open)
            _SaleField(s)
              ..controller.text = (preview[s.id] ?? 0) > 0
                  ? '${preview[s.id]}'
                  : '',
        ];
      } else {
        for (final f in _manual!) {
          f.controller.dispose();
        }
        _manual = null;
      }
      _problem = null;
    });
  }

  Future<void> _pickDate() async {
    final range = receivedOnRange(_today);
    DateTime local(String day) {
      final d = parseDay(day)!;
      return DateTime(d.year, d.month, d.day);
    }

    final picked = await showDatePicker(
      context: context,
      firstDate: local(range.earliest),
      lastDate: local(range.latest),
      initialDate: local(_receivedOn ?? _today),
      builder: (context, child) =>
          Theme(data: stockRangePickerTheme(Theme.of(context)), child: child!),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _receivedOn = dayString(
        DateTime.utc(picked.year, picked.month, picked.day),
      );
      _dateError = null;
    });
  }

  Future<void> _reload() async {
    try {
      final res = await AppScope.of(context).api.vendorCustomer(_id);
      if (res['customer'] is Map && mounted) {
        setState(
          () => _customer = Map<String, dynamic>.from(res['customer'] as Map),
        );
      }
    } catch (_) {
      // The message already says to check; the old figures stay.
    }
  }

  Future<void> _save() async {
    final check = _check;
    if (!check.canSave || _saving) return;
    // Let go of the focused field before it is disabled (web semantics).
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _saving = true;
      _problem = null;
    });
    final body = check.toRequest(
      clientRef: _clientRef,
      receivedOn: _receivedOn,
      note: _note.text,
    );
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorRecordCustomerPayment(_id, body);
      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      Navigator.of(context).pop(res);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      final b = e.body is Map ? e.body as Map : const {};
      switch (e.code) {
        case 'overpayment':
          setState(() {
            _customer = {..._customer, 'owedTzs': intOf(b['owedTzs'])};
          });
        case 'allocation_stale':
          _problem = context.tr('vendor.pay.allocStale');
          await _reload();
          if (_manual != null) _toggleManual();
        case 'allocation_mismatch':
          _problem = fillIn(context.tr('vendor.pay.allocMismatch'), {
            'amount': formatCurrency(check.amountTzs),
          });
        case 'reference_required':
          _refError = context.tr('vendor.pos.referenceRequired');
        case 'received_on_invalid':
          _dateError = context.tr('vendor.pay.dateInvalid');
        case 'customer_archived':
          _problem = context.tr('vendor.pay.archived');
        case 'client_ref_reused':
          _problem = context.tr('vendor.pay.refReused');
        case 'invalid_allocation':
          _problem = context.tr('vendor.pay.invalidAllocation');
        case 'note_too_long':
          _problem = fillIn(context.tr('vendor.customers.noteTooLong'), {
            'max': customerPaymentNoteMax,
          });
        case 'vendor_suspended':
          _problem = context.tr('vendor.sales.suspended');
        default:
          if (e.status == 403) {
            Navigator.of(context).pop();
            FFSnack.error(context, context.tr('vendor.customers.noAccess'));
            return;
          }
          _problem = isRateLimited(e)
              ? rateLimitedText(context, e)
              : context.tr(
                  e.status >= 500 ? 'vendor.pay.failed' : 'vendor.saveFailed',
                );
      }
    } catch (_) {
      // No answer: nothing recorded yet (or unknown). Try again resends the
      // same clientRef, so it is recorded once. Never queued.
      if (mounted) _problem = context.tr('vendor.pay.failed');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final check = _check;
    final open = _open;
    final amount = check.amountTzs;
    final preview = check.preview;
    return PopScope(
      canPop: !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) FocusManager.instance.primaryFocus?.unfocus();
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () {
            if (!_saving) Navigator.of(context).maybePop();
          },
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MoneyRow(
              context.tr('vendor.customers.owes'),
              formatCurrency(_owed),
              strong: true,
              key: const Key('pay-owed'),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            FFTextField(
              key: const Key('pay-amount'),
              controller: _amount,
              label: context.tr('vendor.pay.amount'),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(9),
              ],
              enabled: !_saving,
              errorText: check.overOwed
                  ? fillIn(context.tr('vendor.pay.overOwed'), {
                      'owed': formatCurrency(_owed),
                    })
                  : null,
              onChanged: (_) => _edited(),
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(
              spacing: FFTokens.spacingXs,
              runSpacing: FFTokens.spacingXs,
              children: [
                FFPill(
                  key: const Key('pay-all-owed'),
                  label: fillIn(context.tr('vendor.pay.allOwed'), {
                    'amount': formatCurrency(_owed),
                  }),
                  filled: amount == _owed && _owed > 0,
                  onTap: _saving ? null : () => _setAmount(_owed),
                ),
                if (open.length > 1)
                  FFPill(
                    key: const Key('pay-oldest'),
                    label: fillIn(context.tr('vendor.pay.oldest'), {
                      'amount': formatCurrency(open.first.balanceTzs),
                    }),
                    filled: amount == open.first.balanceTzs,
                    onTap: _saving
                        ? null
                        : () => _setAmount(open.first.balanceTzs),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingMd),
            Text(
              context.tr('vendor.pos.method'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(
              spacing: FFTokens.spacingXs,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final m in salePaymentMethods)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    child: FFPill(
                      key: Key('pay-method-$m'),
                      label: context.tr(paymentMethodKey(m)),
                      filled: _method == m,
                      onTap: _saving
                          ? null
                          : () {
                              _method = m;
                              _edited();
                            },
                    ),
                  ),
              ],
            ),
            if (_method != 'cash') ...[
              const SizedBox(height: FFTokens.spacingSm),
              FFTextField(
                key: const Key('pay-reference'),
                controller: _reference,
                label: context.tr(
                  check.needsReference
                      ? 'vendor.pos.reference'
                      : 'vendor.pos.referenceOptional',
                ),
                helperText: context.tr('vendor.pos.referenceHint'),
                errorText:
                    _refError ??
                    (check.referenceMissing
                        ? context.tr('vendor.pos.referenceRequired')
                        : null),
                maxLength: maxPaymentReference,
                textCapitalization: TextCapitalization.characters,
                enabled: !_saving,
                onChanged: (_) => _edited(),
              ),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            Semantics(
              button: true,
              label:
                  '${context.tr('vendor.pay.date')}, ${formatDay(_receivedOn ?? _today, locale: lang)}',
              excludeSemantics: true,
              child: InkWell(
                key: const Key('pay-date'),
                onTap: _saving ? null : _pickDate,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('vendor.pay.date'),
                              style: theme.textTheme.labelLarge,
                            ),
                            Text(
                              formatDay(_receivedOn ?? _today, locale: lang),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right),
                    ],
                  ),
                ),
              ),
            ),
            if (_dateError != null)
              Text(
                _dateError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            const SizedBox(height: FFTokens.spacingSm),
            FFTextField(
              key: const Key('pay-note'),
              controller: _note,
              label: context.tr('vendor.customers.note'),
              maxLength: customerPaymentNoteMax,
              enabled: !_saving,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context.tr('vendor.pay.appliesTo'),
              style: theme.textTheme.labelLarge,
            ),
            if (_manual == null)
              // Its own node (UAT D6): read out as one polite update, never
              // merged into the method chips above it.
              Semantics(
                key: const Key('pay-preview-region'),
                container: true,
                liveRegion: true,
                label: preview.isEmpty
                    ? context.tr('vendor.pay.oldestFirst')
                    : [
                        context.tr('vendor.pay.appliesTo'),
                        for (final l in preview) _previewText(l),
                      ].join('. '),
                excludeSemantics: true,
                child: Column(
                  key: const Key('pay-preview'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (preview.isEmpty)
                      Text(context.tr('vendor.pay.oldestFirst'))
                    else
                      for (final l in preview) _previewLine(l),
                  ],
                ),
              )
            else ...[
              for (final f in _manual!) _manualRow(f),
              if (check.allocMismatch)
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: Text(
                    fillIn(context.tr('vendor.pay.allocMismatch'), {
                      'amount': formatCurrency(amount),
                    }),
                    key: const Key('pay-alloc-mismatch'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: warningText(context),
                    ),
                  ),
                ),
            ],
            if (open.length > 1)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: FFButton(
                  key: const Key('pay-choose-sales'),
                  label: context.tr(
                    _manual == null
                        ? 'vendor.pay.chooseSales'
                        : 'vendor.pay.oldestFirst',
                  ),
                  variant: FFButtonVariant.ghost,
                  visualDensity: VisualDensity.standard,
                  onPressed: _saving ? null : _toggleManual,
                ),
              ),
            const SizedBox(height: FFTokens.spacingSm),
            FFAlert(
              key: const Key('pay-notice'),
              message: context.tr('vendor.pay.notice'),
            ),
            if (_problem != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Semantics(
                container: true,
                liveRegion: true,
                child: FFAlert(
                  key: const Key('pay-problem'),
                  message: _problem!,
                  tone: FFAlertTone.error,
                ),
              ),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            if (!BrowserOnline.instance.value) ...[
              Semantics(
                container: true,
                liveRegion: true,
                child: Text(
                  context.tr('vendor.pay.offline'),
                  key: const Key('pay-offline'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: FFTokens.spacingXs),
            ],
            FFButton(
              key: const Key('pay-save'),
              label: fillIn(context.tr('vendor.pay.save'), {
                'amount': formatCurrency(amount),
              }),
              fullWidth: true,
              maxLines: 2,
              visualDensity: VisualDensity.standard,
              loading: _saving,
              onPressed: check.canSave ? _save : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewLine(AllocationLine l) =>
      Text(_previewText(l), key: Key('pay-preview-${l.sale.id}'));

  String _previewText(AllocationLine l) => l.paysOff
      ? fillIn(context.tr('vendor.pay.paysOff'), {
          'number': l.sale.number,
          'amount': formatCurrency(l.amountTzs),
        })
      : fillIn(context.tr('vendor.pay.paysPart'), {
          'amount': formatCurrency(l.amountTzs),
          'number': l.sale.number,
          'left': formatCurrency(l.leftTzs),
        });

  Widget _manualRow(_SaleField f) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final v = int.tryParse(f.controller.text) ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingSm),
      child: FFTextField(
        key: Key('pay-alloc-${f.sale.id}'),
        controller: f.controller,
        label:
            '${f.sale.number} · ${fillIn(context.tr('vendor.customers.dueOn'), {'date': formatDay(f.sale.dueDate, locale: lang)})}',
        helperText: fillIn(context.tr('vendor.sales.owesBadge'), {
          'amount': formatCurrency(f.sale.balanceTzs),
        }),
        errorText: v > f.sale.balanceTzs
            ? fillIn(context.tr('vendor.pay.allocOver'), {
                'amount': formatCurrency(f.sale.balanceTzs),
              })
            : null,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(9),
        ],
        enabled: !_saving,
        onChanged: (_) => _edited(),
      ),
    );
  }
}

/// Whether [user] may void [payment] (mirrors the server, #224 M2): the
/// vendor and admin-role staff any payment; other `customers` staff only a
/// payment they recorded, received today (EAT).
bool canVoidPayment(Map<String, dynamic>? user, Map payment, {DateTime? now}) {
  if (payment['status'] == 'voided') return false;
  final type = user?['userType']?.toString();
  if (type == 'vendor') return true;
  if (type != 'vendor_staff') return false;
  final perms = (user?['vendorPermissions'] as List? ?? []);
  if (!perms.contains('customers')) return false;
  if (user?['vendorRole']?.toString() == 'admin') return true;
  final by = payment['recordedBy'] is Map
      ? (payment['recordedBy'] as Map)['id']?.toString()
      : null;
  return by != null &&
      by == user?['id']?.toString() &&
      payment['receivedOn']?.toString() == eatTodayString(now);
}

/// The payment receipt sheet (§7.2): Share, Void, Done. Answers true when
/// the payment was voided.
Future<bool> showPaymentReceipt(
  BuildContext context, {
  required String customerId,
  required String customerName,
  required Map<String, dynamic> payment,
  int? stillOwedTzs,
  bool customerArchived = false,
}) async {
  final voided = await showFFSheet<bool>(
    context,
    title: fillIn(context.tr('vendor.pay.receiptTitle'), {
      'number': payment['number'],
    }),
    child: PaymentReceipt(
      customerId: customerId,
      customerName: customerName,
      payment: payment,
      stillOwedTzs: stillOwedTzs,
      customerArchived: customerArchived,
    ),
  );
  return voided == true;
}

/// Loads one payment and shows its receipt (links from a refused sale void).
Future<bool> openPaymentById(
  BuildContext context, {
  required String customerId,
  required String paymentId,
}) async {
  try {
    final api = AppScope.of(context).api;
    final res = await api.vendorCustomerPayment(customerId, paymentId);
    final p = res['payment'];
    if (p is! Map || !context.mounted) return false;
    final name = await CustomerRepository.fetchName(context, customerId);
    if (!context.mounted) return false;
    return showPaymentReceipt(
      context,
      customerId: customerId,
      customerName: name ?? context.tr('vendor.customers.unnamed'),
      payment: Map<String, dynamic>.from(p),
    );
  } catch (_) {
    if (context.mounted) {
      FFSnack.error(context, context.tr('vendor.customers.failed'));
    }
    return false;
  }
}

class PaymentReceipt extends StatefulWidget {
  const PaymentReceipt({
    super.key,
    required this.customerId,
    required this.customerName,
    required this.payment,
    this.stillOwedTzs,
    this.customerArchived = false,
  });

  final String customerId;
  final String customerName;
  final Map<String, dynamic> payment;
  final int? stillOwedTzs;
  final bool customerArchived;

  @override
  State<PaymentReceipt> createState() => _PaymentReceiptState();
}

class _PaymentReceiptState extends State<PaymentReceipt> {
  late Map<String, dynamic> _payment = widget.payment;
  late int? _owed = widget.stillOwedTzs;
  String? _business;
  String? _lang;
  bool _changed = false;
  final _heading = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _heading.requestFocus();
      final b = await loadBusinessName(context);
      if (mounted) setState(() => _business = b);
    });
  }

  @override
  void dispose() {
    _heading.dispose();
    super.dispose();
  }

  bool get _voided => _payment['status'] == 'voided';

  Future<void> _share(String lang) async {
    final locale = FFLocaleScope.of(context);
    String t(String key) => locale.tIn(lang, key);
    await shareReceipt(
      paymentShareText(
        _payment,
        customerName: widget.customerName,
        stillOwedTzs: _owed ?? 0,
        business: _business,
        t: t,
        lang: lang,
      ),
      [
        ?_business,
        fillIn(t('vendor.pay.receiptTitle'), {'number': _payment['number']}),
      ].join(' '),
    );
  }

  Future<void> _void() async {
    final out = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => VoidPaymentDialog(
        customerId: widget.customerId,
        paymentId: _payment['id'].toString(),
        number: _payment['number']?.toString() ?? '',
      ),
    );
    if (!mounted || out == null) return;
    if (out['payment'] is Map) {
      setState(() {
        _payment = Map<String, dynamic>.from(out['payment'] as Map);
        final c = out['customer'];
        if (c is Map) _owed = intOf(c['owedTzs']);
        _changed = true;
      });
      FFSnack.success(
        context,
        fillIn(context.tr('vendor.pay.voided'), {'number': _payment['number']}),
      );
    } else if (out['reload'] == true) {
      try {
        final res = await AppScope.of(context).api.vendorCustomerPayment(
          widget.customerId,
          _payment['id'].toString(),
        );
        if (res['payment'] is Map && mounted) {
          setState(() {
            _payment = Map<String, dynamic>.from(res['payment'] as Map);
            _changed = true;
          });
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = FFLocaleScope.of(context);
    final lang = _lang ?? locale.locale.languageCode;
    String t(String k) => locale.tIn(lang, k);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final p = _payment;
    final ref = p['reference']?.toString();
    final method = methodLabel(t, p['method']?.toString());
    final allocs = (p['allocations'] as List? ?? []).whereType<Map>();
    final by = p['recordedBy'] is Map
        ? (p['recordedBy'] as Map)['name']?.toString()
        : null;
    final voidedBy = p['voidedBy'] is Map
        ? (p['voidedBy'] as Map)['name']?.toString()
        : null;
    final user = AppScope.of(context).auth.user;
    final mayVoid =
        canVendor(context, 'customers') &&
        !widget.customerArchived &&
        canVoidPayment(user, p);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FFCard(
            key: const Key('payment-receipt'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_business != null)
                  Text(_business!, style: theme.textTheme.titleLarge),
                Focus(
                  focusNode: _heading,
                  child: Semantics(
                    header: true,
                    child: Text(
                      fillIn(t('vendor.pay.receiptTitle'), {
                        'number': p['number'],
                      }),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ),
                Text(
                  formatDay(p['receivedOn']?.toString(), locale: lang),
                  style: muted,
                ),
                Text(
                  fillIn(t('vendor.receipt.customer'), {
                    'name': widget.customerName,
                  }),
                ),
                if (_voided) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  FFBadge(
                    key: const Key('payment-voided-badge'),
                    label: t('vendor.sales.voidedBadge'),
                    tone: FFBadgeTone.gray,
                  ),
                  Text(
                    fillIn(t('vendor.pay.voidedBy'), {
                      'name': voidedBy ?? '—',
                      'time': eatDateTime(
                        p['voidedAt']?.toString(),
                        locale: lang,
                      ),
                      'reason': p['voidReason'] ?? '',
                    }),
                    key: const Key('payment-voided-by'),
                  ),
                ],
                const Divider(height: FFTokens.spacingLg),
                MoneyRow(
                  ref == null ? method : '$method ($ref)',
                  formatCurrency(intOf(p['amountTzs'])),
                  strong: true,
                  strike: _voided,
                ),
                if (allocs.isNotEmpty) ...[
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(
                    t('vendor.pay.paidTowards'),
                    style: theme.textTheme.labelLarge,
                  ),
                  for (final a in allocs)
                    MoneyRow(
                      a['saleNumber']?.toString() ?? '',
                      formatMoney(intOf(a['amountTzs'])),
                    ),
                ],
                if (_owed != null) ...[
                  const Divider(height: FFTokens.spacingLg),
                  MoneyRow(
                    t('vendor.pay.stillOwed'),
                    formatCurrency(_owed!),
                    key: const Key('payment-still-owed'),
                  ),
                ],
                if (p['note'] != null)
                  Text(
                    fillIn(t('vendor.sales.noteLabel'), {'note': p['note']}),
                    style: muted,
                  ),
                if (by != null)
                  Text(
                    fillIn(t('vendor.pay.recordedBy'), {'name': by}),
                    style: muted,
                  ),
                if (_business != null)
                  Text(
                    fillIn(t('vendor.pos.receiptFooter'), {
                      'business': _business,
                    }),
                  ),
                Text(t('vendor.pos.notFiscal'), style: muted),
              ],
            ),
          ),
          const SizedBox(height: FFTokens.spacingMd),
          if (!_voided)
            ReceiptLanguageToggle(
              value: lang,
              onChanged: (v) => setState(() => _lang = v),
            ),
          const SizedBox(height: FFTokens.spacingMd),
          Wrap(
            spacing: FFTokens.spacingSm,
            runSpacing: FFTokens.spacingSm,
            children: [
              // Voided payments cannot be shared (§7.2).
              if (!_voided)
                FFButton(
                  key: const Key('payment-share'),
                  label: context.tr('vendor.pay.share'),
                  icon: Icons.share,
                  variant: FFButtonVariant.secondary,
                  visualDensity: VisualDensity.standard,
                  onPressed: () => _share(lang),
                ),
              if (mayVoid)
                FFButton(
                  key: const Key('payment-void'),
                  label: context.tr('vendor.pay.void'),
                  icon: Icons.block,
                  variant: FFButtonVariant.destructive,
                  visualDensity: VisualDensity.standard,
                  onPressed: _void,
                ),
              FFButton(
                key: const Key('payment-done'),
                label: context.tr('vendor.pos.done'),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                onPressed: () => Navigator.of(context).pop(_changed),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class VoidPaymentDialog extends StatefulWidget {
  const VoidPaymentDialog({
    super.key,
    required this.customerId,
    required this.paymentId,
    required this.number,
  });

  final String customerId;
  final String paymentId;
  final String number;

  @override
  State<VoidPaymentDialog> createState() => _VoidPaymentDialogState();
}

class _VoidPaymentDialogState extends State<VoidPaymentDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _ok => _reason.text.trim().length >= voidReasonMin;

  void _close(Map<String, dynamic>? result) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(result);
  }

  Future<void> _submit() async {
    if (!_ok || _busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await AppScope.of(context).api.vendorVoidCustomerPayment(
        widget.customerId,
        widget.paymentId,
        _reason.text.trim(),
      );
      if (mounted) _close(res);
      return;
    } on ApiException catch (e) {
      if (!mounted) return;
      final body = e.body is Map ? e.body as Map : const {};
      switch (e.code) {
        case 'already_voided':
          FFSnack.info(context, context.tr('vendor.pay.alreadyVoided'));
          _close({'reload': true});
          return;
        case 'void_not_allowed':
          _error = context.tr(
            body['reason'] == 'too_old'
                ? 'vendor.pay.voidTooOld'
                : 'vendor.pay.voidNotOwn',
          );
        case 'customer_archived':
          _error = context.tr('vendor.pay.archived');
        case 'reason_required' || 'reason_too_long':
          _error = context.tr('vendor.sales.voidReasonMissing');
        default:
          _error = isRateLimited(e)
              ? rateLimitedText(context, e)
              : context.tr(
                  e.status == 403
                      ? 'vendor.customers.noAccess'
                      : 'vendor.saveFailed',
                );
      }
    } catch (_) {
      if (mounted) _error = context.tr('vendor.pay.voidOffline');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(
          fillIn(context.tr('vendor.pay.voidTitle'), {'number': widget.number}),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('vendor.pay.voidBody')),
              const SizedBox(height: FFTokens.spacingMd),
              FFTextField(
                key: const Key('payment-void-reason'),
                controller: _reason,
                label: context.tr('vendor.sales.voidReason'),
                maxLength: voidReasonMax,
                maxLines: 3,
                minLines: 1,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(
                  container: true,
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('payment-void-error'),
                    message: _error!,
                    tone: FFAlertTone.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FFButton(
            label: context.tr('common.cancel'),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: _busy ? null : () => _close(null),
          ),
          FFButton(
            key: const Key('payment-void-confirm'),
            label: context.tr('vendor.pay.void'),
            variant: FFButtonVariant.destructive,
            visualDensity: VisualDensity.standard,
            loading: _busy,
            onPressed: _ok ? _submit : null,
          ),
        ],
      ),
    );
  }
}
