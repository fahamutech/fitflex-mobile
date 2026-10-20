// Vendor tools · S3: one recorded walk-in sale (spec §5.3) — the receipt plus
// its audit trail, Share, and Void. Voids need a connection and are never
// queued.
//
// Who may void (backend #214): the vendor account and admin-role staff any
// sale; other staff only a sale they recorded, on the same EAT day it was
// sold. The server enforces it (403 void_not_allowed); the app hides Void
// where it would be refused.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/formatters.dart';
import '../customers/customers_widgets.dart';
import '../customers/payment_sheets.dart';
import '../stock/stock_options.dart';
import 'offline_sale_queue.dart';
import 'receipt_data.dart';
import 'receipt_page.dart';
import 'sale_models.dart';
import 'sales_widgets.dart';

/// Whether [user] may void [sale] (mirrors the server's rule).
bool canVoidSale(
  Map<String, dynamic>? user,
  ReceiptData sale, {
  DateTime? now,
}) {
  if (sale.voided || sale.queued) return false;
  final type = user?['userType']?.toString();
  if (type == 'vendor') return true;
  if (type != 'vendor_staff') return false;
  final perms = (user?['vendorPermissions'] as List? ?? []);
  if (!perms.contains('sales')) return false;
  if (user?['vendorRole']?.toString() == 'admin') return true;
  final own = sale.servedById != null && sale.servedById == user?['id'];
  return own && eatDayOf(sale.soldAt) == eatToday(now);
}

class SaleDetailPage extends StatefulWidget {
  const SaleDetailPage({super.key, required this.saleId});
  final String saleId;

  @override
  State<SaleDetailPage> createState() => _SaleDetailPageState();
}

class _SaleDetailPageState extends State<SaleDetailPage> {
  Map<String, dynamic>? _sale;
  Map<String, dynamic> _profile = const {};
  bool _loading = true;
  bool _notFound = false;
  bool _failed = false;
  bool _suspended = false;
  String? _lang;
  VendorTools _tools = VendorTools.off;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final tools = await enterSalesRoute(context);
    if (tools == null || !mounted) return;
    _tools = tools;
    final api = AppScope.of(context).api;
    final session = SalesSession.of(context);
    () async {
      try {
        final p = await api.vendorProfile();
        await session?.saveBusiness(p);
        if (mounted) setState(() => _profile = p);
      } catch (_) {
        // Staff who may not read the profile: the header this device kept.
        final kept = await session?.loadBusiness() ?? const {};
        if (mounted && kept.isNotEmpty) setState(() => _profile = kept);
      }
    }();
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final res = await AppScope.of(context).api.vendorSale(widget.saleId);
      if (!mounted) return;
      setState(() {
        _sale = res['sale'] is Map
            ? Map<String, dynamic>.from(res['sale'] as Map)
            : null;
        _notFound = _sale == null;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _suspended = e.code == 'vendor_suspended';
        _notFound = !_suspended && (e.status == 404 || e.status == 403);
        _failed = !_notFound && !_suspended;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(salesHomeRoute);
    }
  }

