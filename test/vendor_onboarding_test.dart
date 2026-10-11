// Vendor onboarding changes (11 Oct 2026): a vendor waiting for approval can
// already add products, categories come from a fixed list, and the shop
// shows the localized name of a known category.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/product_categories.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');

  final saved = <Map<String, dynamic>>[];
  Map<String, dynamic>? categories;
  Object? saveFailure;

  @override
  Future<List<dynamic>> vendorProducts() async => const [];
  @override
  Future<List<dynamic>> vendorOrders() async => const [];
  @override
  Future<Map<String, dynamic>> vendorProfile() async => {'status': 'draft'};
  @override
  Future<Map<String, dynamic>> vendorPayments() async => const {};
  @override
  Future<List<dynamic>> vendorEnquiries({String? search}) async => const [];
  @override
  Future<List<dynamic>> vendorStaff() async => const [];
  @override
  Future<Map<String, dynamic>> me() async => throw ApiException(500, null);
  @override
  Future<Map<String, dynamic>> myTerms({String? lang, String? role}) async =>
      throw ApiException(500, null);

  @override
  Future<Map<String, dynamic>> shopCategories() async {
    final c = categories;
    if (c == null) throw ApiException(500, null);
    return c;
  }

  @override
  Future<Map<String, dynamic>> vendorSaveProduct(
    Map<String, dynamic> data, {
    String? productId,
  }) async {
    if (saveFailure != null) throw saveFailure!;
    saved.add(data);
    return {'id': 'prd_1', ...data};
  }
}

Future<AuthState> _signedIn(
  _Api api,
  String userType, {
  String approval = 'approved',
  bool onboarded = true,
}) async {
  final auth = AuthState(api);
  await auth.signIn('jwt', {
    'id': 'usr_1',
    'userType': userType,
    'approvalStatus': approval,
    'onboardingCompleted': onboarded,
    'displayName': 'Asha',
  });
  return auth;
}

Widget _wrap(AuthState auth, Widget home) => AppScope(
  api: auth.api,
  auth: auth,
  child: ThemeScope(
    notifier: ThemeNotifier(),
    child: FFLocaleScope(
      notifier: FFLocale(),
      child: MaterialApp(
        theme: buildTheme(),
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: home,
      ),
    ),
  ),
);

