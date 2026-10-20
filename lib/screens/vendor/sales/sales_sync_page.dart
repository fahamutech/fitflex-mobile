// Vendor tools · S3: sales kept on this device (spec §6.4) — those waiting
// to sync and those the server refused ("Needs fixing"), with Count stock,
// Try again, Edit sale and Discard. Opens even with the feature switched off
// while sales wait here (§6.6); nothing is ever deleted automatically.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../stock/adjust_stock_sheet.dart';
import '../stock/stock_options.dart';
import '../customers/customer_models.dart' show isCustomerConflict;
import 'offline_sale_queue.dart';
import 'receipt_data.dart';
import 'sale_models.dart';
import 'sales_widgets.dart';

class SalesSyncPage extends StatefulWidget {
  const SalesSyncPage({super.key});

  @override
  State<SalesSyncPage> createState() => _SalesSyncPageState();
}

class _SalesSyncPageState extends State<SalesSyncPage> {
  SalesSession? _session;
  bool _ready = false;
  bool _featureOff = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _session?.detach();
    super.dispose();
  }

  Future<void> _start() async {
    final tools = await enterSalesRoute(context, allowQueued: true);
    if (tools == null || !mounted) return;
    setState(() {
      _session = SalesSession.of(context)?..attach();
      _featureOff = !tools.walkInSales;
      _ready = true;
    });
  }

  void _back() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(_featureOff ? '/vendor/home' : salesHomeRoute);
    }
  }

  String _lang() => FFLocaleScope.of(context).locale.languageCode;

  /// The words for a refused sale (spec §9.6); never the raw code.
  String _reason(QueuedSale q) {
    final body = q.errorBody;
    final code = q.errorCode;
    if (isCustomerConflict(code, body)) {
      return context.tr('vendor.sync.conflictCustomer');
    }
    final lines = (q.display['lines'] as List? ?? []).whereType<Map>().toList();
    final rows = (q.body['lines'] as List? ?? []).whereType<Map>().toList();
    String nameOf(Object? productId, Object? variant) {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i]['productId'] == productId &&
            (variant == null || rows[i]['variant'] == variant)) {
          final name = i < lines.length
              ? lines[i]['name']?.toString() ?? ''
              : '';
          return variant == null ? name : '$name ($variant)';
        }
      }
      return '';
    }

    final key = saleErrorKey(code, reason: body['reason']?.toString());
    switch (key) {
      case 'vendor.sync.conflictStock'
          when body['productId'] == null || body['available'] == null:
        // Without the product or the count: no blank name, no "0 left".
        return context.tr('vendor.sync.conflictStockGeneric');
      case 'vendor.sync.conflictTooOld'
          when !soldAtTooOld(q.body['soldAt']?.toString(), body):
        // Ahead of the server's clock: the phone's date is wrong.
        return context.tr('vendor.pos.err.clock');
      case 'vendor.sync.conflictStock':
        final qty = rows
            .where(
              (r) =>
                  r['productId'] == body['productId'] &&
                  (body['variant'] == null || r['variant'] == body['variant']),
            )
            .fold<int>(0, (s, r) => s + ((r['qty'] as num?)?.toInt() ?? 0));
        return fillIn(context.tr(key), {
          'name': nameOf(body['productId'], body['variant']),
          'available': body['available'] ?? 0,
          'qty': qty,
        });
      case 'vendor.pos.err.unavailable':
        return fillIn(context.tr(key), {
          'name': nameOf(body['productId'], body['variant']),
        });
      case 'vendor.pos.short':
        return fillIn(context.tr(key), {
          'amount': formatCurrency((body['shortTzs'] as num?) ?? 0),
        });
      case 'vendor.pos.discountTooBig':
        return fillIn(context.tr(key), {
          'amount': formatCurrency((body['maxTzs'] as num?) ?? 0),
        });
      case 'vendor.sync.conflictOther':
        return fillIn(context.tr(key), {
          'reason': context.tr('vendor.saveFailed'),
        });
      default:
        return context.tr(key);
    }
  }

  Future<void> _count(QueuedSale q) async {
    final productId = q.errorBody['productId']?.toString();
    if (productId == null) return;
    final cached = await _session?.loadProducts();
    if (!mounted) return;
    final product =
        cached?.products
            .where((p) => p['id']?.toString() == productId)
            .firstOrNull ??
        {'id': productId, 'name': '', 'stock': 0};
    await openAdjustStock(
      context,
      product: product,
      variant: q.errorBody['variant']?.toString(),
      initialReason: 'count',
    );
  }

  Future<void> _edit(QueuedSale q) async {
    final session = _session!;
    final draft = await session.loadDraft();
    if (!mounted) return;
    if (draft != null) {
      FFSnack.info(context, context.tr('vendor.sync.finishCurrent'));
      return;
    }
    await session.saveDraft(
      PosCart.fromQueuedRequest(q.body, [
        for (final l in (q.display['lines'] as List? ?? []).whereType<Map>())
          Map<String, dynamic>.from(l),
      ], replaces: q.clientRef),
    );
    if (mounted) unawaited(context.push(posRoute));
  }

  Future<void> _recordToday(QueuedSale q) async {
    final when = eatDayOf(q.body['soldAt']?.toString());
    final originally = fillIn(context.tr('vendor.sync.originally'), {
      'date': when == null
          ? ''
          : formatDate(
              DateTime(when.year, when.month, when.day),
              locale: _lang(),
            ),
    });
    await _session?.recordToday(q.clientRef, originally);
  }

  Future<void> _discard(QueuedSale q) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('vendor.sync.discardTitle'),
      message: context.tr('vendor.sync.discardBody'),
      confirmLabel: context.tr('vendor.sync.discard'),
      destructive: true,
      confirmKey: const Key('sync-discard-confirm'),
    );
    if (ok && mounted) await _session?.remove(q.clientRef);
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(context.tr('vendor.sync.title')),
      ),
      body: !_ready || session == null
          ? const Center(child: FFSpinner())
          : ListenableBuilder(
              listenable: session,
              builder: (context, _) => _content(session),
            ),
    );
  }

  Widget _content(SalesSession session) {
    final theme = Theme.of(context);
    final waiting = session.waiting;
    final conflicts = session.conflicts;
    final paused = session.pause == SalesSyncPause.featureOff || _featureOff;
    final canCount = canVendor(context, 'products');
    if (waiting.isEmpty && conflicts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(FFTokens.spacingLg),
        children: [
          FFEmptyState(
            key: const Key('sync-done'),
            title: context.tr('vendor.sync.done'),
            icon: Icons.cloud_done_outlined,
          ),
        ],
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [
            if (paused)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: FFAlert(
                  key: const Key('sync-feature-off'),
                  message: context.tr('vendor.sync.featureOff'),
                ),
              ),
            if (session.suspended)
              Padding(
                padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
                child: FFAlert(
                  key: const Key('sync-suspended'),
                  message: context.tr('vendor.sales.suspended'),
                  tone: FFAlertTone.warning,
                ),
              ),
            FFCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    fillIn(
                      context.tr(
                        pluralKey('vendor.sync.banner', waiting.length),
                      ),
                      {'n': waiting.length},
                    ),
                    style: theme.textTheme.titleMedium,
                  ),
                  if (session.lastTry != null)
                    Text(
                      fillIn(context.tr('vendor.sync.lastTry'), {
                        'time': eatDateTime(session.lastTry, locale: _lang()),
                      }),
                      style: theme.textTheme.bodySmall,
                    ),
                  const SizedBox(height: FFTokens.spacingSm),
                  Semantics(
                    liveRegion: true,
                    child: FFButton(
                      key: const Key('sync-now'),
                      label: context.tr(
                        session.syncing
                            ? 'vendor.sync.syncing'
                            : 'vendor.sync.now',
                      ),
                      loading: session.syncing,
                      visualDensity: VisualDensity.standard,
                      onPressed: paused || waiting.isEmpty
                          ? null
                          : () => unawaited(session.sync(manual: true)),
                    ),
                  ),
                ],
              ),
            ),
            if (conflicts.isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingLg),
              Semantics(
                header: true,
                child: Text(
                  context.tr('vendor.sync.needsFixing'),
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: warningText(context),
                  ),
                ),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              for (final q in conflicts) _conflictCard(q, canCount, paused),
            ],
            if (waiting.isNotEmpty) ...[
              const SizedBox(height: FFTokens.spacingLg),
              Semantics(
                header: true,
                child: Text(
                  context.tr('vendor.sync.waiting'),
                  style: theme.textTheme.titleMedium,
                ),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              for (final q in waiting) queuedSaleRow(context, q),
            ],
          ],
        ),
      ),
    );
  }

  Widget _conflictCard(QueuedSale q, bool canCount, bool paused) {
    final theme = Theme.of(context);
    final stock = q.errorCode == 'insufficient_stock';
    final customerGone = isCustomerConflict(q.errorCode, q.errorBody);
    // Older than the server keeps (7 days): record it with today's date.
    final tooOld =
        q.errorCode == 'sold_at_out_of_range' &&
        soldAtTooOld(q.body['soldAt']?.toString(), q.errorBody);
    return Padding(
      key: Key('sync-conflict-${q.clientRef}'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FFBadge(
                  label: context.tr('vendor.sync.needsFixing'),
                  tone: FFBadgeTone.warning,
                  wrap: true,
                ),
                Text(
                  fillIn(context.tr('vendor.pos.tempRef'), {
                    'ref': tempRefOf(q.clientRef),
                  }),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            MoneyRow(
              eatDateTime(
                (q.body['soldAt'] ?? q.queuedAt).toString(),
                locale: _lang(),
              ),
              formatCurrency(q.totalTzs),
              strong: true,
            ),
            Text(_reason(q), key: Key('sync-reason-${q.clientRef}')),
            if (stock)
              Text(
                context.tr(
                  canCount
                      ? 'vendor.sync.howToFix'
                      : 'vendor.sync.askOwnerToCount',
                ),
                style: theme.textTheme.bodySmall,
              ),
            const SizedBox(height: FFTokens.spacingSm),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingSm,
              children: [
                if (stock && canCount)
                  FFButton(
                    key: Key('sync-count-${q.clientRef}'),
                    label: context.tr('vendor.sync.countStock'),
                    variant: FFButtonVariant.secondary,
                    visualDensity: VisualDensity.standard,
                    onPressed: () => _count(q),
                  ),
                if (tooOld && !paused)
                  FFButton(
                    key: Key('sync-record-today-${q.clientRef}'),
                    label: context.tr('vendor.sync.recordToday'),
                    variant: FFButtonVariant.secondary,
                    visualDensity: VisualDensity.standard,
                    onPressed: () => _recordToday(q),
                  ),
                if (customerGone && !paused)
                  FFButton(
                    key: Key('sync-no-customer-${q.clientRef}'),
                    label: context.tr('vendor.sync.retryNoCustomer'),
                    variant: FFButtonVariant.secondary,
                    visualDensity: VisualDensity.standard,
                    onPressed: () =>
                        _session?.retryWithoutCustomer(q.clientRef),
                  ),
                FFButton(
                  key: Key('sync-retry-${q.clientRef}'),
                  label: context.tr('vendor.sync.retry'),
                  variant: FFButtonVariant.secondary,
                  visualDensity: VisualDensity.standard,
                  onPressed: paused ? null : () => _session?.retry(q.clientRef),
                ),
                if (!paused)
                  FFButton(
                    key: Key('sync-edit-${q.clientRef}'),
                    label: context.tr('vendor.sync.edit'),
                    variant: FFButtonVariant.ghost,
                    visualDensity: VisualDensity.standard,
                    onPressed: () => _edit(q),
                  ),
                FFButton(
                  key: Key('sync-discard-${q.clientRef}'),
                  label: context.tr('vendor.sync.discard'),
                  variant: FFButtonVariant.destructive,
                  visualDensity: VisualDensity.standard,
                  onPressed: () => _discard(q),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A sale waiting on this device, as a row (Sales tab and sync screen).
Widget queuedSaleRow(BuildContext context, QueuedSale q) {
  final theme = Theme.of(context);
  final lang = FFLocaleScope.of(context).locale.languageCode;
  final time = eatDateTime(
    (q.body['soldAt'] ?? q.queuedAt).toString(),
    locale: lang,
  );
  final ref = tempRefOf(q.clientRef);
  final waitingLabel = context.tr(
    q.isConflict ? 'vendor.sync.needsFixing' : 'vendor.pos.waitingSync',
  );
  return Padding(
    key: Key('sales-queued-${q.clientRef}'),
    padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
    child: FFCard(
      padding: EdgeInsets.zero,
      child: Semantics(
        button: true,
        label:
            '$waitingLabel, ${fillIn(context.tr('vendor.pos.tempRef'), {'ref': ref})}, ${formatCurrency(q.totalTzs)}, $time',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => context.push(queuedReceiptRoute(q.clientRef)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: FFTokens.spacingSm,
                          runSpacing: FFTokens.spacingXs,
                          children: [
                            FFBadge(
                              label: waitingLabel,
                              tone: q.isConflict
                                  ? FFBadgeTone.warning
                                  : FFBadgeTone.brand,
                              wrap: true,
                            ),
                            Text(ref, style: theme.textTheme.titleSmall),
                          ],
                        ),
                      ),
                      Text(
                        formatCurrency(q.totalTzs),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  Text(time, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
