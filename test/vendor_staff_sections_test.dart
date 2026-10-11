// Vendor staff only get the sections their permissions allow. A staff user
// with a single section (or none) used to crash the page: NavigationBar needs
// at least two destinations, and the page also started on the Products tab
// whether or not the user could see it.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

class _Api extends ApiClient {
  _Api() : super(baseUrl: 'http://localhost:0');

  final calls = <String>[];

  @override
  Future<List<dynamic>> vendorProducts() async {
    calls.add('products');
    return const [];
  }

  @override
  Future<List<dynamic>> vendorOrders() async {
    calls.add('orders');
    return const [];
  }

  @override
  Future<Map<String, dynamic>> vendorProfile() async => {'status': 'published'};
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
}

Future<(_Api, Widget)> _page(
  String userType, {
  List<String> permissions = const [],
}) async {
  final api = _Api();
  final auth = AuthState(api);
  await auth.signIn('jwt', {
    'id': 'usr_1',
    'userType': userType,
    'approvalStatus': 'approved',
    'onboardingCompleted': true,
    'displayName': 'Asha',
    if (userType == 'vendor_staff') 'vendorPermissions': permissions,
  });
  final widget = AppScope(
    api: api,
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
          home: const VendorHomePage(),
        ),
      ),
    ),
  );
  return (api, widget);
}

Future<void> _open(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(800, 1600);
  t.view.devicePixelRatio = 2.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(w);
  await t.pumpAndSettle();
}

int _destinations(WidgetTester t) =>
    t.widgetList(find.byType(NavigationDestination)).length;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('owner still gets all five sections', (t) async {
    final (_, w) = await _page('vendor');
    await _open(t, w);
    expect(t.takeException(), isNull);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(_destinations(t), 5);
    expect(find.byKey(const Key('vendor-add-product')), findsOneWidget);
  });

  testWidgets('staff with two sections get a two-item bar on the first one', (
    t,
  ) async {
    final (_, w) = await _page(
      'vendor_staff',
      permissions: ['products', 'orders'],
    );
    await _open(t, w);
    expect(t.takeException(), isNull);
    expect(_destinations(t), 2);
    expect(find.byKey(const Key('vendor-nav-products')), findsOneWidget);
    expect(find.byKey(const Key('vendor-nav-orders')), findsOneWidget);
    expect(find.byKey(const Key('vendor-add-product')), findsOneWidget);
  });

  testWidgets('staff with only Orders do not crash and see Orders, no bar', (
    t,
  ) async {
    final (api, w) = await _page('vendor_staff', permissions: ['orders']);
    await _open(t, w);
    expect(t.takeException(), isNull);
    expect(find.byType(NavigationBar), findsNothing);
    // They land on Orders, not on a Products tab they cannot use.
    expect(find.byKey(const Key('vendor-add-product')), findsNothing);
    expect(api.calls, contains('orders'));
    expect(api.calls, isNot(contains('products')));
  });

  testWidgets('staff with only Products see Products and the add button', (
    t,
  ) async {
    final (_, w) = await _page('vendor_staff', permissions: ['products']);
    await _open(t, w);
    expect(t.takeException(), isNull);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byKey(const Key('vendor-add-product')), findsOneWidget);
  });

  testWidgets('staff with no permitted section see the no-permissions page', (
    t,
  ) async {
    final (api, w) = await _page('vendor_staff', permissions: []);
    await _open(t, w);
    expect(t.takeException(), isNull);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('No marketplace permissions assigned'), findsWidgets);
    expect(find.byKey(const Key('vendor-add-product')), findsNothing);
    expect(api.calls, isEmpty);
  });

  testWidgets('staff without Products start on their first allowed section', (
    t,
  ) async {
    final (_, w) = await _page(
      'vendor_staff',
      permissions: ['orders', 'payments'],
    );
    await _open(t, w);
    expect(t.takeException(), isNull);
    expect(_destinations(t), 2);
    // No Products tab means no add-product button on the landing tab.
    expect(find.byKey(const Key('vendor-add-product')), findsNothing);
    expect(find.byKey(const Key('vendor-nav-orders')), findsOneWidget);
    expect(find.byKey(const Key('vendor-nav-products')), findsNothing);
  });
}
