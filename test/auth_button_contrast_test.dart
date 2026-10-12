// The sign-in "Continue" label used the theme's label style, which carries the
// body-text colour, on the primary fill. With the AA-safe primary that dark
// label fell to about 3:1. The label must use the on-primary colour.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/auth_screen.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';

Widget _wrap(Widget child, ThemeData theme) {
  final api = ApiClient(baseUrl: 'http://localhost:0');
  return AppScope(
    api: api,
    auth: AuthState(api),
    child: ThemeScope(
      notifier: ThemeNotifier(),
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          theme: theme,
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

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'sign-in Continue label is readable on the primary fill (${dark ? 'dark' : 'light'})',
      (tester) async {
        final theme = dark ? buildDarkTheme() : buildTheme();
        await tester.pumpWidget(
          _wrap(const AuthScreen(enableFirebaseRecovery: false), theme),
        );
        await tester.pumpAndSettle();
        final label = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const Key('login-continue')),
            matching: find.byType(Text),
          ),
        );
        final color = label.style?.color;
        expect(color, theme.colorScheme.onPrimary);
        expect(
          _contrast(color!, theme.colorScheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }
}
