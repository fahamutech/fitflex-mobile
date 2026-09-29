import 'package:fitflexmobile/screens/owner/members/data/member_models.dart';
import 'package:fitflexmobile/screens/owner/members/widgets/check_in_member_sheet.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _member = MemberDetail(
  id: 'm1',
  publicId: 'FM1',
  memberType: OwnerMemberType.fitflex,
  status: OwnerMemberStatus.active,
);

Future<void> _openSheet(
  WidgetTester tester, {
  String? Function()? failureMessage,
}) async {
  await tester.pumpWidget(
    FFLocaleScope(
      notifier: FFLocale(),
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showCheckInMemberSheet(
                context,
                member: _member,
                checkedInBy: 'Owner',
                onConfirm: () async => null, // the check-in failed
                failureMessage: failureMessage,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(FilledButton));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a failed check-in shows the reason the caller gives', (
    tester,
  ) async {
    await _openSheet(
      tester,
      failureMessage: () => 'Scan their QR code to check them in.',
    );
    expect(find.text('Scan their QR code to check them in.'), findsOneWidget);
  });

  testWidgets('without a reason the sheet falls back to the generic error', (
    tester,
  ) async {
    await _openSheet(tester);
    expect(find.text(FFLocale().t('owner.errorGeneric')), findsOneWidget);
  });

  test('a paused plan explains itself in English and Swahili', () {
    for (final lang in ['en', 'sw']) {
      final locale = FFLocale()..set(Locale(lang));
      expect(locale.t('members.planPaused'), isNot('members.planPaused'));
    }
  });
}
