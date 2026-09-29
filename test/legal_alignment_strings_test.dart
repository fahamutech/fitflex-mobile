// Strings for the terms-alignment changes (orders awaiting payment, gyms
// managing only their own members) exist in English and Swahili.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/shared/i18n.dart';

void main() {
  const keys = [
    'shop.orderPlaced',
    'shop.awaitingPayment',
    'vendor.awaitingPayment',
    'members.suspendConfirm',
    'members.directOnly',
    'members.ownDetails',
    'members.fitflexManaged',
  ];

  for (final lang in ['en', 'sw']) {
    test('$lang has every terms-alignment string', () {
      final locale = FFLocale()..set(Locale(lang));
      for (final key in keys) {
        expect(locale.t(key), isNot(key), reason: '$lang: $key');
      }
    });
  }

  test('the Swahili strings are translated, not copied', () {
    final en = FFLocale()..set(const Locale('en'));
    final sw = FFLocale()..set(const Locale('sw'));
    for (final key in keys) {
      expect(sw.t(key), isNot(en.t(key)), reason: key);
    }
  });
}
