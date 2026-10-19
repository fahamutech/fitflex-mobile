// Phase A polish round 2 (design-QA re-check on RC a46ebbc): H3 gym grid
// cards, the passes list and the language toggle at 360 wide.
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/gym_card.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_api.dart';

Gym _gym(String id, String name, {required bool verified}) => Gym.fromJson({
  'id': id,
  'name': name,
  'tier': 'standard',
  'location': 'Masaki, Dar es Salaam',
  'perVisitRate': 10000,
  'commissionRate': 12,
  'status': 'active',
  'verified': verified,
  'verificationStatus': verified ? 'verified' : 'pending',
});

final _gyms = [
  _gym('dev', 'Dev Owner Gym', verified: true),
  _gym('iron', 'Iron Paradise (Dev)', verified: false),
  _gym('long', 'Dev Owner Gym Mikocheni Branch', verified: false),
];

Widget _app({
  required String lang,
  required double textScale,
  required Widget home,
}) => FFLocaleScope(
  notifier: FFLocale()..set(Locale(lang)),
  child: MaterialApp(
    theme: buildTheme(),
    supportedLocales: const [Locale('en'), Locale('sw')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(body: home),
  ),
);

/// The member Gyms grid as the tab lays it out: 24 padding, row grid.
Widget _grid() => LayoutBuilder(
  builder: (context, constraints) {
    final cols = ffCardGridColumns(context, constraints.maxWidth);
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          sliver: SliverFFRowGrid(
            columns: cols,
            itemCount: _gyms.length,
            itemBuilder: (context, i) => GymGridCard(
              key: Key('gym-card-${_gyms[i].id}'),
              gym: _gyms[i],
              distanceKm: 3.2,
              imageAspectRatio: cols == 1 ? 16 / 9 : 4 / 3,
            ),
          ),
        ),
      ],
    );
  },
);

RenderParagraph _paragraph(WidgetTester tester, Finder within) =>
    tester.renderObject<RenderParagraph>(
      find.descendant(of: within, matching: find.byType(RichText)).first,
    );

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Name and "Not verified" are read in full: not cut, and inside the card.
void _expectReadable(
  WidgetTester tester,
  Gym gym,
  String lang, {
  bool wholeName = true,
}) {
  final card = tester.getRect(find.byKey(Key('gym-card-${gym.id}')));
  final name = find.byKey(Key('gym-grid-name-${gym.id}'));
  // A very long name may end in "…" after its two lines; real ones do not.
  if (wholeName) {
    expect(
      _paragraph(tester, name).didExceedMaxLines,
      isFalse,
      reason: '${gym.name} cut',
    );
  }
  if (!gymIsVerified(gym)) {
    final row = find.byKey(Key('gym-grid-unverified-${gym.id}'));
    final label = find.descendant(
      of: row,
      matching: find.text(FFLocale.textOf(lang, 'gym.unverified')!),
    );
    expect(label, findsOneWidget);
    expect(_paragraph(tester, label).didExceedMaxLines, isFalse);
    expect(tester.getRect(row).bottom, lessThanOrEqualTo(card.bottom));
  }
  // The badges, last in the card, are inside it (nothing clipped).
  final badges = find.descendant(
    of: find.byKey(Key('gym-card-${gym.id}')),
    matching: find.byType(Wrap),
  );
  expect(tester.getRect(badges).bottom, lessThanOrEqualTo(card.bottom));
}

