// Marketplace checkout rules that do not depend on a screen: the idempotency
// key that makes a retried checkout safe, how an order's payment is described,
// and which failures mean "we do not know whether the order was placed".
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'i18n.dart';

/// One checkout attempt: the key the server uses to recognise a retry, and the
/// signature of what was being bought. The same key is reused while the cart
/// and delivery details are unchanged, so a timeout followed by a second tap
/// returns the first order instead of creating another.
class CheckoutAttempt {
  CheckoutAttempt({required this.key, required this.signature});
  final String key;
  final String signature;

  /// The attempt to use for [signature]: the current one if it is for the same
  /// purchase, otherwise a fresh one.
  static CheckoutAttempt forPurchase(
    CheckoutAttempt? current,
    String signature, {
    String Function()? makeKey,
  }) {
    if (current != null && current.signature == signature) return current;
    return CheckoutAttempt(
      key: (makeKey ?? newCheckoutKey)(),
      signature: signature,
    );
  }
}

/// 128 random bits as hex, prefixed so it is recognisable in logs. Matches the
/// server's rule (8-100 characters of letters, digits and ._:-).
String newCheckoutKey([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  return 'chk_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

/// What is being bought, in a form that changes whenever the order would.
String checkoutSignature({
  required List<Map<String, dynamic>> items,
  required String deliveryMethod,
  String? pickupGymId,
  String? deliveryAddress,
  required String paymentMethod,
}) {
  final lines =
      items
          .map((i) => '${i['productId']}|${i['variant'] ?? ''}|${i['qty']}')
          .toList()
        ..sort();
  return [
    lines.join(','),
    deliveryMethod,
    pickupGymId ?? '',
    deliveryAddress ?? '',
    paymentMethod,
  ].join('#');
}

/// The request may have reached the server and the order may exist: a timeout,
/// a dropped connection, or a server error. The cart must be kept and the same
/// key used for the retry. A clear 4xx answer means no order was made.
bool orderOutcomeUnknown(Object error) {
  if (error is ApiException) return error.status >= 500;
  return true;
}

/// How the customer's money stands for an order.
enum ShopOrderPayment {
  awaitingConfirmation,
  paid,
  refundPending,
  refunded,
  notConfirmed,
  cancelled,
}

ShopOrderPayment shopOrderPayment(Map<dynamic, dynamic> order) {
  switch (order['paymentStatus']?.toString()) {
    case 'paid':
      return ShopOrderPayment.paid;
    case 'refund_pending':
      return ShopOrderPayment.refundPending;
    case 'refunded':
      return ShopOrderPayment.refunded;
    case 'failed':
      return ShopOrderPayment.notConfirmed;
    case 'cancelled':
      return ShopOrderPayment.cancelled;
    default:
      return ShopOrderPayment.awaitingConfirmation;
  }
}

/// Every order status the marketplace can send, buyer- or vendor-side: the
/// canonical lifecycle in fitflex-functions `src/shared/order-lifecycle.mjs`
/// (STATUSES) plus the legacy `confirmed` (= accepted) and `fulfilled`
/// (= delivered) still found on old rows.
const shopOrderStatuses = {
  'pending',
  'accepted',
  'confirmed',
  'processing',
  'packed',
  'dispatched',
  'ready_for_pickup',
  'delivered',
  'fulfilled',
  'cancelled',
};

/// i18n key for an order status; a status this app does not know yet gets a
/// neutral "In progress" instead of its raw code.
String shopOrderStatusKey(Object? status) {
  final code = status?.toString() ?? '';
  return shopOrderStatuses.contains(code)
      ? 'shop.orderStatus.$code'
      : 'shop.orderStatus.unknown';
}

/// An order status in the member's or vendor's language.
/// The short order number people say and see ("7A09CE31" → "09CE31"):
/// `shortRef` when the server sends it (vendor orders do), otherwise the
/// server's own rule (fitflex-functions `shortRef`): the last 6 characters
/// of the id in capitals. Buyer and vendor therefore see the same number.
String shopOrderRef(Map<String, dynamic> order) {
  final ref = order['shortRef']?.toString().trim() ?? '';
  if (ref.isNotEmpty) return ref;
  final id = order['id']?.toString() ?? '';
  return (id.length > 6 ? id.substring(id.length - 6) : id).toUpperCase();
}

String shopOrderStatusLabel(BuildContext context, Object? status) =>
    context.tr(shopOrderStatusKey(status));

/// A stored status as the backend reads it: legacy `confirmed` is
/// `accepted`, legacy `fulfilled` is `delivered` (order-lifecycle.mjs
/// canonicalStatus).
String shopCanonicalOrderStatus(Object? status) => switch ('${status ?? ''}') {
  'confirmed' => 'accepted',
  'fulfilled' => 'delivered',
  final s => s,
};

/// Nothing follows these: no next step and no cancel.
bool shopOrderIsFinal(Object? status) =>
    const {'delivered', 'cancelled'}.contains(shopCanonicalOrderStatus(status));

/// The backend's forward moves per canonical status (order-lifecycle.mjs
/// FORWARD), used when the server sends no `nextStatuses`.
const _forward = <String, List<String>>{
  'pending': ['accepted'],
  'accepted': ['processing', 'packed', 'dispatched', 'ready_for_pickup'],
  'processing': ['packed', 'dispatched', 'ready_for_pickup'],
  'packed': ['dispatched', 'ready_for_pickup'],
  'dispatched': ['ready_for_pickup', 'delivered'],
  'ready_for_pickup': ['delivered'],
};

/// The statuses that may follow [status] for this delivery method, exactly
/// as the backend's nextStatuses(): gym pickup never goes straight from
/// dispatched to delivered; home delivery never uses ready_for_pickup.
List<String> shopAllowedNextStatuses(Object? status, Object? deliveryMethod) {
  final from = shopCanonicalOrderStatus(status);
  final list = _forward[from] ?? const <String>[];
  if (deliveryMethod == 'gym_pickup') {
    return [
      for (final s in list)
        if (!(from == 'dispatched' && s == 'delivered')) s,
    ];
  }
  return [
    for (final s in list)
      if (s != 'ready_for_pickup') s,
  ];
}

/// The one next step the vendor's button offers for their fulfilment, or
/// null when there is none. Prefers the server's own `nextStatuses` for this
/// vendor (sent with each vendor order) and falls back to the same matrix.
/// The step is the first allowed one, except that a gym-pickup order goes
/// to "ready for pickup" rather than "on the way" when both are allowed.
String? vendorNextOrderStatus(Map<dynamic, dynamic> order) {
  final status = order['status'] ?? 'pending';
  if (shopOrderIsFinal(status)) return null;
  final fromServer = order['nextStatuses'];
  var allowed = fromServer is List
      ? [for (final s in fromServer) '$s']
      : shopAllowedNextStatuses(status, order['deliveryMethod']);
  // The server sends none for an unpaid order; the button is still shown,
  // disabled, so the vendor sees what comes once it is paid.
  if (allowed.isEmpty && order['paymentStatus'] != 'paid') {
    allowed = shopAllowedNextStatuses(status, order['deliveryMethod']);
  }
  if (allowed.isEmpty) return null;
  if (order['deliveryMethod'] == 'gym_pickup' &&
      allowed.contains('ready_for_pickup') &&
      allowed.first == 'dispatched') {
    return 'ready_for_pickup';
  }
  return allowed.first;
}

/// The vendor's button for moving an order on to [next] ("Mark as packed",
/// sw "Fungasha oda"). Each step has its own wording; a step the app does
/// not know yet reads "Update status" rather than a word joined to a status.
String vendorMarkStatusLabel(BuildContext context, String next) {
  final key = 'vendor.markStatus.$next';
  final label = context.tr(key);
  return label == key ? context.tr('vendor.updateStatus') : label;
}

/// i18n key for the line shown under an order's total, or null when the order
/// needs no payment note (paid, or cancelled before any payment).
String? shopOrderPaymentKey(Map<dynamic, dynamic> order) =>
    switch (shopOrderPayment(order)) {
      ShopOrderPayment.awaitingConfirmation => 'shop.awaitingPayment',
      ShopOrderPayment.refundPending => 'shop.refundPending',
      ShopOrderPayment.refunded => 'shop.refunded',
      ShopOrderPayment.notConfirmed => 'shop.paymentNotConfirmed',
      _ => null,
    };

/// i18n key for a checkout the server refused, or null to use the generic message.
String? shopCheckoutErrorKey(Object error) {
  if (error is! ApiException) return null;
  return switch (error.code) {
    'insufficient_stock' => 'shop.errInsufficientStock',
    'price_changed' => 'shop.errPriceChanged',
    'product_not_found' => 'shop.errUnavailable',
    'vendor_unavailable' => 'shop.errVendorUnavailable',
    'variant_not_found' => 'shop.errUnavailable',
    'variant_required' => 'shop.errVariantRequired',
    'idempotency_key_reused' => 'shop.errChanged',
    _ => null,
  };
}

/// A message for a failed checkout, in the customer's language.
String shopCheckoutErrorMessage(FFLocale locale, Object error) {
  final key = shopCheckoutErrorKey(error);
  if (key != null) return locale.t(key);
  if (orderOutcomeUnknown(error)) return locale.t('shop.orderUncertain');
  return locale.t('shop.orderFailed');
}
