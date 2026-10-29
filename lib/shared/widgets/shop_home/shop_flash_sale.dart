// Shop home Phase 2 · S4 (flash sales), buyer side: the "Sale ends in …"
// line on the product sheet, the cart's sale notice, and the "Prices have
// changed" sheet shown when checkout answers 409 price_changed.
//
// Contract: fitflex-functions docs/shop-flash-sales-api.md (feat/shop-
// flash-sales, flag SHOP_FLASH_SALES). Every time here is the server's
// ([ShopClock]), never the device's.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../api_client.dart';
import '../../components/components.dart';
import '../../design_tokens.dart';
import '../../formatters.dart';
import '../../i18n.dart';
import '../../shop_home.dart';
import '../shop_browse_page.dart' show ShopCart, ShopProduct;
import 'shop_focus_ring.dart';

/// A cart line counts as "about to end" this long before its sale ends.
const shopSaleEndingSoon = Duration(minutes: 15);

/// "Sale ends in 2 h 14 min" (or "in 9 min", "in less than a minute"); more
/// than 24 hours away, "Sale ends Fri 31 Oct · 18:00". [left] is never
/// negative.
String shopSaleEndsText(
  BuildContext context,
  ShopFlashSale sale,
  Duration left,
) {
  if (left == Duration.zero) return context.tr('shop.home.saleEnded');
  if (left > const Duration(hours: 24)) {
    final lang = FFLocaleScope.of(context).locale.languageCode;
    return context
        .tr('shop.sale.endsOn')
        .replaceAll('{when}', shopSaleEndWhen(sale.endsAt, lang));
  }
  final h = left.inHours;
  final m = left.inMinutes % 60;
  if (h == 0 && m == 0) return context.tr('shop.sale.endsInUnderMin');
  if (h == 0) return context.tr('shop.sale.endsInMin').replaceAll('{m}', '$m');
  // No "0 min".
  if (m == 0) {
    return context.tr('shop.sale.endsInHours').replaceAll('{h}', '$h');
  }
  return context
      .tr('shop.sale.endsIn')
      .replaceAll('{h}', '$h')
      .replaceAll('{m}', '$m');
}

const _weekdaysEn = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', //
  'Friday', 'Saturday', 'Sunday',
];
const _weekdaysSw = [
  'Jumatatu', 'Jumanne', 'Jumatano', 'Alhamisi', //
  'Ijumaa', 'Jumamosi', 'Jumapili',
];

/// "Friday 6:00 pm" / "Ijumaa 6:00 jioni" (spec §8.1, QA #8): the weekday
/// and a 12-hour time of day, on the member's clock.
String shopSaleEndWhen(DateTime endsAt, String lang) {
  final d = localDateTime(endsAt) ?? endsAt;
  final sw = lang == 'sw';
  final day = (sw ? _weekdaysSw : _weekdaysEn)[d.weekday - 1];
  if (sw) return '$day ${formatTimeOfDay(d, locale: 'sw')}';
  final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  return '$day $h12:$mm ${d.hour < 12 ? 'am' : 'pm'}';
}

/// The product sheet's line under the price (spec §8.1): Fuel text, no
/// chips, changing at most once a minute. Read as it is shown.
class ShopSaleEndsLine extends StatefulWidget {
  const ShopSaleEndsLine({super.key, required this.sale});
  final ShopFlashSale sale;

  @override
  State<ShopSaleEndsLine> createState() => _ShopSaleEndsLineState();
}

class _ShopSaleEndsLineState extends State<ShopSaleEndsLine> {
  Timer? _timer;

