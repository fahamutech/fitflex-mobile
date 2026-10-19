// Shared number/currency formatting helpers. No external deps — keeps
// formatting consistent and avoids pulling in locale-dependent behaviour.

/// Formats an integer amount with thousand separators, e.g. `1234567` ->
/// `1,234,567`. Handles negative values correctly.
String formatMoney(num value) {
  final isNegative = value < 0;
  final s = value.abs().toInt().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return isNegative ? '-${buf.toString()}' : buf.toString();
}

/// Display label for an ISO currency code. Tanzanian shillings are shown as
/// "TSh" in English and Swahili (owner decision D-8, 2026-10-19); the ISO
/// code "TZS" stays in data, API fields and payment payloads. Other codes
/// are shown as given.
String currencyLabel(String? code) {
  final c = (code ?? '').trim();
  if (c.isEmpty || c.toUpperCase() == 'TZS') return 'TSh';
  return c;
}

/// Formats an amount as a currency string, e.g. `1234567` with currency
/// `TZS` -> `TSh 1,234,567`. [currency] is the ISO code (data value); it is
/// mapped to its display label with [currencyLabel].
String formatCurrency(num value, {String currency = 'TZS'}) {
  return '${currencyLabel(currency)} ${formatMoney(value)}';
}
