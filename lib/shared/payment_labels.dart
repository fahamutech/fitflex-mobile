import 'package:flutter/widgets.dart';

import 'i18n.dart';
import 'models.dart';

/// A FitFlex Pass tier by name ("Pro"), the code itself for a tier this app
/// does not know yet, or [fallback] when there is none.
String passTierLabel(
  BuildContext context,
  Object? tier, {
  String fallback = '-',
}) {
  final id = tier?.toString().trim() ?? '';
  if (id.isEmpty) return fallback;
  final key = 'pass.$id';
  final label = context.tr(key);
  return label == key ? id.replaceAll('_', ' ') : label;
}

/// What a payment buys, in words the member recognises: a FitFlex Pass tier,
/// a gym plan at a named gym, a trainer session, a trainer's gym pass or a
/// shop order. Never a bare tier/plan code, which reads the same for products
/// that are not the same.
String paymentProductLabel(BuildContext context, PaymentRequest p) {
  String plan(String? id) => id == null ? '' : context.tr('member.plan_$id');
  switch (p.productType) {
    case 'FITFLEX_PASS':
      return '${context.tr('pay.product.fitflexPass')} · ${context.tr('pass.${p.tier}')}';
    case 'GYM_SUBSCRIPTION':
      final gym = p.gymName ?? context.tr('pay.product.gymPlan');
      final period = plan(p.plan);
      return period.isEmpty ? gym : '$gym · $period';
    case 'TRAINER_SERVICE':
      return context.tr('pay.product.trainerSession');
    case 'TRAINER_GYM_PASS':
      final gym = p.gymName ?? context.tr('pay.product.trainerPass');
      return '${context.tr('pay.product.trainerPass')} · $gym';
    case 'SHOP_ORDER':
      return context.tr('pay.product.shopOrder');
  }
  // Server without product types: the old tier/plan codes are all there is.
  if (p.tier.isNotEmpty) return context.tr('pass.${p.tier}');
  return (p.plan ?? '').toUpperCase();
}

/// Which gyms a FitFlex Pass tier opens ("Standard + Mid-tier gyms"), in
/// the member's language; an access level this app does not know is shown
/// as sent, and nothing at all as an empty string.
String passGymAccessLabel(BuildContext context, String? gymAccess) {
  final id = gymAccess?.trim() ?? '';
  if (id.isEmpty) return '';
  final key = 'pass.gymAccess.$id';
  final label = context.tr(key);
  return label == key ? id : label;
}

/// A shop payment method in words (`mpesa` → "M-Pesa"); the code itself,
/// tidied, for one this app does not know yet; [fallback] when there is none.
String shopPaymentMethodLabel(
  BuildContext context,
  Object? method, {
  String fallback = '-',
}) => _codeLabel(context, 'payment.method', method, fallback);

/// A shop order's payment status in words (`paid` → "Paid" / "Imelipwa").
String shopPaymentStatusLabel(
  BuildContext context,
  Object? status, {
  String fallback = '-',
}) => _codeLabel(context, 'payment.status', status, fallback);

String _codeLabel(
  BuildContext context,
  String prefix,
  Object? code,
  String fallback,
) {
  final id = code?.toString().trim() ?? '';
  if (id.isEmpty) return fallback;
  final key = '$prefix.$id';
  final label = context.tr(key);
  return label == key ? id.replaceAll('_', ' ') : label;
}
