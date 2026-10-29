// Shop home Phase 2 · S4 (flash sales): a vendor's flash sale proposals,
// the rules the form checks before the server does, and the server's error
// codes mapped to the form's fields and messages.
//
// Contract: fitflex-functions docs/shop-flash-sales-api.md (feat/shop-
// flash-sales, flag SHOP_FLASH_SALES):
//   GET /vendor/flash-sales → {items, total, nextCursor, vendor: {canPropose,
//   reason}, proposalExpiryDays, openProposals: {open, max}, rules}
//   GET /vendor/flash-sales/price-check?productId&startsAt
//   POST /vendor/flash-sales {productId, salePriceTzs, startsAt, endsAt}
//   PATCH /:id {salePriceTzs?, startsAt?, endsAt?}
//   POST /:id/submit | withdraw | end → {sale}
//   GET /vendor/tools/options → merch: {flashSales: bool}
import '../../../shared/api_client.dart';

/// The numbers (the list's `rules`, with the contract's values when a
/// server does not send them).
class FlashSaleRules {
  const FlashSaleRules({
    this.minDiscountPct = 5,
    this.minLength = const Duration(hours: 1),
    this.maxLength = const Duration(days: 7),
    this.minLead = const Duration(hours: 1),
    this.lookbackDays = 14,
  });

  final int minDiscountPct;
  final Duration minLength;
  final Duration maxLength;
  final Duration minLead;
  final int lookbackDays;

  static FlashSaleRules fromJson(Object? json) {
    if (json is! Map) return const FlashSaleRules();
    int? i(Object? v) => v is num ? v.toInt() : null;
    Duration ms(Object? v, Duration d) =>
        i(v) == null || i(v)! <= 0 ? d : Duration(milliseconds: i(v)!);
    const base = FlashSaleRules();
    return FlashSaleRules(
      minDiscountPct: i(json['minDiscountPct']) ?? base.minDiscountPct,
      minLength: ms(json['minLengthMs'], base.minLength),
      maxLength: ms(json['maxLengthMs'], base.maxLength),
      minLead: ms(json['minLeadMs'], base.minLead),
      lookbackDays: i(json['priceRaiseLookbackDays']) ?? base.lookbackDays,
    );
  }
}

/// The highest sale price that is still [minPct] % off [regular]:
/// floor(regular × (100 − minPct) / 100).
int flashSaleMaxPrice(num regular, {int minPct = 5}) =>
    (regular * (100 - minPct) / 100).floor();

/// floor((regular − sale) × 100 / regular): never overstated.
int flashSalePercent(num regular, num sale) =>
    regular <= 0 ? 0 : ((regular - sale) * 100 / regular).floor();

/// The seller's standing discount, when it is a real one (0 < d < price).
num? standingDiscount(num regular, num? discount) =>
    discount != null && discount > 0 && discount < regular ? discount : null;

/// What is wrong with a sale price, as the form says it: `enterPrice`
/// (empty, 0 or not a whole number), `min5` (less than the minimum off the
/// regular price), `belowDiscount` (not below the standing discount), or
/// null. No maximum discount (owner decision O-4).
String? flashSalePriceProblem({
  required num regular,
  num? discount,
  required int? sale,
  int minPct = 5,
}) {
  if (sale == null || sale < 1) return 'enterPrice';
  if (sale > flashSaleMaxPrice(regular, minPct: minPct)) return 'min5';
  final standing = standingDiscount(regular, discount);
  if (standing != null && sale >= standing) return 'belowDiscount';
  return null;
}

/// What is wrong with the dates: `required`, `startSoon` (less than the
/// lead time from [now]), `endAfter`, `length` (outside 1 hour–7 days), or
/// null. Instants are UTC.
String? flashSaleDatesProblem({
  required DateTime? startsAt,
  required DateTime? endsAt,
  required DateTime now,
  FlashSaleRules rules = const FlashSaleRules(),
}) {
  if (startsAt == null || endsAt == null) return 'required';
  if (startsAt.isBefore(now.add(rules.minLead))) return 'startSoon';
  if (!endsAt.isAfter(startsAt)) return 'endAfter';
  final length = endsAt.difference(startsAt);
  if (length < rules.minLength || length > rules.maxLength) return 'length';
  return null;
}