Widget _routed(AuthState auth, FFLocale locale) {
  final router = GoRouter(
    initialLocation: AppRoutes.vendorHome,
    routes: [
      GoRoute(
        path: AppRoutes.vendorHome,
        builder: (_, _) => const VendorHomePage(),
      ),
      GoRoute(
        path: AppRoutes.verification,
        builder: (_, _) => const Scaffold(body: Text('verification centre')),
      ),
    ],
  );
  return AppScope(
    api: auth.api,
    auth: auth,
    child: ThemeScope(
      notifier: ThemeNotifier(),
      child: FFLocaleScope(
        notifier: locale,
        child: MaterialApp.router(
          theme: buildTheme(),
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
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ProductCategories.reset();
  });

  group('where a signed-in user lands while pending', () {
    test('a pending vendor goes to the vendor home', () async {
      final auth = await _signedIn(
        _Api(),
        'vendor',
        approval: 'pending_approval',
      );
      expect(routeForSignedInUser(auth), AppRoutes.vendorHome);
    });

    test(
      'a pending member or trainer still goes to the pending page',
      () async {
        final member = await _signedIn(
          _Api(),
          'member',
          approval: 'pending_approval',
        );
        expect(routeForSignedInUser(member), AppRoutes.pending);
        final trainer = await _signedIn(
          _Api(),
          'trainer',
          approval: 'pending_approval',
        );
        expect(routeForSignedInUser(trainer), AppRoutes.pending);
        final unregistered = await _signedIn(
          _Api(),
          'trainer',
          approval: 'pending_approval',
          onboarded: false,
        );
        expect(
          routeForSignedInUser(unregistered),
          AppRoutes.trainerRegistration,
        );
        // An owner with no gym yet is still sent to register one.
        final owner = await _signedIn(
          _Api(),
          'gym_operator',
          approval: 'pending_approval',
        );
        expect(routeForSignedInUser(owner), AppRoutes.ownerRegistration);
      },
    );

    testWidgets(
      'the router keeps a pending vendor in the shell and others on the pending page',
      (tester) async {
        // The redirect for a pending vendor is a no-op on the vendor routes
        // and a move to the vendor home elsewhere; other roles are unchanged.
        Future<String> landing(String userType, String to) async {
          final auth = await _signedIn(
            _Api(),
            userType,
            approval: 'pending_approval',
          );
          final router = buildRouter(auth);
          addTearDown(router.dispose);
          await tester.pumpWidget(
            AppScope(
              api: auth.api,
              auth: auth,
              child: ThemeScope(
                notifier: ThemeNotifier(),
                child: FFLocaleScope(
                  notifier: FFLocale(),
                  child: MaterialApp.router(routerConfig: router),
                ),
              ),
            ),
          );
          router.go(to);
          await tester.pump();
          await tester.pump();
          final location = router.state.matchedLocation;
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump(const Duration(seconds: 6));
          return location;
        }

        expect(
          await landing('vendor', AppRoutes.memberHome),
          AppRoutes.vendorHome,
        );
        expect(
          await landing('vendor', AppRoutes.verification),
          AppRoutes.verification,
        );
        expect(
          await landing('member', AppRoutes.memberHome),
          AppRoutes.pending,
        );
        expect(
          await landing('trainer', AppRoutes.vendorHome),
          AppRoutes.pending,
        );
      },
    );
  });

  group('vendor home while pending', () {
    testWidgets('shows the banner, lets the vendor open the product form', (
      tester,
    ) async {
      final api = _Api();
      final auth = await _signedIn(api, 'vendor', approval: 'pending_approval');
      await tester.pumpWidget(_routed(auth, FFLocale()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('vendor-pending-banner')), findsOneWidget);
      expect(
        find.textContaining('You can add your products now'),
        findsOneWidget,
      );
      expect(
        find.textContaining('once your verification is approved'),
        findsOne,
      );

      // Products are the landing tab and the product form opens.
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vendor-product-name')), findsOneWidget);
      expect(find.byKey(const Key('vendor-product-category')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pumpAndSettle();

      // The button leads to the verification centre.
      await tester.tap(find.byKey(const Key('vendor-pending-verification')));
      await tester.pumpAndSettle();
      expect(find.text('verification centre'), findsOneWidget);
    });

    testWidgets('a saved product reaches the server with its category key', (
      tester,
    ) async {
      final api = _Api();
      final auth = await _signedIn(api, 'vendor', approval: 'pending_approval');
      await tester.pumpWidget(_routed(auth, FFLocale()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('vendor-product-name')),
        'Whey protein',
      );
      await tester.enterText(
        find.byKey(const Key('vendor-product-price')),
        '85000',
      );
      await tester.tap(find.byKey(const Key('vendor-product-category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Supplements & nutrition').last);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('vendor-product-save')));
      await tester.tap(find.byKey(const Key('vendor-product-save')));
      await tester.pumpAndSettle();
      expect(api.saved.single['category'], 'supplements_nutrition');
    });

    testWidgets('a refused category is explained in plain words', (
      tester,
    ) async {
      final api = _Api()
        ..saveFailure = ApiException(400, {
          'error': 'invalid_category',
          'allowed': ['equipment'],
        });
      final auth = await _signedIn(api, 'vendor', approval: 'pending_approval');
      await tester.pumpWidget(_routed(auth, FFLocale()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('vendor-add-product')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('vendor-product-name')), 'X');
      await tester.enterText(
        find.byKey(const Key('vendor-product-price')),
        '10',
      );
      await tester.ensureVisible(find.byKey(const Key('vendor-product-save')));
      await tester.tap(find.byKey(const Key('vendor-product-save')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Choose a category from the list.'),
        findsOneWidget,
      );
    });

    testWidgets('an approved vendor has no banner', (tester) async {
      final auth = await _signedIn(_Api(), 'vendor');
      await tester.pumpWidget(_routed(auth, FFLocale()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('vendor-pending-banner')), findsNothing);
      expect(find.byKey(const Key('vendor-add-product')), findsNothing);
    });

    testWidgets('the banner is in Swahili when the app is', (tester) async {
      final auth = await _signedIn(
        _Api(),
        'vendor',
        approval: 'pending_approval',
      );
      await tester.pumpWidget(
        _routed(auth, FFLocale()..set(const Locale('sw'))),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Unaweza kuongeza bidhaa zako sasa'),
        findsOneWidget,
      );
    });
  });

  group('product category on the product form', () {
    Future<Map<String, dynamic>?> openForm(
      WidgetTester tester,
      Map<String, dynamic>? product,
      Future<void> Function() act,
    ) async {
      final auth = await _signedIn(_Api(), 'vendor');
      Map<String, dynamic>? result;
      await tester.pumpWidget(
        _wrap(
          auth,
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showModalBottomSheet<Map<String, dynamic>>(
                    context: ctx,
                    isScrollControlled: true,
                    builder: (_) => VendorProductForm(product: product),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      return result;
    }

    Future<void> save(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('vendor-product-save')));
      await tester.tap(find.byKey(const Key('vendor-product-save')));
      await tester.pumpAndSettle();
    }

    testWidgets('is a list of the eight categories, not free text', (
      tester,
    ) async {
      await openForm(tester, null, () async {
        expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
        await tester.tap(find.byKey(const Key('vendor-product-category')));
        await tester.pumpAndSettle();
        for (final name in [
          'Supplements & nutrition',
          'Sportswear & footwear',
          'Gym & fitness equipment',
          'Accessories & gear',
          'Food & drinks',
          'Health & recovery',
          'Events & tickets',
          'Other',
        ]) {
          expect(find.text(name), findsWidgets, reason: name);
        }
      });
    });

    testWidgets('an older free-text category is shown and not sent', (
      tester,
    ) async {
      final result = await openForm(
        tester,
        {'id': 'p1', 'name': 'Bands', 'priceTzs': 5000, 'category': 'Gear'},
        () async {
          expect(find.text('Gear (old)'), findsOneWidget);
          await save(tester);
        },
      );
      expect(result, isNotNull);
      expect(result!.containsKey('category'), isFalse);
    });

    testWidgets('picking a new one replaces an older free-text category', (
      tester,
    ) async {
      final result = await openForm(
        tester,
        {'id': 'p1', 'name': 'Bands', 'priceTzs': 5000, 'category': 'Gear'},
        () async {
          await tester.tap(find.byKey(const Key('vendor-product-category')));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Accessories & gear').last);
          await tester.pumpAndSettle();
          await save(tester);
        },
      );
      expect(result!['category'], 'accessories_gear');
    });

    testWidgets('a product already on a list key keeps it', (tester) async {
      final result = await openForm(
        tester,
        {
          'id': 'p1',
          'name': 'Bands',
          'priceTzs': 5000,
          'category': 'equipment',
        },
        () async {
          expect(find.text('Gym & fitness equipment'), findsOneWidget);
          await save(tester);
        },
      );
      expect(result!['category'], 'equipment');
    });
  });

  group('category list', () {
    test('the compiled-in list matches the server keys and has en + sw', () {
      expect(kFallbackProductCategories.map((c) => c.key), [
        'supplements_nutrition',
        'sportswear_footwear',
        'equipment',
        'accessories_gear',
        'food_drinks',
        'health_recovery',
        'events',
        'other',
      ]);
      for (final c in kFallbackProductCategories) {
        expect(c.en, isNotEmpty);
        expect(c.sw, isNotEmpty);
      }
    });

    test('known keys are localized and anything else stays as typed', () {
      expect(
        ProductCategories.labelFor('equipment', 'sw'),
        'Vifaa vya gym na mazoezi',
      );
      expect(
        ProductCategories.labelFor('equipment', 'en'),
        'Gym & fitness equipment',
      );
      expect(ProductCategories.labelFor('Gear', 'sw'), 'Gear');
      expect(ProductCategories.labelFor(null, 'en'), '');
    });

    test('older values map to keys by key or English name only', () {
      expect(ProductCategories.keyFor('Food & Drinks'), 'food_drinks');
      expect(ProductCategories.keyFor('events'), 'events');
      expect(ProductCategories.keyFor('Gear'), isNull);
      expect(
        ProductCategories.keysFor(['equipment', 'Equipment', 'x', 'other']),
        ['equipment', 'other'],
      );
    });

    test(
      'the server list is used when it answers, the fallback when not',
      () async {
        final api = _Api();
        expect(
          (await ProductCategories.load(api)).length,
          kFallbackProductCategories.length,
        );
        api.categories = {
          'categories': [
            {'key': 'equipment', 'en': 'Equipment!', 'sw': 'Vifaa!'},
            {'key': 'other', 'en': 'Other', 'sw': 'Nyingine'},
          ],
        };
        final list = await ProductCategories.load(api);
        expect(list.map((c) => c.key), ['equipment', 'other']);
        expect(ProductCategories.labelFor('equipment', 'sw'), 'Vifaa!');
      },
    );
  });
}