  Future<void> _void(ReceiptData data) async {
    final out = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _VoidDialog(
        saleId: widget.saleId,
        number: data.number ?? '',
        credit: data.credit,
        customerId: data.customerId,
      ),
    );
    if (!mounted || out == null) return;
    if (out['sale'] is Map) {
      setState(() => _sale = Map<String, dynamic>.from(out['sale'] as Map));
      FFSnack.success(
        context,
        fillIn(context.tr('vendor.sales.voided'), {'number': data.number}),
      );
    } else if (out['reload'] == true) {
      final key = out['message']?.toString();
      if (key != null) FFSnack.info(context, context.tr(key));
      await _load();
    }
  }

  /// S4: customers screens are on and this person has `customers`.
  bool get _seesCustomers =>
      _tools.customers && canVendor(context, 'customers');

  Future<void> _recordPayment(ReceiptData data) async {
    final id = data.customerId;
    if (id == null) return;
    try {
      final res = await AppScope.of(context).api.vendorCustomer(id);
      final c = res['customer'];
      if (c is! Map || !mounted) return;
      final out = await recordCustomerPayment(
        context,
        customer: Map<String, dynamic>.from(c),
      );
      if (out != null && mounted) await _load();
    } catch (_) {
      if (mounted) FFSnack.error(context, context.tr('vendor.pay.offline'));
    }
  }

  Future<void> _share(ReceiptData data, String lang) async {
    final locale = FFLocaleScope.of(context);
    String t(String key) => locale.tIn(lang, key);
    await shareReceipt(
      receiptShareText(data, t, lang),
      [
        ?data.business,
        fillIn(t('vendor.pos.receiptNo'), {'number': data.number}),
      ].join(' '),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locale = FFLocaleScope.of(context);
    final lang = _lang ?? locale.locale.languageCode;
    final sale = _sale;
    final data = sale == null
        ? null
        : ReceiptData.fromSale(sale, profile: _profile);
    final user = AppScope.of(context).auth.user;
    final mayVoid = data != null && canVoidSale(user, data);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(
          data?.number == null
              ? context.tr('vendor.documents.receipt')
              : fillIn(context.tr('vendor.pos.receiptNo'), {
                  'number': data!.number,
                }),
        ),
      ),
      body: _loading
          ? const Center(child: FFSpinner())
          : data == null
          ? ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                if (_suspended)
                  FFAlert(
                    key: const Key('sale-detail-suspended'),
                    message: context.tr('vendor.sales.suspended'),
                    tone: FFAlertTone.warning,
                  )
                else if (_failed)
                  FFErrorState(
                    message: context.tr('vendor.sales.failed'),
                    onRetry: _load,
                  )
                else
                  FFEmptyState(
                    key: const Key('sale-detail-not-found'),
                    title: context.tr('vendor.sales.notFound'),
                  ),
              ],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  children: [
                    Wrap(
                      spacing: FFTokens.spacingSm,
                      runSpacing: FFTokens.spacingXs,
                      children: [
                        FFBadge(
                          key: const Key('sale-detail-status'),
                          label: context.tr(
                            data.voided
                                ? 'vendor.sales.voidedBadge'
                                : 'vendor.sales.filter.completed',
                          ),
                          tone: data.voided
                              ? FFBadgeTone.gray
                              : FFBadgeTone.success,
                        ),
                        if (data.lateRecorded)
                          FFBadge(
                            label: context.tr('vendor.sales.offlineBadge'),
                            tone: FFBadgeTone.gray,
                          ),
                      ],
                    ),
                    const SizedBox(height: FFTokens.spacingSm),
                    if (data.voided) ...[
                      FFAlert(
                        key: const Key('sale-detail-voided'),
                        message: fillIn(context.tr('vendor.sales.voidedBy'), {
                          'name': data.voidedBy ?? '—',
                          'time': eatDateTime(data.voidedAt, locale: lang),
                          'reason': data.voidReason ?? '',
                        }),
                      ),
                      const SizedBox(height: FFTokens.spacingSm),
                    ],
                    ReceiptView(
                      data: data,
                      lang: lang,
                      t: (k) => locale.tIn(lang, k),
                      audit: true,
                    ),
                    if (data.hasCustomer &&
                        _seesCustomers &&
                        customerIdPattern.hasMatch(data.customerId!)) ...[
                      const SizedBox(height: FFTokens.spacingSm),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: FFButton(
                          key: const Key('sale-detail-customer'),
                          label: data.customerName == null
                              ? context.tr(
                                  data.customerForgotten
                                      ? 'vendor.customers.deletedMember'
                                      : 'vendor.pos.customer.selected',
                                )
                              : data.customerName!,
                          icon: Icons.person_outline,
                          variant: FFButtonVariant.ghost,
                          visualDensity: VisualDensity.standard,
                          onPressed: () =>
                              context.push(customerRoute(data.customerId!)),
                        ),
                      ),
                    ],
                    if (data.credit && data.liveAllocations.isNotEmpty) ...[
                      const SizedBox(height: FFTokens.spacingSm),
                      Text(
                        context.tr('vendor.customers.payments'),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      for (final a in data.liveAllocations)
                        MoneyRow(
                          a['number']?.toString() ?? '',
                          formatCurrency((a['amountTzs'] as num?) ?? 0),
                        ),
                    ],
                    const SizedBox(height: FFTokens.spacingMd),
                    if (!data.voided)
                      ReceiptLanguageToggle(
                        value: lang,
                        onChanged: (v) => setState(() => _lang = v),
                      ),
                    const SizedBox(height: FFTokens.spacingMd),
                    Wrap(
                      spacing: FFTokens.spacingSm,
                      runSpacing: FFTokens.spacingSm,
                      children: [
                        if (!data.voided)
                          FFButton(
                            key: const Key('sale-detail-share'),
                            label: context.tr('vendor.pos.share'),
                            icon: Icons.share,
                            variant: FFButtonVariant.secondary,
                            visualDensity: VisualDensity.standard,
                            onPressed: () => _share(data, lang),
                          ),
                        if (data.credit &&
                            !data.voided &&
                            data.balanceTzs > 0 &&
                            _seesCustomers)
                          FFButton(
                            key: const Key('sale-detail-record-payment'),
                            label: context.tr('vendor.pay.record'),
                            icon: Icons.payments_outlined,
                            visualDensity: VisualDensity.standard,
                            onPressed: () => _recordPayment(data),
                          ),
                        if (mayVoid)
                          FFButton(
                            key: const Key('sale-detail-void'),
                            label: context.tr('vendor.sales.void'),
                            icon: Icons.block,
                            variant: FFButtonVariant.destructive,
                            visualDensity: VisualDensity.standard,
                            onPressed: () => _void(data),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _VoidDialog extends StatefulWidget {
  const _VoidDialog({
    required this.saleId,
    required this.number,
    this.credit = false,
    this.customerId,
  });
  final String saleId;
  final String number;

  /// S4: a pay-later sale (its balance is cancelled with it).
  final bool credit;
  final String? customerId;

  @override
  State<_VoidDialog> createState() => _VoidDialogState();
}

class _VoidDialogState extends State<_VoidDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _fieldError;

  /// S4 (Q-2): customer payments allocated to the sale: `{id, number}`.
  List<Map> _payments = const [];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _ok => _reason.text.trim().length >= voidReasonMin;

  /// D8: the reason field lets go of focus before the dialog closes.
  void _close(Map<String, dynamic>? result) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.of(context).pop(result);
  }

  Future<void> _submit() async {
    if (!_ok || _busy) return;
    // D8: unfocus the reason before it is disabled (web semantics).
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
      _fieldError = null;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorVoidSale(widget.saleId, _reason.text.trim());
      if (mounted) _close(res);
    } on ApiException catch (e) {
      if (!mounted) return;
      final body = e.body is Map ? e.body as Map : const {};
      switch (e.code) {
        case 'already_voided':
          _close({'reload': true, 'message': 'vendor.sales.alreadyVoided'});
          return;
        case 'reason_required' || 'reason_too_long':
          setState(
            () => _fieldError = context.tr('vendor.sales.voidReasonMissing'),
          );
        case 'void_not_allowed':
          setState(
            () => _error = context.tr(
              body['reason'] == 'too_old'
                  ? 'vendor.sales.voidTooOld'
                  : 'vendor.sales.voidNotOwn',
            ),
          );
        case 'vendor_suspended':
          setState(() => _error = context.tr('vendor.sales.suspended'));
        case 'sale_has_payments':
          final pays = (body['payments'] as List? ?? [])
              .whereType<Map>()
              .toList();
          setState(() {
            _payments = pays;
            _error = fillIn(context.tr('vendor.sales.voidHasPayments'), {
              'numbers': pays.map((p) => p['number']).join(', '),
            });
          });
        default:
          setState(
            () => _error = context.tr(
              e.status == 403
                  ? 'vendor.sales.err.voidNotAllowed'
                  : 'vendor.saveFailed',
            ),
          );
      }
      setState(() => _busy = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.tr('vendor.sales.voidOffline');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_busy,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) FocusManager.instance.primaryFocus?.unfocus();
      },
      child: AlertDialog(
        title: Text(
          fillIn(context.tr('vendor.sales.voidTitle'), {
            'number': widget.number,
          }),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(context.tr('vendor.sales.voidBody')),
              if (widget.credit) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Text(
                  context.tr('vendor.sales.voidCreditBody'),
                  key: const Key('sale-void-credit-body'),
                ),
              ],
              const SizedBox(height: FFTokens.spacingMd),
              FFTextField(
                key: const Key('sale-void-reason'),
                controller: _reason,
                label: context.tr('vendor.sales.voidReason'),
                maxLength: voidReasonMax,
                maxLines: 3,
                minLines: 1,
                errorText: _fieldError,
                enabled: !_busy,
                onChanged: (_) => setState(() {}),
              ),
              if (_error != null) ...[
                const SizedBox(height: FFTokens.spacingSm),
                Semantics(
                  liveRegion: true,
                  child: FFAlert(
                    key: const Key('sale-void-error'),
                    message: _error!,
                    tone: FFAlertTone.error,
                  ),
                ),
                // Links to each payment: void those first (§6.3).
                if (widget.customerId != null &&
                    canVendor(context, 'customers'))
                  Wrap(
                    spacing: FFTokens.spacingXs,
                    children: [
                      for (final p in _payments)
                        if (customerIdPattern.hasMatch('${p['id']}'))
                          FFButton(
                            key: Key('sale-void-payment-${p['id']}'),
                            label: p['number']?.toString() ?? '',
                            variant: FFButtonVariant.ghost,
                            visualDensity: VisualDensity.standard,
                            onPressed: _busy
                                ? null
                                : () async {
                                    final changed = await openPaymentById(
                                      context,
                                      customerId: widget.customerId!,
                                      paymentId: p['id'].toString(),
                                    );
                                    if (changed && mounted) {
                                      setState(() {
                                        _payments = _payments
                                            .where((x) => x['id'] != p['id'])
                                            .toList();
                                        if (_payments.isEmpty) _error = null;
                                      });
                                    }
                                  },
                          ),
                    ],
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
            key: const Key('sale-void-confirm'),
            label: context.tr('vendor.sales.void'),
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
