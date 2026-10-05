import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_error_message.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/social.dart';
import 'package:fitflexmobile/shared/wire_labels.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  FFLocale en() => FFLocale();
  FFLocale sw() => FFLocale()..set(const Locale('sw'));

  test('every key exists in both languages', () {
    final english = FFLocale.keysOf('en');
    final swahili = FFLocale.keysOf('sw');
    expect(english.difference(swahili), isEmpty, reason: 'missing in sw');
    expect(swahili.difference(english), isEmpty, reason: 'missing in en');
  });

  test('Swahili never uses the banned terms', () {
    final banned = RegExp(
      r'\b(jimu|kocha|mkufunzi|wakufunzi|changamoto|firebase)\b',
      caseSensitive: false,
    );
    final locale = sw();
    for (final key in FFLocale.keysOf('sw').where(_isNew)) {
      expect(locale.t(key), isNot(matches(banned)), reason: key);
    }
  });

  group('server values get a label', () {
    test('gym tiers keep their English names', () {
      for (final locale in [en(), sw()]) {
        expect(gymTierLabel(locale, 'standard'), 'Standard');
        expect(gymTierLabel(locale, 'midtier'), 'Mid-tier');
        expect(gymTierLabel(locale, 'mid_tier'), 'Mid-tier');
        expect(gymTierLabel(locale, 'premium'), 'Premium');
        expect(gymTierLabel(locale, 'luxury_executive'), 'Luxury/Executive');
        expect(gymTierLabel(locale, 'brand_new'), 'Brand new');
      }
    });

    test('pass gym access', () {
      expect(passGymAccessLabel(en(), 'midtier'), 'Standard + Mid-tier gyms');
      expect(passGymAccessLabel(sw(), 'standard'), 'Gym za Standard');
      expect(
        passGymAccessLabel(sw(), 'luxury_executive'),
        'Gym zote, zikiwemo Luxury/Executive',
      );
      expect(passGymAccessLabel(sw(), 'other'), 'other');
      expect(passGymAccessLabel(sw(), null), '');
    });

    test('statuses', () {
      expect(statusLabel(en(), 'pending'), 'Pending');
      expect(statusLabel(en(), 'out_for_delivery'), 'Out for delivery');
      expect(statusLabel(sw(), 'pending'), 'Inasubiri');
      expect(statusLabel(sw(), 'cancelled'), 'Imeghairiwa');
      expect(statusLabel(sw(), 'canceled'), 'Imeghairiwa');
      expect(statusLabel(sw(), 'failed'), 'Imeshindikana');
      expect(statusLabel(sw(), 'suspended'), 'Imesimamishwa');
      expect(statusLabel(sw(), 'paid'), 'Imelipwa');
      // Unknown values are made readable, never shown as a raw code.
      expect(statusLabel(sw(), 'on_hold_review'), 'On hold review');
      expect(statusLabel(sw(), null, fallback: '-'), '-');
    });

    test('payment methods', () {
      expect(paymentMethodLabel(sw(), 'mpesa'), 'M-Pesa');
      expect(paymentMethodLabel(sw(), 'airtel_money'), 'Airtel Money');
      expect(paymentMethodLabel(sw(), 'card'), 'Kadi');
      expect(paymentMethodLabel(sw(), 'bank'), 'Benki');
      expect(paymentMethodLabel(en(), 'card'), 'Card');
    });

    test('the vendor button has one label per step', () {
      expect(vendorSetStatusLabel(en(), 'accepted'), 'Mark accepted');
      expect(
        vendorSetStatusLabel(en(), 'ready_for_pickup'),
        'Mark ready for pickup',
      );
      expect(vendorSetStatusLabel(sw(), 'accepted'), 'Weka kuwa imekubaliwa');
      expect(vendorSetStatusLabel(sw(), 'delivered'), 'Weka kuwa imefikishwa');
      expect(vendorSetStatusLabel(sw(), 'something_new'), 'Badilisha hali');
    });
  });

  group('errors', () {
    test('an unknown server reason is not shown in English to Swahili', () {
      final unknown = ApiException(400, {'error': 'phone_already_used'});
      expect(
        apiErrorMessage(en(), unknown),
        'Request declined: Phone already used',
      );
      expect(
        apiErrorMessage(sw(), unknown),
        'Ombi halikukamilika. Jaribu tena.',
      );
      expect(
        apiErrorMessage(sw(), ApiException(404, {'message': 'Gym not found'})),
        'Kitu ulichoomba hakikupatikana.',
      );
      // A known reason is still explained.
      expect(
        apiErrorMessage(sw(), ApiException(400, {'error': 'gym_closed'})),
        'Ombi limekataliwa: Gym hii imefungwa kwa sasa',
      );
    });

    test('sign-in errors never show the SDK message or a raw code', () {
      expect(
        authErrorMessage(en(), 'too-many-requests'),
        'Too many attempts. Wait a moment and try again.',
      );
      expect(
        authErrorMessage(sw(), 'no-current-user'),
        'Hujaingia. Ingia tena kisha ujaribu.',
      );
      expect(
        authErrorMessage(sw(), 'missing-google-id-token'),
        'Imeshindikana kuingia kwa Google. Jaribu tena.',
      );
      expect(
        authErrorMessage(sw(), 'internal-error'),
        'Imeshindikana. Jaribu tena.',
      );
      expect(sw().t('auth.errorTitle'), 'Imeshindikana kuingia');
    });
  });

  test('a person with no name gets a translated one', () {
    en();
    expect(const SocialPerson(id: 'p1').name, 'FitFlex member');
    sw();
    expect(const SocialPerson(id: 'p1').name, 'Mwanachama wa FitFlex');
    expect(const SocialPerson(id: 'p1', displayName: ' Asha ').name, 'Asha');
    expect(FFLocale.textIn('sw', 'lang.continue'), 'Endelea');
  });
}

bool _isNew(String key) =>
    key.startsWith('wire.') ||
    key.startsWith('gym.tier.') ||
    key.startsWith('pass.access.') ||
    key.startsWith('vendor.setStatus.') ||
    key.startsWith('kyc.country.') ||
    key.startsWith('auth.') ||
    key.startsWith('common.');
