// AC-B10 (docs/design/photo-hero-screens.md §7.1): under PHOTO_HERO_UI the
// member Home app bar is transparent over the hero and paints a solid
// `surface` once the hero has scrolled under it, with the theme's icon
// colours and status bar style.

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/photo_hero_flag.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A member with an active pass, so Home shows the hero and the pass card.
class _ActivePassApi extends ApiClient {
  _ActivePassApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<Map<String, dynamic>> me() async => {
    'user': {'id': 'm1', 'displayName': 'Amina', 'onboardingCompleted': true},
    'visitsUsed': 7,
    'visitCap': 18,
    'subscription': {
      'id': 's1',
      'type': 'platform_pass',
      'tier': 'pro',
      'status': 'active',
      'expiresAt': DateTime.now()
          .add(const Duration(days: 30, hours: 12))
          .toUtc()
          .toIso8601String(),
    },
  };
}

const _barKey = Key('member-home-hero-app-bar');

Future<void> _pumpShellHome(
  WidgetTester tester, {
  required bool dark,
  String location = '/member',
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = const Size(390 * 2, 640 * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final api = _ActivePassApi();
  final auth = AuthState(api);
  await auth.setRole('member');
  final router = GoRouter(
    initialLocation: location,
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            MemberShell(state: state, child: child),
        routes: [
          GoRoute(
            path: '/member',
            builder: (_, _) => MemberHomeTab(now: DateTime(2026, 10, 19, 19)),
          ),
          GoRoute(
            path: '/member/activity',
            builder: (_, _) => const MemberActivityTab(),
          ),
          GoRoute(
            path: '/member/profile',
            builder: (_, _) => const MemberProfileTab(),
          ),
        ],
      ),
    ],
  );
  await tester.pumpWidget(
    AppScope(
      api: api,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
        child: FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp.router(
            theme: dark ? buildDarkTheme() : buildTheme(),
            routerConfig: router,
            supportedLocales: const [Locale('en'), Locale('sw')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Material the AppBar paints its background with.
Material _barMaterial(WidgetTester tester) => tester.widget<Material>(
  find
      .descendant(of: find.byKey(_barKey), matching: find.byType(Material))
      .first,
);

SystemUiOverlayStyle _barOverlay(WidgetTester tester) => tester
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find
          .descendant(
            of: find.byKey(_barKey),
            matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
          )
          .first,
    )
    .value;

Color? _titleColor(WidgetTester tester) {
  final title = find.descendant(
    of: find.byKey(_barKey),
    matching: find.text('FitFlex'),
  );
  return tester
      .widget<RichText>(
        find.descendant(of: title, matching: find.byType(RichText)).first,
      )
      .text
      .style
      ?.color;
}

void main() {
  setUp(() => debugPhotoHeroUiOverride = true);
  tearDown(() => debugPhotoHeroUiOverride = null);

  for (final dark in [true, false]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('AC-B10 ($mode): the bar paints solid surface once scrolled', (
      tester,
    ) async {
      await _pumpShellHome(tester, dark: dark);
      final theme = Theme.of(tester.element(find.byKey(_barKey)));
      final surface = theme.colorScheme.surface;

      // Over the hero: transparent, light icons and status bar.
      expect(find.byKey(_barKey), findsOneWidget);
      expect(_barMaterial(tester).color?.a, 0);
      expect(_barOverlay(tester).statusBarIconBrightness, Brightness.light);
      expect(_titleColor(tester), FFTokens.heroText);

      // Scroll the hero under the bar.
      await tester.drag(
        find.byKey(const Key('member-home')),
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();

      // Solid: the bar's own Material paints an opaque surface over its
      // full, non-zero size.
      final material = _barMaterial(tester);
      expect(material.color, surface);
      expect(material.color!.a, 1.0);
      expect(material.type, isNot(MaterialType.transparency));
      final box = tester.renderObject<RenderBox>(
        find
            .descendant(
              of: find.byKey(_barKey),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(box.size.width, 390);
      expect(box.size.height, greaterThanOrEqualTo(kToolbarHeight));

      // Theme icon colours and status bar style.
      expect(_titleColor(tester), theme.appBarTheme.foregroundColor);
      expect(
        _barOverlay(tester).statusBarIconBrightness,
        dark ? Brightness.light : Brightness.dark,
      );

      // Back to the top: transparent again.
      await tester.drag(
        find.byKey(const Key('member-home')),
        const Offset(0, 2000),
      );
      await tester.pumpAndSettle();
      expect(_barMaterial(tester).color?.a, 0);
    });
  }

  testWidgets('AC-B10: reduced motion turns the bar solid instantly', (
    tester,
  ) async {
    await _pumpShellHome(tester, dark: true);
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await tester.pump();
    final surface = Theme.of(
      tester.element(find.byKey(_barKey)),
    ).colorScheme.surface;

    await tester.drag(
      find.byKey(const Key('member-home')),
      const Offset(0, -900),
    );
    await tester.pump(); // the notification sets state
    await tester.pump(); // one frame, no animation time
    expect(_barMaterial(tester).color, surface);
  });

  // Spec C-7: Activity and Profile share Home's floating bar.
  for (final (location, scroll) in [
    ('/member/activity', 'activity-scroll'),
    ('/member/profile', 'profile-scroll'),
  ]) {
    testWidgets('C-7 $location: transparent over the hero, solid scrolled', (
      tester,
    ) async {
      await _pumpShellHome(tester, dark: false, location: location);
      expect(find.byKey(_barKey), findsOneWidget);
      expect(_barMaterial(tester).color?.a, 0);
      expect(_titleColor(tester), FFTokens.heroText);
      await tester.drag(find.byKey(Key(scroll)), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(_barMaterial(tester).color?.a, 1.0);
    });
  }

  testWidgets('flag off: Profile keeps the plain bar', (tester) async {
    debugPhotoHeroUiOverride = false;
    await _pumpShellHome(tester, dark: false, location: '/member/profile');
    expect(find.byKey(_barKey), findsNothing);
  });
}
