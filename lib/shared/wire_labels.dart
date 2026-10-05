// Labels for values the server sends as codes ("midtier", "out_for_delivery").
// A code is never shown raw: each has a label in both languages, and one the
// app does not know yet falls back to readable text.

import 'i18n.dart';

String? _label(FFLocale locale, String key) {
  final text = locale.t(key);
  return text == key ? null : text;
}

String _code(String? value) =>
    (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');

/// "out_for_delivery" → "Out for delivery".
String _readable(String value) {
  final clean = value.replaceAll(RegExp(r'[_-]+'), ' ').trim();
  if (clean.isEmpty) return '';
  return '${clean[0].toUpperCase()}${clean.substring(1)}';
}

/// A gym tier badge: "midtier" → "Mid-tier". Tier names stay English.
String gymTierLabel(FFLocale locale, String? tier) {
  final code = switch (_code(tier)) {
    'mid_tier' || 'mid_range' => 'midtier',
    'luxury' || 'executive' => 'luxury_executive',
    final other => other,
  };
  return _label(locale, 'gym.tier.$code') ?? _readable(tier ?? '');
}

/// Which gyms a pass opens, from its `gymAccess` tier.
String passGymAccessLabel(FFLocale locale, String? gymAccess) =>
    _label(locale, 'pass.access.${_code(gymAccess)}') ?? (gymAccess ?? '');

/// An order, payment, enquiry, shop or gym status.
String statusLabel(FFLocale locale, String? status, {String fallback = ''}) {
  final code = switch (_code(status)) {
    'canceled' => 'cancelled',
    final other => other,
  };
  if (code.isEmpty) return fallback;
  return _label(locale, 'wire.status.$code') ?? _readable(status!);
}

/// How an order was paid. Provider names are brands and are not translated.
String paymentMethodLabel(FFLocale locale, String? method) {
  const brands = {
    'mpesa': 'M-Pesa',
    'airtel_money': 'Airtel Money',
    'mixx': 'Mixx',
    'halopesa': 'HaloPesa',
  };
  final code = _code(method);
  return brands[code] ??
      _label(locale, 'wire.pay.$code') ??
      _readable(method ?? '');
}

/// The vendor's button that moves an order to [nextStatus].
String vendorSetStatusLabel(FFLocale locale, String nextStatus) =>
    _label(locale, 'vendor.setStatus.${_code(nextStatus)}') ??
    locale.t('vendor.setStatus.other');
