// Settings → "Home photo and logo" (spec §41, §42): every state (AC-P14),
// takedowns for all seven reasons (AC-P15), Remove (AC-P16), gyms (AC-P19),
// offline (AC-P20), the vendor note (AC-P22), the upload sheet's server
// texts and ticks (AC-P25), the wording-changed reload (AC-P26), the
// multipart upload (AC-P27), refusals before any request (AC-P23), the
// plate choice (AC-P29) and the entry tiles (AC-P13).

import 'package:fitflexmobile/screens/partner/partner_media_entry_tile.dart';
import 'package:fitflexmobile/screens/partner/partner_media_page.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_flag.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_image_check.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_store.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';

const _trainer = {'id': 'u1', 'userType': 'trainer', 'displayName': 'Asha'};
const _owner = {
  'id': 'o1',
  'userType': 'gym_operator',
  'displayName': 'Rehema',
};
const _vendor = {'id': 'v1', 'userType': 'vendor'};

PickedPartnerImage _photo({int width = 1600}) => PickedPartnerImage(
  bytes: Uint8List.fromList(onePixelPng),
  filename: 'gym.png',
  type: 'image/png',
  width: width,
  height: 1000,
);

PickedPartnerImage _logo({String type = 'image/png'}) => PickedPartnerImage(
  bytes: Uint8List.fromList(onePixelPng),
  filename: 'logo.png',
  type: type,
  width: 512,
  height: 256,
);

Future<PageHost> _open(
  WidgetTester tester,
  RecordingApi api, {
  String side = 'trainer',
  String? gymId,
  Map<String, dynamic> user = _trainer,
  String lang = 'en',
  // Tall, so every card and the sheet's boxes are built (lazy lists).
  Size size = const Size(390, 3200),
}) => pumpPage(
  tester,
  api,
  PartnerMediaPage(side: side, gymId: gymId),
  user: user,
  lang: lang,
  size: size,
  keepRequests: true,
);

