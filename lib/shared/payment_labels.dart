import 'package:flutter/widgets.dart';

import 'i18n.dart';
import 'models.dart';

/// What a payment buys, in words the member recognises: a FitFlex Pass tier,
/// a gym plan at a named gym, a trainer session, a trainer's gym pass or a
/// shop order. Never a bare tier/plan code, which reads the same for products
/// that are not the same.
String paymentProductLabel(BuildContext context, PaymentRequest p) {
  String plan(String? id) =>
      id == null ? '' : context.tr('member.plan_$id');
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
