import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/auth_screen.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';

Widget _wrap(Widget child) {
  final api = ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(api);
  final locale = FFLocale();

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
        home: child,
      ),
    ),
  );
}

void main() {
  testWidgets('auth screen uses centered email and Google layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AuthScreen(enableFirebaseRecovery: false)),
    );

    expect(find.text('Log in to your account'), findsOneWidget);
    expect(
      find.text('Welcome back! Please enter your details.'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Continue with email'), findsOneWidget);
    expect(find.text('OR'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
    expect(find.text('Don\'t have an account?'), findsOneWidget);
    expect(find.text('Sign up'), findsOneWidget);
  });

  testWidgets('email sign-up validates password confirmation', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmailAuthScreen(
          initialEmail: 'member@example.com',
          initialMode: EmailAuthMode.signUp,
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(2), '123456');
    await tester.enterText(find.byType(TextFormField).at(3), '654321');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('email sign-up requires terms acceptance', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmailAuthScreen(
          initialEmail: 'member@example.com',
          initialMode: EmailAuthMode.signUp,
        ),
      ),
    );

    await tester.enterText(find.byType(TextFormField).at(2), '123456');
    await tester.enterText(find.byType(TextFormField).at(3), '123456');
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pump();

    expect(
      find.text('Accept the Terms and Conditions to create an account.'),
      findsOneWidget,
    );
  });
}
