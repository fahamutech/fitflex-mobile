// Shop home Phase 2 · S1: the vendor's Promotions (banner proposals).
//
// Mocks the contract from fitflex-functions feat/shop-banners:
//   GET /vendor/tools/options → merch: {banners: bool}
//   GET/POST /vendor/shop-banners, PATCH /:id, POST /:id/submit|withdraw,
//   POST /:id/image (multipart)
//   422 price_claim_in_text {field}, 422 missing_translation {field},
//   403 target_not_owned, 409 not_editable, 404 feature_disabled.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/vendor/merch/banner_form_page.dart';
import 'package:fitflexmobile/screens/vendor/merch/banner_models.dart';
import 'package:fitflexmobile/screens/vendor/merch/vendor_banners_page.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import '../support/recording_api.dart';
import 'stock_support.dart';

final _now = DateTime.utc(2026, 10, 20, 8);
DateTime _clock() => _now;

const _merchOn = {
  'stockLedger': false,
  'merch': {'banners': true},
};

Map<String, dynamic> _text(String en, String sw) => {'en': en, 'sw': sw};

/// The vendor view (docs/shop-banners-api.md).
Map<String, dynamic> _banner(
  String id,
  String status, {
  String? statusReason,
  bool endedByFitflex = false,
  List<String>? actions,
  String startsAt = '2026-10-25T06:00:00Z',
  String endsAt = '2026-11-01T06:00:00Z',
  Map<String, dynamic> target = const {'type': 'product', 'value': 'p1'},
  List<String> audience = const ['member', 'trainer', 'owner'],
  bool published = false,
}) => {
  'id': id,
  'origin': 'vendor',
  'vendorId': 'v1',
  'status': status == 'live' ? 'approved' : status,
  'effectiveStatus': status,
  'image': {
    'id': 'hero_$id',
    'width': 2560,
    'height': 1600,
    'people': 'none',
    'previewUrl': '/vendor/shop-banners/$id/image',
    'public': published
        ? {
            'url1x': '/storage/cid/$id-1x.webp',
            'url2x': '/storage/cid/$id-2x.webp',
            'urlWide': '/storage/cid/$id-wide.webp',
          }
        : null,
  },
  'imageAlt': _text('A foam roller', 'Roli ya povu'),
  'headlineLead': _text('Recover', 'Pona'),
  'headlineAccent': _text('faster $id', 'haraka $id'),
  'subline': null,
  'ctaLabel': _text('View product', 'Tazama bidhaa'),
  'ctaLabelCustom': false,
  'target': target,
  'targetName': 'Foam Roller',
  'audienceRoles': audience,
  'startsAt': startsAt,
  'endsAt': endsAt,
  'expiresAt': status == 'pending_approval' ? '2026-10-25T06:00:00Z' : null,
  'statusReason': statusReason,
  'endedByFitflex': endedByFitflex,
  'allowedActions':
      actions ??
      switch (status) {
        'draft' => ['edit', 'image', 'submit', 'withdraw'],
        'pending_approval' || 'approved' => ['edit', 'image', 'withdraw'],
        'live' => ['edit', 'image', 'end'],
        'rejected' => ['edit', 'image'],
        _ => <String>[],
      },
};

Map<String, dynamic> _list(
  List<Map<String, dynamic>> items, {
  bool canPropose = true,
  String? reason,
}) => {
  'items': items,
  'total': items.length,
  'nextCursor': null,
  'vendor': {'canPropose': canPropose, 'reason': reason},
  'proposalExpiryDays': 14,
};

final _products = [
  stockProduct('p1', 'Foam Roller'),
  stockProduct('p2', 'Old Mat', stock: 0),
  {...stockProduct('p3', 'Paused Band'), 'status': 'paused'},
];

void _seedPage(
  RecordingApi api, {
  List<Map<String, dynamic>> banners = const [],
  Map<String, dynamic> tools = _merchOn,
}) {
  api.on('GET /vendor/tools/options', tools);
  api.on('GET /vendor/shop-banners', _list(banners));
  api.on('GET /vendor/products', _products);
  api.on('GET /vendor/profile', {'businessName': 'Duka la Asha'});
}

Future<PageHost> _pumpPage(
  WidgetTester tester,
  RecordingApi api, {
  Map<String, dynamic> user = vendorUser,
  String lang = 'en',
  double scale = 1,
}) => pumpPage(
  tester,
  api,
  VendorBannersPage(now: _clock),
  user: user,
  lang: lang,
  textScale: scale,
  size: const Size(400, 900),
);

Finder _key(String k) => find.byKey(Key(k));

