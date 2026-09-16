import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/member/widgets/trainer_actions_sheet.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/shop_browse_page.dart';

({Widget widget, AuthState auth}) _wrap(Widget child) {
  final api = ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(api);
  final locale = FFLocale();
  return (
    auth: auth,
    widget: AppScope(
      api: api,
      auth: auth,
      child: ThemeScope(
        notifier: ThemeNotifier(),
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
            home: Scaffold(body: child),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('vendor session is routed to the vendor marketplace', () async {
    final wrapped = _wrap(const SizedBox());
    await wrapped.auth.setRole('vendor');
    await wrapped.auth.signIn('vendor-token', {
      'id': 'usr_vendor_test',
      'userType': 'vendor',
      'status': 'active',
    });

    expect(routeForSignedInUser(wrapped.auth), AppRoutes.vendorHome);
  });

  test(
    'session persists the authoritative vendor role returned by login',
    () async {
      final wrapped = _wrap(const SizedBox());
      await wrapped.auth.setRole('member');
      await wrapped.auth.signIn('vendor-token', {
        'id': 'usr_vendor_test',
        'userType': 'vendor',
        'approvalStatus': 'approved',
      });

      expect(wrapped.auth.role, 'vendor');
      expect(routeForSignedInUser(wrapped.auth), AppRoutes.vendorHome);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('role'), 'vendor');
    },
  );

  test(
    'vendor staff session is routed to the permission-aware vendor portal',
    () async {
      final wrapped = _wrap(const SizedBox());
      await wrapped.auth.setRole('vendor');
      await wrapped.auth.signIn('vendor-staff-token', {
        'id': 'usr_vendor_staff_test',
        'userType': 'vendor_staff',
        'vendorId': 'usr_vendor_test',
        'vendorPermissions': ['products'],
        'status': 'active',
      });

      expect(routeForSignedInUser(wrapped.auth), AppRoutes.vendorHome);
    },
  );

  testWidgets('vendor product form exposes the complete inventory payload', (
    tester,
  ) async {
    final wrapped = _wrap(const VendorProductForm());
    await tester.pumpWidget(wrapped.widget);
    await tester.pumpAndSettle();

    expect(find.text('Add product'), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-name')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-description')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-category')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-price')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-stock')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-brand')), findsOneWidget);
    expect(
      find.byKey(const Key('vendor-product-discount-price')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('vendor-product-sku')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-weight')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-variants')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-visibility')), findsOneWidget);
    expect(find.byKey(const Key('vendor-product-save')), findsOneWidget);
  });

  testWidgets('vendor business profile requires every publication field', (
    tester,
  ) async {
    final wrapped = _wrap(const VendorProfileForm(profile: {}));
    await tester.pumpWidget(wrapped.widget);
    await tester.pumpAndSettle();

    for (final key in [
      'businessName',
      'description',
      'businessCategory',
      'contactNumber',
      'email',
      'address',
      'deliveryRegions',
      'businessHours',
      'settlementAccount',
    ]) {
      expect(find.byKey(Key('vendor-profile-$key')), findsOneWidget);
    }
    expect(find.byKey(const Key('vendor-profile-publish')), findsOneWidget);
  });

  testWidgets('vendor staff form exposes role and permission controls', (
    tester,
  ) async {
    final wrapped = _wrap(const VendorStaffForm());
    await tester.pumpWidget(wrapped.widget);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('vendor-staff-name')), findsOneWidget);
    expect(find.byKey(const Key('vendor-staff-email')), findsOneWidget);
    expect(find.byKey(const Key('vendor-staff-phone')), findsOneWidget);
    expect(find.byKey(const Key('vendor-staff-password')), findsOneWidget);
    expect(find.byKey(const Key('vendor-staff-role')), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(6));
  });

  testWidgets(
    'buyer storefront exposes profile, products, reviews and search',
    (tester) async {
      final wrapped = _wrap(
        VendorStoreSheet(
          store: {
            'businessName': 'FitFlex Performance Store',
            'description': 'Equipment and nutrition',
            'contactNumber': '+255700000001',
            'email': 'store@fitflex.test',
            'address': 'Masaki',
            'rating': '4.80',
            'reviewCount': 1,
            'products': [
              {
                'id': 'bands',
                'name': 'Resistance Bands',
                'category': 'Equipment',
                'priceTzs': 39000,
                'stock': 5,
              },
              {
                'id': 'whey',
                'name': 'Whey Protein',
                'category': 'Supplements',
                'priceTzs': 85000,
                'stock': 4,
              },
            ],
            'reviews': [
              {'rating': 5, 'comment': 'Excellent service'},
            ],
          },
        ),
      );
      await tester.pumpWidget(wrapped.widget);
      await tester.pumpAndSettle();

      expect(find.text('FitFlex Performance Store'), findsOneWidget);
      expect(find.text('Resistance Bands'), findsOneWidget);
      expect(find.text('Excellent service'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('shop-store-search')),
        'whey',
      );
      await tester.pump();
      expect(find.text('Whey Protein'), findsOneWidget);
      expect(find.text('Resistance Bands'), findsNothing);
    },
  );

  testWidgets(
    'seven-day booking sheet fits the Pixel viewport and can scroll',
    (tester) async {
      tester.view.physicalSize = const Size(411, 731);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const days = [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      ];
      final trainer = TrainerProfile(
        id: 'trn-layout-test',
        displayName: 'Seven Day Trainer',
        hourlyRateTzs: 35000,
        gymIds: const ['gym-layout-test'],
        status: 'active',
        availability: [
          for (final day in days)
            TrainerAvailability(
              day: day,
              gymId: 'gym-layout-test',
              slots: const ['08:00', '10:00', '12:00', '14:00', '16:00'],
            ),
        ],
      );
      final wrapped = _wrap(TrainerBookingSheet(trainer: trainer));
      await tester.pumpWidget(wrapped.widget);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(
        find.byKey(const Key('trainer-book-confirm')).hitTestable(),
        findsOneWidget,
      );
      expect(find.byKey(const Key('slot-monday-08:00')), findsOneWidget);
      expect(find.byKey(const Key('slot-sunday-16:00')), findsOneWidget);
    },
  );
}
