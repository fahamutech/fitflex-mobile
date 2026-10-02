import 'package:fitflexmobile/screens/owner/members/widgets/add_member_sheet.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/pin_credentials.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _testApp({required ValueChanged<Map<String, dynamic>?> onSubmitted}) {
  final locale = FFLocale();
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp(
      theme: buildTheme(),
      supportedLocales: const [Locale('en'), Locale('sw')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                onSubmitted(
                  await openAddMemberSheet(
                    context,
                    gyms: const [
                      {'id': 'gym_1', 'name': 'Gym One'},
                    ],
                  ),
                );
              },
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('owner can register a direct member with a 4-digit PIN', (
    tester,
  ) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(
      _testApp(onSubmitted: (payload) => submitted = payload),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-member-name')),
      'Amina Said',
    );
    await tester.enterText(
      find.byKey(const Key('add-member-email')),
      'amina@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('add-member-initial-password')),
      '2468',
    );
    await tester.ensureVisible(find.byKey(const Key('add-member-save')));
    await tester.tap(find.byKey(const Key('add-member-save')));
    await tester.pumpAndSettle();

    expect(find.text('PIN must be exactly 4 digits.'), findsNothing);
    expect(submitted, isNotNull);
    expect(submitted!['initialPassword'], firebasePasswordForPin('2468'));
  });

  testWidgets('a PIN that is not four digits is refused', (tester) async {
    Map<String, dynamic>? submitted;
    await tester.pumpWidget(
      _testApp(onSubmitted: (payload) => submitted = payload),
    );

    await tester.tap(find.text('Open form'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('add-member-name')),
      'Amina Said',
    );
    await tester.enterText(
      find.byKey(const Key('add-member-email')),
      'amina@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('add-member-initial-password')),
      '246810',
    );
    await tester.ensureVisible(find.byKey(const Key('add-member-save')));
    await tester.tap(find.byKey(const Key('add-member-save')));
    await tester.pumpAndSettle();

    expect(find.text('PIN must be exactly 4 digits.'), findsOneWidget);
    expect(submitted, isNull);
  });
}