/// The 14-day rule's answer (GET /vendor/flash-sales/price-check, or the
/// body of `422 price_raised_recently`).
class FlashSalePriceCheck {
  const FlashSalePriceCheck({
    required this.ok,
    this.regularPriceTzs,
    this.discountPriceTzs,
    this.maxSalePriceTzs,
    this.raisedOn,
    this.earliestStart,
    this.lockedStartsAt,
    this.lockedEndsAt,
    this.listedOn,
  });

  final bool ok;

  /// `price_history_too_short`: the product was listed on this Tanzania day
  /// and needs 14 days in the shop before a sale ([earliestStart]).
  final DateTime? listedOn;

  /// The 14 days of price history are not there yet (a new product).
  bool get historyShort => raised && listedOn != null;
  final num? regularPriceTzs;
  final num? discountPriceTzs;
  final num? maxSalePriceTzs;

  /// The Tanzania date of the raise (`YYYY-MM-DD`), as a calendar day.
  final DateTime? raisedOn;
  final DateTime? earliestStart;

  /// Another sale holds the product (`lockedBy`).
  final DateTime? lockedStartsAt;
  final DateTime? lockedEndsAt;

  /// The 14-day rule failed.
  bool get raised => !ok && earliestStart != null;

  /// Another sale holds the product at that time.
  bool get locked => !ok && lockedStartsAt != null;

  static DateTime? _date(Object? v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toUtc();

  /// An instant (`listedAt`) as the Tanzania calendar day it fell on.
  static DateTime? tanzaniaDay(Object? v) {
    final at = DateTime.tryParse(v?.toString() ?? '');
    if (at == null) return null;
    final e = at.toUtc().add(const Duration(hours: 3));
    return DateTime(e.year, e.month, e.day);
  }

  /// `raisedOn` is a date with no time: kept as that calendar day.
  static DateTime? day(Object? v) {
    final s = v?.toString() ?? '';
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    return DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
  }

  static FlashSalePriceCheck fromJson(Map json) {
    num? n(Object? v) => v is num ? v : null;
    final lock = json['lockedBy'] is Map ? json['lockedBy'] as Map : null;
    return FlashSalePriceCheck(
      ok: json['ok'] != false,
      regularPriceTzs: n(json['regularPriceTzs']),
      discountPriceTzs: n(json['discountPriceTzs']),
      maxSalePriceTzs: n(json['maxSalePriceTzs']),
      raisedOn: day(json['raisedOn']),
      earliestStart: _date(json['earliestStart']),
      lockedStartsAt: _date(lock?['startsAt']),
      lockedEndsAt: _date(lock?['endsAt']),
      listedOn: tanzaniaDay(json['listedAt']),
    );
  }
}

/// One flash sale on the vendor's products (the vendor view).
class VendorFlashSale {
  const VendorFlashSale({
    required this.id,
    required this.status,
    required this.productId,
    this.origin = 'vendor',
    this.productName = '',
    this.productImage,
    this.salePriceTzs = 0,
    this.regularPriceTzs = 0,
    this.discountPriceTzs,
    this.wasPriceTzs,
    this.discountPct,
    this.savingTzs,
    this.startsAt,
    this.endsAt,
    this.expiresAt,
    this.endedAt,
    this.reasonCode,
    this.reasonNote,
    this.endedByFitflex = false,
    this.allowedActions,
  });

  final String id;

  /// `effectiveStatus`: draft, pending_approval, approved, live, ended,
  /// rejected, expired, withdrawn.
  final String status;

  /// `vendor`, or `staff` (FitFlex made it on this product: read-only).
  final String origin;
  final String productId;
  final String productName;
  final String? productImage;
  final num salePriceTzs;

  /// The product's price now.
  final num regularPriceTzs;
  final num? discountPriceTzs;

  /// The price when it was approved (null until then).
  final num? wasPriceTzs;
  final int? discountPct;
  final num? savingTzs;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? expiresAt;
  final DateTime? endedAt;