void main() {
  setUp(() {
    debugPhotoHeroUiOverride = true;
    debugPartnerMediaUiOverride = true;
    PartnerMediaStore.debugInstance = null;
  });
  tearDown(() {
    debugPhotoHeroUiOverride = null;
    debugPartnerMediaUiOverride = null;
    debugPartnerMediaPicker = null;
  });

  group('states (AC-P14)', () {
    apiTest('empty: FitFlex photo, no logo, upload buttons', (
      tester,
      api,
    ) async {
      api.on('GET /partner/media', overview());
      final h = await _open(tester, api);
      expect(find.text(h.tr('partnerMedia.default')), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.noLogo')), findsOneWidget);
      expect(
        find.byKey(const Key('partner-media-hero-upload')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('partner-media-logo-upload')),
        findsOneWidget,
      );
      expect(find.text(h.tr('partnerMedia.onlyYouSelf')), findsOneWidget);
      expect(find.byKey(const Key('partner-media-vendor-note')), findsNothing);
    });

    apiTest('live, bright, and set by FitFlex', (tester, api) async {
      api.on(
        'GET /partner/media',
        overview(
          hero: heroItem(bright: true),
          logo: {...logoItem(), 'origin': 'fitflex'},
        ),
      );
      final h = await _open(tester, api);
      expect(find.text(h.tr('partnerMedia.live')), findsNWidgets(2));
      expect(find.text('Added 29 Oct 2026'), findsOneWidget);
      expect(find.text('Added by FitFlex on 29 Oct 2026'), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.bright')), findsOneWidget);
      expect(
        find.byKey(const Key('partner-media-hero-replace')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('partner-media-logo-remove')),
        findsOneWidget,
      );
    });

    for (final reason in const [
      'inappropriate',
      'rights',
      'other_brand',
      'not_own_logo',
      'person_request',
      'quality',
      'other',
    ]) {
      apiTest('taken down: $reason (AC-P15)', (tester, api) async {
        api.on(
          'GET /partner/media',
          overview(
            heroDown: heroItem(
              status: 'taken_down',
              takedown: {'reason': reason, 'note': 'See the sign', 'at': 'x'},
            ),
          ),
        );
        final h = await _open(tester, api, lang: 'sw');
        final alert = find.byKey(const Key('partner-media-hero-taken-down'));
        expect(alert, findsOneWidget);
        final text =
            (tester.widget(
                      find
                          .descendant(of: alert, matching: find.byType(Text))
                          .first,
                    )
                    as Text)
                .data!;
        expect(text, contains(h.tr('partnerMedia.reason.$reason')));
        expect(text, contains('See the sign'));
        expect(text, contains(h.tr('partnerMedia.takenDownNext')));
        expect(
          find.byKey(const Key('partner-media-hero-upload')),
          findsOneWidget,
        );
        expect(find.text(h.tr('partnerMedia.uploadNew')), findsOneWidget);
      });
    }

    apiTest('load error, then Try again', (tester, api) async {
      api.fail('GET /partner/media', 500);
      final h = await _open(tester, api);
      expect(find.byKey(const Key('partner-media-load-error')), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.loadError')), findsOneWidget);
      api.heal('GET /partner/media');
      api.on('GET /partner/media', overview());
      await tapVisible(tester, find.text(h.tr('common.retry')));
      expect(find.byKey(const Key('partner-media-hero-card')), findsOneWidget);
    });

    apiTest('offline: actions disabled with the reason (AC-P20)', (
      tester,
      api,
    ) async {
      api.onCall(
        'GET /partner/media',
        (_) => throw http.ClientException('offline'),
      );
      final h = await _open(tester, api);
      expect(find.byKey(const Key('partner-media-offline')), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.offline')), findsOneWidget);
      expect(
        isEnabled(tester, find.byKey(const Key('partner-media-hero-upload'))),
        isFalse,
      );
    });

    apiTest('canEdit false: no access, nothing to change', (tester, api) async {
      api.on('GET /partner/media', overview(type: 'vendor', canEdit: false));
      final h = await _open(
        tester,
        api,
        side: 'vendor',
        user: const {'id': 's1', 'userType': 'vendor_staff'},
      );
      expect(find.text(h.tr('partnerMedia.restrictedVendor')), findsOneWidget);
      expect(find.byKey(const Key('partner-media-hero-card')), findsNothing);
    });

    apiTest('a gym the person cannot edit: no access, no gym switch '
        '(AC-P19)', (tester, api) async {
      api.on('GET /owner/gyms', [
        {'id': 'gym_a', 'name': 'Arena'},
      ]);
      api.fail('GET /partner/media', 403, {'error': 'not_your_gym'});
      final h = await _open(
        tester,
        api,
        side: 'gym',
        gymId: 'gym_x',
        user: _owner,
      );
      expect(find.text(h.tr('partnerMedia.restrictedGym')), findsOneWidget);
      expect(api.only('GET', '/partner/media').query, 'gymId=gym_x');
    });

    apiTest('owner with no gym yet', (tester, api) async {
      api.on('GET /owner/gyms', []);
      final h = await _open(tester, api, side: 'gym', user: _owner);
      expect(find.text(h.tr('partnerMedia.noGym')), findsOneWidget);
      expect(api.sent('GET', '/partner/media'), isFalse);
    });

    apiTest('feature off on the server', (tester, api) async {
      api.fail('GET /partner/media', 404, {'error': 'feature_disabled'});
      final h = await _open(tester, api);
      expect(find.text(h.tr('partnerMedia.off')), findsOneWidget);
    });

    apiTest('a member opening the page: no access, nothing asked', (
      tester,
      api,
    ) async {
      final h = await _open(
        tester,
        api,
        user: const {'id': 'm', 'userType': 'member'},
      );
      expect(find.text(h.tr('partnerMedia.restrictedGym')), findsOneWidget);
      expect(api.sent('GET', '/partner/media'), isFalse);
    });

    apiTest('vendor: the storefront note names Edit business profile '
        '(AC-P22)', (tester, api) async {
      api.on('GET /partner/media', overview(type: 'vendor', name: 'Duka'));
      final h = await _open(
        tester,
        api,
        side: 'vendor',
        user: _vendor,
        lang: 'sw',
      );
      final note = tester.widget<Text>(
        find.byKey(const Key('partner-media-vendor-note')),
      );
      expect(note.data, contains('Hariri wasifu wa biashara'));
      expect(find.text(h.tr('partnerMedia.onlyYouTeam')), findsOneWidget);
    });
  });

  group('Swahili at 360 wide, 1.3x (AC-P43)', () {
    apiTest('page and sheet lay out without clipping', (tester, api) async {
      debugPartnerMediaPicker = (_) async => _logo();
      api.on(
        'GET /partner/media',
        overview(
          type: 'vendor',
          hero: heroItem(bright: true),
          logoDown: logoItem(
            status: 'taken_down',
            takedown: {'reason': 'not_own_logo', 'note': 'Si nembo yenu'},
          ),
        ),
      );
      await pumpPage(
        tester,
        api,
        const PartnerMediaPage(side: 'vendor'),
        user: _vendor,
        lang: 'sw',
        textScale: 1.3,
        size: const Size(360, 3600),
      );
      expect(tester.takeException(), isNull);
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-logo-upload')),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-source-gallery')),
      );
      expect(
        find.byKey(const Key('partner-media-confirm-own-logo')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    apiTest('the title fits and the entry tiles wrap', (tester, api) async {
      api.on('GET /partner/media', overview());
      await pumpPage(
        tester,
        api,
        const Column(
          children: [
            PartnerMediaEntryTile(
              side: 'gym',
              gymName: 'Mazoezi Arena Kinondoni',
            ),
            PartnerMediaEntryTile(side: 'vendor'),
          ],
        ),
        user: _owner,
        lang: 'sw',
        textScale: 1.3,
        size: const Size(360, 800),
      );
      expect(tester.takeException(), isNull);
      await pumpPage(
        tester,
        api,
        const PartnerMediaPage(side: 'trainer'),
        user: _trainer,
        lang: 'sw',
        textScale: 1.3,
        size: const Size(360, 800),
      );
      expect(tester.takeException(), isNull);
      final title = tester.getRect(
        find.byKey(const Key('partner-media-title')),
      );
      expect(title.right, lessThanOrEqualTo(360));
    });
  });

  group('owner gyms (AC-P19)', () {
    apiTest('the gym row reloads the page for another gym', (
      tester,
      api,
    ) async {
      api.on('GET /owner/gyms', [
        {'id': 'gym_a', 'name': 'Arena'},
        {'id': 'gym_b', 'name': 'Bahari'},
      ]);
      api.on('GET /partner/media', overview(type: 'gym', id: 'gym_a'));
      final h = await _open(tester, api, side: 'gym', user: _owner);
      expect(find.text('Gym: Arena'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('partner-media-gym')));
      await tapVisible(tester, find.text('Bahari'));
      expect(api.where('GET', '/partner/media').last.query, 'gymId=gym_b');
      expect(find.text('Gym: Bahari'), findsOneWidget);
      expect(h.lang, 'en');
    });
  });

  group('Remove (AC-P16)', () {
    apiTest('confirm, delete, back to the empty state', (tester, api) async {
      api.on('GET /partner/media', overview(hero: heroItem()));
      final h = await _open(tester, api);
      api.on('GET /partner/media', overview());
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-hero-remove')),
      );
      expect(find.text(h.tr('partnerMedia.removeHeroTitle')), findsOneWidget);
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-remove-confirm')),
      );
      expect(api.only('DELETE', '/partner/media/pmd_hero1'), isNotNull);
      expect(h.snack(h.tr('partnerMedia.removed')), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.default')), findsOneWidget);
    });
  });

  group('Remove when it is already gone', () {
    apiTest('media_not_found: no error, reloaded, Removed.', (
      tester,
      api,
    ) async {
      api.on('GET /partner/media', overview(hero: heroItem()));
      final h = await _open(tester, api);
      api.fail('DELETE /partner/media/pmd_hero1', 404, {
        'error': 'media_not_found',
      });
      api.on('GET /partner/media', overview());
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-hero-remove')),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-remove-confirm')),
      );
      expect(find.byKey(const Key('partner-media-hero-error')), findsNothing);
      expect(h.snack(h.tr('partnerMedia.removed')), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.default')), findsOneWidget);
    });
  });

  group('upload sheet', () {
    Future<PageHost> openSheet(
      WidgetTester tester,
      RecordingApi api, {
      String kind = 'hero',
      PickedPartnerImage? picked,
      String lang = 'en',
    }) async {
      debugPartnerMediaPicker = (_) async => picked ?? _photo();
      api.on('GET /partner/media', overview());
      final h = await _open(tester, api, lang: lang);
      await tapVisible(tester, find.byKey(Key('partner-media-$kind-upload')));
      // Phones first ask where from.
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-source-gallery')),
      );
      return h;
    }

    apiTest('server texts verbatim, button off until ticked, upload sends '
        'the original file (AC-P25, AC-P27)', (tester, api) async {
      api.on('POST /partner/media/hero', {'item': heroItem()});
      final h = await openSheet(tester, api, lang: 'sw');
      expect(find.text(h.tr('partnerMedia.sheet.titleHero')), findsOneWidget);
      expect(
        find.text((confirmation['rights'] as Map)['sw'] as String),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('partner-media-confirm-own-logo')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('partner-media-preview-phone')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('partner-media-preview-wide')),
        findsOneWidget,
      );
      expect(
        isEnabled(tester, find.byKey(const Key('partner-media-use'))),
        isFalse,
      );
      // The 3 x 3 grid moves the focus point.
      await tapVisible(tester, find.byKey(const Key('ff-focal-pos-2')));
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-confirm-rights')),
      );
      expect(
        isEnabled(tester, find.byKey(const Key('partner-media-use'))),
        isTrue,
      );
      api.on('GET /partner/media', overview(hero: heroItem()));
      await tapVisible(tester, find.byKey(const Key('partner-media-use')));
      final post = api.only('POST', '/partner/media/hero');
      final body = post.body! as Map;
      expect(body['bytes'], greaterThan(onePixelPng.length));
      expect(body['fields'], {
        'rightsConfirmed': 'true',
        'confirmationVersion': '2026-10-29.draft1',
        'focalX': '1.000',
        'focalY': '-1.000',
      });
      expect(post.headers['authorization'], 'Bearer token');
      expect(h.snack(h.tr('partnerMedia.liveNowHero')), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.live')), findsOneWidget);
    });

    apiTest('Enter on the disabled button asks to tick the box (§42.5)', (
      tester,
      api,
    ) async {
      final h = await openSheet(tester, api);
      expect(find.text(h.tr('merch.confirmRequired')), findsNothing);
      Focus.of(
        tester.element(find.byKey(const Key('partner-media-use'))),
      ).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text(h.tr('merch.confirmRequired')), findsOneWidget);
      expect(api.sent('POST', '/partner/media/hero'), isFalse);
      // Ticking the box removes the ask and enables the button.
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-confirm-rights')),
      );
      expect(find.text(h.tr('merch.confirmRequired')), findsNothing);
      expect(
        isEnabled(tester, find.byKey(const Key('partner-media-use'))),
        isTrue,
      );
    });

    apiTest('wording changed: texts reloaded, boxes unticked (AC-P26)', (
      tester,
      api,
    ) async {
      api.fail('POST /partner/media/hero', 400, {
        'error': 'confirmation_version_mismatch',
        'current': 'v2',
      });
      final h = await openSheet(tester, api);
      api.on(
        'GET /partner/media',
        overview(
          conf: {
            ...confirmation,
            'version': 'v2',
            'rights': {'en': 'New wording.', 'sw': 'Maneno mapya.'},
          },
        ),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-confirm-rights')),
      );
      await tapVisible(tester, find.byKey(const Key('partner-media-use')));
      expect(
        find.byKey(const Key('partner-media-wording-changed')),
        findsOneWidget,
      );
      expect(find.text('New wording.'), findsOneWidget);
      expect(
        isEnabled(tester, find.byKey(const Key('partner-media-use'))),
        isFalse,
      );
      expect(h.lang, 'en');
    });

    apiTest('server refusal keeps the sheet and the ticks', (
      tester,
      api,
    ) async {
      api.fail('POST /partner/media/hero', 409, {
        'error': 'image_taken_down_before',
      });
      final h = await openSheet(tester, api);
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-confirm-rights')),
      );
      await tapVisible(tester, find.byKey(const Key('partner-media-use')));
      expect(
        find.text(h.tr('partnerMedia.error.image_taken_down_before')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('partner-media-choose-another')),
        findsOneWidget,
      );
    });

    apiTest('permission refused: closes into no access', (tester, api) async {
      api.fail('POST /partner/media/hero', 403, {'error': 'acl_forbidden'});
      final h = await openSheet(tester, api);
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-confirm-rights')),
      );
      await tapVisible(tester, find.byKey(const Key('partner-media-use')));
      expect(find.text(h.tr('partnerMedia.restrictedGym')), findsOneWidget);
    });

    apiTest('a too-small photo is refused before any request (AC-P23)', (
      tester,
      api,
    ) async {
      final h = await openSheet(tester, api, picked: _photo(width: 900));
      expect(
        find.byKey(const Key('partner-media-sheet-problem')),
        findsOneWidget,
      );
      expect(
        find.text(
          h
              .tr('partnerMedia.error.image_too_small')
              .replaceAll('{minWidth}', '1080'),
        ),
        findsOneWidget,
      );
      expect(api.sent('POST', '/partner/media/hero'), isFalse);
    });

    apiTest('logo: two boxes, plate choice sent (AC-P29)', (tester, api) async {
      api.on('POST /partner/media/logo', {'item': logoItem()});
      final h = await openSheet(tester, api, kind: 'logo', picked: _logo());
      expect(
        find.byKey(const Key('partner-media-confirm-own-logo')),
        findsOneWidget,
      );
      await tapVisible(tester, find.text(h.tr('partnerMedia.sheet.plateDark')));
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-confirm-rights')),
      );
      expect(
        isEnabled(tester, find.byKey(const Key('partner-media-use'))),
        isFalse,
      );
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-confirm-own-logo')),
      );
      await tapVisible(tester, find.byKey(const Key('partner-media-use')));
      final body = api.only('POST', '/partner/media/logo').body! as Map;
      expect(body['fields'], {
        'rightsConfirmed': 'true',
        'confirmationVersion': '2026-10-29.draft1',
        'ownLogoConfirmed': 'true',
        'plate': 'dark',
      });
    });

    apiTest('an SVG logo is refused locally', (tester, api) async {
      final h = await openSheet(
        tester,
        api,
        kind: 'logo',
        picked: _logo(type: 'image/svg+xml'),
      );
      expect(
        find.text(h.tr('partnerMedia.error.svg_not_allowed')),
        findsOneWidget,
      );
    });

    apiTest('choosing from the gallery or camera', (tester, api) async {
      final sources = <ImageSource>[];
      debugPartnerMediaPicker = (s) async {
        sources.add(s);
        return null;
      };
      api.on('GET /partner/media', overview());
      await _open(tester, api);
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-hero-upload')),
      );
      await tapVisible(
        tester,
        find.byKey(const Key('partner-media-source-camera')),
      );
      expect(sources, [ImageSource.camera]);
      // Cancelling the picker changes nothing.
      expect(
        find.byKey(const Key('partner-media-hero-upload')),
        findsOneWidget,
      );
    });
  });

  group('entry tiles (AC-P13)', () {
    apiTest('flag off: nothing', (tester, api) async {
      debugPartnerMediaUiOverride = false;
      await pumpPage(
        tester,
        api,
        const PartnerMediaEntryTile(side: 'trainer'),
        keepRequests: true,
      );
      expect(find.byKey(const Key('trainer-brand-media')), findsNothing);
      expect(api.requests, isEmpty);
    });

    apiTest('trainer: shown at once, opens the page', (tester, api) async {
      final h = await pumpPage(
        tester,
        api,
        const PartnerMediaEntryTile(side: 'trainer'),
        user: _trainer,
        extraRoutes: [
          GoRoute(
            path: '/trainer/brand-media',
            builder: (_, _) =>
                const Scaffold(body: Text('ROUTE-/trainer/brand-media')),
          ),
        ],
      );
      expect(find.text(h.tr('partnerMedia.entryHint')), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('trainer-brand-media')));
      expect(find.text('ROUTE-/trainer/brand-media'), findsOneWidget);
    });

    apiTest('staff: hidden until canEdit is true', (tester, api) async {
      api.on('GET /partner/media', overview(type: 'vendor', canEdit: false));
      await pumpPage(
        tester,
        api,
        const PartnerMediaEntryTile(side: 'vendor', askServer: true),
        user: const {'id': 's1', 'userType': 'vendor_staff'},
      );
      expect(find.byKey(const Key('vendor-brand-media')), findsNothing);
    });

    apiTest('admin staff: shown once the server says canEdit', (
      tester,
      api,
    ) async {
      api.on('GET /partner/media', overview(type: 'vendor'));
      final h = await pumpPage(
        tester,
        api,
        const PartnerMediaEntryTile(side: 'vendor', askServer: true),
        user: const {'id': 's1', 'userType': 'vendor_staff'},
      );
      expect(find.byKey(const Key('vendor-brand-media')), findsOneWidget);
      expect(find.text(h.tr('partnerMedia.entryHintVendor')), findsOneWidget);
    });

    apiTest('owner with two gyms: names the gym', (tester, api) async {
      await pumpPage(
        tester,
        api,
        const PartnerMediaEntryTile(side: 'gym', gymId: 'g1', gymName: 'Arena'),
        user: _owner,
      );
      expect(find.text('For Arena'), findsOneWidget);
    });
  });
}
