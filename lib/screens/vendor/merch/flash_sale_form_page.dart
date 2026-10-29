import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../router.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../stock/stock_options.dart';
import 'banner_models.dart' show fromEatWallClock, toEatWallClock;
import 'flash_sale_models.dart';

/// The flash sale form at its own address (spec §8.3):
/// `/vendor/merch/sale/new` (`?productId=` from a product's "Start a flash
/// sale", `?copy=<id>` for "Copy to new") and
/// `/vendor/merch/sale/<id>/edit`. It loads what the form needs (the tool,
/// the vendor's sales and rules, their products), so a refresh brings it
/// back.
class VendorFlashSaleFormRoute extends StatefulWidget {
  const VendorFlashSaleFormRoute({
    super.key,
    this.saleId,
    this.copyId,
    this.productId,
    this.now,
  });

  final String? saleId;
  final String? copyId;
  final String? productId;

  /// The clock (tests).
  final DateTime Function()? now;

  @override
  State<VendorFlashSaleFormRoute> createState() =>
      _VendorFlashSaleFormRouteState();
}

class _VendorFlashSaleFormRouteState extends State<VendorFlashSaleFormRoute> {
  bool _loading = true;
  String? _blocked;
  Object? _error;
  VendorFlashSale? _sale;
  VendorFlashSale? _copy;
  List<Map<String, dynamic>> _products = const [];
  FlashSaleRules _rules = const FlashSaleRules();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _blocked = null;
    });
    final scope = AppScope.of(context);
    final tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    String? blocked;
    if (tools.suspended) {
      blocked = 'merch.suspended';
    } else if (!tools.flashSales) {
      blocked = 'merch.unavailable';
    } else if (!canManageProducts(context)) {
      blocked = 'vendor.noAccess';
    } else if (scope.auth.isPendingApproval &&
        scope.auth.user?['userType'] == 'vendor') {
      blocked = 'merch.pendingTitle';
    }
    if (blocked != null) {
      setState(() {
        _blocked = blocked;
        _loading = false;
      });
      return;
    }
    try {
      final api = scope.api;
      final results = await Future.wait<Object?>([
        api.vendorFlashSales(),
        api.vendorProducts().catchError((Object _) => <dynamic>[]),
      ]);
      if (!mounted) return;
      final list = results[0] as Map<String, dynamic>;
      final sales = [
        for (final m in (list['items'] as List? ?? const []).whereType<Map>())
          VendorFlashSale.fromJson(Map<String, dynamic>.from(m)),
      ];
      Future<VendorFlashSale?> find(String? id) async {
        if (id == null) return null;
        final known = sales.where((s) => s.id == id).firstOrNull;
        if (known != null) return known;
        // Not on the first page: ask for it.
        try {
          final out = await api.vendorFlashSale(id);
          return VendorFlashSale.fromJson(out);
        } on ApiException {
          return null;
        }
      }

      final sale = await find(widget.saleId);
      final copy = await find(widget.copyId);
      if (!mounted) return;
      final vendor = list['vendor'] is Map ? list['vendor'] as Map : const {};
      setState(() {
        _sale = sale;
        _copy = copy;
        _rules = FlashSaleRules.fromJson(list['rules']);
        _products = (results[1] as List)
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        if (widget.saleId != null && sale == null) {
          _blocked = 'merch.notYours';
        } else if (vendor['canPropose'] == false) {
          _blocked = vendor['reason'] == 'vendor_suspended'
              ? 'merch.suspended'
              : 'merch.pendingTitle';
        } else if (sale != null && !sale.canEdit) {
          _blocked = 'merch.sale.notEditable';
        }
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _blocked = e.code == 'feature_disabled' ? 'merch.unavailable' : null;
        _error = _blocked == null ? e : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _back() => context.canPop()
      ? context.pop(false)
      : context.go('${AppRoutes.vendorMerch}?tab=sales');

  @override
  Widget build(BuildContext context) {
    if (!_loading && _blocked == null && _error == null) {
      return VendorFlashSaleFormPage(
        sale: _sale,
        copyFrom: _copy,
        productId: widget.productId,
        products: _products,
        rules: _rules,
        now: widget.now,
      );
    }
    final Widget body;
    if (_loading) {
      body = FFSkeletonList(
        key: const Key('merch-sale-form-loading'),
        semanticLabel: context.tr('common.loading'),
      );
    } else if (_error != null) {
      final offline = isNetworkError(_error!);
      body = FFErrorState(
        key: const Key('merch-sale-form-error'),
        icon: offline ? Icons.wifi_off : Icons.error_outline,
        title: context.tr(offline ? 'merch.offlineTitle' : 'merch.sales.error'),
        onRetry: _load,
      );
    } else {
      body = FFEmptyState(
        key: const Key('merch-sale-form-blocked'),
        icon: Icons.bolt_outlined,
        title: context.tr(_blocked!),
        action: FFButton(
          label: context.tr('merch.back'),
          variant: FFButtonVariant.secondary,
          visualDensity: VisualDensity.standard,
          onPressed: _back,
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(
            widget.saleId == null
                ? 'merch.sale.newTitle'
                : 'merch.sale.editTitle',
          ),
          maxLines: 2,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [body],
      ),
    );
  }
}

/// Digits only, shown with thousands separators ("69,000").
class _ThousandsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final trimmed = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final out = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      if (i > 0 && (trimmed.length - i) % 3 == 0) out.write(',');
      out.write(trimmed[i]);
    }
    final text = out.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

int? _parsePrice(String text) {
  final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.isEmpty ? null : int.tryParse(digits);
}

String _grouped(num v) {
  final s = v.round().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

class VendorFlashSaleFormPage extends StatefulWidget {
  const VendorFlashSaleFormPage({
    super.key,
    this.sale,
    this.copyFrom,
    this.productId,
    required this.products,
    this.rules = const FlashSaleRules(),
    this.now,
  });

  /// The sale being edited; null for a new one.
  final VendorFlashSale? sale;

  /// A past sale whose product and price start a new one.
  final VendorFlashSale? copyFrom;

  /// The product to start with (a product's "Start a flash sale").
  final String? productId;

  /// GET /vendor/products rows, for the picker and the prices.
  final List<Map<String, dynamic>> products;
  final FlashSaleRules rules;

  /// The clock (tests).
  final DateTime Function()? now;

  @override
  State<VendorFlashSaleFormPage> createState() =>
      _VendorFlashSaleFormPageState();
}

class _VendorFlashSaleFormPageState extends State<VendorFlashSaleFormPage> {
  final _price = TextEditingController();
  final Map<String, FocusNode> _focus = {};
  final Map<String, GlobalKey> _anchors = {};
  String? _productId;
  DateTime? _startsAt;
  DateTime? _endsAt;
  String? _saleId;
  String _status = 'draft';
  bool _submitted = false;
  bool _busy = false;
  bool _dirty = false;
  final Map<String, String> _serverErrors = {};

  /// The 14-day rule for the chosen product and start.
  FlashSalePriceCheck? _check;
  bool _checking = false;
  bool _checkFailed = false;
  int _checkRun = 0;

  /// The live % line as a screen reader hears it: 500 ms after typing
  /// stops (spec §11.2), not on every key.
  String _helperSpoken = '';
  Timer? _speak;

  DateTime get _now => (widget.now ?? DateTime.now)().toUtc();

  FocusNode _node(String key) => _focus[key] ??= FocusNode(debugLabel: key);
  GlobalKey _anchor(String key) =>
      _anchors[key] ??= GlobalKey(debugLabel: 'merch-sale-anchor-$key');

  bool get _editing => widget.sale != null;

  @override
  void initState() {
    super.initState();
    final source = widget.sale ?? widget.copyFrom;
    if (source != null) {
      _productId = source.productId;
      _price.text = _grouped(source.salePriceTzs);
    } else if (widget.productId != null &&
        _eligible.any((p) => p['id']?.toString() == widget.productId)) {
      _productId = widget.productId;
    }
    if (widget.sale case final s?) {
      _saleId = s.id;
      _status = s.status;
      _startsAt = s.startsAt;
      _endsAt = s.endsAt;
    }
    var last = _price.text;
    _price.addListener(() {
      if (_price.text == last) return;
      last = _price.text;
      setState(() {
        _dirty = true;
        _serverErrors.remove('price');
      });
      _speak?.cancel();
      _speak = Timer(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _helperSpoken = _helperText(context) ?? '');
      });
    });
    if (_productId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _runCheck());
    }
  }

  @override
  void dispose() {
    _speak?.cancel();
    _price.dispose();
    for (final n in _focus.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Products a sale may be put on: the vendor's active, approved ones (out
  /// of stock allowed, with a warning). Editing keeps its own product.
  List<Map<String, dynamic>> get _eligible => widget.products.where((p) {
    final status = p['status']?.toString() ?? 'active';
    final approval = p['approvalStatus']?.toString() ?? 'approved';
    return status == 'active' && approval == 'approved';
  }).toList();

  Map<String, dynamic>? get _product => _productId == null
      ? null
      : widget.products
            .where((p) => p['id']?.toString() == _productId)
            .firstOrNull;

  num? _n(Object? v) => v is num ? v : num.tryParse('${v ?? ''}');

  /// The regular price: the price check's, else the product row's, else
  /// the sale's own.
  num? get _regular =>
      _check?.regularPriceTzs ??
      _n(_product?['priceTzs']) ??
      (widget.sale ?? widget.copyFrom)?.regularPriceTzs;

  num? get _discount {
    final regular = _regular;
    if (regular == null) return null;
    return standingDiscount(
      regular,
      _check?.discountPriceTzs ?? _n(_product?['discountPriceTzs']),
    );
  }

  String get _lang => FFLocaleScope.of(context).locale.languageCode;
  String _money(Object? v) => v is num ? formatCurrency(v) : '-';
  String _when(DateTime? at) =>
      at == null ? '-' : formatDateTime(toEatWallClock(at), locale: _lang);

  /// "24% off · buyers save TSh 16,000" while the price is valid.
  String? _helperText(BuildContext context) {
    final regular = _regular;
    final sale = _parsePrice(_price.text);
    if (regular == null || sale == null) return null;
    if (flashSalePriceProblem(
          regular: regular,
          discount: _discount,
          sale: sale,
          minPct: widget.rules.minDiscountPct,
        ) !=
        null) {
      return null;
    }
    return context
        .tr('merch.sale.live')
        .replaceAll('{pct}', '${flashSalePercent(regular, sale)}')
        .replaceAll('{saving}', formatCurrency(regular - sale));
  }

  String? _priceError(BuildContext context) {
    final regular = _regular;
    if (regular == null) return null;
    final problem = flashSalePriceProblem(
      regular: regular,
      discount: _discount,
      sale: _parsePrice(_price.text),
      minPct: widget.rules.minDiscountPct,
    );
    return switch (problem) {
      'enterPrice' => context.tr('merch.sale.enterPrice'),
      'min5' =>
        context
            .tr('merch.sale.min5')
            .replaceAll(
              '{max}',
              formatCurrency(
                flashSaleMaxPrice(regular, minPct: widget.rules.minDiscountPct),
              ),
            ),
      'belowDiscount' =>
        context
            .tr('merch.sale.belowDiscount')
            .replaceAll('{discount}', formatCurrency(_discount!)),
      _ => null,
    };
  }

  String? _datesError() {
    final problem = flashSaleDatesProblem(
      startsAt: _startsAt,
      endsAt: _endsAt,
      now: _now,
      rules: widget.rules,
    );
    return problem;
  }

  /// Every client-side problem, in focus order (key → message).
  Map<String, String> _errors() {
    final out = <String, String>{};
    if (_productId == null) {
      out['product'] = context.tr(
        _eligible.isEmpty
            ? 'merch.sale.noProducts'
            : 'merch.sale.productRequired',
      );
    }
    final price = _priceError(context);
    if (price != null) out['price'] = price;
    if (_productId != null &&
        _regular == null &&
        _parsePrice(_price.text) == null) {
      out['price'] = context.tr('merch.sale.enterPrice');
    }
    switch (_datesError()) {
      case 'required':
        if (_startsAt == null) {
          out['startsAt'] = context.tr('merch.dates.required');
        }
        if (_endsAt == null) {
          out['endsAt'] = context.tr('merch.dates.required');
        }
      case 'startSoon':
        out['startsAt'] = context.tr('merch.dates.startSoon');
      case 'endAfter':
        out['endsAt'] = context.tr('merch.dates.endAfter');
      case 'length':
        out['endsAt'] = context.tr('merch.sale.length');
    }
    return out;
  }

  String? _errorFor(String key) {
    final server = _serverErrors[key];
    if (server != null) return server;
    if (!_submitted) {
      // The price is checked as it is typed (spec §8.3 live helper).
      if (key == 'price' && _price.text.isNotEmpty) return _priceError(context);
      return null;
    }
    return _errors()[key];
  }

  /// The 14-day rule (and another sale on the product) as soon as the
  /// product and start are known. Send stays off until it passes.
  Future<void> _runCheck() async {
    final productId = _productId;
    if (productId == null) return;
    final run = ++_checkRun;
    setState(() {
      _checking = true;
      _checkFailed = false;
    });
    try {
      final out = await AppScope.of(
        context,
      ).api.vendorFlashSalePriceCheck(productId, startsAt: _startsAt);
      if (!mounted || run != _checkRun) return;
      setState(() {
        _check = FlashSalePriceCheck.fromJson(out);
        _checking = false;
      });
      if (_check!.raised) {
        // Announced once when it appears (polite).
        SemanticsService.sendAnnouncement(
          View.of(context),
          _raisedText(_check!.raisedOn, _check!.earliestStart),
          Directionality.of(context),
        );
      }
    } catch (_) {
      if (!mounted || run != _checkRun) return;
      setState(() {
        _checking = false;
        _checkFailed = true;
      });
    }
  }

  String _raisedText(DateTime? raisedOn, DateTime? earliest) => context
      .tr('merch.sale.raised')
      .replaceAll(
        '{date}',
        raisedOn == null ? '-' : formatDate(raisedOn, locale: _lang),
      )
      .replaceAll('{earliest}', _when(earliest));

  /// The check says this sale may not go ahead as set. An edited sale's
  /// own lock (`lockedBy` = itself) is not a clash.
  bool get _checkBlocks {
    final c = _check;
    if (c == null) return _checking || _checkFailed;
    if (c.raised) {
      final start = _startsAt;
      return start == null || start.isBefore(c.earliestStart!);
    }
    return false;
  }

  Future<void> _pickDate(bool start) async {
    final current = start ? _startsAt : _endsAt;
    final base = toEatWallClock(
      current ??
          (start
              ? _now.add(const Duration(days: 1))
              : (_startsAt ?? _now.add(const Duration(days: 1))).add(
                  const Duration(days: 1),
                )),
    );
    final today = toEatWallClock(_now);
    final day = await showDatePicker(
      context: context,
      initialDate: base.isBefore(today) ? today : base,
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 1, today.month, today.day),
      helpText: context.tr(start ? 'merch.sale.starts' : 'merch.sale.ends'),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: base.hour, minute: base.minute),
      helpText: context.tr('merch.dates.tzNote'),
    );
    if (time == null || !mounted) return;
    _setDate(
      start,
      fromEatWallClock(day.year, day.month, day.day, time.hour, time.minute),
    );
  }

  void _setDate(bool start, DateTime at) {
    setState(() {
      _dirty = true;
      if (start) {
        _startsAt = at;
        _serverErrors.remove('startsAt');
        _serverErrors.remove('raised');
      } else {
        _endsAt = at;
        _serverErrors.remove('endsAt');
      }
    });
    if (start) _runCheck();
  }

  /// "Start on {date}": the earliest start the 14-day rule allows, keeping
  /// the sale's length when an end was set.
  void _startOnEarliest(DateTime earliest) {
    final length = _startsAt != null && _endsAt != null
        ? _endsAt!.difference(_startsAt!)
        : null;
    _setDate(true, earliest);
    if (length != null && !length.isNegative) {
      setState(() => _endsAt = earliest.add(length));
    }
  }

  void _focusFirst(Iterable<String> keys) {
    const order = ['product', 'price', 'startsAt', 'endsAt', 'raised'];
    final set = keys.toSet();
    final first = order.firstWhere(set.contains, orElse: () => '');
    if (first.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final anchor = _anchors[first]?.currentContext;
      if (anchor != null && anchor.mounted) {
        Scrollable.ensureVisible(
          anchor,
          alignment: 0.1,
          duration: MediaQuery.disableAnimationsOf(anchor)
              ? Duration.zero
              : FFTokens.motionMedium,
        );
      }
      _focus[first]?.requestFocus();
    });
  }

  Map<String, dynamic> _body() => {
    if (!_editing) 'productId': _productId,
    'salePriceTzs': _parsePrice(_price.text),
    'startsAt': _startsAt!.toUtc().toIso8601String(),
    'endsAt': _endsAt!.toUtc().toIso8601String(),
  };

  Future<void> _send() async {
    if (_busy) return;
    setState(() {
      _submitted = true;
      _serverErrors.clear();
    });
    final errors = _errors();
    if (errors.isNotEmpty) {
      _focusFirst(errors.keys);
      return;
    }
    if (_checkBlocks) {
      _focusFirst(const ['raised']);
      return;
    }
    // Changing a scheduled sale sends it back for approval.
    if (_saleId != null && _status == 'approved') {
      final ok = await showFFConfirmDialog(
        context,
        title: context.tr('merch.sale.resend.title'),
        message: context.tr('merch.sale.resend.body'),
        confirmLabel: context.tr('merch.resend.confirm'),
        cancelLabel: context.tr('merch.resend.keep'),
        confirmKey: const Key('merch-sale-resend-confirm'),
      );
      if (!ok || !mounted) return;
    }
    final api = AppScope.of(context).api;
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy = true);
    try {
      Map<String, dynamic> saved;
      if (_saleId == null) {
        saved = await api.vendorCreateFlashSale(_body());
        _saleId = saved['id']?.toString();
        if (_saleId == null || _saleId!.isEmpty) throw ApiException(500, null);
      } else {
        saved = await api.vendorUpdateFlashSale(_saleId!, _body());
      }
      _status =
          (saved['effectiveStatus'] ?? saved['status'])?.toString() ?? _status;
      // A draft (new, or a rejected one that was edited) is sent; a pending
      // one stays pending; a scheduled one went back to pending by itself.
      if (_status == 'draft') {
        final out = await api.vendorSubmitFlashSale(_saleId!);
        _status =
            (out['effectiveStatus'] ?? out['status'])?.toString() ??
            'pending_approval';
      }
      if (!mounted) return;
      messenger.success(locale.t('merch.sent'));
      _dirty = false;
      _leave(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      final err = flashSaleError(e);
      if (err.target == 'message') {
        messenger.error(locale.t(err.key));
        if (err.closes) {
          _dirty = false;
          _leave(true);
        }
        return;
      }
      setState(() {
        if (err.target == 'raised') {
          _check = FlashSalePriceCheck(
            ok: false,
            regularPriceTzs: _check?.regularPriceTzs,
            discountPriceTzs: _check?.discountPriceTzs,
            raisedOn: FlashSalePriceCheck.day(err.params['raisedOn']),
            earliestStart: DateTime.tryParse(
              '${err.params['earliestStart'] ?? ''}',
            )?.toUtc(),
          );
        } else {
          _serverErrors[err.target] = _fill(err);
        }
      });
      _focusFirst([err.target]);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.error(
        locale.t(
          isNetworkError(e) || e is TimeoutException
              ? 'merch.notSentOffline'
              : 'merch.saveFailed',
        ),
      );
    }
  }

  String _fill(FlashSaleError err) {
    DateTime? d(Object? v) => DateTime.tryParse('${v ?? ''}')?.toUtc();
    final text = context
        .tr(err.key)
        .replaceAll('{max}', _money(err.params['max']))
        .replaceAll('{discount}', _money(err.params['discount']));
    if (err.key == 'merch.sale.overlap') {
      final start = d(err.params['start']);
      final end = d(err.params['end']);
      if (start == null || end == null) {
        return context.tr('merch.sale.overlapNoDates');
      }
      return text
          .replaceAll('{start}', _when(start))
          .replaceAll('{end}', _when(end));
    }
    return text;
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty || _busy) return !_busy;
    return showFFConfirmDialog(
      context,
      title: context.tr('merch.discard.title'),
      confirmLabel: context.tr('merch.discard.confirm'),
      cancelLabel: context.tr('merch.discard.keep'),
      destructive: true,
      confirmKey: const Key('merch-sale-discard-confirm'),
    );
  }

  Future<void> _cancel() async {
    if (await _confirmDiscard() && mounted) {
      _dirty = false;
      _leave(false);
    }
  }

  void _leave(bool sent) {
    final nav = Navigator.of(context);
    if (nav.canPop()) {
      nav.pop(sent);
    } else {
      context.go('${AppRoutes.vendorMerch}?tab=sales');
    }
  }

  // ── Building blocks ────────────────────────────────────────────────────

  Widget _label(BuildContext context, String text, {String? help}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        top: FFTokens.spacingMd,
        bottom: FFTokens.spacingSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (help != null) ...[
            const SizedBox(height: FFTokens.spacing2xs),
            Text(help, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }

  Widget _error(String key) {
    final message = _errorFor(key);
    if (message == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: FFTokens.spacingXs),
      child: Semantics(
        liveRegion: true,
        child: Text(
          message,
          key: Key('merch-sale-error-$key'),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ),
    );
  }

  Widget _productField(BuildContext context) {
    final eligible = _eligible;
    final product = _product;
    final theme = Theme.of(context);
    final stock = _n(product?['stock']) ?? 0;
    return KeyedSubtree(
      key: _anchor('product'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, context.tr('merch.sale.product')),
          if (_editing)
            // The product can't change after create (make a new sale).
            Text(
              product?['name']?.toString() ?? widget.sale!.productName,
              key: const Key('merch-sale-product-name'),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            )
          else
            Focus(
              focusNode: _node('product'),
              skipTraversal: true,
              child: eligible.isEmpty
                  ? Text(
                      context.tr('merch.sale.noProducts'),
                      key: const Key('merch-sale-no-products'),
                    )
                  : FFDropdownField<String>(
                      key: const Key('merch-sale-product'),
                      value: eligible.any((p) => p['id'] == _productId)
                          ? _productId
                          : null,
                      label: context.tr('merch.sale.product'),
                      isExpanded: true,
                      items: [
                        for (final p in eligible)
                          DropdownMenuItem(
                            value: p['id']?.toString(),
                            child: Text(
                              p['name']?.toString() ?? '',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        if (_busy) return;
                        setState(() {
                          _productId = v;
                          _check = null;
                          _dirty = true;
                          _serverErrors.remove('product');
                          _serverErrors.remove('price');
                        });
                        _runCheck();
                      },
                    ),
            ),
          _error('product'),
          if (product != null && stock <= 0) ...[
            const SizedBox(height: FFTokens.spacingSm),
            FFAlert(
              key: const Key('merch-sale-oos'),
              tone: FFAlertTone.warning,
              message: context.tr('merch.sale.oos'),
            ),
          ],
          if (_check?.locked == true &&
              !_editing &&
              _check!.lockedStartsAt != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            FFAlert(
              key: const Key('merch-sale-locked'),
              tone: FFAlertTone.warning,
              message: context
                  .tr('merch.sale.overlap')
                  .replaceAll('{start}', _when(_check!.lockedStartsAt))
                  .replaceAll('{end}', _when(_check!.lockedEndsAt)),
            ),
          ],
          if (_regular != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(
              context
                  .tr('merch.sale.regular')
                  .replaceAll('{price}', formatCurrency(_regular!)),
              key: const Key('merch-sale-regular'),
            ),
            if (_discount != null)
              Text(
                context
                    .tr('merch.sale.currentDiscount')
                    .replaceAll('{price}', formatCurrency(_discount!)),
                key: const Key('merch-sale-current-discount'),
              ),
          ],
        ],
      ),
    );
  }

  Widget _priceField(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final helper = _helperText(context);
    final error = _errorFor('price');
    return KeyedSubtree(
      key: _anchor('price'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, context.tr('merch.sale.price')),
          FFTextField(
            key: const Key('merch-sale-price'),
            controller: _price,
            focusNode: _node('price'),
            enabled: !_busy,
            label: context.tr('merch.sale.price'),
            keyboardType: TextInputType.number,
            inputFormatters: [_ThousandsFormatter()],
            prefixIcon: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Text('TSh'),
            ),
          ),
          if (helper != null && error == null)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingXs),
              // The words change as they type; a screen reader hears them
              // 500 ms after typing stops.
              child: Semantics(
                liveRegion: true,
                label: _helperSpoken,
                child: ExcludeSemantics(
                  child: Text(
                    helper,
                    key: const Key('merch-sale-helper'),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: dark ? FFTokens.fuelOnDark : FFTokens.fuel,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          _error('price'),
        ],
      ),
    );
  }

  Widget _dateField(BuildContext context, bool start) {
    final key = start ? 'startsAt' : 'endsAt';
    final at = start ? _startsAt : _endsAt;
    final name = context.tr(start ? 'merch.sale.starts' : 'merch.sale.ends');
    final text = at == null ? context.tr('merch.dates.pick') : _when(at);
    return KeyedSubtree(
      key: _anchor(key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _label(context, name, help: context.tr('merch.dates.tzNote')),
          Focus(
            focusNode: _node(key),
            skipTraversal: true,
            child: FFButton(
              key: Key('merch-sale-$key'),
              label: text,
              icon: Icons.event_outlined,
              variant: FFButtonVariant.secondary,
              fullWidth: true,
              visualDensity: VisualDensity.standard,
              maxLines: 2,
              semanticLabel:
                  '$name, $text, ${context.tr('merch.dates.tzNote')}',
              onPressed: _busy ? null : () => _pickDate(start),
            ),
          ),
          _error(key),
        ],
      ),
    );
  }

  /// The 14-day rule's line above the buttons (spec §8.3).
  Widget _ruleCheck(BuildContext context) {
    final c = _check;
    return KeyedSubtree(
      key: _anchor('raised'),
      child: Padding(
        padding: const EdgeInsets.only(top: FFTokens.spacingMd),
        child: _checking
            ? Text(
                context.tr('merch.sale.checking'),
                key: const Key('merch-sale-checking'),
              )
            : _checkFailed
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FFAlert(
                    key: const Key('merch-sale-check-failed'),
                    tone: FFAlertTone.warning,
                    message: context.tr('merch.sale.checkFailed'),
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FFButton(
                      key: const Key('merch-sale-check-retry'),
                      label: context.tr('common.retry'),
                      variant: FFButtonVariant.ghost,
                      visualDensity: VisualDensity.standard,
                      onPressed: _runCheck,
                    ),
                  ),
                ],
              )
            : c != null && c.raised && _checkBlocks
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FFAlert(
                    key: const Key('merch-sale-raised'),
                    tone: FFAlertTone.error,
                    message: _raisedText(c.raisedOn, c.earliestStart),
                  ),
                  const SizedBox(height: FFTokens.spacingXs),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Focus(
                      focusNode: _node('raised'),
                      skipTraversal: true,
                      child: FFButton(
                        key: const Key('merch-sale-start-on'),
                        label: context
                            .tr('merch.sale.startOn')
                            .replaceAll('{date}', _when(c.earliestStart)),
                        variant: FFButtonVariant.secondary,
                        visualDensity: VisualDensity.standard,
                        maxLines: 2,
                        onPressed: _busy
                            ? null
                            : () => _startOnEarliest(c.earliestStart!),
                      ),
                    ),
                  ),
                ],
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sendBlocked = _busy || (_productId != null && _checkBlocks);
    return PopScope(
      canPop: !_dirty && !_busy,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          _dirty = false;
          _leave(false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            context.tr(
              _editing ? 'merch.sale.editTitle' : 'merch.sale.newTitle',
            ),
            key: const Key('merch-sale-form-title'),
            maxLines: 2,
          ),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _productField(context),
                  _priceField(context),
                  _dateField(context, true),
                  _dateField(context, false),
                  if (_productId != null) _ruleCheck(context),
                  const SizedBox(height: FFTokens.spacingMd),
                  FFAlert(
                    key: const Key('merch-sale-notes'),
                    message: [
                      context.tr('merch.sale.youPay'),
                      context.tr('merch.sale.rule14'),
                      context.tr('merch.sale.reviewNote'),
                    ].join('\n\n'),
                  ),
                  const SizedBox(height: FFTokens.spacingLg),
                  FFButton(
                    key: const Key('merch-sale-send'),
                    label: context.tr('merch.send'),
                    fullWidth: true,
                    maxLines: 2,
                    visualDensity: VisualDensity.standard,
                    loading: _busy,
                    onPressed: sendBlocked ? null : _send,
                  ),
                  const SizedBox(height: FFTokens.spacingXs),
                  FFButton(
                    key: const Key('merch-sale-cancel'),
                    label: context.tr('common.cancel'),
                    variant: FFButtonVariant.ghost,
                    fullWidth: true,
                    visualDensity: VisualDensity.standard,
                    onPressed: _busy ? null : _cancel,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
