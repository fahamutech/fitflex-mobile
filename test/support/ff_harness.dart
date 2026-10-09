import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Pumps [child] inside a themed MaterialApp with the app's locale scope.
Future<void> pumpFF(
  WidgetTester tester,
  Widget child, {
  bool dark = false,
  String lang = 'en',
  double textScale = 1.0,
  double? width,
  bool disableAnimations = false,
}) async {
  final locale = FFLocale()..set(Locale(lang));
  await tester.pumpWidget(
    FFLocaleScope(
      notifier: locale,
      child: MaterialApp(
        theme: dark ? buildDarkTheme() : buildTheme(),
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
          ),
          child: c!,
        ),
        home: Scaffold(
          body: Center(
            child: width == null ? child : SizedBox(width: width, child: child),
          ),
        ),
      ),
    ),
  );
}
