// Vendor tools · S1: one product's stock history — every change, why, by
// whom, and the stock before and after (GET
// /vendor/products/:id/stock-movements). Route: /vendor/products/:id/stock.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/tone_theme.dart';
import 'adjust_stock_sheet.dart';
import 'stock_options.dart';

/// Where "back" goes when there is nothing to go back to (opened from a
/// notification): the products, showing the low ones.
const vendorLowProductsRoute = '/vendor/home?open=products&filter=low';

enum _Problem { none, failed, network, notFound, notAllowed }

class StockHistoryPage extends StatefulWidget {
  const StockHistoryPage({
    super.key,
    required this.productId,
    this.variant,
    this.fromPush = false,
  });

  final String productId;

  /// The variant a notification was about; "Adjust stock" starts on it.
  final String? variant;
  final bool fromPush;

  @override
  State<StockHistoryPage> createState() => _StockHistoryPageState();
}

class _StockHistoryPageState extends State<StockHistoryPage> {
  Map<String, dynamic>? _product;
  LowStockIndex _low = LowStockIndex.empty();
  final List<Map<String, dynamic>> _rows = [];
  num? _opening;
  num? _closing;
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreFailed = false;
  _Problem _problem = _Problem.none;
  String _range = '30d';
  DateTimeRange? _custom;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted) return;
    if (!canManageProducts(context)) {
      FFSnack.error(context, context.tr('vendor.stock.noProductsAccess'));
      context.go('/vendor/home');
      return;
    }
    final tools = await VendorToolsOptions.of(context);
    if (!mounted) return;
    if (!tools.stockLedger) {
      context.go('/vendor/home?open=products');
      return;
    }
    await _load();
  }

  (String, String) get _period {
    final today = eatToday();
    if (_range == 'custom' && _custom != null) {
      return (eatDay(_custom!.start), eatDay(_custom!.end));
    }
    final days = _range == '7d' ? 6 : 29;
    return (eatDay(today.subtract(Duration(days: days))), eatDay(today));
  }

  _Problem _problemOf(Object e) {
    if (e is ApiException) {
      if (e.status == 404 && e.code != 'feature_disabled') {
        return _Problem.notFound;
      }
      if (e.status == 403) return _Problem.notAllowed;
      return _Problem.failed;
    }
    return _Problem.network;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _problem = _Problem.none;
      _moreFailed = false;
    });
    final api = AppScope.of(context).api;
    final (from, to) = _period;
    try {
      final results = await Future.wait<Object?>([
        api.vendorProducts(),
        api
            .vendorLowStock()
            .then<Object?>((v) => v)
            .catchError((Object _) => <dynamic>[]),
        api.vendorStockMovements(widget.productId, from: from, to: to),
      ]);
      if (!mounted) return;
      final product = (results[0] as List).whereType<Map>().firstWhere(
        (p) => p['id']?.toString() == widget.productId,
        orElse: () => const {},
      );
      final page = results[2] as Map<String, dynamic>;
      setState(() {
        _loading = false;
        if (product.isEmpty) {
          _problem = _Problem.notFound;
          return;
        }
        _product = Map<String, dynamic>.from(product);
        _low = LowStockIndex(results[1] as List? ?? const []);
        _rows
          ..clear()
          ..addAll(_rowsOf(page));
        _opening = page['openingStock'] as num?;
        _closing = page['closingStock'] as num?;
        _cursor = page['nextCursor']?.toString();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = _problemOf(e);
      });
    }
  }

  List<Map<String, dynamic>> _rowsOf(Map<String, dynamic> page) =>
      (page['rows'] as List? ?? const [])
          .whereType<Map>()
          .map(Map<String, dynamic>.from)
          .toList();

  Future<void> _loadMore() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    final (from, to) = _period;
    try {
      final page = await AppScope.of(context).api.vendorStockMovements(
        widget.productId,
        from: from,
        to: to,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _rows.addAll(_rowsOf(page));
        _cursor = page['nextCursor']?.toString();
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _moreFailed = true;
      });
    }
  }

  Future<void> _pickRange(String value) async {
    if (value == 'custom') {
      final today = eatToday();
      final last = DateTime(today.year, today.month, today.day);
      final picked = await showDateRangePicker(
        context: context,
        firstDate: last.subtract(const Duration(days: 730)),
        lastDate: last,
        initialDateRange: _custom,
      );
      if (picked == null || !mounted) return;
      _custom = picked;
    }
    setState(() => _range = value);
    await _load();
  }

  Future<void> _adjust() async {
    final product = _product;
    if (product == null) return;
    final result = await openAdjustStock(
      context,
      product: product,
      variant: widget.variant,
    );
    if (result == null || !mounted) return;
    setState(() => _product = withAdjustedStock(product, result.product));
    await _load();
  }

  void _back() {
    if (!widget.fromPush && context.canPop()) {
      context.pop();
    } else {
      context.go(vendorLowProductsRoute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = _product?['name']?.toString() ?? '';
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr('vendor.stock.history')),
            if (name.isNotEmpty)
              Semantics(
                label: name,
                excludeSemantics: true,
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: _body(context),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          const FFSkeletonCard(),
          const SizedBox(height: FFTokens.spacingMd),
          FFSkeletonList(
            count: 5,
            semanticLabel: context.tr('vendor.stock.loading'),
          ),
        ],
      );
    }
    if (_problem != _Problem.none) {
      final gone =
          _problem == _Problem.notFound || _problem == _Problem.notAllowed;
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFErrorState(
            key: const Key('stock-history-error'),
            message: context.tr(switch (_problem) {
              _Problem.notFound => 'vendor.stock.notFound',
              _Problem.notAllowed => 'vendor.stock.notAllowed',
              _Problem.network => 'error.network',
              _ => 'vendor.stock.historyFailed',
            }),
            onRetry: gone
                ? () => context.go('/vendor/home?open=products')
                : _load,
            retryLabel: context.tr(
              gone ? 'vendor.stock.backToProducts' : 'common.retry',
            ),
          ),
        ],
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final header = _header(context, wide);
    final range = _rangePicker(context);
    return ListView(
      key: const Key('stock-history-list'),
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: header),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(child: range),
            ],
          )
        else ...[
          header,
          const SizedBox(height: FFTokens.spacingMd),
          range,
        ],
        const SizedBox(height: FFTokens.spacingMd),
        Row(
          children: [
            Expanded(
              child: FFStatTile(
                key: const Key('stock-opening'),
                icon: Icons.first_page,
                value: formatStock(_opening ?? 0),
                label: context.tr('vendor.stock.opening'),
              ),
            ),
            const SizedBox(width: FFTokens.spacingSm),
            Expanded(
              child: FFStatTile(
                key: const Key('stock-closing'),
                icon: Icons.last_page,
                value: formatStock(_closing ?? 0),
                label: context.tr('vendor.stock.closing'),
              ),
            ),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (_rows.isEmpty)
          FFEmptyState(
            key: const Key('stock-history-empty'),
            icon: Icons.history,
            title: context.tr('vendor.stock.historyEmpty'),
            action: FFButton(
              label: context.tr('vendor.stock.adjust'),
              onPressed: _adjust,
            ),
          ),
        for (final row in _rows) _rowTile(context, row),
        if (_moreFailed) ...[
          FFAlert(
            key: const Key('stock-more-failed'),
            message: context.tr('vendor.stock.historyFailed'),
            tone: FFAlertTone.error,
          ),
          const SizedBox(height: FFTokens.spacingSm),
        ],
        if (_cursor != null)
          FFButton(
            key: const Key('stock-load-more'),
            label: context.tr(
              _moreFailed ? 'common.retry' : 'vendor.stock.loadMore',
            ),
            variant: FFButtonVariant.ghost,
            loading: _loadingMore,
            fullWidth: true,
            onPressed: _loadMore,
          ),
      ],
    );
  }

  Widget _header(BuildContext context, bool wide) {
    final theme = Theme.of(context);
    final product = _product!;
    final id = widget.productId;
    final reorder = product['reorderLevel'];
    final variants = trackedVariants(product);
    final lowVariants = _low.lowVariants(id).toSet();
    return FFCard(
      key: const Key('stock-header'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('vendor.stock.current'),
            style: theme.textTheme.labelMedium,
          ),
          Wrap(
            spacing: FFTokens.spacingSm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                formatStock(product['stock'] as num? ?? 0),
                key: const Key('stock-current'),
                style: theme.textTheme.titleLarge,
              ),
              if (_low.productLow(id) || (variants.isEmpty && _low.isLow(id)))
                FFBadge(
                  key: const Key('stock-low-badge'),
                  label: context.tr('vendor.stock.lowBadge'),
                  tone: FFBadgeTone.warning,
                ),
            ],
          ),
          Text(
            '${context.tr('vendor.stock.reorderLevel')}: '
            '${reorder is num ? formatStock(reorder) : '—'}',
            style: theme.textTheme.bodySmall,
          ),
          if (variants.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingSm),
            for (final v in variants)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingXs),
                child: Wrap(
                  spacing: FFTokens.spacingSm,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${v.name} · ${formatStock(v.stock)}'),
                    if (lowVariants.contains(v.name))
                      FFBadge(
                        label: context.tr('vendor.stock.lowBadge'),
                        tone: FFBadgeTone.warning,
                      ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: FFTokens.spacingSm),
          Align(
            alignment: wide
                ? AlignmentDirectional.centerEnd
                : AlignmentDirectional.centerStart,
            child: FFButton(
              key: const Key('stock-adjust'),
              label: context.tr('vendor.stock.adjust'),
              icon: Icons.tune,
              fullWidth: !wide,
              onPressed: _adjust,
            ),
          ),
        ],
      ),
    );
  }

  Widget _rangePicker(BuildContext context) => FFSegmented(
    key: const Key('stock-range'),
    value: _range,
    options: [
      ('7d', context.tr('vendor.stock.range.7d')),
      ('30d', context.tr('vendor.stock.range.30d')),
      ('custom', context.tr('vendor.stock.range.custom')),
    ],
    onChanged: _pickRange,
  );

  String _when(String? createdAt) {
    final at = DateTime.tryParse(createdAt ?? '');
    if (at == null) return '';
    final eat = at.toUtc().add(const Duration(hours: 3));
    final lang = FFLocaleScope.of(context).locale.languageCode;
    try {
      return DateFormat('d MMM, HH:mm', lang).format(eat);
    } catch (_) {
      return DateFormat('d MMM, HH:mm').format(eat);
    }
  }

  Widget _rowTile(BuildContext context, Map<String, dynamic> row) {
    final theme = Theme.of(context);
    final tones = FFToneTheme.of(context);
    final id = row['id']?.toString() ?? '';
    final delta = (row['delta'] as num?) ?? 0;
    final reason = stockReasonLabel(context, row['reason']?.toString());
    final variant = row['variant']?.toString() ?? '';
    final before = row['stockBefore'] as num?;
    final after = row['stockAfter'] as num?;
    final actor = row['actor'] is Map
        ? (row['actor'] as Map)['name']?.toString()
        : null;
    final who = row['actor'] is Map
        ? fillIn(context.tr('vendor.stock.by'), {'name': actor ?? '—'})
        : context.tr('vendor.stock.bySystem');
    final when = _when(row['createdAt']?.toString());
    final note = stockNoteLabel(context, row['note']?.toString());
    final doc = row['document'] is Map ? row['document'] as Map : null;
    final title = variant.isEmpty ? reason : '$reason · $variant';
    final beforeAfter = before == null || after == null
        ? null
        : '${formatStock(before)} → ${formatStock(after)}';
    final deltaWords = fillIn(
      context.tr(delta >= 0 ? 'vendor.stock.deltaIn' : 'vendor.stock.deltaOut'),
      {'n': formatStock(delta.abs())},
    );
    final label = fillIn(context.tr('vendor.stock.rowLabel'), {
      'reason': title,
      'delta': deltaWords,
      'before': before == null ? '—' : formatStock(before),
      'after': after == null ? '—' : formatStock(after),
      'time': when,
      'actor': who,
    });
    Widget? orderLink;
    if (doc != null && doc['type'] == 'order') {
      final docId = doc['id']?.toString() ?? '';
      final ref = (doc['number']?.toString().isNotEmpty ?? false)
          ? doc['number'].toString()
          : (docId.length > 8 ? docId.substring(docId.length - 8) : docId);
      final text = fillIn(context.tr('vendor.stock.order'), {'ref': ref});
      orderLink = canVendor(context, 'orders')
          ? FFButton(
              key: Key('stock-order-$id'),
              label: text,
              variant: FFButtonVariant.ghost,
              size: FFButtonSize.sm,
              onPressed: () => context.go('/vendor/home?open=orders'),
            )
          : Text(text, style: theme.textTheme.bodySmall);
    }
    final expanded = _expanded.contains(id);
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        key: Key('stock-row-$id'),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                label: label,
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(title, style: theme.textTheme.titleSmall),
                        ),
                        Text(
                          formatDelta(delta),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: delta > 0
                                ? tones.success.fg
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      [
                        ?beforeAfter,
                        when,
                        who,
                      ].where((s) => s.isNotEmpty).join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (note != null)
                InkWell(
                  onTap: () => setState(
                    () => expanded ? _expanded.remove(id) : _expanded.add(id),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.only(top: FFTokens.spacingXs),
                    child: Text(
                      note,
                      maxLines: expanded ? null : 3,
                      overflow: expanded ? null : TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
              if (orderLink != null)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: orderLink,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Stored variants with the counts from an adjustment's answer.
List<Map<String, dynamic>> _mergeVariants(List stored, List fresh) {
  final counts = {
    for (final v in fresh.whereType<Map>()) v['name']?.toString(): v['stock'],
  };
  return [
    for (final v in stored.whereType<Map>())
      {
        ...Map<String, dynamic>.from(v),
        if (counts.containsKey(v['name']?.toString()))
          'stock': counts[v['name']?.toString()],
      },
  ];
}

/// [product] with the counts from an adjustment's answer.
Map<String, dynamic> withAdjustedStock(
  Map<String, dynamic> product,
  Map<String, dynamic> fresh,
) => {
  ...product,
  if (fresh['stock'] != null) 'stock': fresh['stock'],
  if (fresh['variants'] is List)
    'variants': _mergeVariants(
      product['variants'] as List? ?? const [],
      fresh['variants'] as List,
    ),
};