  /// `statusReason` (window_passed, ended_by_vendor, ended_by_fitflex,
  /// price_not_credible, product, timing, other, not_reviewed_in_time,
  /// start_passed) and staff's note.
  final String? reasonCode;
  final String? reasonNote;
  final bool endedByFitflex;

  /// What this vendor may do now (edit, submit, withdraw, end). Null from a
  /// server that does not send it: worked out from [status].
  final List<String>? allowedActions;

  /// The price the % is measured against: the approved "was" price, else
  /// the product's price now.
  num get basePrice => wasPriceTzs ?? regularPriceTzs;

  int get percentOff =>
      discountPct ?? flashSalePercent(basePrice, salePriceTzs);

  static DateTime? _date(Object? v) =>
      DateTime.tryParse(v?.toString() ?? '')?.toUtc();

  static String? _str(Object? v) {
    final s = v?.toString().trim() ?? '';
    return s.isEmpty ? null : s;
  }

  static num _num(Object? v) => v is num ? v : num.tryParse('$v') ?? 0;
  static num? _numOrNull(Object? v) => v is num ? v : null;

  factory VendorFlashSale.fromJson(Map<String, dynamic> json) {
    final actions = json['allowedActions'];
    return VendorFlashSale(
      id: json['id']?.toString() ?? '',
      status:
          (json['effectiveStatus'] ?? json['status'])?.toString() ?? 'draft',
      origin: json['origin']?.toString() == 'staff' ? 'staff' : 'vendor',
      productId: json['productId']?.toString() ?? '',
      productName: json['productName']?.toString() ?? '',
      productImage: _str(json['productImage']),
      salePriceTzs: _num(json['salePriceTzs']),
      regularPriceTzs: _num(json['regularPriceTzs']),
      discountPriceTzs: _numOrNull(json['discountPriceTzs']),
      wasPriceTzs: _numOrNull(json['wasPriceTzs']),
      discountPct: _numOrNull(json['discountPct'])?.toInt(),
      savingTzs: _numOrNull(json['savingTzs']),
      startsAt: _date(json['startsAt']),
      endsAt: _date(json['endsAt']),
      expiresAt: _date(json['expiresAt']),
      endedAt: _date(json['endedAt']),
      reasonCode: _str(json['statusReason']),
      reasonNote: _str(json['statusReasonNote']),
      endedByFitflex:
          json['endedByFitflex'] == true ||
          json['statusReason'] == 'ended_by_fitflex',
      allowedActions: actions is List
          ? [for (final a in actions) a.toString()]
          : null,
    );
  }

  /// FitFlex made it: the vendor sees it but does nothing with it.
  bool get byFitflex => origin == 'staff';

  bool _may(String action, Set<String> fallback) =>
      allowedActions?.contains(action) ??
      (!byFitflex && fallback.contains(status));

  /// Edit (a scheduled one goes back for approval; a rejected one becomes
  /// a draft). Live, ended, expired and withdrawn ones can't change.
  bool get canEdit =>
      _may('edit', const {'draft', 'pending_approval', 'approved', 'rejected'});
  bool get canSubmit => _may('submit', const {'draft'});
  bool get canWithdraw =>
      _may('withdraw', const {'draft', 'pending_approval', 'approved'});

  /// End now: a live sale; also a scheduled one FitFlex made (the vendor
  /// can't withdraw those, owner ruling 2026-10-29: vendors may end
  /// FitFlex-made sales on their products). The server's allowedActions
  /// decide when sent.
  bool get canEnd =>
      allowedActions?.contains('end') ??
      (byFitflex
          ? const {'live', 'approved'}.contains(status)
          : status == 'live');

  bool get editResends => status == 'approved';
}

/// The list group a status falls in (same as banners).
String flashSaleGroup(String status) => switch (status) {
  'live' => 'live',
  'approved' => 'scheduled',
  'pending_approval' => 'waiting',
  'draft' => 'drafts',
  _ => 'past',
};

const flashSaleGroups = ['live', 'scheduled', 'waiting', 'drafts', 'past'];

/// The i18n key for a rejection reason, or null for another code.
String? flashSaleRejectKey(String? code) => switch (code) {
  'price_not_credible' => 'merch.sale.reject.priceNotCredible',
  'product' => 'merch.sale.reject.product',
  'timing' => 'merch.sale.reject.timing',
  'other' => 'merch.reject.other',
  _ => null,
};

/// Where a refused save is shown: under a field (`price`, `startsAt`,
/// `endsAt`, `product`), as the 14-day alert (`raised`), or as a message
/// over the form (`message`; [closes] when the form can't go on).
class FlashSaleError {
  const FlashSaleError(
    this.target,
    this.key, {
    this.params = const {},
    this.closes = false,
  });

