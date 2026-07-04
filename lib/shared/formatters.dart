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

/// Formats an amount as a currency string, e.g. `1234567` with currency
/// `TZS` -> `TZS 1,234,567`.
String formatCurrency(num value, {String currency = 'TZS'}) {
  return '$currency ${formatMoney(value)}';
}
