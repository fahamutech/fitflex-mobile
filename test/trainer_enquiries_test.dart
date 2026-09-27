// Trainer enquiries as conversations (list, read, reply, close), the shared
// chat widgets, and "Coach replied" notifications opening the trainer.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/trainer/trainer_enquiries_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/enquiry_thread.dart';

Map<String, dynamic> _enquiry({
  String status = 'new',
  bool unread = true,
  List<Map<String, dynamic>>? messages,
}) => {
  'id': 'tng_1',
  'type': 'enquiry',
  'status': status,
  'unread': unread,
  'lastMessageFrom': 'member',
  'member': {
    'id': 'usr_m',
    'displayName': 'Neema',
    'phone': '+255700000001',
    'email': 'neema@example.com',
  },
  'messages':
      messages ??
      [
        {
          'from': 'member',
          'text': 'Do you train beginners?',
          'at': '2026-09-28T08:00:00Z',
        },
      ],
};

class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost:0');

  Map<String, dynamic> row = _enquiry();
  final calls = <String>[];

  @override
  Future<List<dynamic>> trainerEngagements() async => [row];

  @override
  Future<Map<String, dynamic>> trainerReadEngagement(String id) async {
    calls.add('read:$id');
    return row = {...row, 'status': 'read', 'unread': false};
  }

  @override
  Future<Map<String, dynamic>> trainerReplyEngagement(
    String id,
    String message,
  ) async {
    calls.add('reply:$id:$message');
    return row = {
      ...row,
      'status': 'replied',
      'lastMessageFrom': 'trainer',
      'messages': [
        ...(row['messages'] as List),
        {'from': 'trainer', 'text': message, 'at': '2026-09-28T08:05:00Z'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> trainerCloseEngagement(String id) async {
    calls.add('close:$id');
    return row = {...row, 'status': 'closed'};
  }
}

Widget _wrap(Widget child, ApiClient api) => AppScope(
  api: api,
  auth: AuthState(api),
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
        home: child,
      ),
    ),
  ),
);

void main() {
  test('a trainer reply notification opens that trainer for the member', () {
    expect(
      memberRouteFor(
        deepLink: '',
        type: 'trainer_enquiry_reply',
        trainerId: 'trn_1',
      ),
      '/member/trainers/trn_1',
    );
    expect(
      memberRouteFor(
        deepLink: '',
        type: 'trainer_enquiry_reply',
        trainerId: '../x',
      ),
      isNull,
    );
    expect(memberRouteFor(deepLink: '', type: 'trainer_enquiry_reply'), isNull);
  });

  test('older enquiries without a thread parse to nothing, not a crash', () {
    expect(EnquiryMessage.listFrom({'message': 'old'}), isEmpty);
    expect(EnquiryMessage.listFrom(null), isEmpty);
  });

  testWidgets('reply box sends, clears, and quick replies fill it', (
    tester,
  ) async {
    final sent = <String>[];
    await tester.pumpWidget(
      _wrap(
        Scaffold(
          body: EnquiryReplyBox(
            onSend: (t) async {
              sent.add(t);
              return true;
            },
            suggestions: const ['Quick one'],
          ),
        ),
        _FakeApi(),
      ),
    );
    await tester.tap(find.byKey(const Key('enquiry-suggestion-0')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('enquiry-send')));
    await tester.pumpAndSettle();
    expect(sent, ['Quick one']);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('enquiry-reply-field')))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('trainer opens an unread enquiry, replies and closes it', (
    tester,
  ) async {
    final api = _FakeApi();
    await tester.pumpWidget(_wrap(const TrainerEnquiriesPage(), api));
    await tester.pumpAndSettle();
    expect(find.text('Neema'), findsOneWidget);
    expect(find.byKey(const Key('enquiry-unread-tng_1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('enquiry-tng_1')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('read:tng_1'), reason: 'opening marks it read');
    expect(find.text('Do you train beginners?'), findsOneWidget);
    expect(find.byKey(const Key('enquiry-call')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('enquiry-reply-field')),
      'Yes, 6am weekdays.',
    );
    await tester.tap(find.byKey(const Key('enquiry-send')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('reply:tng_1:Yes, 6am weekdays.'));
    expect(find.text('Yes, 6am weekdays.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('enquiry-close')));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'close:tng_1');
    expect(find.byKey(const Key('enquiry-close')), findsNothing);

    // Back on the list: it moved to Closed.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('enquiry-tng_1')), findsNothing);
    await tester.tap(find.text('Closed'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('enquiry-tng_1')), findsOneWidget);
  });

  test('every new check-in and enquiry string has a Swahili translation', () {
    final en = FFLocale.keysOf(
      'en',
    ).where((k) => k.startsWith('checkin.') || k.startsWith('enquiry.'));
    final sw = FFLocale.keysOf('sw');
    expect(en.length, greaterThanOrEqualTo(25));
    expect(en.where((k) => !sw.contains(k)), isEmpty);
  });
}
