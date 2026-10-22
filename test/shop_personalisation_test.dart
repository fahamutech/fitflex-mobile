// Shop home Phase 2 S2 (personalisation): the "Personalised shop" switch in
// the Why sheet and on the member Privacy page, the new reason bullets, and
// the vendor product form's "Who it's for" pickers.
//
// Contract: fitflex-functions docs/shop-personalisation-api.md
// (GET/PUT /shop/preferences, GET /shop/home `personalisation` +
// `reasonParams`, vendor `targetGender` / `targetAgeBands`,
// /vendor/tools/options `merch.productTargets`). Mocked at the HTTP level
// with test/support/recording_api.dart.
import 'dart:ui' show CheckedState, SemanticsFlags, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/screens/member/member_privacy_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/router.dart' show AppRoutes;
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/network/browser_online.dart';
import 'package:fitflexmobile/shared/shop_home.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';
import 'package:fitflexmobile/shared/widgets/shop_home/shop_personalisation.dart';

import 'support/recording_api.dart';

Map<String, dynamic> _p(String id, String name) => {
  'id': id,
  'vendorId': 'v1',
  'name': name,
  'category': 'equipment',
  'priceTzs': 10000,
  'stock': 10,
  'rating': 0,
  'reviewCount': 0,
  'soldCount': 0,
  'deliveryAvailable': true,
};

final _products = {
  for (final p in [
    _p('p1', 'Whey Protein'),
    _p('p2', 'Yoga Mat'),
    _p('p3', 'Kettlebell'),
    _p('p4', 'Running Shoes'),
  ])
    p['id']: p,
};

Map<String, dynamic> _home({
  Map<String, dynamic>? personalisation,
  bool personalised = false,
  List<String> codes = const ['bought_category', 'role_context'],
  Map<String, dynamic>? params = const {'category': 'sportswear_footwear'},
  String mode = 'member',
}) => {
  'serverNow': '2026-10-22T08:00:00Z',
  'mode': mode,
  'personalised': personalised,
  'signalsUsed': <String>[],
  'personalisation': ?personalisation,
  'categories': <dynamic>[],
  'sections': [
    {
      'key': 'recommended',
      'title': {'en': 'Recommended for you', 'sw': 'Zilizopendekezwa kwako'},
      'reasonCodes': codes,
      'reasonParams': ?params,
      'viewAll': {'query': <String, String>{}},
      'productIds': ['p1', 'p2', 'p3', 'p4'],
    },
  ],
  'products': _products,
};

void _seedShop(RecordingApi api, Map<String, dynamic> home) {
  api.on('GET /shop/products', _products.values.toList());
  api.on('GET /me/shop-orders', <dynamic>[]);
  api.on('GET /gyms', <dynamic>[]);
  api.on('GET /shop/home', home);
}

const _member = {'id': 'm1', 'userType': 'member', 'displayName': 'Amina'};

Future<PageHost> _pumpShop(
  WidgetTester tester,
  RecordingApi api, {
  ShopHomeMode mode = ShopHomeMode.member,
  String lang = 'en',
  double scale = 1,
  Size size = const Size(420, 900),
  List<RouteBase> extraRoutes = const [],
}) => pumpPage(
  tester,
  api,
  ShopBrowseBody(mode: mode),
  user: _member,
  lang: lang,
  textScale: scale,
  size: size,
  keepRequests: true,
  extraRoutes: extraRoutes,
);

/// Whether keyboard focus is on (or inside) the widget with [key].
bool _focusIn(String key) {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget.key == Key(key)) return true;
  var hit = false;
  ctx.visitAncestorElements((e) {
    if (e.widget.key == Key(key)) {
      hit = true;
      return false;
    }
    return true;
  });
  return hit;
}

Future<void> _tab(WidgetTester tester, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.pumpAndSettle();
}

Finder _key(String k) => find.byKey(Key(k));

Future<void> _openWhy(WidgetTester tester) async {
  await tapVisible(tester, _key('shop-home-why-recommended'));
  expect(_key('shop-why-recommended'), findsOneWidget);
}

bool _switchValue(WidgetTester tester) =>
    tester.widget<Switch>(_key('shop-why-personalised')).value;

