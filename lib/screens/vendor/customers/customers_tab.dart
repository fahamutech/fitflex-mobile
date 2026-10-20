// Vendor tools · S4: the Customers tab on the vendor home (spec §1.1, §2,
// §10). With `tools.customers` on, tab 3 ("Messages" until now) becomes
// Customers with the segments Customers | Owed | Messages. The Messages
// segment is the old enquiries list, built by the home page.
//
// Online only: nothing here is kept on the device (spec §8).
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';
import '../sales/sales_widgets.dart' show MoneyRow;
import '../stock/stock_options.dart' show fillIn;
import '../sales/sale_models.dart' show pluralKey;
import 'customer_models.dart';
import 'customers_widgets.dart';

class VendorCustomersTab extends StatelessWidget {
  const VendorCustomersTab({
    super.key,
    required this.view,
    required this.onView,
    required this.messages,
    this.listKey,
    this.owedKey,
  });

  /// `list` | `owed` | `messages`.
  final String view;
  final ValueChanged<String> onView;

  /// The enquiries list (the old Messages tab).
  final Widget messages;

  final GlobalKey<CustomersListViewState>? listKey;
  final GlobalKey<OwedViewState>? owedKey;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(
          FFTokens.spacingLg,
          FFTokens.spacingMd,
          FFTokens.spacingLg,
          0,
        ),
        child: FFSegmented(
          key: const Key('customers-segments'),
          value: view,
          options: [
            ('list', context.tr('vendor.customers.seg.list')),
            ('owed', context.tr('vendor.customers.seg.owed')),
            ('messages', context.tr('vendor.customers.seg.messages')),
          ],
          onChanged: onView,
        ),
      ),
      Expanded(
        child: switch (view) {
          'owed' => OwedView(key: owedKey),
          'messages' => messages,
          _ => CustomersListView(key: listKey),
        },
      ),
    ],
  );
}

// ── Customers segment ─────────────────────────────────────────────────────

class CustomersListView extends StatefulWidget {
  const CustomersListView({super.key});

  @override
  State<CustomersListView> createState() => CustomersListViewState();
}