/// The text shown by [f] (a Text, or the first Text inside it).
String _txt(WidgetTester tester, Finder f) {
  final text = tester.widget<Text>(
    find.descendant(of: f, matching: find.byType(Text), matchRoot: true).first,
  );
  return text.data ?? text.textSpan?.toPlainText() ?? '';
}

PickedBannerImage _image({
  int width = 2000,
  int height = 1250,
  int bytes = 2000,
  String name = 'roller.webp',
}) => PickedBannerImage(
  bytes: Uint8List(bytes),
  filename: name,
  width: width,
  height: height,
);

Future<void> _type(WidgetTester tester, String field, String lang, String v) =>
    typeInto(tester, _key('merch-field-$field-$lang'), v);

/// Fills a valid new banner (image, texts, product, dates).
Future<void> _fillValid(WidgetTester tester) async {
  debugBannerImagePicker = () async => _image();
  await tapVisible(tester, _key('merch-pick-image'));
  await tapVisible(tester, _key('merch-people-none'));
  await tapVisible(tester, _key('merch-check-rights'));
  await _type(tester, 'imageAlt', 'en', 'A blue foam roller');
  await _type(tester, 'imageAlt', 'sw', 'Roli ya povu ya bluu');
  await _type(tester, 'headlineLead', 'en', 'Recover');
  await _type(tester, 'headlineLead', 'sw', 'Pona');
  await _type(tester, 'headlineAccent', 'en', 'faster');
  await _type(tester, 'headlineAccent', 'sw', 'haraka');
  await tester.ensureVisible(_key('merch-product'));
  await tester.tap(_key('merch-product'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Foam Roller').last);
  await tester.pumpAndSettle();
  for (final k in ['merch-startsAt', 'merch-endsAt']) {
    await tapVisible(tester, _key(k));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }
}

Future<void> _openNewForm(WidgetTester tester) async {
  await tapVisible(tester, _key('merch-propose'));
  expect(_key('merch-banner-form'), findsOneWidget);
}

Future<void> _send(WidgetTester tester) async {
  await tapVisible(tester, _key('merch-send'));
}

String? _errorText(WidgetTester tester, String field, String lang) {
  final f = find.descendant(
    of: _key('merch-field-$field-$lang'),
    matching: find.byType(TextField),
  );
  return tester.widget<TextField>(f).decoration?.errorText;
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => debugBannerImagePicker = null);

  group('options gating (vendor home)', () {
    for (final (name, tools, shown) in [
      ('merch.banners true', _merchOn, true),
      (
        'merch.banners false',
        {
          'merch': {'banners': false},
        },
        false,
      ),
      ('no merch key (older server)', {'stockLedger': false}, false),
      (
        'merch.banners "true" (not exactly true)',
        {
          'merch': {'banners': 'true'},
        },
        false,
      ),
    ]) {
      apiTest('$name → Promotions ${shown ? 'shown' : 'hidden'}', (
        tester,
        api,
      ) async {
        seedVendorHome(
          api,
          products: [stockProduct('p1', 'Roller')],
          tools: tools,
        );
        final host = await pumpVendorHome(tester, api);
        expect(
          _key('vendor-merch-entry'),
          shown ? findsOneWidget : findsNothing,
        );
        if (shown) {
          expect(find.text(host.tr('merch.entry.title')), findsOneWidget);
        }
      });
    }

    apiTest('options call fails → hidden', (tester, api) async {
      seedVendorHome(api, products: [stockProduct('p1', 'Roller')]);
      api.fail('GET /vendor/tools/options', 500);
      await pumpVendorHome(tester, api);
      expect(_key('vendor-merch-entry'), findsNothing);
    });

    apiTest('staff without products permission → hidden', (tester, api) async {
      seedVendorHome(api, products: const [], tools: _merchOn);
      await pumpVendorHome(
        tester,
        api,
        user: const {
          'id': 's1',
          'userType': 'vendor_staff',
          'vendorId': 'v1',
          'vendorPermissions': ['orders'],
        },
      );
      expect(_key('vendor-merch-entry'), findsNothing);
    });

    apiTest('the tile opens /vendor/merch', (tester, api) async {
      seedVendorHome(
        api,
        products: [stockProduct('p1', 'Roller')],
        tools: _merchOn,
      );
      api.on('GET /vendor/shop-banners', _list(const []));
      await pumpPage(
        tester,
        api,
        const VendorHomePage(),
        size: const Size(400, 900),
        extraRoutes: [
          GoRoute(
            path: AppRoutes.vendorMerch,
            builder: (_, _) => VendorBannersPage(now: _clock),
          ),
        ],
      );
      await tapVisible(tester, _key('vendor-merch-entry'));
      expect(find.byType(VendorBannersPage), findsOneWidget);
      expect(_key('merch-empty'), findsOneWidget);
    });
  });

  group('list', () {
    apiTest('grouped, with status and reason', (tester, api) async {
      _seedPage(
        api,
        banners: [
          _banner('b1', 'pending_approval'),
          _banner('b2', 'rejected', statusReason: 'Photo is blurry'),
          _banner('b3', 'approved'),
          _banner(
            'b4',
            'live',
            startsAt: '2026-10-19T06:00:00Z',
            endsAt: '2026-10-30T06:00:00Z',
            published: true,
          ),
          _banner('b5', 'draft'),
          _banner('b6', 'expired'),
        ],
      );
      final host = await _pumpPage(tester, api);
      expect(
        verticalOrder(tester, [
          host.tr('merch.group.live'),
          host.tr('merch.group.scheduled'),
          host.tr('merch.group.waiting'),
          host.tr('merch.group.drafts'),
          host.tr('merch.group.past'),
        ]),
        ['Live', 'Scheduled', 'Waiting for approval', 'Not sent yet', 'Past'],
      );
      String status(String id) => _txt(
        tester,
        find.descendant(
          of: _key('merch-status-$id'),
          matching: find.byType(Text),
        ),
      );
      expect(status('b1'), 'Waiting for approval');
      expect(status('b2'), 'Rejected');
      expect(status('b3'), 'Scheduled');
      expect(status('b4'), 'Live');
      expect(status('b6'), 'Expired');
      expect(find.text('Reason: Photo is blurry'), findsOneWidget);
      // The server's expiresAt, in Tanzania time (06:00Z = 09:00 EAT).
      expect(
        _txt(tester, _key('merch-line-b1')),
        'Expires 25 Oct 2026, 09:00 if not reviewed',
      );
      expect(find.textContaining('Links to: Foam Roller'), findsWidgets);
      // Actions by state.
      expect(_key('merch-withdraw-b1'), findsOneWidget);
      expect(_key('merch-edit-b1'), findsOneWidget);
      // Live: End now and Edit (back for approval), never Withdraw.
      expect(_key('merch-withdraw-b4'), findsNothing);
      expect(_key('merch-end-b4'), findsOneWidget);
      expect(_key('merch-edit-b4'), findsOneWidget);
      expect(_key('merch-submit-b5'), findsOneWidget);
      // Rejected: Edit (becomes a draft) and Copy to new.
      expect(_key('merch-copy-b2'), findsOneWidget);
      expect(_key('merch-edit-b2'), findsOneWidget);
      expect(_key('merch-withdraw-b2'), findsNothing);
      expect(_key('merch-edit-b6'), findsNothing);
      expect(
        find.text('Shown to: Members, Trainers, Gym owners'),
        findsWidgets,
      );
    });

    apiTest('Swahili labels', (tester, api) async {
      _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
      await _pumpPage(tester, api, lang: 'sw');
      expect(find.text('Promosheni'), findsOneWidget);
      expect(find.text('Inasubiri idhini'), findsOneWidget);
      expect(find.text('Pendekeza bango'), findsOneWidget);
    });

    apiTest('tool off → "isn\'t available yet", no list call', (
      tester,
      api,
    ) async {
      _seedPage(api, tools: {'stockLedger': true});
      final host = await _pumpPage(tester, api);
      expect(_key('merch-unavailable'), findsOneWidget);
      expect(find.text(host.tr('merch.unavailable')), findsOneWidget);
      expect(api.sent('GET', '/vendor/shop-banners'), isFalse);
    });

    apiTest('404 feature_disabled → unavailable', (tester, api) async {
      _seedPage(api);
      api.fail('GET /vendor/shop-banners', 404, {'error': 'feature_disabled'});
      await _pumpPage(tester, api);
      expect(_key('merch-unavailable'), findsOneWidget);
    });

    apiTest('server error → error state with retry', (tester, api) async {
      _seedPage(api);
      api.fail('GET /vendor/shop-banners', 500);
      await _pumpPage(tester, api);
      expect(_key('merch-error'), findsOneWidget);
    });

    apiTest('pending vendor → why, and the Verification centre', (
      tester,
      api,
    ) async {
      _seedPage(api);
      final host = await _pumpPage(
        tester,
        api,
        user: const {
          'id': 'v1',
          'userType': 'vendor',
          'approvalStatus': 'pending_approval',
        },
      );
      expect(_key('merch-pending'), findsOneWidget);
      expect(find.text(host.tr('merch.pendingTitle')), findsOneWidget);
      expect(_key('merch-propose'), findsNothing);
      expect(api.sent('GET', '/vendor/shop-banners'), isFalse);
    });

    apiTest('withdraw: confirm → POST withdraw → list reloads', (
      tester,
      api,
    ) async {
      _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
      final host = await _pumpPage(tester, api);
      api.clear();
      api.on('GET /vendor/shop-banners', _list([_banner('b1', 'withdrawn')]));
      await tapVisible(tester, _key('merch-withdraw-b1'));
      expect(find.text(host.tr('merch.withdraw.title')), findsOneWidget);
      await tapVisible(tester, _key('merch-withdraw-confirm'));
      api.only('POST', '/vendor/shop-banners/b1/withdraw');
      expect(host.snack(host.tr('merch.withdrawn')), findsOneWidget);
      expect(api.sent('GET', '/vendor/shop-banners'), isTrue);
      expect(find.text('Withdrawn'), findsOneWidget);
    });

    apiTest('withdraw cancelled → nothing sent', (tester, api) async {
      _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
      await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-withdraw-b1'));
      await tapVisible(tester, find.text('Keep'));
      expect(api.sent('POST', '/vendor/shop-banners/b1/withdraw'), isFalse);
    });

    apiTest('withdraw refused 409 not_editable → says so', (tester, api) async {
      _seedPage(api, banners: [_banner('b1', 'approved')]);
      final host = await _pumpPage(tester, api);
      api.fail('POST /vendor/shop-banners/b1/withdraw', 409, {
        'error': 'not_editable',
      });
      await tapVisible(tester, _key('merch-withdraw-b1'));
      await tapVisible(tester, _key('merch-withdraw-confirm'));
      expect(host.snack(host.tr('merch.notEditable')), findsOneWidget);
    });

    apiTest('live: End now asks, then POST end', (tester, api) async {
      _seedPage(api, banners: [_banner('b4', 'live', published: true)]);
      final host = await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-end-b4'));
      expect(find.text(host.tr('merch.endBanner.title')), findsOneWidget);
      await tapVisible(tester, _key('merch-end-confirm'));
      api.only('POST', '/vendor/shop-banners/b4/end');
      expect(host.snack(host.tr('merch.ended')), findsOneWidget);
    });

    apiTest('ended by FitFlex shows the reason', (tester, api) async {
      _seedPage(
        api,
        banners: [
          _banner(
            'b7',
            'ended',
            statusReason: 'Wrong product photo',
            endedByFitflex: true,
          ),
        ],
      );
      await _pumpPage(tester, api);
      expect(
        find.text('Ended by FitFlex: Wrong product photo'),
        findsOneWidget,
      );
    });

    for (final (reason, key) in [
      ('vendor_suspended', 'merch.suspended'),
      ('vendor_not_approved', 'merch.pendingBody'),
    ]) {
      apiTest('canPropose false ($reason) → alert, no Propose', (
        tester,
        api,
      ) async {
        _seedPage(api);
        api.on(
          'GET /vendor/shop-banners',
          _list(
            [_banner('b1', 'pending_approval')],
            canPropose: false,
            reason: reason,
          ),
        );
        final host = await _pumpPage(tester, api);
        expect(_key('merch-propose'), findsNothing);
        expect(find.text(host.tr(key)), findsOneWidget);
        expect(_key('merch-banner-b1'), findsOneWidget);
      });
    }

    apiTest('409 proposal_expired on submit → says it can\'t change', (
      tester,
      api,
    ) async {
      _seedPage(api, banners: [_banner('b5', 'draft')]);
      final host = await _pumpPage(tester, api);
      api.fail('POST /vendor/shop-banners/b5/submit', 409, {
        'error': 'proposal_expired',
      });
      await tapVisible(tester, _key('merch-submit-b5'));
      expect(host.snack(host.tr('merch.notEditable')), findsOneWidget);
    });

    apiTest('a draft can be sent from the list', (tester, api) async {
      _seedPage(api, banners: [_banner('b5', 'draft')]);
      final host = await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-submit-b5'));
      api.only('POST', '/vendor/shop-banners/b5/submit');
      expect(host.snack(host.tr('merch.sent')), findsOneWidget);
    });

    apiTest('130% text, Swahili: cards do not overflow', (tester, api) async {
      _seedPage(
        api,
        banners: [
          _banner('b1', 'pending_approval'),
          _banner('b2', 'rejected', statusReason: 'Picha haieleweki vizuri'),
        ],
      );
      await _pumpPage(tester, api, lang: 'sw', scale: 1.3);
      expect(tester.takeException(), isNull);
    });
  });

  group('form validation', () {
    apiTest('empty: every required field says so; nothing is sent', (
      tester,
      api,
    ) async {
      _seedPage(api);
      final host = await _pumpPage(tester, api);
      await _openNewForm(tester);
      api.clear();
      await _send(tester);
      expect(
        _txt(tester, _key('merch-error-image')),
        host.tr('merch.banner.imageRequired'),
      );
      for (final f in ['imageAlt', 'headlineLead', 'headlineAccent']) {
        expect(_errorText(tester, f, 'en'), 'Write this in English.');
        expect(_errorText(tester, f, 'sw'), 'Write this in Swahili.');
      }
      // The button text starts filled in for the target, in both languages.
      expect(_errorText(tester, 'ctaLabel', 'en'), isNull);
      expect(_errorText(tester, 'ctaLabel', 'sw'), isNull);
      // Subline is optional.
      expect(_errorText(tester, 'subline', 'en'), isNull);
      expect(
        _txt(tester, _key('merch-error-target')),
        host.tr('merch.banner.productRequired'),
      );
      expect(
        _txt(tester, _key('merch-error-startsAt')),
        host.tr('merch.dates.required'),
      );
      expect(api.requests.where((r) => r.method != 'GET'), isEmpty);
    });

    apiTest('the button follows the target: View product / Visit store', (
      tester,
      api,
    ) async {
      _seedPage(api);
      await _pumpPage(tester, api);
      await _openNewForm(tester);
      expect(_txt(tester, _key('merch-button-label')), 'Button: View product');
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: _key('merch-field-ctaLabel-sw'),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        'Tazama bidhaa',
      );
      await tapVisible(tester, _key('merch-target-vendor_store'));
      expect(_txt(tester, _key('merch-button-label')), 'Button: Visit store');
      // Only own active, approved products in stock can be picked.
      await tapVisible(tester, _key('merch-target-product'));
      await tester.ensureVisible(_key('merch-product'));
      await tester.tap(_key('merch-product'));
      await tester.pumpAndSettle();
      expect(find.text('Foam Roller'), findsWidgets);
      expect(find.text('Old Mat'), findsNothing);
      expect(find.text('Paused Band'), findsNothing);
    });

    apiTest('no prices, percentages, links or phone numbers', (
      tester,
      api,
    ) async {
      _seedPage(api);
      final host = await _pumpPage(tester, api);
      await _openNewForm(tester);
      await _type(tester, 'headlineLead', 'en', 'Only TSh 50,000');
      await _type(tester, 'headlineLead', 'sw', 'Punguzo 20%');
      await _type(tester, 'headlineAccent', 'en', 'call 0712 345 678');
      await _type(tester, 'headlineAccent', 'sw', 'www.duka.co.tz');
      await _send(tester);
      final noPrices = host.tr('merch.banner.noPrices');
      final noLinks = host.tr('merch.banner.noLinks');
      expect(_errorText(tester, 'headlineLead', 'en'), noPrices);
      expect(_errorText(tester, 'headlineLead', 'sw'), noPrices);
      expect(_errorText(tester, 'headlineAccent', 'en'), noLinks);
      expect(_errorText(tester, 'headlineAccent', 'sw'), noLinks);
    });

    apiTest('headline length, subline in one language only', (
      tester,
      api,
    ) async {
      _seedPage(api);
      final host = await _pumpPage(tester, api);
      await _openNewForm(tester);
      await _type(tester, 'headlineLead', 'en', 'Recover faster after');
      await _type(tester, 'headlineAccent', 'en', 'every long run');
      await _type(tester, 'subline', 'en', 'New this week');
      await _send(tester);
      expect(
        _errorText(tester, 'headlineLead', 'en'),
        host.tr('merch.banner.tooLong').replaceAll('{n}', '32'),
      );
      expect(_errorText(tester, 'subline', 'sw'), 'Add the Swahili text too.');
    });

    test('text rule', () {
      for (final bad in [
        'Save 20%',
        'Only 50,000/=',
        'TSh 45000',
        'tzs 10',
        'Asilimia 10',
        '10 off today',
        'bei 5000',
      ]) {
        expect(bannerTextProblem(bad), 'price', reason: bad);
      }
      for (final bad in ['Call +255 712 345 678', 'duka.com', 'https://x.y']) {
        expect(bannerTextProblem(bad), 'contact', reason: bad);
      }
      for (final ok in [
        'Join our 5K run',
        'Recover faster',
        'Mazoezi 3 kwa wiki',
      ]) {
        expect(bannerTextProblem(ok), isNull, reason: ok);
      }
    });

    for (final (name, image, key) in [
      (
        '1200 × 800',
        _image(width: 1200, height: 800),
        'merch.banner.imageSize',
      ),
      ('6 MB', _image(bytes: 6 * 1024 * 1024), 'merch.banner.imageWeight'),
      ('a GIF', _image(name: 'x.gif'), 'merch.banner.imageType'),
    ]) {
      apiTest('image rejected: $name', (tester, api) async {
        _seedPage(api);
        final host = await _pumpPage(tester, api);
        await _openNewForm(tester);
        debugBannerImagePicker = () async => image;
        await tapVisible(tester, _key('merch-pick-image'));
        await _send(tester);
        expect(_txt(tester, _key('merch-error-image')), host.tr(key));
      });
    }

    apiTest('rights and models confirmations are required', (
      tester,
      api,
    ) async {
      _seedPage(api);
      final host = await _pumpPage(tester, api);
      await _openNewForm(tester);
      debugBannerImagePicker = () async => _image();
      await tapVisible(tester, _key('merch-pick-image'));
      await tapVisible(tester, _key('merch-people-product_models'));
      await _send(tester);
      final tick = host.tr('merch.confirmRequired');
      expect(_txt(tester, _key('merch-error-rights')), tick);
      expect(_txt(tester, _key('merch-error-models')), tick);
    });

    apiTest('dates: start an hour ahead, end after start; no maximum', (
      tester,
      api,
    ) async {
      _seedPage(
        api,
        banners: [
          _banner(
            'b5',
            'draft',
            startsAt: '2026-10-20T08:30:00Z',
            endsAt: '2026-10-20T08:00:00Z',
          ),
          _banner(
            'b6',
            'draft',
            startsAt: '2026-10-21T08:00:00Z',
            endsAt: '2027-01-25T08:00:00Z',
          ),
        ],
      );
      final host = await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-edit-b5'));
      await _send(tester);
      expect(
        _txt(tester, _key('merch-error-startsAt')),
        host.tr('merch.dates.startSoon'),
      );
      expect(
        _txt(tester, _key('merch-error-endsAt')),
        host.tr('merch.dates.endAfter'),
      );
      await tapVisible(tester, _key('merch-cancel'));
      // A three-month run is fine (owner: no maximum length).
      api.on('PATCH /vendor/shop-banners/b6', {
        'banner': {'id': 'b6', 'status': 'draft', 'effectiveStatus': 'draft'},
      });
      await tapVisible(tester, _key('merch-edit-b6'));
      await _send(tester);
      expect(_key('merch-error-endsAt'), findsNothing);
      api.only('POST', '/vendor/shop-banners/b6/submit');
    });

    apiTest('Show to: at least one audience', (tester, api) async {
      _seedPage(api);
      final host = await _pumpPage(tester, api);
      await _openNewForm(tester);
      for (final a in ['member', 'trainer', 'owner']) {
        await tapVisible(tester, _key('merch-audience-$a'));
      }
      await _send(tester);
      expect(
        _txt(tester, _key('merch-error-audience')),
        host.tr('merch.banner.pickAudience'),
      );
    });
  });

  group('form submit', () {
    apiTest('new: POST, image upload, submit; back on the list', (
      tester,
      api,
    ) async {
      _seedPage(api);
      final host = await _pumpPage(tester, api);
      await _openNewForm(tester);
      await _fillValid(tester);
      api.clear();
      api.on('POST /vendor/shop-banners', {'banner': _banner('b9', 'draft')});
      api.on('POST /vendor/shop-banners/b9/image', {
        'banner': _banner('b9', 'draft'),
      });
      api.on('POST /vendor/shop-banners/b9/submit', {
        'banner': _banner('b9', 'pending_approval'),
      });
      api.on(
        'GET /vendor/shop-banners',
        _list([_banner('b9', 'pending_approval')]),
      );
      await _send(tester);
      expect(api.only('POST', '/vendor/shop-banners').body, {
        'imageAlt': {'en': 'A blue foam roller', 'sw': 'Roli ya povu ya bluu'},
        'headlineLead': {'en': 'Recover', 'sw': 'Pona'},
        'headlineAccent': {'en': 'faster', 'sw': 'haraka'},
        // The button text was not changed: the server's default is used.
        'target': {'type': 'product', 'value': 'p1'},
        'audienceRoles': ['member', 'trainer', 'owner'],
        // Tomorrow 11:00 Tanzania time, and a week later.
        'startsAt': '2026-10-21T08:00:00.000Z',
        'endsAt': '2026-10-28T08:00:00.000Z',
      });
      expect(api.only('POST', '/vendor/shop-banners/b9/image').body, {
        'multipart': true,
        'bytes': greaterThan(2000),
        'fields': {'people': 'none', 'rightsConfirmed': 'true'},
      });
      api.only('POST', '/vendor/shop-banners/b9/submit');
      expect(
        api.requests
            .map((r) => r.key)
            .toList()
            .indexOf('POST /vendor/shop-banners/b9/image'),
        lessThan(
          api.requests
              .map((r) => r.key)
              .toList()
              .indexOf('POST /vendor/shop-banners/b9/submit'),
        ),
      );
      expect(host.snack(host.tr('merch.sent')), findsOneWidget);
      expect(_key('merch-banner-form'), findsNothing);
      expect(_key('merch-banner-b9'), findsOneWidget);
    });

    apiTest('store target sends the vendor id', (tester, api) async {
      _seedPage(api);
      await _pumpPage(tester, api);
      await _openNewForm(tester);
      await _fillValid(tester);
      await tapVisible(tester, _key('merch-target-vendor_store'));
      api.on('POST /vendor/shop-banners', {'banner': _banner('b9', 'draft')});
      await _send(tester);
      final body = api.only('POST', '/vendor/shop-banners').body as Map;
      expect(body['target'], {'type': 'vendor_store', 'value': 'v1'});
      // Default button for the store: left to the server.
      expect(body.containsKey('ctaLabel'), isFalse);
    });

    apiTest('edit a pending banner: PATCH, stays pending, no submit', (
      tester,
      api,
    ) async {
      _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
      await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-edit-b1'));
      await _type(tester, 'headlineAccent', 'en', 'quicker');
      api.on('PATCH /vendor/shop-banners/b1', {
        'banner': _banner('b1', 'pending_approval'),
      });
      await _send(tester);
      final body = api.only('PATCH', '/vendor/shop-banners/b1').body as Map;
      expect(body['headlineAccent'], {'en': 'quicker', 'sw': 'haraka b1'});
      // No subline: cleared explicitly on a PATCH.
      expect(body.containsKey('subline'), isTrue);
      expect(body['subline'], isNull);
      expect(api.sent('POST', '/vendor/shop-banners/b1/submit'), isFalse);
      expect(api.sent('POST', '/vendor/shop-banners/b1/image'), isFalse);
    });

    apiTest('edit a scheduled banner asks first, then sends it again', (
      tester,
      api,
    ) async {
      _seedPage(api, banners: [_banner('b3', 'approved')]);
      final host = await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-edit-b3'));
      // An approved banner goes back to pending by itself: no submit.
      api.on('PATCH /vendor/shop-banners/b3', {
        'banner': _banner('b3', 'pending_approval'),
      });
      await _send(tester);
      expect(find.text(host.tr('merch.resend.title')), findsOneWidget);
      await tapVisible(tester, _key('merch-resend-confirm'));
      api.only('PATCH', '/vendor/shop-banners/b3');
      expect(api.sent('POST', '/vendor/shop-banners/b3/submit'), isFalse);
    });

    apiTest('edit a rejected banner: PATCH makes a draft, then submit', (
      tester,
      api,
    ) async {
      _seedPage(api, banners: [_banner('b2', 'rejected', statusReason: 'x')]);
      await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-edit-b2'));
      api.on('PATCH /vendor/shop-banners/b2', {
        'banner': _banner('b2', 'draft'),
      });
      await _send(tester);
      api.only('POST', '/vendor/shop-banners/b2/submit');
    });

    apiTest(
      'models in the photo: peopleConfirmed is sent',
      (tester, api) async {
        _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
        await _pumpPage(tester, api);
        await tapVisible(tester, _key('merch-edit-b1'));
        debugBannerImagePicker = () async => _image();
        await tapVisible(tester, _key('merch-pick-image'));
        await tapVisible(tester, _key('merch-people-product_models'));
        await tapVisible(tester, _key('merch-check-rights'));
        await tapVisible(tester, _key('merch-check-models'));
        api.on('PATCH /vendor/shop-banners/b1', {
          'banner': _banner('b1', 'pending_approval'),
        });
        await _send(tester);
        expect(
          (api.only('POST', '/vendor/shop-banners/b1/image').body
              as Map)['fields'],
          {
            'people': 'product_models',
            'rightsConfirmed': 'true',
            'peopleConfirmed': 'true',
          },
        );
      },
    );

    apiTest('413 file_too_large on upload → under the image', (
      tester,
      api,
    ) async {
      _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
      final host = await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-edit-b1'));
      debugBannerImagePicker = () async => _image();
      await tapVisible(tester, _key('merch-pick-image'));
      await tapVisible(tester, _key('merch-people-none'));
      await tapVisible(tester, _key('merch-check-rights'));
      api.on('PATCH /vendor/shop-banners/b1', {
        'banner': _banner('b1', 'pending_approval'),
      });
      api.fail('POST /vendor/shop-banners/b1/image', 413, {
        'error': 'file_too_large',
        'maxBytes': 5242880,
      });
      await _send(tester);
      expect(
        _txt(tester, _key('merch-error-image')),
        host.tr('merch.banner.imageWeight'),
      );
    });

    for (final (code, status, field, expected) in [
      (
        'price_claim_in_text',
        422,
        'subline.sw',
        'Banners can\'t show prices or discounts. Use a flash sale for a deal.',
      ),
      (
        'missing_translation',
        422,
        'headlineAccent.sw',
        'Add the Swahili text too.',
      ),
      (
        'contact_in_text',
        422,
        'headlineLead.en',
        'Remove links and phone numbers.',
      ),
      (
        'headline_too_long',
        422,
        'headlineLead.sw',
        'Keep the headline to 42 characters.',
      ),
    ]) {
      apiTest('server $code {field: $field} → under that field', (
        tester,
        api,
      ) async {
        _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
        await _pumpPage(tester, api);
        await tapVisible(tester, _key('merch-edit-b1'));
        api.fail('PATCH /vendor/shop-banners/b1', status, {
          'error': code,
          'field': field,
        });
        await _send(tester);
        final parts = field.split('.');
        expect(_errorText(tester, parts[0], parts[1]), expected);
        // Still on the form, input kept.
        expect(_key('merch-banner-form'), findsOneWidget);
      });
    }

    apiTest('403 target_not_owned → under Links to', (tester, api) async {
      _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
      final host = await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-edit-b1'));
      api.fail('PATCH /vendor/shop-banners/b1', 403, {
        'error': 'target_not_owned',
      });
      await _send(tester);
      expect(
        _txt(tester, _key('merch-error-target')),
        host.tr('merch.banner.targetNotOwned'),
      );
    });

    apiTest('409 not_editable → message, back to the list', (
      tester,
      api,
    ) async {
      _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
      final host = await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-edit-b1'));
      api.fail('PATCH /vendor/shop-banners/b1', 409, {'error': 'not_editable'});
      await _send(tester);
      expect(host.snack(host.tr('merch.notEditable')), findsOneWidget);
      expect(_key('merch-banner-form'), findsNothing);
    });

    apiTest('404 feature_disabled → "isn\'t available yet"', (
      tester,
      api,
    ) async {
      _seedPage(api, banners: [_banner('b1', 'pending_approval')]);
      final host = await _pumpPage(tester, api);
      await tapVisible(tester, _key('merch-edit-b1'));
      api.fail('PATCH /vendor/shop-banners/b1', 404, {
        'error': 'feature_disabled',
      });
      await _send(tester);
      expect(host.snack(host.tr('merch.unavailable')), findsOneWidget);
    });

    apiTest('upload fails after create: retry PATCHes, never a second POST', (
      tester,
      api,
    ) async {
      _seedPage(api);
      final host = await _pumpPage(tester, api);
      await _openNewForm(tester);
      await _fillValid(tester);
      api.on('POST /vendor/shop-banners', {'banner': _banner('b9', 'draft')});
      api.fail('POST /vendor/shop-banners/b9/image', 500);
      await _send(tester);
      expect(
        _txt(tester, _key('merch-error-image')),
        host.tr('merch.banner.uploadFailed'),
      );
      api.heal('POST /vendor/shop-banners/b9/image');
      api.on('PATCH /vendor/shop-banners/b9', {
        'banner': _banner('b9', 'draft'),
      });
      await _send(tester);
      api.only('POST', '/vendor/shop-banners');
      api.only('PATCH', '/vendor/shop-banners/b9');
      api.only('POST', '/vendor/shop-banners/b9/submit');
    });

    apiTest('cancel with changes asks before discarding', (tester, api) async {
      _seedPage(api);
      final host = await _pumpPage(tester, api);
      await _openNewForm(tester);
      await _type(tester, 'headlineLead', 'en', 'Recover');
      await tapVisible(tester, _key('merch-cancel'));
      expect(find.text(host.tr('merch.discard.title')), findsOneWidget);
      await tapVisible(tester, _key('merch-discard-confirm'));
      expect(_key('merch-banner-form'), findsNothing);
    });

    apiTest('form at 130% Swahili: no overflow', (tester, api) async {
      _seedPage(api);
      await _pumpPage(tester, api, lang: 'sw', scale: 1.3);
      await _openNewForm(tester);
      await _send(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
