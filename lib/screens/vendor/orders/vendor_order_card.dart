// Vendor tools · S2 (order privacy): one order in the vendor Orders tab.
//
// Reads the allowlisted vendor order of fitflex-functions#200:
// { id, shortRef, status (own), items[{ name, variant|null, qty, … }],
//   totalTzs, paymentStatus, paymentMethod, deliveryMethod,
//   pickupGymId|null, pickupGym{ id, name|null }|null,
//   buyer{ customerId, displayName|null, phone?, contactVisibleUntil? },
//   deliveryAddress? }.
// Every S2 field is optional here so the card keeps working against an older
// backend (no shortRef, buyer or pickupGym; deliveryAddress always present).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/payment_labels.dart';
import '../../../shared/i18n.dart';
import '../../../shared/shop_checkout.dart';
import '../stock/stock_options.dart';

/// Opens the phone app; tests replace it.
@visibleForTesting
Future<bool> Function(Uri uri) vendorOrderDialer = (uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// The order number shown to the vendor: `shortRef`, or (older backend) the
/// same rule the server uses, the last 6 characters of the id in capitals.
String vendorOrderRef(Map<String, dynamic> order) {
  final ref = order['shortRef']?.toString().trim() ?? '';
  if (ref.isNotEmpty) return ref;
  final id = order['id']?.toString() ?? '';
  return (id.length > 6 ? id.substring(id.length - 6) : id).toUpperCase();
}

/// The pickup gym's name; the raw id only when the server sent no name.
String vendorPickupGymLabel(Map<String, dynamic> order) {
  final gym = order['pickupGym'];
  if (gym is Map) {
    final name = gym['name']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    final id = gym['id']?.toString() ?? '';
    if (id.isNotEmpty) return id;
  }
  final id = order['pickupGymId']?.toString() ?? '';
  return id.isEmpty ? '-' : id;
}

class VendorOrderCard extends StatelessWidget {
  const VendorOrderCard({
    super.key,
    required this.order,
    this.tools = VendorTools.off,
    this.actions,
  });

  final Map<String, dynamic> order;
  final VendorTools tools;

  /// Next-step and cancel buttons, built by the Orders tab.
  final Widget? actions;

  String get _id => order['id']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final status = order['status']?.toString() ?? 'pending';
    final delivered = shopCanonicalOrderStatus(status) == 'delivered';
    final pickup = order['deliveryMethod'] == 'gym_pickup';
    final buyer = order['buyer'] is Map
        ? Map<String, dynamic>.from(order['buyer'] as Map)
        : null;
    final phone = buyer?['phone']?.toString().trim() ?? '';
    final address = order['deliveryAddress']?.toString().trim() ?? '';
    final until = buyer?['contactVisibleUntil'];
    final lang = FFLocaleScope.of(context).locale.languageCode;
    final items = (order['items'] as List? ?? []).whereType<Map>().toList();

    return FFCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context
                .tr('vendor.orders.ref')
                .replaceAll('{ref}', vendorOrderRef(order)),
            key: Key('vendor-order-ref-$_id'),
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: 2),
          for (final item in items) _itemLine(context, item),
          const SizedBox(height: 4),
          Text(
            '${formatCurrency(order['totalTzs'] as num? ?? 0)} · ${context.tr('vendor.status')}: ${shopOrderStatusLabel(context, status)}',
            key: Key('vendor-order-status-$_id'),
          ),
          Text(
            '${context.tr('vendor.payment')}: ${shopPaymentStatusLabel(context, order['paymentStatus'])} · ${shopPaymentMethodLabel(context, order['paymentMethod'])}',
          ),
          if (buyer != null)
            Text(
              context
                  .tr('vendor.orders.buyer')
                  .replaceAll('{name}', _buyerName(context, buyer)),
              key: Key('vendor-order-buyer-$_id'),
            ),
          if (pickup)
            Text(
              '${context.tr('vendor.pickupGym')}: ${vendorPickupGymLabel(order)}',
              key: Key('vendor-order-pickup-$_id'),
            )
          else if (address.isNotEmpty)
            Text('${context.tr('vendor.deliveryAddress')}: $address')
          else if (!delivered)
            Text('${context.tr('vendor.deliveryAddress')}: -'),
          if (phone.isNotEmpty) ...[
            const SizedBox(height: FFTokens.spacingXs),
            FFButton(
              key: Key('vendor-order-call-$_id'),
              label: context
                  .tr('vendor.orders.call')
                  .replaceAll('{phone}', phone),
              semanticLabel: context
                  .tr('vendor.orders.callBuyer')
                  .replaceAll('{phone}', phone),
              icon: Icons.call_outlined,
              variant: FFButtonVariant.secondary,
              // 48px, also on web (the compact default is 40).
              visualDensity: VisualDensity.standard,
              onPressed: () => _call(context, phone),
            ),
          ],
          if (until is String && until.trim().isNotEmpty)
            Text(
              context
                  .tr('vendor.orders.contactUntil')
                  .replaceAll(
                    '{date}',
                    formatDate(_calendarDay(until), locale: lang),
                  ),
              key: Key('vendor-order-contact-until-$_id'),
              style: muted,
            ),
          // O-3: the server stops sending the contact 7 days after delivery.
          if (delivered && phone.isEmpty && address.isEmpty)
            if (tools.buyerContact)
              Text(
                context.tr('vendor.orders.contactHidden'),
                key: Key('vendor-order-contact-hidden-$_id'),
                style: muted,
              )
            else if (!pickup)
              Text(
                context.tr('vendor.orders.addressHidden'),
                key: Key('vendor-order-contact-hidden-$_id'),
                style: muted,
              ),
          if (order['paymentStatus'] == 'pending')
            Text(context.tr('vendor.awaitingPayment'), style: muted),
          ?actions,
        ],
      ),
    );
  }

  Widget _itemLine(BuildContext context, Map item) {
    final variant = item['variant']?.toString().trim() ?? '';
    final line = '${item['qty']}× ${item['name']}';
    return Text(
      variant.isEmpty
          ? line
          : '$line · ${context.tr('vendor.orders.variant').replaceAll('{name}', variant)}',
      style: Theme.of(context).textTheme.titleSmall,
    );
  }

  String _buyerName(BuildContext context, Map<String, dynamic> buyer) {
    final name = buyer['displayName']?.toString().trim() ?? '';
    return name.isEmpty ? context.tr('vendor.orders.buyerUnnamed') : name;
  }

  /// The day in the server's own (EAT) date, so a phone on another time
  /// zone does not show the day before or after.
  static Object _calendarDay(String value) {
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value.trim());
    if (match == null) return value;
    return DateTime(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      12,
    );
  }

  Future<void> _call(BuildContext context, String phone) async {
    final failed = context
        .tr('vendor.orders.callFailed')
        .replaceAll('{phone}', phone);
    var ok = false;
    try {
      ok = await vendorOrderDialer(
        Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^\d+]'), '')),
      );
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) FFSnack.error(context, failed);
  }
}
