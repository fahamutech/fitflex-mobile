// Smoke test: language screen renders.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/language_screen.dart';

void main() {
  testWidgets('Language screen offers EN and SW', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final api = ApiClient(baseUrl: 'http://localhost:0');
    final auth = AuthState(api);
    await auth.hydrate();
    final locale = FFLocale();

    await tester.pumpWidget(
      AppScope(
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
            home: const LanguageScreen(),
          ),
        ),
      ),
    );

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Kiswahili'), findsOneWidget);
    expect(find.text('FitFlex Af'), findsOneWidget);
  });
}
