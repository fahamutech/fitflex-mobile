import 'package:fitflexmobile/screens/member/widgets/gym_card.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_filters.dart';
import 'package:fitflexmobile/screens/owner/owner_qr_scanner_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/payment_labels.dart';
import 'package:fitflexmobile/shared/shop_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps [build] under the app's locale scope and returns what it produced.
Future<String> _say(
  WidgetTester tester,
  String Function(BuildContext) build, {
  String lang = 'en',
}) async {
  final locale = FFLocale();
  if (lang != 'en') locale.set(Locale(lang));
  late String out;
  await tester.pumpWidget(
    FFLocaleScope(
      notifier: locale,
      child: Builder(
        builder: (context) {
          out = build(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return out;
}

Gym _gym(String tier) => Gym.fromJson({
  'id': 'g-$tier',
  'name': 'Gym $tier',
  'tier': tier,
  'location': 'Masaki',
  'perVisitRate': 5000,
  'commissionRate': 10,
  'status': 'active',
});

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('gym tier labels', () {
    testWidgets('codes read as words in both languages', (tester) async {
      expect(
        await _say(tester, (c) => gymTierLabel(c, _gym('midtier'))),
        'Mid-tier',
      );
      expect(
        await _say(tester, (c) => gymTierLabel(c, _gym('mid-range'))),
        'Mid-tier',
      );
      expect(
        await _say(tester, (c) => gymTierLabel(c, _gym('luxury'))),
        'Luxury / Executive',
      );
      expect(
        await _say(tester, (c) => gymTierLabel(c, _gym('luxury_executive'))),
        'Luxury / Executive',
      );
      // Tier names stay English in Swahili (owner decision 2026-10-04).
      expect(
        await _say(tester, (c) => gymTierLabel(c, _gym('midtier')), lang: 'sw'),
        'Mid-tier',
      );
      // A tier the app does not know is tidied, never a key.
      expect(await _say(tester, (c) => tierLabel(c, 'gold_plus')), 'gold plus');
    });

    test('every gym tier has English and Swahili', () {
      for (final t in ['standard', 'midtier', 'premium', 'luxury_executive']) {
        expect(FFLocale.textOf('en', 'tier.$t'), isNotNull, reason: t);
        expect(FFLocale.textOf('sw', 'tier.$t'), isNotNull, reason: t);
      }
    });

    testWidgets('the gym card shows "Mid-tier", not "midtier"', (tester) async {
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp(
            home: Scaffold(body: GymCard(gym: _gym('midtier'))),
          ),
        ),
      );
      expect(find.text('Mid-tier'), findsOneWidget);
      expect(find.text('midtier'), findsNothing);
    });

    testWidgets('pass tiers on the scanner and invitations are named', (
      tester,
    ) async {
      expect(await _say(tester, (c) => passTierLabel(c, 'pro')), 'Pro');
      expect(await _say(tester, (c) => passTierLabel(c, null)), '-');
      expect(
        await _say(tester, (c) => passTierLabel(c, 'new_tier')),
        'new tier',
      );
    });
  });

  group('shop order statuses', () {
    // fitflex-functions src/shared/order-lifecycle.mjs: STATUSES + LEGACY_INPUTS.
    const backend = [
      'pending',
      'accepted',
      'processing',
      'packed',
      'dispatched',
      'ready_for_pickup',
      'delivered',
      'cancelled',
      'confirmed',
      'fulfilled',
    ];

    test('every status the server sends has English and Swahili', () {
      expect(shopOrderStatuses, containsAll(backend));
      for (final s in backend) {
        final key = shopOrderStatusKey(s);
        expect(key, 'shop.orderStatus.$s');
        final en = FFLocale.textOf('en', key);
        final sw = FFLocale.textOf('sw', key);
        expect(en, isNotNull, reason: s);
        expect(sw, isNotNull, reason: s);
        expect(sw, isNot(en), reason: s);
        expect(en, isNot(contains('_')), reason: s);
      }
    });

    test('an unknown status falls back to a neutral label', () {
      expect(shopOrderStatusKey('placed'), 'shop.orderStatus.unknown');
      expect(shopOrderStatusKey(null), 'shop.orderStatus.unknown');
      expect(FFLocale.textOf('sw', 'shop.orderStatus.unknown'), isNotNull);
    });

    testWidgets('legacy codes read like their canonical status', (
      tester,
    ) async {
      expect(
        await _say(tester, (c) => shopOrderStatusLabel(c, 'confirmed')),
        'Accepted',
      );
      expect(
        await _say(tester, (c) => shopOrderStatusLabel(c, 'fulfilled')),
        'Delivered',
      );
      expect(
        await _say(
          tester,
          (c) => shopOrderStatusLabel(c, 'ready_for_pickup'),
          lang: 'sw',
        ),
        'Iko tayari kuchukuliwa',
      );
    });

    testWidgets('vendor buttons say what they do, in both languages', (
      tester,
    ) async {
      expect(
        await _say(tester, (c) => vendorMarkStatusLabel(c, 'packed')),
        'Mark as packed',
      );
      expect(
        await _say(
          tester,
          (c) => vendorMarkStatusLabel(c, 'accepted'),
          lang: 'sw',
        ),
        'Kubali oda',
      );
      for (final s in [
        'accepted',
        'processing',
        'packed',
        'dispatched',
        'ready_for_pickup',
        'delivered',
      ]) {
        expect(FFLocale.textOf('sw', 'vendor.markStatus.$s'), isNotNull);
      }
    });
  });

  group('owner scan reasons', () {
    testWidgets('gym not verified and tier not configured are explained', (
      tester,
    ) async {
      final notVerified = await _say(
        tester,
        (c) => ownerScanReasonLabel(c, 'gym_not_verified'),
      );
      expect(notVerified, contains('not verified'));
      expect(notVerified, contains('until FitFlex verifies'));
      expect(
        await _say(
          tester,
          (c) => ownerScanReasonLabel(c, 'tier_not_configured'),
        ),
        isNot(contains('ownerScan.')),
      );
      expect(
        await _say(
          tester,
          (c) => ownerScanReasonLabel(c, 'gym_not_verified'),
          lang: 'sw',
        ),
        contains('haijathibitishwa'),
      );
    });

    testWidgets('an unknown reason never shows a raw key', (tester) async {
      expect(
        await _say(tester, (c) => ownerScanReasonLabel(c, 'brand_new_code')),
        "This member can't check in here right now.",
      );
      expect(
        await _say(tester, (c) => ownerScanReasonLabel(c, '')),
        "This member can't check in here right now.",
      );
    });

    test('new scan reasons have Swahili', () {
      for (final k in [
        'ownerScan.reason_gym_not_verified',
        'ownerScan.reason_tier_not_configured',
        'ownerScan.reason_unknown',
      ]) {
        expect(FFLocale.textOf('en', k), isNotNull, reason: k);
        expect(FFLocale.textOf('sw', k), isNotNull, reason: k);
        expect(FFLocale.textOf('sw', k), isNot(FFLocale.textOf('en', k)));
      }
    });
  });

  group('API errors from scanning', () {
    for (final (code, en) in const [
      (
        'operator_not_assigned_to_gym',
        'Your account is not linked to a gym yet. Ask the gym owner.',
      ),
      ('member_not_found', 'We could not find this member'),
      ('gym_not_found', 'We could not find this gym'),
      (
        'tier_not_configured',
        'This pass is not set up yet. Contact FitFlex support.',
      ),
      // functions#189: a tier not configured for sale (409) on subscribe,
      // upgrade, mobile-money pay and sponsor/B2B pass paths.
      ('tier_not_available', 'this pass is not on sale right now'),
    ]) {
      test('$code is explained, not shown as a code', () {
        final message = apiErrorMessage(
          FFLocale(),
          ApiException(400, {'error': code}),
        );
        expect(message, 'Request declined: $en');
        expect(message, isNot(contains(code)));
      });
    }
  });

  test('activity copy mentions Health Connect only, not Apple Health', () {
    for (final lang in ['en', 'sw']) {
      for (final k in ['activity.getStarted.body', 'origin.noDevicesYet']) {
        final text = FFLocale.textOf(lang, k)!;
        expect(text, isNot(contains('Apple Health')), reason: '$lang $k');
        expect(text, contains('Health Connect'), reason: '$lang $k');
      }
    }
  });

  test('tier_not_available reads in Swahili too', () {
    final locale = FFLocale()..set(const Locale('sw'));
    expect(
      apiErrorMessage(
        locale,
        ApiException(409, {'error': 'tier_not_available'}),
      ),
      contains('pasi hii haiuzwi kwa sasa'),
    );
  });
}