  Duration get _left {
    final d = widget.sale.endsAt.difference(ShopClock.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ShopSaleEndsLine old) {
    super.didUpdateWidget(old);
    if (old.sale.endsAt != widget.sale.endsAt) _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    final ms = _left.inMilliseconds;
    if (ms <= 0) return;
    // The next whole minute of the time left (or the end itself).
    final next = ms <= 60000 ? ms : (ms % 60000 == 0 ? 60000 : ms % 60000);
    _timer = Timer(Duration(milliseconds: next), () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final left = _left;
    return Text(
      shopSaleEndsText(context, widget.sale, left),
      key: const Key('shop-sale-ends'),
      // QA #8: read in words at minute precision ("Sale ends in 2 hours 14
      // minutes"); over 24 h the visible "Sale ends Friday 6:00 pm".
      semanticsLabel: left > const Duration(hours: 24)
          ? null
          : ffCountdownA11yLabel(context, left),
      style: theme.textTheme.bodyMedium?.copyWith(
        color: left == Duration.zero
            ? theme.colorScheme.onSurface
            : (dark ? FFTokens.fuelOnDark : FFTokens.fuel),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

/// The warning about sale lines in the cart (P1 §9, AC-23): a sale that
/// ended ("You'll pay the current price"), else one about to end. Wakes
/// exactly when something it says changes (QA #3): a line's sale end, the
/// start of its last 15 minutes, and each minute inside them. [onChanged]
/// tells the screen around it (the cart bar's total) at those moments.
/// Nothing when no line is on sale.
class ShopCartSaleNotice extends StatefulWidget {
  const ShopCartSaleNotice({super.key, required this.cart, this.onChanged});
  final ShopCart cart;
  final VoidCallback? onChanged;

  @override
  State<ShopCartSaleNotice> createState() => _ShopCartSaleNoticeState();
}

/// The next moment a cart line's sale state or its "ends in N min" changes
/// (server clock), or null when no line is in a live sale.
DateTime? shopCartNextSaleBoundary(ShopCart cart, DateTime now) {
  DateTime? next;
  void consider(DateTime at) {
    if (!at.isAfter(now)) return;
    if (next == null || at.isBefore(next!)) next = at;
  }

  for (final (product, _, _) in cart.lines) {
    final sale = product.sale;
    if (sale == null || !product.flashSaleLive) continue;
    consider(sale.endsAt);
    final soon = sale.endsAt.subtract(shopSaleEndingSoon);
    if (now.isBefore(soon)) {
      consider(soon);
    } else {
      // Inside the last 15 minutes: the next whole minute of the time left.
      final ms = sale.endsAt.difference(now).inMilliseconds % 60000;
      consider(now.add(Duration(milliseconds: ms == 0 ? 60000 : ms)));
    }
  }
  return next;
}

class _ShopCartSaleNoticeState extends State<ShopCartSaleNotice> {
  Timer? _timer;

  void _schedule() {
    _timer?.cancel();
    final now = ShopClock.now();
    final next = shopCartNextSaleBoundary(widget.cart, now);
    if (next == null) return;
    // A moment after the boundary, so it reads as passed when it fires.
    _timer = Timer(next.difference(now) + const Duration(milliseconds: 1), () {
      if (!mounted) return;
      setState(() {});
      widget.onChanged?.call();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _schedule();
    final ended = widget.cart.saleEndedProducts;
    if (ended.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
        child: FFAlert(
          key: const Key('shop-cart-sale-ended'),
          tone: FFAlertTone.warning,
          message: ended.length == 1
              ? context.tr('shop.home.saleEndedInCart')
              : context
                    .tr('shop.home.saleEndedInCartMany')
                    .replaceAll('{n}', '${ended.length}'),
        ),
      );
    }
    final now = ShopClock.now();
    for (final (product, _, _) in widget.cart.lines) {
      final sale = product.sale;
      if (sale == null || !product.flashSaleLive) continue;
      final left = sale.endsAt.difference(now);
      if (left > shopSaleEndingSoon) continue;
      final m = left.inMinutes < 1 ? 1 : left.inMinutes;
      return Padding(
        padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
        child: FFAlert(
          key: const Key('shop-cart-sale-ending'),
          tone: FFAlertTone.warning,
          message: context
              .tr('shop.sale.endingSoonInCart')
              .replaceAll('{name}', product.name)
              .replaceAll('{m}', '$m'),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

// ── 409 price_changed ─────────────────────────────────────────────────────

/// One changed line of a `409 price_changed`.
class ShopPriceChangeLine {
  const ShopPriceChangeLine({
    required this.productId,
    required this.currentPriceTzs,
    this.variant,
    this.expectedPriceTzs,
    this.reason = 'price_changed',
  });

  final String productId;
  final String? variant;

  /// The unit price the app showed (null when it sent none).
  final num? expectedPriceTzs;
  final num currentPriceTzs;

  /// `sale_ended`, `sale_started` or `price_changed`.
  final String reason;

  String get reasonKey => switch (reason) {
    'sale_ended' => 'shop.priceChanged.saleEnded',
    'sale_started' => 'shop.priceChanged.saleStarted',
    _ => 'shop.priceChanged.changed',
  };
}

/// The body of `409 price_changed` (docs/shop-flash-sales-api.md):
/// `{productId, currentPriceTzs, lines: [{productId, variant,
/// expectedPriceTzs, currentPriceTzs, reason}], expectedTotalTzs,
/// totalTzs}`.
class ShopPriceChange {
  const ShopPriceChange({
    required this.lines,
    this.expectedTotalTzs,
    this.totalTzs,
  });

  final List<ShopPriceChangeLine> lines;
  final num? expectedTotalTzs;
  final num? totalTzs;

  /// The change this error describes, or null when it is not a
  /// `price_changed` the sheet can show (an older server's bare code: the
  /// plain message is shown instead).
  static ShopPriceChange? fromError(Object error) {
    if (error is! ApiException || error.code != 'price_changed') return null;
    final body = error.body;
    if (body is! Map) return null;
    num? n(Object? v) => v is num ? v : null;
    final lines = <ShopPriceChangeLine>[
      for (final l
          in (body['lines'] is List ? body['lines'] as List : const []))
        if (l is Map &&
            (l['productId']?.toString() ?? '').isNotEmpty &&
            n(l['currentPriceTzs']) != null)
          ShopPriceChangeLine(
            productId: l['productId'].toString(),
            variant: (l['variant']?.toString() ?? '').isEmpty
                ? null
                : l['variant'].toString(),
            expectedPriceTzs: n(l['expectedPriceTzs']),
            currentPriceTzs: n(l['currentPriceTzs'])!,
            reason: l['reason']?.toString() ?? 'price_changed',
          ),
    ];
    // Only the first line (an older shape of the same answer).
    if (lines.isEmpty &&
        (body['productId']?.toString() ?? '').isNotEmpty &&
        n(body['currentPriceTzs']) != null) {
      lines.add(
        ShopPriceChangeLine(
          productId: body['productId'].toString(),
          currentPriceTzs: n(body['currentPriceTzs'])!,
        ),
      );
    }
    if (lines.isEmpty) return null;
    return ShopPriceChange(
      lines: lines,
      expectedTotalTzs: n(body['expectedTotalTzs']),
      totalTzs: n(body['totalTzs']),
    );
  }
}

/// What a "Continue with {total}" attempt came to.
enum ShopPriceRetry {
  /// The order was placed: the sheet closes.
  placed,

  /// The prices moved again: the caller updated the sheet's change, which
  /// refreshes in place and says "Prices changed again".
  changedAgain,

  /// No connection: the sheet stays, saying so.
  offline,

  /// Any other failure: the sheet closes and the caller says why.
  failed,
}

/// Opens the "Prices have changed" sheet (spec §8.2). Not closed by a tap
/// outside; Back and the drag handle mean "Back to cart". Resolves true
/// when the order was placed from the sheet, false or null otherwise.
Future<bool?> showShopPriceChangedSheet(
  BuildContext context, {
  required ValueNotifier<ShopPriceChange> change,
  required ShopProduct? Function(String productId) product,
  required Future<ShopPriceRetry> Function() onContinue,
}) => showFFSheet<bool>(
  context,
  title: context.tr('shop.priceChanged.title'),
  showClose: false,
  isDismissible: false,
  wideDialogWidth: 480,
  // QA #4: focus opens on the title; title → rows → totals → Continue →
  // Back to cart, and stays inside the sheet.
  focusTitle: true,
  trapFocus: true,
  child: ShopPriceChangedBody(
    change: change,
    product: product,
    onContinue: onContinue,
  ),
);

class ShopPriceChangedBody extends StatefulWidget {
  const ShopPriceChangedBody({
    super.key,
    required this.change,
    required this.product,
    required this.onContinue,
  });

  final ValueNotifier<ShopPriceChange> change;
  final ShopProduct? Function(String productId) product;
  final Future<ShopPriceRetry> Function() onContinue;

  @override
  State<ShopPriceChangedBody> createState() => _ShopPriceChangedBodyState();
}

class _ShopPriceChangedBodyState extends State<ShopPriceChangedBody> {
  bool _busy = false;
  bool _offline = false;
  bool _again = false;

  Future<void> _continue() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _offline = false;
    });
    final result = await widget.onContinue();
    if (!mounted) return;
    switch (result) {
      case ShopPriceRetry.placed:
        Navigator.of(context).pop(true);
      case ShopPriceRetry.failed:
        Navigator.of(context).pop(false);
      case ShopPriceRetry.offline:
        setState(() {
          _busy = false;
          _offline = true;
        });
      case ShopPriceRetry.changedAgain:
        setState(() {
          _busy = false;
          _again = true;
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          context.tr('shop.priceChanged.again'),
          Directionality.of(context),
        );
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ShopPriceChange>(
    valueListenable: widget.change,
    builder: (context, change, _) => _body(context, change),
  );

  Widget _body(BuildContext context, ShopPriceChange change) {
    final theme = Theme.of(context);
    final rows = [for (final line in change.lines) _row(context, line)];
    final oldTotal = formatCurrency(change.expectedTotalTzs ?? 0);
    final newTotal = formatCurrency(change.totalTzs ?? 0);
    final hasTotals = change.totalTzs != null;
    return Column(
      key: const Key('shop-price-changed'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('shop.priceChanged.body'),
          style: theme.textTheme.bodyMedium,
        ),
        if (_again) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context.tr('shop.priceChanged.again'),
            key: const Key('shop-price-changed-again'),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        // More than 4 rows scroll on their own; the buttons stay in view.
        if (rows.length > 4)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 4 * 80),
            child: Scrollbar(child: ListView(shrinkWrap: true, children: rows)),
          )
        else
          ...rows,
        const Divider(),
        if (hasTotals)
          _stop(
            Semantics(
              key: const Key('shop-price-changed-totals'),
              container: true,
              excludeSemantics: true,
              label: context
                  .tr('shop.a11y.priceChangedTotal')
                  .replaceAll('{old}', oldTotal)
                  .replaceAll('{new}', newTotal),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (change.expectedTotalTzs != null)
                    Text(
                      context
                          .tr('shop.priceChanged.totalWas')
                          .replaceAll('{total}', oldTotal),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: FFTokens.mutedText(context),
                      ),
                    ),
                  Text(
                    context
                        .tr('shop.priceChanged.newTotal')
                        .replaceAll('{total}', newTotal),
                    key: const Key('shop-price-changed-new-total'),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_offline) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Semantics(
            liveRegion: true,
            child: Text(
              context.tr('shop.priceChanged.offline'),
              key: const Key('shop-price-changed-offline'),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        FFButton(
          key: const Key('shop-price-changed-continue'),
          label: hasTotals
              ? context
                    .tr('shop.priceChanged.continue')
                    .replaceAll('{total}', newTotal)
              : context.tr('shop.payAndOrder'),
          fullWidth: true,
          maxLines: 2,
          visualDensity: VisualDensity.standard,
          loading: _busy,
          onPressed: _busy ? null : _continue,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        FFButton(
          key: const Key('shop-price-changed-back'),
          label: context.tr('shop.priceChanged.back'),
          variant: FFButtonVariant.ghost,
          fullWidth: true,
          maxLines: 2,
          visualDensity: VisualDensity.standard,
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, ShopPriceChangeLine line) {
    final theme = Theme.of(context);
    final product = widget.product(line.productId);
    final name = [
      product?.name ?? '',
      ?line.variant,
    ].where((s) => s.isNotEmpty).join(' · ');
    final old = line.expectedPriceTzs == null
        ? null
        : formatCurrency(line.expectedPriceTzs!);
    final now = formatCurrency(line.currentPriceTzs);
    final reason = context.tr(line.reasonKey);
    final image = product?.images.firstOrNull;
    return _stop(
      Semantics(
        key: Key(
          'price-changed-${line.productId}'
          '${line.variant == null ? '' : '-${line.variant}'}',
        ),
        container: true,
        excludeSemantics: true,
        label: context
            .tr('shop.a11y.priceChangedRow')
            .replaceAll('{name}', name)
            .replaceAll('{old}', old ?? '-')
            .replaceAll('{new}', now)
            .replaceAll('{reason}', reason),
        child: Padding(
          padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(FFTokens.radiusSm),
                child: Container(
                  width: 48,
                  height: 48,
                  color: Colors.white,
                  child: image == null
                      ? const Icon(Icons.shopping_bag_outlined)
                      : FFRemoteImage(
                          src: image,
                          width: 48,
                          height: 48,
                          fit: BoxFit.contain,
                          fallback: const Icon(Icons.shopping_bag_outlined),
                        ),
                ),
              ),
              const SizedBox(width: FFTokens.spacingSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (old != null)
                      Text(
                        old,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: FFTokens.mutedText(context),
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    Text(
                      now,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: FFTokens.spacing2xs),
                    FFBadge(label: reason, tone: FFBadgeTone.gray, wrap: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A keyboard stop (with the shop's focus ring) for text the buyer
  /// should be able to reach with Tab: the rows and the totals.
  Widget _stop(Widget child) => ShopFocusRing(
    builder: (node) => Focus(focusNode: node, child: child),
  );
}
