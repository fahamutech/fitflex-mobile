import 'package:flutter/material.dart';
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
import 'banner_models.dart' show toEatWallClock;
import 'flash_sale_models.dart';

/// The Flash sales tab of the vendor's Promotions page (Phase 2 S4): the
/// sales on their products by state, with Send for approval / Edit /
/// Withdraw / End now / Copy to new, "Propose a flash sale" and
/// "{open} of {max} open proposals".
///
/// Shown inside [VendorMerchPage] while GET /vendor/tools/options says
/// `merch.flashSales: true`. Staff need the `products` permission. Sales
/// FitFlex made on the vendor's products are listed read-only.
class VendorFlashSalesPage extends StatefulWidget {
  const VendorFlashSalesPage({super.key, this.now, this.item});

  /// The clock (tests).
  final DateTime Function()? now;

  /// A sale to scroll to and highlight (`?item=`, from a notification).
  final String? item;

  @override
  State<VendorFlashSalesPage> createState() => _VendorFlashSalesPageState();
}

class _VendorFlashSalesPageState extends State<VendorFlashSalesPage> {
  bool _loading = true;
  bool _unavailable = false;
  bool _suspended = false;
  Object? _error;
  List<VendorFlashSale> _sales = const [];
  final Set<String> _busy = {};

  bool _canPropose = true;
  String? _cannotReason;
  int? _open;
  int? _maxOpen;
  bool get _atLimit => _open != null && _maxOpen != null && _open! >= _maxOpen!;

  String? _highlight;
  bool _itemHandled = false;
  final _itemKey = GlobalKey(debugLabel: 'merch-sale-item');

  static const _maxPages = 20;

