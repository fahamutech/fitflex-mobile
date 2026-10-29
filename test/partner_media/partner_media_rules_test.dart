// Partner home photo and logo (spec §39–§45): the answer's parsing, the
// file address rule, the checks before any upload (AC-P23), the plate rule
// (AC-P7), every error text in both languages (AC-P28), the plate geometry
// (AC-P5) and where the takedown notice leads.
import 'dart:typed_data';

import 'package:fitflexmobile/screens/partner/partner_media_sheet.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_flag.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_image_check.dart';
import 'package:fitflexmobile/shared/partner_media/partner_media_models.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

PickedPartnerImage _picked({
  String? type = 'image/jpeg',
  int bytes = 1000,
  int? width = 1600,
  int? height = 1000,
}) => PickedPartnerImage(
  bytes: Uint8List(bytes),
  filename: 'x.jpg',
  type: type,
  width: width,
  height: height,
);

void main() {
  tearDown(() {
    debugPhotoHeroUiOverride = null;
    debugPartnerMediaUiOverride = null;
  });

  group('flag', () {
    test('off by default, and needs PHOTO_HERO_UI', () {
      expect(partnerMediaUi, isFalse);
      debugPartnerMediaUiOverride = true;
      debugPhotoHeroUiOverride = false;
      expect(partnerMediaUi, isFalse);
      debugPhotoHeroUiOverride = true;
      expect(partnerMediaUi, isTrue);
    });
  });

  group('GET /partner/media answer', () {
    test('live photo and logo, limits and texts', () {
      final o = PartnerMediaOverview.tryParse(
        overview(hero: heroItem(), logo: logoItem()),
      )!;
      expect(o.canEdit, isTrue);
      expect(o.subjectName, 'Asha');
      expect(o.hero!.focal, const Alignment(0.5, -0.25));
      expect(o.hero!.aspect, 1.5);
      expect(o.logo!.plate, 'dark');
      expect(
        o.logo!.files['logo256'],
        '/partner/media/pmd_logo1/file?variant=logo256',
      );
      expect(o.confirmation!.version, '2026-10-29.draft1');
      expect(o.confirmation!.rightsIn('sw'), startsWith('Nilipiga picha hii'));
      expect(o.limits.heroMinWidth, 1080);
      expect(o.limits.logoTypes, isNot(contains('image/svg+xml')));
    });

    test('a takedown with its reason and note; a live item is never a '
        'takedown', () {
      final o = PartnerMediaOverview.tryParse(
        overview(
          heroDown: heroItem(
            status: 'taken_down',
            takedown: {
              'reason': 'person_request',
              'note': 'Asked by the person',
              'at': 'x',
            },
          ),
          logoDown: logoItem(),
        ),
      )!;
      expect(o.hero, isNull);
      expect(o.heroTakedown!.takedownReason, 'person_request');
      expect(o.heroTakedown!.takedownNote, 'Asked by the person');
      expect(o.heroTakedown!.files, isEmpty);
      expect(o.logoTakedown, isNull);
    });

    test('no people field is read or needed anywhere', () {
      final raw = overview(hero: heroItem());
      expect(raw.toString(), isNot(contains('people')));
      expect(PartnerMediaOverview.tryParse(raw), isNotNull);
    });
  });

  group('file address (session header goes to the API host only)', () {
    const base = 'https://api.fitflex.test';
    test('accepted', () {
      expect(
        partnerMediaFileUri('/partner/media/pmd_1/file?variant=x2', base),
        Uri.parse('$base/partner/media/pmd_1/file?variant=x2'),
      );
      expect(
        partnerMediaFileUri('/partner/media/pmd_1/file?variant=logo128', base),
        isNotNull,
      );
    });
    test('refused', () {
      for (final p in [
        'https://evil.test/partner/media/pmd_1/file?variant=x2',
        '//evil.test/partner/media/pmd_1/file?variant=x2',
        '/partner/media/pmd_1/file?variant=master',
        '/partner/media/../admin/file?variant=x2',
        '/partner/media/pmd%2e1/file?variant=x2',
        '/partner/media/pmd_1/file?variant=x2&x=1',
        '/media/p/abc',
        null,
        42,
      ]) {
        expect(partnerMediaFileUri(p, base), isNull, reason: '$p');
      }
      expect(
        partnerMediaFileUri('/partner/media/pmd_1/file?variant=x2', 'ftp://a'),
        isNull,
      );
    });
  });

  group('checks before any request (AC-P23)', () {
    const l = PartnerMediaLimits();
    test('a 900 px photo, 200 px logo, SVG, GIF, 16 MB photo, 3 MB logo', () {
      expect(
        partnerMediaProblem('hero', _picked(width: 900, height: 600), l)?.code,
        'image_too_small',
      );
      expect(
        partnerMediaProblem(
          'logo',
          _picked(type: 'image/png', width: 200, height: 400),
          l,
        )?.code,
        'image_too_small_logo',
      );
      expect(
        partnerMediaProblem('logo', _picked(type: 'image/svg+xml'), l)?.code,
        'svg_not_allowed',
      );
      expect(
        partnerMediaProblem('hero', _picked(type: 'image/gif'), l)?.code,
        'unsupported_file_type',
      );
      expect(
        partnerMediaProblem('hero', _picked(bytes: 16 * 1024 * 1024), l),
        const PartnerMediaProblem('file_too_large', {'maxMb': '15'}),
      );
      expect(
        partnerMediaProblem(
          'logo',
          _picked(type: 'image/png', bytes: 3 * 1024 * 1024),
          l,
        ),
        const PartnerMediaProblem('file_too_large', {'maxMb': '2'}),
      );
      expect(partnerMediaProblem('hero', _picked(), l), isNull);
      // HEIC whose size the phone can't read: the server decides.
      expect(
        partnerMediaProblem(
          'hero',
          _picked(type: 'image/heic', width: null, height: null),
          l,
        ),
        isNull,
      );
    });

    test('the limits come from the server answer, not app constants', () {
      final stricter = PartnerMediaLimits.parse({
        'hero': {
          'minWidth': 2000,
          'maxBytes': 1000,
          'types': ['image/png'],
        },
      });
      expect(
        partnerMediaProblem('hero', _picked(bytes: 10), stricter)?.code,
        'unsupported_file_type',
      );
      expect(
        partnerMediaProblem(
          'hero',
          _picked(type: 'image/png', bytes: 10),
          stricter,
        ),
        const PartnerMediaProblem('image_too_small', {'minWidth': 2000}),
      );
    });

    test('types are read from the first bytes, never the name', () {
      expect(sniffImageType([0xFF, 0xD8, 0xFF, 0xE0]), 'image/jpeg');
      expect(sniffImageType(onePixelPng), 'image/png');
      expect(
        sniffImageType('RIFF\x00\x00\x00\x00WEBPVP8 '.codeUnits),
        'image/webp',
      );
      expect(sniffImageType('GIF89a'.codeUnits), 'image/gif');
      expect(
        sniffImageType('\x00\x00\x00\x18ftypheic'.codeUnits),
        'image/heic',
      );
      expect(
        sniffImageType('  <?xml version="1.0"?><svg xmlns="x"/>'.codeUnits),
        'image/svg+xml',
      );
      expect(sniffImageType('hello'.codeUnits), isNull);
    });
  });

  group('automatic plate (AC-P7, server rule)', () {
    Uint8List px(int r, int g, int b, int a) => Uint8List.fromList([
      for (var i = 0; i < 16; i++) ...[r, g, b, a],
    ]);
    test('white logo → dark plate; dark logo → light plate', () {
      expect(luminanceOfRgba(px(255, 255, 255, 255)), greaterThan(0.6));
      expect(luminanceOfRgba(px(20, 40, 120, 255)), lessThan(0.6));
      // Transparent pixels don't count.
      expect(luminanceOfRgba(px(255, 255, 255, 0)), 0);
    });
  });

  group('plate geometry (AC-P5)', () {
    test('square, 4:1 and 1:3 logos', () {
      final sq = FFLogoPlate.sizeFor(1);
      expect((sq.logoWidth, sq.logoHeight, sq.plateWidth), (28.0, 28.0, 40.0));
      final wide = FFLogoPlate.sizeFor(4);
      expect(wide.logoWidth, 108);
      expect(wide.logoHeight, 27);
      expect(wide.plateWidth, 120);
      final tall = FFLogoPlate.sizeFor(1 / 3);
      expect(tall.logoHeight, 28);
      expect(tall.logoWidth, closeTo(28 / 3, 1e-9));
      expect(tall.plateWidth, 40);
    });
  });

  group('every error code in English and Swahili (AC-P28)', () {
    const codes = [
      'not_your_gym',
      'acl_forbidden',
      'subject_not_found',
      'rate_limited',
      'image_too_small',
      'unsupported_file_type',
      'svg_not_allowed',
      'file_too_large',
      'variant_over_budget',
      'invalid_focal',
      'not_editable',
      'image_save_failed',
      'image_taken_down_before',
    ];
    for (final lang in ['en', 'sw']) {
      testWidgets(lang, (tester) async {
        late BuildContext ctx;
        await tester.pumpWidget(
          FFLocaleScope(
            notifier: FFLocale()..set(Locale(lang)),
            child: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        );
        final seen = <String>{};
        for (final code in codes) {
          for (final kind in ['hero', 'logo']) {
            final t = partnerMediaErrorText(
              ctx,
              kind,
              code,
              values: const {
                'minWidth': 1080,
                'minSide': 256,
                'maxBytes': 2097152,
              },
            );
            expect(t, isNot(contains('partnerMedia.')), reason: code);
            expect(t, isNot(contains('{')), reason: code);
            seen.add(t);
          }
        }
        expect(seen.length, greaterThan(codes.length));
        expect(
          partnerMediaErrorText(
            ctx,
            'logo',
            'image_too_small',
            values: const {'minSide': 256},
          ),
          FFLocale.textOf(
            lang,
            'partnerMedia.error.image_too_small_logo',
          )!.replaceAll('{minSide}', '256'),
        );
        // functions#277 at 5a6612b: the 429 scopes and the busy codes.
        String rl(Map<String, Object?> v) =>
            partnerMediaErrorText(ctx, 'hero', 'rate_limited', values: v);
        expect(
          rl(const {'limit': 'minute', 'scope': 'person'}),
          FFLocale.textOf(lang, 'partnerMedia.error.rate_limited'),
        );
        for (final scope in ['person', 'partner']) {
          expect(
            rl({'limit': 'day', 'scope': scope}),
            FFLocale.textOf(lang, 'partnerMedia.error.rate_limited_day'),
          );
        }
        expect(
          rl(const {'limit': 'day', 'scope': 'partner_attempts'}),
          FFLocale.textOf(lang, 'partnerMedia.error.rate_limited_attempts'),
        );
        for (final code in ['image_service_busy', 'rate_limit_unavailable']) {
          expect(
            partnerMediaErrorText(ctx, 'hero', code),
            FFLocale.textOf(lang, 'partnerMedia.error.$code'),
          );
        }
        expect(
          partnerMediaErrorText(ctx, 'hero', 'weird_code'),
          FFLocale.textOf(
            lang,
            'partnerMedia.error.unknown',
          )!.replaceAll('{code}', 'weird_code'),
        );
      });
    }
  });

  group('copy', () {
    test('every partnerMedia key has English and Swahili', () {
      final en = FFLocale.keysOf(
        'en',
      ).where((k) => k.startsWith('partnerMedia.'));
      final sw = FFLocale.keysOf(
        'sw',
      ).where((k) => k.startsWith('partnerMedia.'));
      expect(en.length, greaterThan(100));
      expect(sw.toSet(), en.toSet());
      expect(FFLocale.textOf('sw', 'inbox.open.brandMedia'), isNotNull);
    });

    test('no pending, approval, expiry or withdraw words (AC-P18)', () {
      for (final lang in ['en', 'sw']) {
        // `noGym` speaks of the gym's own approval (spec §41.3), not a photo's.
        for (final k in FFLocale.keysOf(lang).where(
          (k) => k.startsWith('partnerMedia.') && k != 'partnerMedia.noGym',
        )) {
          final t = FFLocale.textOf(lang, k)!.toLowerCase();
          for (final w in [
            'pending',
            'waiting for review',
            'approved',
            'expires',
            'withdraw',
            'inasubiri',
            'imeidhinishwa',
          ]) {
            expect(t, isNot(contains(w)), reason: '$lang $k');
          }
        }
      }
    });

    test('no people or faces confirmation exists (AC-P25)', () {
      final keys = FFLocale.keysOf(
        'en',
      ).where((k) => k.startsWith('partnerMedia.'));
      expect(
        keys.where(
          (k) =>
              k.toLowerCase().contains('people') && !k.endsWith('rules.people'),
        ),
        isEmpty,
      );
      expect(keys.where((k) => k.toLowerCase().contains('face')), isEmpty);
    });
  });

  group('takedown notice links (spec §41.1, §44.3)', () {
    test('each side opens its own page; gym ids are checked', () {
      debugPhotoHeroUiOverride = true;
      debugPartnerMediaUiOverride = true;
      expect(
        partnerRouteFor(
          side: 'gym',
          type: partnerMediaTakenDownType,
          gymId: 'gym_1',
        ),
        '/owner/brand-media?gymId=gym_1',
      );
      expect(
        partnerRouteFor(
          side: 'gym',
          type: partnerMediaTakenDownType,
          gymId: '../x',
        ),
        '/owner/brand-media',
      );
      expect(
        partnerRouteFor(side: 'trainer', type: partnerMediaTakenDownType),
        '/trainer/brand-media',
      );
      expect(
        partnerRouteFor(side: 'vendor', type: partnerMediaTakenDownType),
        '/vendor/brand-media',
      );
      expect(
        pushTargetFor(
          role: 'gym_staff',
          data: const {
            'type': partnerMediaTakenDownType,
            'gymId': 'gym_2',
            'route': 'https://evil.test/',
          },
        ),
        (location: '/owner/brand-media?gymId=gym_2', go: true),
      );
    });

    test('with the flag off the notice leads nowhere new', () {
      expect(
        partnerLinkFor(side: 'vendor', type: partnerMediaTakenDownType),
        '',
      );
      expect(
        partnerRouteFor(side: 'trainer', type: partnerMediaTakenDownType),
        isNull,
      );
    });
  });
}
