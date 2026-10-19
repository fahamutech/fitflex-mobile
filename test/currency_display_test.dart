// D-8 (owner, 2026-10-19): money is displayed as "TSh" in English and
// Swahili; "TZS" stays only as the ISO code in data and API payloads.
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('currencyLabel', () {
    test('maps the ISO code TZS to TSh', () {
      expect(currencyLabel('TZS'), 'TSh');
      expect(currencyLabel('tzs'), 'TSh');
      expect(currencyLabel(' TZS '), 'TSh');
    });

    test('falls back to TSh when no code is given', () {
      expect(currencyLabel(null), 'TSh');
      expect(currencyLabel(''), 'TSh');
    });

    test('leaves other codes as they are', () {
      expect(currencyLabel('USD'), 'USD');
    });
  });

  group('formatCurrency', () {
    test('shows TSh by default', () {
      expect(formatCurrency(279000), 'TSh 279,000');
      expect(formatCurrency(0), 'TSh 0');
      expect(formatCurrency(-3500), 'TSh -3,500');
    });

    test('shows TSh when the data code is TZS', () {
      expect(formatCurrency(1234567, currency: 'TZS'), 'TSh 1,234,567');
    });

    test('keeps a non-TZS code', () {
      expect(formatCurrency(50, currency: 'USD'), 'USD 50');
    });
  });

  test('no English or Swahili string displays TZS', () {
    for (final lang in ['en', 'sw']) {
      final bad = FFLocale.keysOf(
        lang,
      ).where((k) => (FFLocale.textOf(lang, k) ?? '').contains('TZS')).toList();
      expect(bad, isEmpty, reason: '$lang strings still show TZS');
    }
  });
}