class CustomersListViewState extends State<CustomersListView> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _filter = 'all';
  String _sort = 'name';
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreFailed = false;
  bool _neverAny = false;
  CustomerLoadProblem _problem = CustomerLoadProblem.none;
  int _ask = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(reload());
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> reload() async {
    final ask = ++_ask;
    setState(() {
      _loading = true;
      _problem = CustomerLoadProblem.none;
      _moreFailed = false;
    });
    final api = AppScope.of(context).api;
    try {
      final res = await api.vendorCustomers(
        q: _search.text,
        filter: _filter,
        sort: _sort,
        limit: customersPageSize,
      );
      final rows = (res['customers'] as List? ?? []).whereType<Map>().toList();
      if (!mounted || ask != _ask) return;
      setState(() {
        _rows = [for (final r in rows) Map<String, dynamic>.from(r)];
        _cursor = res['nextCursor']?.toString();
        _neverAny =
            rows.isEmpty && _filter == 'all' && _search.text.trim().isEmpty;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || ask != _ask) return;
      setState(() {
        _loading = false;
        _problem = problemOf(e);
      });
    }
  }

  Future<void> _more() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final res = await AppScope.of(context).api.vendorCustomers(
        q: _search.text,
        filter: _filter,
        sort: _sort,
        limit: customersPageSize,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _rows = [
          ..._rows,
          for (final r in (res['customers'] as List? ?? []).whereType<Map>())
            Map<String, dynamic>.from(r),
        ];
        _cursor = res['nextCursor']?.toString();
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingMore = false;
          _moreFailed = true;
        });
      }
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), reload);
  }

  Future<void> _pickSort() async {
    final picked = await showFFSheet<String>(
      context,
      title: context.tr('vendor.customers.sort'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final s in customerSorts)
            Semantics(
              inMutuallyExclusiveGroup: true,
              selected: s == _sort,
              child: ListTile(
                key: Key('customers-sort-$s'),
                minTileHeight: 48,
                title: Text(context.tr('vendor.customers.sort.$s')),
                trailing: s == _sort ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(s),
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == _sort || !mounted) return;
    setState(() => _sort = picked);
    await reload();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          key: const Key('customers-list'),
          padding: const EdgeInsets.fromLTRB(
            FFTokens.spacingLg,
            FFTokens.spacingMd,
            FFTokens.spacingLg,
            96,
          ),
          children: [
            FFTextField(
              key: const Key('customers-search'),
              controller: _search,
              label: context.tr('vendor.customers.search'),
              hint: context.tr('vendor.customers.searchHint'),
              prefixIcon: const Icon(Icons.search),
              onChanged: _onSearch,
            ),
            const SizedBox(height: FFTokens.spacingSm),
            Wrap(
              spacing: FFTokens.spacingSm,
              runSpacing: FFTokens.spacingXs,
              children: [
                for (final f in customerFilters)
                  Semantics(
                    inMutuallyExclusiveGroup: true,
                    selected: _filter == f,
                    child: FFPill(
                      key: Key('customers-filter-$f'),
                      label: context.tr(customerFilterKey(f)),
                      filled: _filter == f,
                      onTap: () {
                        setState(() => _filter = f);
                        unawaited(reload());
                      },
                    ),
                  ),
              ],
            ),
            const SizedBox(height: FFTokens.spacingXs),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FFPill(
                key: const Key('customers-sort'),
                label:
                    '${context.tr('vendor.customers.sort')}: ${context.tr('vendor.customers.sort.$_sort')}',
                onTap: _pickSort,
              ),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            ..._body(),
          ],
        ),
      ),
    );
  }

  List<Widget> _body() {
    if (_loading) {
      return [
        FFSkeletonList(semanticLabel: context.tr('vendor.customers.loading')),
      ];
    }
    if (_problem != CustomerLoadProblem.none) {
      return [
        customerErrorState(
          context,
          _problem,
          key: const Key('customers-failed'),
          failedKey: 'vendor.customers.failed',
          onRetry: reload,
        ),
      ];
    }
    if (_rows.isEmpty) {
      final q = _search.text.trim();
      return [
        FFEmptyState(
          key: Key(_neverAny ? 'customers-empty-first' : 'customers-empty'),
          icon: Icons.people_outline,
          title: _neverAny
              ? context.tr('vendor.customers.emptyFirst')
              : q.isNotEmpty
              ? fillIn(context.tr('vendor.customers.noMatch'), {'q': q})
              : context.tr('vendor.customers.empty'),
          action: _neverAny
              ? FFButton(
                  label: context.tr('vendor.customers.add'),
                  icon: Icons.person_add_alt,
                  onPressed: () => context.push(newCustomerRoute),
                )
              : null,
        ),
      ];
    }
    return [
      for (final c in _rows) _row(c),
      if (_moreFailed)
        FFAlert(
          message: context.tr('vendor.customers.failed'),
          tone: FFAlertTone.error,
        ),
      if (_cursor != null)
        Center(
          child: FFButton(
            key: const Key('customers-load-more'),
            label: context.tr(
              _moreFailed ? 'common.retry' : 'vendor.stock.loadMore',
            ),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            loading: _loadingMore,
            onPressed: _more,
          ),
        ),
    ];
  }

  Widget _row(Map<String, dynamic> c) {
    final theme = Theme.of(context);
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final id = c['id']?.toString() ?? '';
    final name = customerDisplayName(c, context.tr);
    final owed = intOf(c['owedTzs']);
    final overdue = intOf(c['overdueTzs']) > 0;
    final type = context.tr(
      c['source'] == 'marketplace'
          ? 'vendor.customers.badge.app'
          : 'vendor.customers.badge.shop',
    );
    final last = c['lastPurchaseAt']?.toString();
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final phone = c['source'] == 'manual' ? c['phone']?.toString() : null;
    return Padding(
      key: Key('customers-row-$id'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        padding: EdgeInsets.zero,
        child: Semantics(
          button: true,
          label: [
            fillIn(context.tr('vendor.customers.rowLabel'), {
              'name': name,
              'type': type,
              'amount': formatCurrency(owed),
              'status': overdue
                  ? context.tr('vendor.customers.overdueBadge')
                  : '',
            }),
            if (c['archived'] == true)
              context.tr('vendor.customers.badge.archived'),
          ].join(', '),
          excludeSemantics: true,
          child: InkWell(
            onTap: customerIdPattern.hasMatch(id)
                ? () async {
                    await context.push(customerRoute(id));
                    if (mounted) unawaited(reload());
                  }
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        if (owed > 0) ...[
                          const SizedBox(width: FFTokens.spacingSm),
                          // Money is never cut off.
                          Text(
                            formatCurrency(owed),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    Wrap(
                      spacing: FFTokens.spacingXs,
                      runSpacing: FFTokens.spacingXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        customerSourceBadge(context, c),
                        if (c['archived'] == true)
                          FFBadge(
                            label: context.tr(
                              'vendor.customers.badge.archived',
                            ),
                            tone: FFBadgeTone.gray,
                          ),
                        if (overdue) overdueBadge(context),
                        if (last != null)
                          Text(
                            fillIn(context.tr('vendor.customers.lastBought'), {
                              'date': formatDate(last, locale: lang),
                            }),
                            style: theme.textTheme.bodySmall,
                          ),
                        if (wide && phone != null)
                          Text(phone, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Owed segment ──────────────────────────────────────────────────────────

class OwedView extends StatefulWidget {
  const OwedView({super.key});

  @override
  State<OwedView> createState() => OwedViewState();
}

class OwedViewState extends State<OwedView> {
  String? _bucket;
  Map<String, dynamic>? _totals;
  String? _asOf;
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  bool _loading = true;
  bool _loadingMore = false;
  bool _moreFailed = false;
  CustomerLoadProblem _problem = CustomerLoadProblem.none;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(reload());
    });
  }

  Future<void> reload() async {
    setState(() {
      _loading = true;
      _problem = CustomerLoadProblem.none;
      _moreFailed = false;
    });
    try {
      final res = await AppScope.of(
        context,
      ).api.vendorReceivablesAging(bucket: _bucket, limit: customersPageSize);
      if (!mounted) return;
      setState(() {
        _totals = res['totals'] is Map
            ? Map<String, dynamic>.from(res['totals'] as Map)
            : const {};
        _asOf = res['asOf']?.toString();
        _rows = [
          for (final r in (res['rows'] as List? ?? []).whereType<Map>())
            Map<String, dynamic>.from(r),
        ];
        _cursor = res['nextCursor']?.toString();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _problem = problemOf(e);
      });
    }
  }

  Future<void> _more() async {
    final cursor = _cursor;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _moreFailed = false;
    });
    try {
      final res = await AppScope.of(context).api.vendorReceivablesAging(
        bucket: _bucket,
        limit: customersPageSize,
        cursor: cursor,
      );
      if (!mounted) return;
      setState(() {
        _rows = [
          ..._rows,
          for (final r in (res['rows'] as List? ?? []).whereType<Map>())
            Map<String, dynamic>.from(r),
        ];
        _cursor = res['nextCursor']?.toString();
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loadingMore = false;
          _moreFailed = true;
        });
      }
    }
  }

  void _toggle(String? bucket) {
    setState(() => _bucket = _bucket == bucket ? null : bucket);
    unawaited(reload());
  }

  @override
  Widget build(BuildContext context) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final t = _totals;
    final children = <Widget>[];
    if (_loading && t == null) {
      children.add(
        FFSkeletonList(semanticLabel: context.tr('vendor.customers.loading')),
      );
    } else if (_problem != CustomerLoadProblem.none) {
      children.add(
        customerErrorState(
          context,
          _problem,
          key: const Key('owed-failed'),
          failedKey: 'vendor.customers.failed',
          onRetry: reload,
        ),
      );
    } else if (t != null && intOf(t['owedTzs']) == 0) {
      children.add(
        FFEmptyState(
          key: const Key('owed-empty'),
          icon: Icons.check_circle_outline,
          title: context.tr('vendor.owed.empty'),
        ),
      );
    } else if (t != null) {
      children.addAll([
        _summary(t, lang),
        const SizedBox(height: FFTokens.spacingMd),
        AgingTiles(
          aging: t,
          selected: _bucket,
          onSelect: _toggle,
          keyPrefix: 'owed-bucket',
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Semantics(
            selected: _bucket == null,
            child: FFPill(
              key: const Key('owed-bucket-all'),
              label: context.tr('vendor.customers.filter.all'),
              filled: _bucket == null,
              onTap: () => _toggle(null),
            ),
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (_loading)
          FFSkeletonList(semanticLabel: context.tr('vendor.customers.loading'))
        else if (_rows.isEmpty)
          FFEmptyState(
            key: const Key('owed-empty-bucket'),
            title: context.tr('vendor.owed.emptyBucket'),
          )
        else ...[
          for (final r in _rows) _row(r, lang),
          if (_moreFailed)
            FFAlert(
              message: context.tr('vendor.customers.failed'),
              tone: FFAlertTone.error,
            ),
          if (_cursor != null)
            Center(
              child: FFButton(
                key: const Key('owed-load-more'),
                label: context.tr(
                  _moreFailed ? 'common.retry' : 'vendor.stock.loadMore',
                ),
                variant: FFButtonVariant.ghost,
                visualDensity: VisualDensity.standard,
                loading: _loadingMore,
                onPressed: _more,
              ),
            ),
        ],
      ]);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: ListView(
          key: const Key('owed-list'),
          padding: const EdgeInsets.fromLTRB(
            FFTokens.spacingLg,
            FFTokens.spacingMd,
            FFTokens.spacingLg,
            96,
          ),
          children: children,
        ),
      ),
    );
  }

  Widget _summary(Map t, String lang) {
    final theme = Theme.of(context);
    return FFCard(
      key: const Key('owed-summary'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              context.tr('vendor.owed.title'),
              style: theme.textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          LayoutBuilder(
            builder: (context, box) {
              final stack =
                  box.maxWidth < 420 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.3;
              final tiles = [
                FFStatTile(
                  key: const Key('owed-total'),
                  icon: Icons.account_balance_wallet_outlined,
                  value: formatCurrency(intOf(t['owedTzs'])),
                  label: context.tr('vendor.owed.total'),
                  fitValue: true,
                ),
                FFStatTile(
                  key: const Key('owed-overdue'),
                  icon: Icons.warning_amber_outlined,
                  value: formatCurrency(intOf(t['overdueTzs'])),
                  label: context.tr('vendor.owed.overdue'),
                  fitValue: true,
                ),
                FFStatTile(
                  key: const Key('owed-customers'),
                  icon: Icons.people_outline,
                  value: '${intOf(t['customerCount'])}',
                  label: context.tr('vendor.owed.customers'),
                ),
              ];
              if (stack) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final w in tiles)
                      Padding(
                        padding: const EdgeInsets.only(
                          bottom: FFTokens.spacingSm,
                        ),
                        child: w,
                      ),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < tiles.length; i++) ...[
                      if (i > 0) const SizedBox(width: FFTokens.spacingSm),
                      Expanded(child: tiles[i]),
                    ],
                  ],
                ),
              );
            },
          ),
          if (_asOf != null)
            Text(
              fillIn(context.tr('vendor.customers.asOf'), {
                'date': formatDay(_asOf, locale: lang),
              }),
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> r, String lang) {
    final theme = Theme.of(context);
    final id = r['customerId']?.toString() ?? '';
    final name = customerDisplayName(r, context.tr);
    final owed = intOf(r['owedTzs']);
    final overdue = intOf(r['overdueTzs']);
    final days = intOf(r['maxDaysOverdue']);
    final oldest = r['oldestDueDate']?.toString();
    return Padding(
      key: Key('owed-row-$id'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: FFCard(
        padding: EdgeInsets.zero,
        child: Semantics(
          button: true,
          label: [
            name,
            fillIn(context.tr('vendor.sales.owesBadge'), {
              'amount': formatCurrency(owed),
            }),
            if (overdue > 0)
              fillIn(context.tr('vendor.customers.overdueAmount'), {
                'amount': formatCurrency(overdue),
              }),
            if (days > 0)
              fillIn(
                context.tr(pluralKey('vendor.customers.daysOverdue', days)),
                {'n': days},
              ),
          ].join(', '),
          excludeSemantics: true,
          child: InkWell(
            onTap: customerIdPattern.hasMatch(id)
                ? () async {
                    await context.push(customerRoute(id));
                    if (mounted) unawaited(reload());
                  }
                : null,
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
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(width: FFTokens.spacingSm),
                        Text(
                          formatCurrency(owed),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    if (overdue > 0)
                      MoneyRow(
                        context.tr('vendor.owed.overdue'),
                        formatCurrency(overdue),
                      ),
                    Wrap(
                      spacing: FFTokens.spacingXs,
                      runSpacing: FFTokens.spacingXs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (oldest != null)
                          Text(
                            '${context.tr('vendor.owed.oldestDue')}: ${formatDay(oldest, locale: lang)}',
                            style: theme.textTheme.bodySmall,
                          ),
                        if (days > 0)
                          overdueBadge(
                            context,
                            label: fillIn(
                              context.tr(
                                pluralKey('vendor.customers.daysOverdue', days),
                              ),
                              {'n': days},
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
