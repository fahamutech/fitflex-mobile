// UAT Phase 2 — mobile (Flutter) UI-flow journeys.
// Verifies the member/owner feedback that lives in the app UI:
//   B5 — Marketplace / Shop appears under "My QR" with a "Coming soon" badge.
//   B2 — A gym with several photos is scrollable (PageView) with a position indicator.
//   B3 — Amenities are grouped by category (Wellness, Facilities, ...).
//   B6 — Subscription review shows the number of gyms available for a plan.
//   B7 — Members can upload a photo from Gallery OR Camera.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/widgets/ff_photo_picker_field.dart';

// A valid 1x1 transparent PNG so FFRemoteImage uses MemoryImage (no network in tests).
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

Widget _wrap(Widget child, {MemberData? data}) {
  final api = ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(api);
  final locale = FFLocale();

  Widget tree = child;
  if (data != null) {
    tree = MemberDataScope(data: data, child: child);
  }

  return AppScope(
    api: api,
    auth: auth,
    child: FFLocaleScope(
      notifier: locale,
      child: MaterialApp(
        theme: buildTheme(),
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: tree,
      ),
    ),
  );
}

Gym _gym({
  String id = 'gym1',
  List<String> images = const [],
  List<String> amenities = const [],
}) => Gym(
  id: id,
  name: 'Iron Paradise',
  tier: 'standard',
  location: 'Masaki, Dar es Salaam',
  perVisitRate: 5000,
  commissionRate: 12,
  status: 'active',
  accessMode: 'paid_visit',
  venueType: 'physical',
  images: images,
  amenities: amenities,
);

void main() {
  // ───────────────────────── B5: Marketplace "coming soon" under My QR ─────────────────────────
  testWidgets('B5: My QR tab shows Marketplace / Shop with a Coming soon badge', (
    tester,
  ) async {
    final data = MemberData();
    await tester.pumpWidget(_wrap(const MemberQrTab(), data: data));
    await tester.pump();

    // The card sits below the QR section in a lazy ListView — scroll it into view.
    final marketplace = find.text('Marketplace / Shop');
    await tester.scrollUntilVisible(
      marketplace,
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(marketplace, findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
  });

  // ───────────────────────── B2: scrollable gym photos ─────────────────────────
  testWidgets(
    'B2: a gym with multiple photos renders a scrollable PageView with an indicator',
    (tester) async {
      final data = MemberData()
        ..gyms = [
          _gym(images: [_png, _png, _png]),
        ];
      await tester.pumpWidget(
        _wrap(const MemberGymDetailPage(gymId: 'gym1'), data: data),
      );
      await tester.pump();

      expect(
        find.byType(PageView),
        findsOneWidget,
        reason: 'multiple images must be swipeable',
      );
      expect(
        find.text('1/3'),
        findsOneWidget,
        reason: 'photo position indicator expected',
      );
    },
  );

  // ───────────────────────── B3: amenities grouped by category ─────────────────────────
  testWidgets('B3: gym amenities are grouped under category headings', (
    tester,
  ) async {
    final data = MemberData()
      ..gyms = [
        _gym(images: [_png], amenities: ['dry sauna', 'lockers', 'showers']),
      ];
    await tester.pumpWidget(
      _wrap(const MemberGymDetailPage(gymId: 'gym1'), data: data),
    );
    await tester.pump();

    // 'dry sauna' → Wellness & Recovery; 'lockers'/'showers' → Member Facilities & Comfort.
    expect(find.text('Wellness & Recovery'), findsOneWidget);
    expect(find.text('Member Facilities & Comfort'), findsOneWidget);
    expect(find.text('dry sauna'), findsOneWidget);
  });

  // ───────────────────────── B6: subscription review shows gym count ─────────────────────────
  testWidgets('B6: choosing a plan shows how many gyms it unlocks', (
    tester,
  ) async {
    final data = MemberData()
      ..passesLoaded = true
      ..passes = [
        PassTier(
          id: 'basic',
          price: 30000,
          visitCap: 12,
          gymAccess: 'standard',
        ),
      ]
      ..gyms = [_gym(id: 'g1'), _gym(id: 'g2')];

    await tester.pumpWidget(_wrap(const MemberPassesPage(), data: data));
    await tester.pump();

    // Both seeded gyms are 'standard' tier → the standard plan unlocks 2 gyms.
    expect(find.text('Standard gyms'), findsOneWidget);
    expect(find.textContaining('(2 gym'), findsOneWidget);
  });

  // ───────────────────────── B7: member photo from gallery or camera ─────────────────────────
  testWidgets('B7: photo picker offers both Camera and Gallery sources', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        Scaffold(
          body: Center(child: FFPhotoPickerField(onChanged: (_) {})),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(FFPhotoPickerField));
    await tester.pumpAndSettle();

    expect(find.text('Take a photo'), findsOneWidget);
    expect(find.text('Choose from gallery'), findsOneWidget);
  });
}