void main() {
  // Real Inter widths, so "cut or not" matches a phone.
  setUpAll(loadAppFonts);

  group('H3 gym grid at 360', () {
    for (final lang in ['en', 'sw']) {
      for (final scale in [1.0, 1.3]) {
        testWidgets('[$lang x$scale] names and verification read in full', (
          tester,
        ) async {
          _setSize(tester, const Size(360, 2400));
          await tester.pumpWidget(
            _app(lang: lang, textScale: scale, home: _grid()),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
          for (final g in _gyms) {
            _expectReadable(tester, g, lang, wholeName: g.id != 'long');
          }
          final a = tester.getRect(find.byKey(const Key('gym-card-dev')));
          final b = tester.getRect(find.byKey(const Key('gym-card-iron')));
          if (scale > 1.2) {
            // Narrow for the text size: one card per row.
            expect(b.top, greaterThan(a.bottom));
          } else {
            // Two per row, both as tall as the taller one.
            expect(b.top, a.top);
            expect(b.height, a.height);
          }
        });
      }
    }

    testWidgets('columns: 1 at 360 x1.3, 2 at 360 and 390 x1.3, 3/4 wider', (
      tester,
    ) async {
      late BuildContext ctx;
      Future<void> at(double scale) async {
        await tester.pumpWidget(
          _app(
            lang: 'en',
            textScale: scale,
            home: Builder(
              builder: (c) {
                ctx = c;
                return const SizedBox();
              },
            ),
          ),
        );
      }

      await at(1.3);
      expect(ffCardGridColumns(ctx, 360), 1);
      expect(ffCardGridColumns(ctx, 390), 2);
      expect(ffCardGridColumns(ctx, 700), 3);
      expect(ffCardGridColumns(ctx, 1000), 4);
      await at(1.0);
      expect(ffCardGridColumns(ctx, 360), 2);
    });

    for (final lang in ['en', 'sw']) {
      testWidgets('[$lang] Featured strip at x1.3 is as tall as its cards', (
        tester,
      ) async {
        _setSize(tester, const Size(360, 800));
        await tester.pumpWidget(
          _app(
            lang: lang,
            textScale: 1.3,
            home: FFFeaturedStrip(
              title: 'Featured',
              count: 2,
              fitContent: true,
              itemBuilder: (context, i) => GymGridCard(
                key: Key('gym-card-${_gyms[i].id}'),
                gym: _gyms[i],
                distanceKm: 3.2,
              ),
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        _expectReadable(tester, _gyms[0], lang);
        _expectReadable(tester, _gyms[1], lang);
      });
    }
  });

  group('passes list at 360', () {
    for (final lang in ['en', 'sw']) {
      apiTest('[$lang] Premium gym access is never cut', (tester, api) async {
        final data = MemberData()
          ..me = MemberMeResponse.fromJson({
            'user': {
              'id': 'm1',
              'displayName': 'Amina',
              'onboardingCompleted': true,
            },
          })
          ..passes = [
            PassTier.fromJson({
              'id': 'basic',
              'price': 30000,
              'visitCap': 12,
              'gymAccess': 'standard',
            }),
            PassTier.fromJson({
              'id': 'premium',
              'price': 100000,
              'visitCap': 30,
              'gymAccess': 'premium',
            }),
          ]
          ..passesLoaded = true
          ..gyms = [_gyms[0], _gyms[1]];
        await pumpPage(
          tester,
          api,
          MemberDataScope(data: data, child: const MemberPassesPage()),
          user: const {'id': 'm1', 'userType': 'member'},
          lang: lang,
          size: const Size(360, 1600),
        );
        final access = find.byKey(const Key('pass-gym-access-premium'));
        expect(access, findsOneWidget);
        expect(
          tester.widget<Text>(access).data,
          FFLocale.textOf(lang, 'pass.gymAccess.premium'),
        );
        expect(_paragraph(tester, access).didExceedMaxLines, isFalse);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('language toggle', () {
    for (final lang in ['en', 'sw']) {
      testWidgets('[$lang] spoken name and tooltip are in the page language', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(
          _app(lang: lang, textScale: 1, home: const LanguageToggleButton()),
        );
        final expected = lang == 'sw'
            ? 'Badilisha lugha iwe Kiingereza'
            : 'Switch to Swahili';
        expect(find.bySemanticsLabel(expected), findsOneWidget);
        expect(find.byTooltip(expected), findsOneWidget);
        handle.dispose();
      });
    }

    test('Swahili has its own words for both directions', () {
      for (final k in ['lang.switchToEnglish', 'lang.switchToSwahili']) {
        expect(FFLocale.textOf('sw', k), isNot(FFLocale.textOf('en', k)));
      }
    });
  });
}