/// The texts shown in the open Why sheet.
List<String> _whyTexts(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: _key('shop-why-recommended'),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data ?? '')
    .toList();

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    debugShopHomeV2Override = true;
    ShopEvents.reset();
  });
  tearDown(() => debugShopHomeV2Override = null);

  group('Why sheet switch', () {
    apiTest('shown on when available; turning it off saves and reloads', (
      tester,
      api,
    ) async {
      _seedShop(
        api,
        _home(
          personalisation: {'available': true, 'enabled': true},
          personalised: true,
        ),
      );
      api.on('PUT /shop/preferences', {
        'personalised': false,
        'available': true,
      });
      final host = await _pumpShop(tester, api);
      // The personalised rail has the person icon.
      expect(
        find.descendant(
          of: _key('shop-home-section-recommended'),
          matching: find.byIcon(Icons.person_outline),
        ),
        findsOneWidget,
      );
      await _openWhy(tester);
      expect(_switchValue(tester), isTrue);
      expect(find.text(host.tr('shop.why.switch')), findsOneWidget);
      expect(find.text(host.tr('shop.why.switchHintMember')), findsOneWidget);
      expect(_key('shop-why-privacy'), findsOneWidget);
      final homeLoads = api.where('GET', '/shop/home').length;

      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();

      expect(api.only('PUT', '/shop/preferences').body, {
        'personalised': false,
        'source': 'why_sheet',
      });
      expect(_switchValue(tester), isFalse);
      // Said under the switch, not in a snackbar over the sheet's link.
      expect(_key('shop-why-personalised-saved'), findsOneWidget);
      expect(host.snack(host.tr('shop.why.saved')), findsNothing);
      // The home reloaded behind the sheet, which stays open.
      expect(api.where('GET', '/shop/home').length, homeLoads + 1);
      expect(_key('shop-why-recommended'), findsOneWidget);
    });

    apiTest('disabled with a spinner while saving', (tester, api) async {
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      final gate = api.hold('PUT /shop/preferences');
      api.on('PUT /shop/preferences', {
        'personalised': false,
        'available': true,
      });
      await _pumpShop(tester, api);
      await _openWhy(tester);
      await tester.tap(_key('shop-why-personalised'));
      await tester.pump();
      final sw = tester.widget<Switch>(_key('shop-why-personalised'));
      expect(sw.value, isFalse, reason: 'optimistic');
      expect(sw.onChanged, isNull);
      expect(spinner, findsWidgets);
      gate.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<Switch>(_key('shop-why-personalised')).onChanged,
        isNotNull,
      );
    });

    apiTest('a failed save reverts and says so', (tester, api) async {
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      api.fail('PUT /shop/preferences', 500);
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();
      expect(api.sent('PUT', '/shop/preferences'), isTrue);
      expect(_switchValue(tester), isTrue);
      expect(_key('shop-why-personalised-error'), findsOneWidget);
      expect(find.text(host.tr('shop.why.saveFailed')), findsWidgets);
    });

    apiTest('a save answering 404 feature_disabled hides the switch', (
      tester,
      api,
    ) async {
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      api.fail('PUT /shop/preferences', 404, {'error': 'feature_disabled'});
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();
      expect(_key('shop-why-personalised'), findsNothing);
      expect(_key('shop-why-personalised-error'), findsNothing);
      expect(host.snack(host.tr('shop.why.saveFailed')), findsNothing);
    });

    apiTest('bought_category names the category from the server list first', (
      tester,
      api,
    ) async {
      final home = _home(
        personalisation: {'available': true, 'enabled': true},
        codes: ['bought_category'],
        params: {'category': 'equipment'},
      );
      home['categories'] = [
        {
          'key': 'equipment',
          'en': 'Home gym kit',
          'sw': 'Vifaa vya gym nyumbani',
        },
      ];
      _seedShop(api, home);
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      expect(
        _whyTexts(tester),
        contains(
          host
              .tr('shop.why.boughtCategory')
              .replaceAll('{category}', 'Home gym kit'),
        ),
      );
    });

    apiTest('not available (under 18 / no member persona): no switch and '
        'nothing personal', (tester, api) async {
      _seedShop(
        api,
        _home(
          personalisation: {'available': false, 'enabled': false},
          codes: [
            'bought_category',
            'profile_gender',
            'profile_age',
            'generic',
          ],
        ),
      );
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      expect(_key('shop-why-personalised'), findsNothing);
      expect(_key('shop-why-privacy'), findsNothing);
      final texts = _whyTexts(tester);
      expect(texts, contains(host.tr('shop.why.generic')));
      expect(texts, isNot(contains(host.tr('shop.why.gender'))));
      expect(texts, isNot(contains(host.tr('shop.why.age'))));
      expect(
        texts.where((t) => t.contains('Sportswear')),
        isEmpty,
        reason: 'bought_category is personal',
      );
      expect(api.sent('GET', '/shop/preferences'), isFalse);
    });

    apiTest('switched off: personal reasons are not shown', (
      tester,
      api,
    ) async {
      _seedShop(
        api,
        _home(
          personalisation: {'available': true, 'enabled': false},
          codes: ['bought_category', 'generic'],
        ),
      );
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      expect(_switchValue(tester), isFalse);
      final texts = _whyTexts(tester);
      expect(texts, contains(host.tr('shop.why.generic')));
      expect(texts.where((t) => t.contains('Sportswear')), isEmpty);
    });

    apiTest('flag off (no personalisation key): Phase 1 sheet unchanged', (
      tester,
      api,
    ) async {
      _seedShop(api, _home(codes: ['bought_category', 'role_context']));
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      expect(_key('shop-why-personalised'), findsNothing);
      expect(_key('shop-why-privacy'), findsNothing);
      expect(
        _whyTexts(tester),
        contains(
          host
              .tr('shop.why.boughtCategory')
              .replaceAll('{category}', 'Sportswear & footwear'),
        ),
      );
      expect(api.sent('GET', '/shop/preferences'), isFalse);
      expect(api.sent('PUT', '/shop/preferences'), isFalse);
    });

    apiTest('trainer mode: the partner hint, no Privacy link', (
      tester,
      api,
    ) async {
      _seedShop(
        api,
        _home(
          mode: 'trainer',
          personalisation: {'available': true, 'enabled': true},
        ),
      );
      final host = await _pumpShop(tester, api, mode: ShopHomeMode.trainer);
      await _openWhy(tester);
      expect(find.text(host.tr('shop.why.switchHintPartner')), findsOneWidget);
      expect(find.text(host.tr('shop.why.switchHintMember')), findsNothing);
      expect(_key('shop-why-privacy'), findsNothing);
    });

    apiTest('the switch reads as one labelled toggle of 48dp or more', (
      tester,
      api,
    ) async {
      final handle = tester.ensureSemantics();
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      final node = tester.getSemantics(_key('shop-why-personalised'));
      expect(node.label, contains(host.tr('shop.why.switch')));
      expect(node.label, contains(host.tr('shop.why.switchHintMember')));
      final flags = node.getSemanticsData().flagsCollection;
      expect(flags.isToggled, Tristate.isTrue);
      expect(
        tester.getSize(_key('shop-why-personalised')).height,
        greaterThanOrEqualTo(48),
      );
      handle.dispose();
    });
  });

  group('QA round 1', () {
    apiTest('1: switching off drops personal reasons at once and says '
        'suggestions are off', (tester, api) async {
      _seedShop(
        api,
        _home(
          personalisation: {'available': true, 'enabled': true},
          personalised: true,
          codes: ['bought_category', 'profile_gender', 'role_context'],
        ),
      );
      api.on('PUT /shop/preferences', {
        'personalised': false,
        'available': true,
        'uses': <String>[],
      });
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      final bought = host
          .tr('shop.why.boughtCategory')
          .replaceAll('{category}', 'Sportswear & footwear');
      expect(_whyTexts(tester), contains(bought));
      expect(_key('shop-why-off'), findsNothing);
      // The reload answers with the old page; the sheet must not show it.
      final gate = api.hold('GET /shop/home');
      await tester.tap(_key('shop-why-personalised'));
      await tester.pump();
      await tester.pump();
      final texts = _whyTexts(tester);
      expect(texts, isNot(contains(bought)));
      expect(texts, isNot(contains(host.tr('shop.why.gender'))));
      expect(texts, contains(host.tr('shop.why.offMember')));
      gate.complete();
      await tester.pumpAndSettle();
      expect(_whyTexts(tester), isNot(contains(bought)));
      expect(_key('shop-why-off'), findsOneWidget);
    });

    for (final (mode, key) in [
      (ShopHomeMode.trainer, 'shop.why.offTrainer'),
      (ShopHomeMode.owner, 'shop.why.offOwner'),
    ]) {
      apiTest('1: off line names the role (${mode.wire})', (tester, api) async {
        _seedShop(
          api,
          _home(
            mode: mode.wire,
            personalisation: {'available': true, 'enabled': false},
          ),
        );
        final host = await _pumpShop(tester, api, mode: mode);
        await _openWhy(tester);
        expect(find.text(host.tr(key)), findsOneWidget);
      });
    }

    apiTest('2: keyboard: Close, then the switch row (one stop), then '
        'Privacy & data, then back to Close; ring shows; Escape returns '
        'focus to the opener', (tester, api) async {
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      await _pumpShop(tester, api);
      // Open with the keyboard.
      final opener = _key('shop-home-why-recommended');
      Focus.of(
        tester.element(
          find.descendant(of: opener, matching: find.byType(Icon)),
        ),
      ).requestFocus();
      await tester.pump();
      expect(_focusIn('shop-home-why-recommended'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(_key('shop-why-recommended'), findsOneWidget);
      await _tab(tester);
      expect(_focusIn('ff-sheet-close'), isTrue);
      await _tab(tester);
      expect(_focusIn('shop-why-personalised-row'), isTrue);
      // The two-tone ring is drawn round the focused row.
      expect(
        find.ancestor(
          of: _key('shop-why-personalised-row'),
          matching: find.byKey(const Key('shop-home-focus-ring')),
        ),
        findsWidgets,
      );
      await _tab(tester);
      expect(_focusIn('shop-why-privacy'), isTrue);
      expect(find.byKey(const Key('shop-home-focus-ring')), findsWidgets);
      await _tab(tester);
      // Trapped in the sheet: back to Close.
      expect(_focusIn('ff-sheet-close'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(_key('shop-why-recommended'), findsNothing);
      expect(_focusIn('shop-home-why-recommended'), isTrue);
    });

    apiTest('2: Space on the focused row toggles the switch', (
      tester,
      api,
    ) async {
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      api.on('PUT /shop/preferences', {
        'personalised': false,
        'available': true,
      });
      await _pumpShop(tester, api);
      await _openWhy(tester);
      await _tab(tester);
      await _tab(tester);
      expect(_focusIn('shop-why-personalised-row'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(api.only('PUT', '/shop/preferences').body, {
        'personalised': false,
        'source': 'why_sheet',
      });
    });

    apiTest('5: the mode is sent with the switch', (tester, api) async {
      _seedShop(
        api,
        _home(
          mode: 'trainer',
          personalisation: {'available': true, 'enabled': true},
        ),
      );
      api.on('PUT /shop/preferences', {
        'personalised': false,
        'available': true,
      });
      await _pumpShop(tester, api, mode: ShopHomeMode.trainer);
      await _openWhy(tester);
      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();
      expect(api.only('PUT', '/shop/preferences').query, 'mode=trainer');
    });

    apiTest('6: a failed save shows the error once, under the switch', (
      tester,
      api,
    ) async {
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      api.fail('PUT /shop/preferences', 500);
      final host = await _pumpShop(tester, api);
      await _openWhy(tester);
      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();
      expect(find.text(host.tr('shop.why.saveFailed')), findsOneWidget);
      expect(host.snack(host.tr('shop.why.saveFailed')), findsNothing);
    });

    apiTest('9: from 1024 px the sheet is a centred dialog 480 wide', (
      tester,
      api,
    ) async {
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      await _pumpShop(tester, api, size: const Size(1280, 900));
      await _openWhy(tester);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester
            .getSize(
              find.descendant(
                of: find.byType(Dialog),
                matching: find.byType(FFSheet),
              ),
            )
            .width,
        lessThanOrEqualTo(480),
      );
    });

    apiTest('12: Privacy & data from the Why sheet is pushed; its Back '
        'returns to the shop', (tester, api) async {
      _seedShop(
        api,
        _home(personalisation: {'available': true, 'enabled': true}),
      );
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
        'uses': <String>[],
      });
      final host = await _pumpShop(
        tester,
        api,
        size: const Size(420, 1400),
        extraRoutes: [
          GoRoute(
            path: AppRoutes.memberPrivacy,
            builder: (_, _) => Scaffold(
              body: MemberDataScope(
                data: MemberData(),
                child: const MemberPrivacyPage(),
              ),
            ),
          ),
        ],
      );
      await _openWhy(tester);
      await tapVisible(tester, _key('shop-why-privacy'));
      expect(find.byType(MemberPrivacyPage), findsOneWidget);
      await tapVisible(tester, buttonLabelled(host.tr('member.profile')));
      expect(find.byType(MemberPrivacyPage), findsNothing);
      expect(_key('shop-home'), findsOneWidget);
    });
  });

  group('reason bullets', () {
    for (final lang in ['en', 'sw']) {
      apiTest('new reason codes have app wording ($lang)', (tester, api) async {
        _seedShop(
          api,
          _home(
            personalisation: {'available': true, 'enabled': true},
            codes: ['bought_category', 'profile_gender', 'profile_age'],
            params: {'category': 'equipment'},
          ),
        );
        final host = await _pumpShop(tester, api, lang: lang);
        await _openWhy(tester);
        final cat = lang == 'sw'
            ? 'Vifaa vya gym na mazoezi'
            : 'Gym & fitness equipment';
        final texts = _whyTexts(tester);
        expect(
          texts,
          containsAll([
            host.tr('shop.why.boughtCategory').replaceAll('{category}', cat),
            host.tr('shop.why.gender'),
            host.tr('shop.why.age'),
          ]),
        );
        // Never names a gender or an age group.
        for (final t in texts) {
          expect(
            t,
            isNot(
              matches(
                RegExp(
                  r'\b(women|men|wanawake|wanaume)\b',
                  caseSensitive: false,
                ),
              ),
            ),
          );
        }
      });

      apiTest('bought_product uses reasonParams.productName ($lang)', (
        tester,
        api,
      ) async {
        _seedShop(
          api,
          _home(
            personalisation: {'available': true, 'enabled': true},
            codes: ['bought_product'],
            params: {'productName': 'Whey Protein'},
          ),
        );
        final host = await _pumpShop(tester, api, lang: lang);
        await _openWhy(tester);
        expect(
          _whyTexts(tester),
          contains(
            host
                .tr('shop.why.boughtProduct')
                .replaceAll('{product}', 'Whey Protein'),
          ),
        );
      });
    }

    test('every new key resolves in both languages', () {
      final en = FFLocale()..set(const Locale('en'));
      final sw = FFLocale()..set(const Locale('sw'));
      for (final key in [
        'shop.why.switch',
        'shop.why.switchHintMember',
        'shop.why.switchHintPartner',
        'shop.why.age',
        'shop.why.saved',
        'shop.why.saveFailed',
        'shop.why.loadFailed',
        'shop.why.privacyLink',
        'privacy.shop.title',
        'privacy.shop.on',
        'privacy.shop.off',
        'privacy.shop.loadFailed',
        'privacy.shop.offline',
        'privacy.shop.loading',
        'privacy.shop.usesTitle',
        'privacy.shop.usesHistory',
        'privacy.shop.usesHistoryOne',
        'privacy.shop.usesGenderAge',
        'privacy.shop.usesGender',
        'privacy.shop.usesAge',
        'privacy.shop.usesGoal',
        'privacy.shop.usesSpecialty',
        'privacy.shop.usesNone',
        'member.dobPick',
        'member.dobClear',
        'member.dobInvalid',
        'privacy.shop.orderOnly',
        'privacy.shop.never',
        'privacy.shop.draft',
        'vendor.target.title',
        'vendor.target.hint',
        'vendor.target.madeFor',
        'vendor.target.everyone',
        'vendor.target.women',
        'vendor.target.men',
        'vendor.target.ageGroup',
        'vendor.target.allAges',
        'vendor.target.a11yBand',
        'vendor.target.a11yBandPlus',
        'vendor.target.a11yOption',
        for (final b in kTargetAgeBands) 'vendor.target.band.$b',
      ]) {
        expect(en.t(key), isNot(key), reason: 'en $key');
        expect(sw.t(key), isNot(key), reason: 'sw $key');
      }
      expect(sw.t('shop.why.switch'), 'Duka kwa ajili yako');
      expect(sw.t('vendor.target.madeFor'), 'Walengwa');
      expect(sw.t('shop.why.loadFailed'), contains('chaguo lako'));
      expect(
        sw.t('privacy.shop.usesHistory').replaceAll('{months}', '12'),
        contains('katika miezi 12 iliyopita'),
      );
      expect(
        sw.t('privacy.shop.usesGenderAge'),
        contains('(havitumiki kwa walio chini ya miaka 18)'),
      );
      expect(en.t('vendor.target.hint'), contains('members it suits'));
      expect(
        en.t('shop.why.deliversToArea'),
        'It delivers to your current area.',
      );
      expect(
        sw.t('shop.why.deliversToArea'),
        'Ina delivery kwenye eneo ulipo sasa.',
      );
      for (final key in ['shop.why.switchHintPartner', 'vendor.target.hint']) {
        expect(sw.t(key), isNot(contains('mkufunzi')));
        expect(sw.t(key), isNot(contains('kocha')));
      }
    });
  });

  group('Privacy page tile', () {
    Future<PageHost> pumpTile(
      WidgetTester tester,
      RecordingApi api, {
      String lang = 'en',
      double scale = 1,
    }) => pumpPage(
      tester,
      api,
      const SingleChildScrollView(child: ShopPrivacyTile()),
      user: _member,
      lang: lang,
      textScale: scale,
      size: const Size(375, 812),
      keepRequests: true,
    );

    apiTest('shows On and opens the sheet with the switch and what is used', (
      tester,
      api,
    ) async {
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
        'historyDays': 365,
        'uses': ['purchase_history', 'profile_gender', 'profile_age'],
      });
      api.on('PUT /shop/preferences', {
        'personalised': false,
        'available': true,
        'historyDays': 365,
        'uses': <String>[],
      });
      final host = await pumpTile(tester, api);
      expect(_key('privacy-shop'), findsOneWidget);
      expect(find.text(host.tr('privacy.shop.title')), findsOneWidget);
      expect(find.text(host.tr('privacy.shop.on')), findsOneWidget);
      await tapVisible(tester, _key('privacy-shop'));
      expect(_key('privacy-shop-sheet'), findsOneWidget);
      expect(
        find.text(
          host.tr('privacy.shop.usesHistory').replaceAll('{months}', '12'),
        ),
        findsOneWidget,
      );
      for (final k in [
        'privacy.shop.usesGenderAge',
        'privacy.shop.orderOnly',
        'privacy.shop.never',
        'privacy.shop.draft',
      ]) {
        expect(find.text(host.tr(k)), findsOneWidget, reason: k);
      }
      // No location line until slice 3.
      expect(find.textContaining('area'), findsNothing);
      expect(_switchValue(tester), isTrue);
      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();
      // Off: the server says nothing is used now; the list follows it.
      expect(_key('privacy-shop-uses-none'), findsOneWidget);
      expect(_key('privacy-shop-order-only'), findsNothing);
      expect(api.only('PUT', '/shop/preferences').body, {
        'personalised': false,
        'source': 'privacy_page',
      });
      await tapVisible(tester, _key('ff-sheet-close'));
      expect(find.text(host.tr('privacy.shop.off')), findsOneWidget);
    });

    apiTest('on the Privacy page between Message preferences and sharing', (
      tester,
      api,
    ) async {
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
      });
      await pumpPage(
        tester,
        api,
        MemberDataScope(data: MemberData(), child: const MemberPrivacyPage()),
        user: _member,
        size: const Size(375, 1400),
      );
      expect(_key('privacy-shop'), findsOneWidget);
      final messages = tester.getTopLeft(_key('privacy-messages')).dy;
      final shop = tester.getTopLeft(_key('privacy-shop')).dy;
      final sharing = tester.getTopLeft(_key('privacy-activity-sharing')).dy;
      expect(messages < shop && shop < sharing, isTrue);
    });

    apiTest('hidden when not available (flag off or under 18)', (
      tester,
      api,
    ) async {
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': false,
      });
      await pumpTile(tester, api);
      expect(_key('privacy-shop'), findsNothing);
    });

    for (final lang in ['en', 'sw']) {
      apiTest('lists only what `uses` holds ($lang)', (tester, api) async {
        api.on('GET /shop/preferences', {
          'personalised': true,
          'available': true,
          'historyDays': 180,
          'uses': ['purchase_history', 'profile_gender', 'goal', 'location'],
        });
        final host = await pumpTile(tester, api, lang: lang);
        await tapVisible(tester, _key('privacy-shop'));
        final texts = [
          for (var i = 0; i < 5; i++)
            if (find.byKey(Key('privacy-shop-use-$i')).evaluate().isNotEmpty)
              tester.widget<Text>(_key('privacy-shop-use-$i')).data,
        ];
        expect(texts, [
          host.tr('privacy.shop.usesHistory').replaceAll('{months}', '6'),
          host.tr('privacy.shop.usesGender'),
          host.tr('privacy.shop.usesGoal'),
        ]);
        if (lang == 'sw') {
          expect(texts.first, contains('katika miezi 6 iliyopita'));
        }
        expect(find.text(host.tr('privacy.shop.usesAge')), findsNothing);
        expect(find.text(host.tr('privacy.shop.usesGenderAge')), findsNothing);
      });
    }

    apiTest('no `uses` from the server: no list, never a guess', (
      tester,
      api,
    ) async {
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
      });
      final host = await pumpTile(tester, api);
      await tapVisible(tester, _key('privacy-shop'));
      expect(_key('privacy-shop-sheet'), findsOneWidget);
      expect(find.text(host.tr('privacy.shop.usesTitle')), findsNothing);
      expect(_key('privacy-shop-use-0'), findsNothing);
      expect(_key('privacy-shop-uses-none'), findsNothing);
      expect(_key('privacy-shop-order-only'), findsNothing);
      expect(find.text(host.tr('privacy.shop.never')), findsOneWidget);
    });

    apiTest('unknown or old spellings in `uses` are ignored', (
      tester,
      api,
    ) async {
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
        'uses': ['history', 'gender', 'specialty'],
      });
      final host = await pumpTile(tester, api);
      await tapVisible(tester, _key('privacy-shop'));
      expect(
        tester.widget<Text>(_key('privacy-shop-use-0')).data,
        host.tr('privacy.shop.usesSpecialty'),
      );
      expect(_key('privacy-shop-use-1'), findsNothing);
    });

    apiTest('a save answering 404 hides the switch and the tile', (
      tester,
      api,
    ) async {
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
        'uses': ['purchase_history'],
      });
      api.fail('PUT /shop/preferences', 404, {'error': 'feature_disabled'});
      final host = await pumpTile(tester, api);
      await tapVisible(tester, _key('privacy-shop'));
      await tester.tap(_key('shop-why-personalised'));
      await tester.pumpAndSettle();
      expect(_key('shop-why-personalised'), findsNothing);
      expect(find.text(host.tr('shop.why.saveFailed')), findsNothing);
      await tapVisible(tester, _key('ff-sheet-close'));
      expect(_key('privacy-shop'), findsNothing);
    });

    apiTest('5: asks with ?mode=member', (tester, api) async {
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
      });
      await pumpTile(tester, api);
      expect(api.only('GET', '/shop/preferences').query, 'mode=member');
    });

    apiTest('7: loading shows a skeleton line, announced', (tester, api) async {
      final handle = tester.ensureSemantics();
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
      });
      final gate = api.hold('GET /shop/preferences');
      final host = await pumpPage(
        tester,
        api,
        const SingleChildScrollView(child: ShopPrivacyTile()),
        user: _member,
        size: const Size(375, 812),
        settle: false,
      );
      await tester.pump();
      await tester.pump();
      expect(_key('privacy-shop-loading'), findsOneWidget);
      expect(
        find.descendant(
          of: _key('privacy-shop-loading'),
          matching: find.byType(FFSkeletonLine),
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          RegExp(RegExp.escape(host.tr('privacy.shop.loading'))),
        ),
        findsWidgets,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text(host.tr('privacy.shop.on')), findsOneWidget);
      handle.dispose();
    });

    apiTest('7: offline: disabled with "Needs internet"; loads once online', (
      tester,
      api,
    ) async {
      addTearDown(() => BrowserOnline.debugSet(true));
      BrowserOnline.debugSet(false);
      api.on('GET /shop/preferences', {
        'personalised': true,
        'available': true,
      });
      final host = await pumpTile(tester, api);
      expect(find.text(host.tr('privacy.shop.offline')), findsOneWidget);
      expect(tester.widget<FFActionTile>(_key('privacy-shop')).onTap, isNull);
      await tester.tap(_key('privacy-shop'));
      await tester.pumpAndSettle();
      expect(_key('privacy-shop-sheet'), findsNothing);
      expect(api.sent('GET', '/shop/preferences'), isFalse);
      BrowserOnline.debugSet(true);
      await tester.pumpAndSettle();
      expect(find.text(host.tr('privacy.shop.on')), findsOneWidget);
    });

    for (final lang in ['en', 'sw']) {
      apiTest('8: the draft note is muted and seen without scrolling at '
          '375x812, 130% ($lang)', (tester, api) async {
        api.on('GET /shop/preferences', {
          'personalised': true,
          'available': true,
          'historyDays': 365,
          'uses': ['purchase_history', 'profile_gender', 'profile_age', 'goal'],
        });
        final host = await pumpTile(tester, api, lang: lang, scale: 1.3);
        await tapVisible(tester, _key('privacy-shop'));
        final draft = _key('privacy-shop-draft');
        expect(find.text(host.tr('privacy.shop.draft')), findsOneWidget);
        expect(tester.getBottomLeft(draft).dy, lessThanOrEqualTo(812));
        final ctx = tester.element(draft);
        expect(
          tester.widget<Text>(draft).style?.color,
          Theme.of(ctx).colorScheme.onSurfaceVariant,
        );
      });
    }

    apiTest('hidden on 404 feature_disabled', (tester, api) async {
      api.fail('GET /shop/preferences', 404, {'error': 'feature_disabled'});
      await pumpTile(tester, api);
      expect(_key('privacy-shop'), findsNothing);
    });

    apiTest('a load failure says so and retries on tap', (tester, api) async {
      api.fail('GET /shop/preferences', 500);
      final host = await pumpTile(tester, api);
      expect(find.text(host.tr('privacy.shop.loadFailed')), findsOneWidget);
      api.heal('GET /shop/preferences');
      api.on('GET /shop/preferences', {
        'personalised': false,
        'available': true,
      });
      await tapVisible(tester, _key('privacy-shop'));
      expect(find.text(host.tr('privacy.shop.off')), findsOneWidget);
      expect(_key('privacy-shop-sheet'), findsNothing);
    });

    for (final lang in ['en', 'sw']) {
      apiTest('sheet fits at 375 and 130% text ($lang)', (tester, api) async {
        api.on('GET /shop/preferences', {
          'personalised': true,
          'available': true,
        });
        final errors = await captureFlutterErrors(() async {
          await pumpTile(tester, api, lang: lang, scale: 1.3);
          await tapVisible(tester, _key('privacy-shop'));
        });
        expect(errors, isEmpty);
        expect(_key('privacy-shop-sheet'), findsOneWidget);
      });
    }
  });

  group('vendor product form', () {
    void seedVendor(RecordingApi api, {bool targets = true, List? products}) {
      api.on('GET /vendor/products', products ?? <dynamic>[]);
      api.on('GET /vendor/orders', <dynamic>[]);
      api.on('GET /vendor/profile', {
        'businessName': 'Store',
        'status': 'published',
      });
      api.on('GET /vendor/payments', <String, dynamic>{});
      api.on('GET /vendor/enquiries', <dynamic>[]);
      api.on('GET /vendor/staff', <dynamic>[]);
      api.on('GET /vendor/tools/options', {
        'merch': {'banners': false, 'productTargets': targets},
      });
    }

    Future<PageHost> pumpVendor(
      WidgetTester tester,
      RecordingApi api, {
      String lang = 'en',
      double scale = 1,
    }) => pumpPage(
      tester,
      api,
      const VendorHomePage(),
      user: const {'id': 'v1', 'userType': 'vendor'},
      lang: lang,
      textScale: scale,
    );

    Future<void> fillAndSave(WidgetTester tester) async {
      await typeInto(tester, _key('vendor-product-name'), 'Sports bra');
      await typeInto(tester, _key('vendor-product-price'), '25000');
      await tapVisible(tester, _key('vendor-product-save'));
    }

    apiTest('productTargets on: pickers shown; body carries the choices', (
      tester,
      api,
    ) async {
      seedVendor(api);
      final host = await pumpVendor(tester, api);
      await tester.tap(_key('vendor-add-product'));
      await tester.pumpAndSettle();
      expect(_key('vendor-product-targets'), findsOneWidget);
      expect(find.text(host.tr('vendor.target.title')), findsOneWidget);

      await tapVisible(tester, _key('vendor-target-gender-women'));
      await tapVisible(tester, _key('vendor-target-age-30_44'));
      await tapVisible(tester, _key('vendor-target-age-18_29'));
      await fillAndSave(tester);
      final body = api.only('POST', '/vendor/products').body as Map;
      expect(body['targetGender'], 'women');
      // Display order, whatever order they were picked in.
      expect(body['targetAgeBands'], ['18_29', '30_44']);
    });

    apiTest('defaults: Everyone and All ages send null and []', (
      tester,
      api,
    ) async {
      seedVendor(api);
      await pumpVendor(tester, api);
      await tester.tap(_key('vendor-add-product'));
      await tester.pumpAndSettle();
      await fillAndSave(tester);
      final body = api.only('POST', '/vendor/products').body as Map;
      expect(body.containsKey('targetGender'), isTrue);
      expect(body['targetGender'], isNull);
      expect(body['targetAgeBands'], isEmpty);
    });

    apiTest('All ages clears the bands; a band clears All ages', (
      tester,
      api,
    ) async {
      seedVendor(api);
      await pumpVendor(tester, api);
      await tester.tap(_key('vendor-add-product'));
      await tester.pumpAndSettle();
      bool selected(String key) =>
          tester.widget<FFFilterChip>(_key(key)).selected;
      expect(selected('vendor-target-age-all'), isTrue);
      await tapVisible(tester, _key('vendor-target-age-60_plus'));
      expect(selected('vendor-target-age-all'), isFalse);
      expect(selected('vendor-target-age-60_plus'), isTrue);
      await tapVisible(tester, _key('vendor-target-age-all'));
      expect(selected('vendor-target-age-all'), isTrue);
      expect(selected('vendor-target-age-60_plus'), isFalse);
      // Made for is single choice.
      await tapVisible(tester, _key('vendor-target-gender-men'));
      await tapVisible(tester, _key('vendor-target-gender-women'));
      expect(selected('vendor-target-gender-men'), isFalse);
      expect(selected('vendor-target-gender-women'), isTrue);
      expect(selected('vendor-target-gender-everyone'), isFalse);
    });

    apiTest('picking every band becomes All ages and sends []', (
      tester,
      api,
    ) async {
      seedVendor(api);
      await pumpVendor(tester, api);
      await tester.tap(_key('vendor-add-product'));
      await tester.pumpAndSettle();
      for (final b in kTargetAgeBands) {
        await tapVisible(tester, _key('vendor-target-age-$b'));
      }
      expect(
        tester.widget<FFFilterChip>(_key('vendor-target-age-all')).selected,
        isTrue,
      );
      for (final b in kTargetAgeBands) {
        expect(
          tester.widget<FFFilterChip>(_key('vendor-target-age-$b')).selected,
          isFalse,
        );
      }
      await fillAndSave(tester);
      final body = api.only('POST', '/vendor/products').body as Map;
      expect(body['targetAgeBands'], isEmpty);
    });

    apiTest('editing prefills the stored targets and PUTs them', (
      tester,
      api,
    ) async {
      seedVendor(
        api,
        products: [
          {
            'id': 'p9',
            'name': 'Sports bra',
            'priceTzs': 25000,
            'stock': 3,
            'status': 'active',
            'targetGender': 'women',
            'targetAgeBands': ['45_59'],
          },
        ],
      );
      final host = await pumpVendor(tester, api);
      final menu = find.descendant(
        of: _key('vendor-product-p9'),
        matching: find.byType(PopupMenuButton<String>),
      );
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text(host.tr('vendor.edit')).last);
      await tester.pumpAndSettle();
      bool selected(String key) =>
          tester.widget<FFFilterChip>(_key(key)).selected;
      expect(selected('vendor-target-gender-women'), isTrue);
      expect(selected('vendor-target-age-45_59'), isTrue);
      expect(selected('vendor-target-age-all'), isFalse);
      await tapVisible(tester, _key('vendor-target-gender-everyone'));
      await tapVisible(tester, _key('vendor-product-save'));
      final body = api.only('PUT', '/vendor/products/p9').body as Map;
      expect(body['targetGender'], isNull);
      expect(body['targetAgeBands'], ['45_59']);
    });

    apiTest('productTargets off: no pickers and nothing new sent', (
      tester,
      api,
    ) async {
      seedVendor(api, targets: false);
      await pumpVendor(tester, api);
      await tester.tap(_key('vendor-add-product'));
      await tester.pumpAndSettle();
      expect(_key('vendor-product-targets'), findsNothing);
      await fillAndSave(tester);
      final body = api.only('POST', '/vendor/products').body as Map;
      expect(body.containsKey('targetGender'), isFalse);
      expect(body.containsKey('targetAgeBands'), isFalse);
    });

    apiTest('Swahili chip labels use "Walengwa"', (tester, api) async {
      final handle = tester.ensureSemantics();
      seedVendor(api);
      await pumpVendor(tester, api, lang: 'sw');
      await tester.tap(_key('vendor-add-product'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('vendor-target-gender-women'));
      await tester.pumpAndSettle();
      expect(find.text('Walengwa'), findsOneWidget);
      expect(
        tester.getSemantics(_key('vendor-target-gender-women')).label,
        'Walengwa, Wanawake',
      );
      expect(
        tester.getSemantics(_key('vendor-target-age-30_44')).label,
        'Kundi la umri, 30 hadi 44',
      );
      handle.dispose();
    });

    apiTest('3: Made for chips are radios, Age group chips checkboxes, '
        'with their checked state', (tester, api) async {
      final handle = tester.ensureSemantics();
      seedVendor(api);
      await pumpVendor(tester, api);
      await tester.tap(_key('vendor-add-product'));
      await tester.pumpAndSettle();
      await tapVisible(tester, _key('vendor-target-gender-women'));
      await tapVisible(tester, _key('vendor-target-age-30_44'));
      SemanticsFlags flags(String k) =>
          tester.getSemantics(_key(k)).getSemanticsData().flagsCollection;
      final women = flags('vendor-target-gender-women');
      expect(women.isChecked, CheckedState.isTrue);
      expect(women.isInMutuallyExclusiveGroup, isTrue);
      final men = flags('vendor-target-gender-men');
      expect(men.isChecked, CheckedState.isFalse);
      expect(men.isInMutuallyExclusiveGroup, isTrue);
      final band = flags('vendor-target-age-30_44');
      expect(band.isChecked, CheckedState.isTrue);
      expect(band.isInMutuallyExclusiveGroup, isFalse);
      expect(flags('vendor-target-age-45_59').isChecked, CheckedState.isFalse);
      handle.dispose();
    });

    apiTest('13: the product menu is labelled with the product, ledger off', (
      tester,
      api,
    ) async {
      seedVendor(
        api,
        products: [
          {'id': 'p9', 'name': 'Sports bra', 'priceTzs': 25000, 'stock': 3},
        ],
      );
      final host = await pumpVendor(tester, api);
      final menu = tester.widget<PopupMenuButton<String>>(
        find.descendant(
          of: _key('vendor-product-p9'),
          matching: find.byType(PopupMenuButton<String>),
        ),
      );
      expect(
        menu.tooltip,
        host.tr('vendor.productActions').replaceAll('{name}', 'Sports bra'),
      );
    });

    apiTest('chips are 48dp and announce their group', (tester, api) async {
      final handle = tester.ensureSemantics();
      seedVendor(api);
      final host = await pumpVendor(tester, api);
      await tester.tap(_key('vendor-add-product'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(_key('vendor-target-age-30_44'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(_key('vendor-target-age-30_44')).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSemantics(_key('vendor-target-age-30_44')).label,
        '${host.tr('vendor.target.ageGroup')}, 30 to 44',
      );
      expect(
        tester.getSemantics(_key('vendor-target-gender-women')).label,
        '${host.tr('vendor.target.madeFor')}, ${host.tr('vendor.target.women')}',
      );
      handle.dispose();
    });

    for (final lang in ['en', 'sw']) {
      apiTest('fits at 130% text ($lang)', (tester, api) async {
        seedVendor(api);
        final errors = await captureFlutterErrors(() async {
          await pumpVendor(tester, api, lang: lang, scale: 1.3);
          await tester.tap(_key('vendor-add-product'));
          await tester.pumpAndSettle();
          await tester.ensureVisible(_key('vendor-target-age-60_plus'));
          await tester.pumpAndSettle();
        });
        expect(errors, isEmpty);
        expect(_key('vendor-product-targets'), findsOneWidget);
      });
    }
  });

  apiTest('13: product sheet: no struck-through price when the discount '
      'is 0', (tester, api) async {
    debugShopHomeV2Override = false;
    final free = {..._p('p7', 'Water bottle'), 'discountPriceTzs': 0};
    api.on('GET /shop/products', [free]);
    api.on('GET /me/shop-orders', <dynamic>[]);
    api.on('GET /gyms', <dynamic>[]);
    api.on('GET /shop/products/p7', free);
    await pumpPage(
      tester,
      api,
      const ShopBrowsePage(),
      user: _member,
      size: const Size(420, 900),
    );
    await tester.tap(find.text('Water bottle'));
    await tester.pumpAndSettle();
    final struck = tester
        .widgetList<Text>(find.byType(Text))
        .where((t) => t.style?.decoration == TextDecoration.lineThrough);
    expect(struck, isEmpty);
  });

  group('parsing', () {
    test('reasonParams apply to string reason codes', () {
      final s = ShopHomeSection.fromJson({
        'key': 'recommended',
        'reasonCodes': ['bought_category', 'role_context'],
        'reasonParams': {'category': 'equipment'},
      });
      expect(s.reasonCodes.first.params, {'category': 'equipment'});
    });

    test('personalisation missing means null; present is read exactly', () {
      expect(ShopHomeData.fromJson({}).personalisation, isNull);
      final p = ShopHomeData.fromJson({
        'personalisation': {'available': true, 'enabled': false},
      }).personalisation!;
      expect(p.available, isTrue);
      expect(p.enabled, isFalse);
      expect(p.active, isFalse);
    });

    test('preferences: no value means on; available only when true', () {
      final p = ShopPreferences.fromJson({});
      expect(p.personalised, isTrue);
      expect(p.available, isFalse);
    });
  });
}
