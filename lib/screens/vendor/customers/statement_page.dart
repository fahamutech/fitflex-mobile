// Vendor tools · S4: a customer statement (spec §7.3) — open pay-later
// sales, the last 90 days' payments, total owed and the aging line, as
// plain text shared by the vendor themselves. FitFlex never sends it to the
// customer. No phone, email or address of the customer is ever in it.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../sales/receipt_page.dart' show shareReceipt;
import '../sales/sales_widgets.dart' show ReceiptLanguageToggle;
import '../stock/stock_options.dart';
import 'customer_models.dart';
import 'customers_widgets.dart';
import 'payment_sheets.dart' show loadBusinessName;

class StatementPage extends StatefulWidget {
  const StatementPage({super.key, required this.customerId, this.now});

  final String customerId;
  final DateTime Function()? now;

  @override
  State<StatementPage> createState() => _StatementPageState();
}

class _StatementPageState extends State<StatementPage> {
  Map<String, dynamic>? _customer;
  List<Map> _payments = [];
  String? _business;
  bool _loading = true;
  CustomerLoadProblem _problem = CustomerLoadProblem.none;
  String? _lang;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final tools = await enterCustomersRoute(context);
    if (tools == null || !mounted) return;
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = CustomerLoadProblem.none;
    });
    final api = AppScope.of(context).api;
    final from = addDaysTo(
      eatTodayString(widget.now?.call()),
      -statementPaymentDays,
    );
    try {
      final business = loadBusinessName(context);
      final res = await api.vendorCustomer(widget.customerId);
      final c = res['customer'];
      if (c is! Map) throw ApiException(404, null);
      final pays = await api.vendorCustomerPayments(
        widget.customerId,
        from: from,
        limit: 200,
      );
      final b = await business;
      if (!mounted) return;
      setState(() {
        _customer = Map<String, dynamic>.from(c);
        _payments = (pays['payments'] as List? ?? []).whereType<Map>().toList();
        _business = b;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _problem = problemOf(e);
        });
      }
    }
  }

  String _text(String lang) {
    final locale = FFLocaleScope.of(context);
    return statementShareText(
      customer: _customer!,
      payments: _payments,
      business: _business,
      t: (k) => locale.tIn(lang, k),
      lang: lang,
    );
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(customerRoute(widget.customerId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = FFLocaleScope.of(context);
    final lang = _lang ?? locale.locale.languageCode;
    final c = _customer;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(
          c == null
              ? context.tr('vendor.statement.share')
              : fillIn(context.tr('vendor.statement.title'), {
                  'name': customerDisplayName(c, context.tr),
                }),
        ),
      ),
      body: _loading
          ? const Center(child: FFSpinner())
          : c == null
          ? ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                customerErrorState(
                  context,
                  _problem,
                  failedKey: 'vendor.customers.failed',
                  onRetry: _load,
                ),
              ],
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  children: [
                    FFCard(
                      key: const Key('statement-preview'),
                      child: SelectableText(
                        _text(lang),
                        style: const TextStyle(
                          fontFamily: 'JetBrains Mono',
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                    ReceiptLanguageToggle(
                      value: lang,
                      onChanged: (v) => setState(() => _lang = v),
                    ),
                    const SizedBox(height: FFTokens.spacingMd),
                    FFButton(
                      key: const Key('statement-share'),
                      label: context.tr('vendor.statement.share'),
                      icon: Icons.share,
                      fullWidth: true,
                      visualDensity: VisualDensity.standard,
                      onPressed: () => shareReceipt(
                        _text(lang),
                        fillIn(locale.tIn(lang, 'vendor.statement.title'), {
                          'name': customerDisplayName(
                            c,
                            (k) => locale.tIn(lang, k),
                          ),
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