  final String target;
  final String key;
  final Map<String, Object?> params;
  final bool closes;
}

/// The server's refusal as the form shows it (docs/shop-flash-sales-api.md
/// "Rules"). Anything not listed: "Couldn't save. Try again."
FlashSaleError flashSaleError(ApiException e) {
  final body = e.body is Map ? e.body as Map : const {};
  switch (e.code) {
    case 'invalid_field':
      return switch (body['field']?.toString()) {
        'startsAt' => const FlashSaleError('startsAt', 'merch.dates.required'),
        'endsAt' => const FlashSaleError('endsAt', 'merch.dates.required'),
        'productId' => const FlashSaleError(
          'product',
          'merch.sale.productRequired',
        ),
        _ => const FlashSaleError('price', 'merch.sale.enterPrice'),
      };
    case 'discount_out_of_range':
      if (body['reason'] == 'not_below_effective') {
        return FlashSaleError(
          'price',
          'merch.sale.belowDiscount',
          params: {
            'discount': body['discountPriceTzs'] ?? body['effectivePriceTzs'],
          },
        );
      }
      return FlashSaleError(
        'price',
        'merch.sale.min5',
        params: {'max': body['maxSalePriceTzs']},
      );
    case 'sale_length_out_of_range':
      return const FlashSaleError('endsAt', 'merch.sale.length');
    case 'end_before_start':
      return const FlashSaleError('endsAt', 'merch.dates.endAfter');
    case 'start_too_soon':
      return const FlashSaleError('startsAt', 'merch.dates.startSoon');
    case 'invalid_date':
      return FlashSaleError(
        body['field']?.toString() == 'endsAt' ? 'endsAt' : 'startsAt',
        'merch.dates.required',
      );
    case 'price_raised_recently':
      return FlashSaleError(
        'raised',
        'merch.sale.raised',
        params: {
          'raisedOn': body['raisedOn'],
          'earliestStart': body['earliestStart'],
        },
      );
    case 'price_history_too_short':
      return FlashSaleError(
        'raised',
        'merch.sale.historyShort',
        params: {
          'listedAt': body['listedAt'],
          'earliestStart': body['earliestStart'],
        },
      );
    case 'sale_overlap':
      return FlashSaleError(
        'product',
        'merch.sale.overlap',
        params: {'start': body['startsAt'], 'end': body['endsAt']},
      );
    case 'product_not_eligible':
    case 'product_not_found':
    case 'not_your_product':
      return const FlashSaleError('product', 'merch.sale.notEligible');
    case 'vendor_suspended':
      return const FlashSaleError(
        'message',
        'merch.sale.suspended',
        closes: true,
      );
    case 'vendor_not_approved':
      return const FlashSaleError('message', 'merch.pendingBody', closes: true);
    case 'vendor_permission_forbidden':
      return const FlashSaleError('message', 'vendor.noAccess', closes: true);
    case 'too_many_open_proposals':
      return const FlashSaleError('message', 'merch.sales.tooManyOpen');
    case 'rate_limited':
      return const FlashSaleError('message', 'merch.rateLimited');
    case 'not_editable':
    case 'invalid_transition':
    case 'proposal_expired':
    case 'product_not_editable':
      return const FlashSaleError(
        'message',
        'merch.sale.notEditable',
        closes: true,
      );
    case 'vendor_not_found':
    case 'sale_not_found':
      return const FlashSaleError('message', 'merch.notYours', closes: true);
    case 'feature_disabled':
      return const FlashSaleError('message', 'merch.unavailable', closes: true);
    default:
      return const FlashSaleError('message', 'merch.saveFailed');
  }
}