  bool get _pendingVendor {
    final auth = AppScope.of(context).auth;
    return auth.isPendingApproval && auth.user?['userType'] == 'vendor';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final tools = await VendorToolsOptions.of(context, refresh: refresh);
    if (!mounted) return;
    if (tools.suspended) {
      setState(() {
        _suspended = true;
        _canPropose = false;
        _loading = false;
      });
      return;
    }
    if (!tools.flashSales) {
      setState(() {
        _unavailable = true;
        _loading = false;
      });
      return;
    }
    if (!canManageProducts(context)) {
      setState(() => _loading = false);
      return;
    }
    try {
      final list = await _allSales(AppScope.of(context).api);
      if (!mounted) return;
      final vendor = list['vendor'] is Map ? list['vendor'] as Map : const {};
      final open = list['openProposals'] is Map
          ? list['openProposals'] as Map
          : const {};
      setState(() {
        _canPropose = vendor['canPropose'] != false && !_pendingVendor;
        _cannotReason = _pendingVendor
            ? 'vendor_not_approved'
            : vendor['reason']?.toString();
        _open = open['open'] is num ? (open['open'] as num).toInt() : null;
        _maxOpen = open['max'] is num ? (open['max'] as num).toInt() : null;
        _sales = (list['items'] is List ? list['items'] as List : const [])
            .whereType<Map>()
            .map((m) => VendorFlashSale.fromJson(Map<String, dynamic>.from(m)))
            .where((s) => s.id.isNotEmpty)
            .toList();
        _unavailable = false;
        _loading = false;
      });
      _showItem();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _unavailable = e.status == 404 && e.code == 'feature_disabled';
        _suspended = e.code == 'vendor_suspended';
        _error = _unavailable || _suspended ? null : e;
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

  /// Every page (limit 100, following nextCursor); the first page's
  /// `vendor`, `openProposals` and `rules` are kept.
  static Future<Map<String, dynamic>> _allSales(ApiClient api) async {
    final first = await api.vendorFlashSales();
    final items = [...?(first['items'] as List?)];
    var cursor = first['nextCursor']?.toString();
    for (var page = 1; page < _maxPages && (cursor ?? '').isNotEmpty; page++) {
      final next = await api.vendorFlashSales(cursor: cursor);
      items.addAll((next['items'] as List?) ?? const []);
      final more = next['nextCursor']?.toString();
      if (more == cursor) break;
      cursor = more;
    }
    return {...first, 'items': items};
  }

  void _showItem() {
    final id = widget.item;
    if (_itemHandled || id == null || id.isEmpty) return;
    _itemHandled = true;
    if (!_sales.any((s) => s.id == id)) {
      FFSnack.info(context, context.tr('merch.notYours'));
      return;
    }
    setState(() => _highlight = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _itemKey.currentContext;
      if (target == null || !target.mounted) return;
      Scrollable.ensureVisible(
        target,
        alignment: 0.1,
        duration: MediaQuery.disableAnimationsOf(target)
            ? Duration.zero
            : FFTokens.motionMedium,
      );
    });
  }

  Future<void> _openForm({VendorFlashSale? sale, VendorFlashSale? copy}) async {
    final path = sale != null
        ? AppRoutes.vendorMerchSaleEdit(sale.id)
        : copy != null
        ? '${AppRoutes.vendorMerchSaleNew}?copy=${Uri.encodeQueryComponent(copy.id)}'
        : AppRoutes.vendorMerchSaleNew;
    final sent = await context.push<bool>(path);
    if (sent == true && mounted) await _load();
  }

  Future<void> _withdraw(VendorFlashSale sale) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('merch.sale.withdraw.title'),
      message: context.tr('merch.sale.withdraw.body'),
      confirmLabel: context.tr('merch.withdraw.confirm'),
      cancelLabel: context.tr('merch.sale.keep'),
      destructive: true,
      confirmKey: const Key('merch-sale-withdraw-confirm'),
    );
    if (!ok || !mounted) return;
    await _act(
      sale,
      () => AppScope.of(context).api.vendorWithdrawFlashSale(sale.id),
      'merch.sale.withdrawn',
    );
  }

  Future<void> _end(VendorFlashSale sale) async {
    final ok = await showFFConfirmDialog(
      context,
      title: context.tr('merch.endSale.title'),
      message: context.tr('merch.endSale.body'),
      confirmLabel: context.tr('merch.sale.endConfirm'),
      cancelLabel: context.tr('merch.sale.keep'),
      destructive: true,
      confirmKey: const Key('merch-sale-end-confirm'),
    );
    if (!ok || !mounted) return;
    await _act(
      sale,
      () => AppScope.of(context).api.vendorEndFlashSale(sale.id),
      'merch.sale.endedDone',
    );
  }

  Future<void> _submit(VendorFlashSale sale) => _act(
    sale,
    () => AppScope.of(context).api.vendorSubmitFlashSale(sale.id),
    'merch.sale.sent',
  );

  /// Runs a list action, then reloads. A refusal says why (a sale with a
  /// rule problem is fixed with Edit).
  Future<void> _act(
    VendorFlashSale sale,
    Future<Object?> Function() call,
    String doneKey,
  ) async {
    final messenger = FFSnack.of(context);
    final locale = FFLocaleScope.of(context);
    setState(() => _busy.add(sale.id));
    try {
      await call();
      messenger.success(locale.t(doneKey));
    } on ApiException catch (e) {
      final err = flashSaleError(e);
      messenger.error(
        err.target == 'message'
            ? locale.t(err.key)
            : _fieldMessage(locale, err),
      );
    } catch (e) {
      messenger.error(
        locale.t(
          isNetworkError(e) ? 'merch.sale.notSentOffline' : 'merch.saveFailed',
        ),
      );
    }
    if (!mounted) return;
    setState(() => _busy.remove(sale.id));
    await _load();
  }

  /// A field problem from a list action (submit re-checks every rule).
  String _fieldMessage(FFLocale locale, FlashSaleError err) {
    final lang = locale.locale.languageCode;
    String when(Object? v) {
      final d = DateTime.tryParse(v?.toString() ?? '');
      return d == null ? '-' : formatDateTime(toEatWallClock(d), locale: lang);
    }

    String money(Object? v) => v is num ? formatCurrency(v) : '-';
    // An overlap without its dates: the general words.
    if (err.key == 'merch.sale.overlap' &&
        (DateTime.tryParse('${err.params['start'] ?? ''}') == null ||
            DateTime.tryParse('${err.params['end'] ?? ''}') == null)) {
      return locale.t('merch.sale.overlapNoDates');
    }
    if (err.key == 'merch.sale.historyShort') {
      final listed = FlashSalePriceCheck.tanzaniaDay(err.params['listedAt']);
      return locale
          .t(err.key)
          .replaceAll(
            '{date}',
            listed == null ? '-' : formatDate(listed, locale: lang),
          )
          .replaceAll('{earliest}', when(err.params['earliestStart']));
    }
    if (err.key == 'merch.sale.raised') {
      final raised = FlashSalePriceCheck.day(err.params['raisedOn']);
      return locale
          .t(err.key)
          .replaceAll(
            '{date}',
            raised == null ? '-' : formatDate(raised, locale: lang),
          )
          .replaceAll('{earliest}', when(err.params['earliestStart']));
    }
    return locale
        .t(err.key)
        .replaceAll('{max}', money(err.params['max']))
        .replaceAll('{discount}', money(err.params['discount']))
        .replaceAll('{start}', when(err.params['start']))
        .replaceAll('{end}', when(err.params['end']))
        .replaceAll('{date}', '${err.params['raisedOn'] ?? '-'}')
        .replaceAll('{earliest}', when(err.params['earliestStart']));
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: () => _load(refresh: true),
    child: _body(context),
  );

  Widget _scroll(List<Widget> children) => SingleChildScrollView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 960),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    ),
  );

  Widget _body(BuildContext context) {
    if (_loading) {
      return _scroll([
        FFSkeletonList(
          key: const Key('merch-sales-loading'),
          semanticLabel: context.tr('common.loading'),
        ),
      ]);
    }
    if (_suspended) {
      return _scroll([
        FFAlert(
          key: const Key('merch-sales-suspended'),
          tone: FFAlertTone.error,
          message: context.tr('merch.sale.suspended'),
        ),
      ]);
    }
    if (_unavailable) {
      return _scroll([
        FFEmptyState(
          key: const Key('merch-sales-unavailable'),
          icon: Icons.bolt_outlined,
          title: context.tr('merch.unavailable'),
        ),
      ]);
    }
    if (!canManageProducts(context)) {
      return _scroll([
        FFEmptyState(
          key: const Key('merch-sales-restricted'),
          title: context.tr('vendor.noAccess'),
        ),
      ]);
    }
    final error = _error;
    if (error != null) {
      final offline = isNetworkError(error);
      return _scroll([
        FFErrorState(
          key: Key(offline ? 'merch-sales-offline' : 'merch-sales-error'),
          icon: offline ? Icons.wifi_off : Icons.error_outline,
          title: context.tr(
            offline ? 'merch.offlineTitle' : 'merch.sales.error',
          ),
          message: offline ? context.tr('merch.sales.offlineBody') : null,
          onRetry: _load,
        ),
      ]);
    }
    final Widget propose = _canPropose
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FFButton(
                key: const Key('merch-sale-propose'),
                label: context.tr('merch.sales.propose'),
                icon: Icons.add,
                fullWidth: true,
                visualDensity: VisualDensity.standard,
                maxLines: 2,
                onPressed: _atLimit ? null : () => _openForm(),
              ),
              if (_open != null && _maxOpen != null) ...[
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  context
                      .tr(_atLimit ? 'merch.sale.openFull' : 'merch.openCount')
                      .replaceAll('{open}', '$_open')
                      .replaceAll('{max}', '$_maxOpen'),
                  key: const Key('merch-sale-open-count'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          )
        : _cannotReason == 'vendor_suspended'
        ? FFAlert(
            key: const Key('merch-sales-suspended'),
            tone: FFAlertTone.error,
            message: context.tr('merch.sale.suspended'),
          )
        : FFEmptyState(
            key: const Key('merch-sales-pending'),
            icon: Icons.hourglass_empty,
            title: context.tr('merch.pendingTitle'),
            body: context.tr('merch.pendingBody'),
            action: FFButton(
              key: const Key('merch-sales-open-verification'),
              label: context.tr('merch.openVerification'),
              variant: FFButtonVariant.secondary,
              icon: Icons.verified_user_outlined,
              visualDensity: VisualDensity.standard,
              maxLines: 2,
              onPressed: () => context.push(AppRoutes.verification),
            ),
          );
    if (_sales.isEmpty && !_canPropose) return _scroll([propose]);
    if (_sales.isEmpty) {
      return _scroll([
        FFEmptyState(
          key: const Key('merch-sales-empty'),
          icon: Icons.bolt_outlined,
          title: context.tr('merch.sales.emptyTitle'),
          body: context.tr('merch.sales.emptyBody'),
          action: propose,
        ),
      ]);
    }
    final groups = {
      for (final g in flashSaleGroups)
        g: _sales.where((s) => flashSaleGroup(s.status) == g).toList(),
    };
    final theme = Theme.of(context);
    return _scroll([
      Semantics(
        header: true,
        child: Text(
          context.tr('merch.sales.title'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      const SizedBox(height: FFTokens.spacingMd),
      propose,
      for (final g in flashSaleGroups)
        if (groups[g]!.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingLg),
          Semantics(
            header: true,
            child: Text(
              context.tr('merch.sale.group.$g'),
              key: Key('merch-sale-group-$g'),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          for (final s in groups[g]!) _card(context, s),
        ],
    ]);
  }

  String _when(DateTime? at) {
    if (at == null) return '-';
    return formatDateTime(
      toEatWallClock(at),
      locale: FFLocaleScope.of(context).locale.languageCode,
    );
  }

  /// The line under the status (spec §4.2).
  String? _extraLine(BuildContext context, VendorFlashSale s) {
    String fill(String key, String value) =>
        context.tr(key).replaceAll('{date}', value);
    switch (s.status) {
      case 'draft':
        return context.tr('merch.sale.line.notSent');
      case 'pending_approval':
        return s.expiresAt == null
            ? null
            : fill('merch.sale.line.expires', _when(s.expiresAt));
      case 'approved':
        return fill('merch.sale.line.starts', _when(s.startsAt));
      case 'live':
        return fill('merch.sale.line.ends', _when(s.endsAt));
      case 'ended':
        if (s.endedByFitflex) {
          final note = s.reasonNote?.trim() ?? '';
          return context
              .tr(
                note.isEmpty
                    ? 'merch.sale.line.endedByFitflexNoReason'
                    : 'merch.sale.line.endedByFitflex',
              )
              .replaceAll('{date}', _when(s.endedAt ?? s.endsAt))
              .replaceAll('{reason}', note);
        }
        if (s.reasonCode == 'ended_by_vendor') {
          return context.tr('merch.sale.line.youEnded');
        }
        return fill('merch.sale.line.endedOn', _when(s.endedAt ?? s.endsAt));
      case 'rejected':
        final key = flashSaleRejectKey(s.reasonCode);
        final reason = [
          if (key != null) context.tr(key),
          ?s.reasonNote,
        ].where((x) => x.trim().isNotEmpty).join('. ');
        return reason.isEmpty
            ? null
            : context.tr('merch.line.reason').replaceAll('{reason}', reason);
      case 'expired':
        return context.tr('merch.sale.line.notReviewed');
      case 'withdrawn':
        return context.tr('merch.sale.line.youWithdrew');
    }
    return null;
  }

  static FFBadgeTone _tone(String status) => switch (status) {
    'pending_approval' => FFBadgeTone.warning,
    'approved' => FFBadgeTone.brand,
    'live' => FFBadgeTone.success,
    'rejected' => FFBadgeTone.danger,
    'ended' => FFBadgeTone.defaultTone,
    _ => FFBadgeTone.gray,
  };

  static String _statusKey(String status) => switch (status) {
    'pending_approval' => 'merch.status.pending',
    'approved' ||
    'live' ||
    'ended' ||
    'rejected' ||
    'expired' ||
    'withdrawn' => 'merch.status.$status',
    // "Haijatumwa": ofa agreement, not the banner's "Halijatumwa".
    _ => 'merch.sale.status.draft',
  };

  Widget _card(BuildContext context, VendorFlashSale s) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final busy = _busy.contains(s.id);
    final name = s.productName.isEmpty ? '-' : s.productName;
    final extra = _extraLine(context, s);
    final sale = formatCurrency(s.salePriceTzs);
    final was = formatCurrency(s.basePrice);
    Widget action(String key, String label, String a11y, VoidCallback onTap) =>
        Semantics(
          button: true,
          excludeSemantics: true,
          label: context.tr(a11y).replaceAll('{product}', name),
          onTap: busy ? null : onTap,
          child: FFButton(
            key: Key('merch-sale-$key-${s.id}'),
            label: context.tr(label),
            variant: FFButtonVariant.ghost,
            visualDensity: VisualDensity.standard,
            onPressed: busy ? null : onTap,
          ),
        );
    final actions = <Widget>[
      if (s.canSubmit && _canPropose)
        action(
          'submit',
          'merch.send',
          'merch.sale.a11ySubmit',
          () => _submit(s),
        ),
      if (s.canEdit && _canPropose)
        action(
          'edit',
          'merch.action.edit',
          'merch.sale.a11yEdit',
          () => _openForm(sale: s),
        ),
      if (s.canWithdraw)
        action(
          'withdraw',
          'merch.action.withdraw',
          'merch.sale.a11yWithdraw',
          () => _withdraw(s),
        ),
      if (s.canEnd)
        action(
          'end',
          'merch.action.endNow',
          'merch.sale.a11yEnd',
          () => _end(s),
        ),
      if (flashSaleGroup(s.status) == 'past' && _canPropose && !s.byFitflex)
        action(
          'copy',
          'merch.action.copy',
          'merch.sale.a11yCopy',
          () => _openForm(copy: s),
        ),
    ];
    final card = FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                  child: Container(
                    width: 64,
                    height: 64,
                    color: Colors.white,
                    child: s.productImage == null
                        ? const Icon(Icons.shopping_bag_outlined)
                        : FFRemoteImage(
                            src: s.productImage!,
                            width: 64,
                            height: 64,
                            fit: BoxFit.contain,
                            fallback: const Icon(Icons.shopping_bag_outlined),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: FFTokens.spacingMd),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacing2xs),
                    // "TSh 69,000 · −24%", the regular price struck below;
                    // read once.
                    Semantics(
                      container: true,
                      excludeSemantics: true,
                      label: context
                          .tr('merch.sale.cardA11y')
                          .replaceAll('{product}', name)
                          .replaceAll('{sale}', sale)
                          .replaceAll('{old}', was)
                          .replaceAll('{pct}', '${s.percentOff}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: FFTokens.spacingXs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                sale,
                                key: Key('merch-sale-price-${s.id}'),
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: dark
                                      ? FFTokens.fuelOnDark
                                      : FFTokens.fuel,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              FFBadge(
                                key: Key('merch-sale-pct-${s.id}'),
                                label: '−${s.percentOff}%',
                                tone: FFBadgeTone.fuel,
                              ),
                            ],
                          ),
                          Text(
                            was,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: FFTokens.mutedText(context),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacingXs),
                    FFBadge(
                      key: Key('merch-sale-status-${s.id}'),
                      label: context.tr(_statusKey(s.status)),
                      tone: _tone(s.status),
                      wrap: true,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          if (s.byFitflex)
            Text(
              context.tr('merch.sale.byFitflex'),
              key: Key('merch-sale-byfitflex-${s.id}'),
              style: theme.textTheme.bodyMedium,
            ),
          if (extra != null)
            Text(
              extra,
              key: Key('merch-sale-line-${s.id}'),
              style: theme.textTheme.bodyMedium,
            ),
          Text(
            '${_when(s.startsAt)} – ${_when(s.endsAt)} '
            '(${context.tr('merch.dates.tzNote')})',
            style: theme.textTheme.bodySmall,
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingXs),
            Wrap(spacing: FFTokens.spacingXs, children: actions),
          ],
        ],
      ),
    );
    final highlighted = _highlight == s.id;
    return Padding(
      key: Key('merch-sale-${s.id}'),
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: KeyedSubtree(
        key: highlighted ? _itemKey : null,
        child: highlighted
            ? DecoratedBox(
                key: Key('merch-sale-highlight-${s.id}'),
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(FFTokens.radiusLg),
                ),
                child: card,
              )
            : card,
      ),
    );
  }
}
