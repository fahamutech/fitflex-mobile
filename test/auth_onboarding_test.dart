import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/auth_screen.dart';
import 'package:fitflexmobile/screens/email_auth_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/components/custom_keypad.dart';
import 'package:fitflexmobile/shared/components/pin_input_row.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/firebase_auth_service.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/pin_credentials.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

Widget _wrap(Widget child) {
  final api = ApiClient(baseUrl: 'http://localhost:0');
  final auth = AuthState(api);
  final locale = FFLocale();

  return AppScope(
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
          home: child,
        ),
      ),
    ),
  );
}

void main() {
  test('role conflict automatically selects the single non-member profile', () {
    expect(
      preferredAutomaticRole({
        'error': 'profile_role_required',
        'availableRoles': ['member', 'vendor'],
      }),
      'vendor',
    );
    expect(
      preferredAutomaticRole({
        'error': 'profile_role_required',
        'availableRoles': ['gym_operator', 'member'],
      }),
      'gym_operator',
    );
    expect(
      preferredAutomaticRole({
        'error': 'profile_role_required',
        'availableRoles': ['trainer', 'vendor', 'member'],
      }),
      isNull,
    );
  });

  test(
    'authentication operations time out instead of loading forever',
    () async {
      final pending = Completer<String>();

      await expectLater(
        authenticationWithTimeout(
          pending.future,
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(
          isA<FirebaseAuthException>().having(
            (error) => error.code,
            'code',
            'network-request-failed',
          ),
        ),
      );
    },
  );

  test('Firebase password uses a string credential derived from the PIN', () {
    final password = firebasePasswordForPin('1234');

    expect(password, isNot('1234'));
    expect(password.length, greaterThanOrEqualTo(6));
    expect(password.endsWith('1234'), isTrue);
  });

  testWidgets('auth screen uses centered email and Google layout', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(const AuthScreen(enableFirebaseRecovery: false)),
    );

    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byKey(const Key('login-identifier')), findsOneWidget);
    expect(find.byKey(const Key('login-continue')), findsOneWidget);
    expect(find.text('OR'), findsOneWidget);
    expect(find.text('CONTINUE WITH GOOGLE'), findsOneWidget);
    expect(find.text('Don\'t have an account?'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
  });

  testWidgets('email sign-up enables submission at four PIN digits', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const EmailAuthScreen(
          initialEmail: 'member@example.com',
          initialMode: EmailAuthMode.signUp,
        ),
      ),
    );

    expect(
      tester.widget<CustomKeypad>(find.byType(CustomKeypad)).okEnabled,
      isFalse,
    );
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('1'));
      await tester.pump();
    }
    expect(
      tester.widget<CustomKeypad>(find.byType(CustomKeypad)).okEnabled,
      isTrue,
    );
  });

  testWidgets('a new PIN is exactly four digits', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const EmailAuthScreen(
          initialEmail: 'member@example.com',
          initialMode: EmailAuthMode.signUp,
        ),
      ),
    );

    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('2'));
      await tester.pump();
    }

    expect(tester.widget<PinInputRow>(find.byType(PinInputRow)).pin, '2222');
  });

  testWidgets('signing in still accepts an older PIN of up to eight digits', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const EmailAuthScreen(
          initialEmail: 'member@example.com',
          initialMode: EmailAuthMode.signIn,
        ),
      ),
    );

    for (var i = 0; i < 10; i++) {
      await tester.tap(find.text('2'));
      await tester.pump();
    }

    expect(
      tester.widget<PinInputRow>(find.byType(PinInputRow)).pin,
      '22222222',
    );
  });
}
