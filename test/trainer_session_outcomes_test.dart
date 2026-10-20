// Trainer session outcomes (Phase B · B1b, fitflex-functions#231): a trainer
// marks a session completed or records that the client didn't come, only
// when the server's `actions` allow it, after a confirm. The member sees the
// missed session as "Didn't attend", can't cancel it, can still review the
// trainer, and is told in their language with a link to the session.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_sessions_page.dart';
import 'package:fitflexmobile/screens/trainer/widgets/trainer_sheets.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/formatters.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/inbox/inbox_pages.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/widgets/reviews_section.dart';

// ── Trainer side ────────────────────────────────────────────────────────────

class _TrainerApi extends ApiClient {
  _TrainerApi({this.actions}) : super(baseUrl: 'http://localhost:0');

  /// `actions` on booking tbk_1, as GET /trainer/bookings returns it.
  /// Null = the flag is off: no `actions` key at all.
  Map<String, dynamic>? actions;
  String status = 'confirmed';
  ApiException? completeError;
  ApiException? noShowError;
  final calls = <String>[];

  @override
  Future<Map<String, dynamic>> trainerSessions({String? date}) async => {
    'date': '2026-10-20',
    'sessions': [
      {
        'id': 'tbk_1',
        'source': 'booking',
        'date': '2026-10-20',
        'slot': '10:00',
        'status': status,
        'amountTzs': 30000,
        'member': {'displayName': 'Asha Mushi'},
        'gym': {'name': 'Kilele Fitness'},
      },
      // A manual session never gets outcome buttons.
      {
        'id': 'tss_1',
        'source': 'manual',
        'date': '2026-10-20',
        'slot': '12:00',
        'status': 'recorded',
        'amountTzs': 15000,
        'customerName': 'Walk-in Baraka',
      },
    ],
  };

  @override
  Future<List<Map<String, dynamic>>> trainerBookings() async {
    calls.add('bookings');
    return [
      {'id': 'tbk_1', 'status': status, 'actions': ?actions},
    ];
  }

  @override
  Future<Map<String, dynamic>> trainerCompleteBooking(String bookingId) async {
    calls.add('complete:$bookingId');
    if (completeError != null) throw completeError!;
    status = 'completed';
    actions = {'canComplete': false, 'canMarkNoShow': false};
    return {
      'booking': {'id': bookingId, 'status': status, 'actions': actions},
    };
  }

  @override
  Future<Map<String, dynamic>> trainerMarkNoShow(String bookingId) async {
    calls.add('noShow:$bookingId');
    if (noShowError != null) throw noShowError!;
    status = 'no_show';
    actions = {'canComplete': false, 'canMarkNoShow': false};
    return {
      'booking': {'id': bookingId, 'status': status, 'actions': actions},
    };
  }
}

Widget _trainerApp(ApiClient api, {String lang = 'en'}) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale()..set(Locale(lang)),
    child: const MaterialApp(home: Scaffold(body: TrainerSessionsSheet())),
  ),
);

const _both = {'canComplete': true, 'canMarkNoShow': true};

void _size(WidgetTester tester, {double width = 1080, double dpr = 2.5}) {
  tester.view.physicalSize = Size(width, 2600);
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
}

// ── Member side ─────────────────────────────────────────────────────────────

class _MemberApi extends ApiClient {
  _MemberApi(this.bookings) : super(baseUrl: 'http://localhost:0');

  final List<Map<String, dynamic>> bookings;
  final reviewChecks = <String>[];

  @override
  Future<List<dynamic>> myTrainerBookings() async => bookings;

  @override
  Future<Map<String, dynamic>> myRefunds() async => {'refunds': []};

  @override
  Future<MyReviewState> myReviewState(ReviewSubject subject, String id) async {
    reviewChecks.add('${subject.path}:$id');
    return const MyReviewState(eligible: true, reason: 'completed_booking');
  }
}

Map<String, dynamic> _memberBooking(String id, String status) => {
  'id': id,
  'trainerId': 'trn_1',
  'date': '2026-10-18',
  'slot': '10:00',
  'status': status,
  'amountTzs': 30000,
  'trainer': {'id': 'trn_1', 'displayName': 'Coach Juma'},
  'gym': {'name': 'Kilele Fitness'},
  // What the server answers for a session that already happened.
  'cancellation': {'canCancel': false, 'refundable': false, 'cancelBy': null},
  'actions': {'canComplete': false, 'canMarkNoShow': false},
};

Widget _memberApp(ApiClient api, {String lang = 'en', String? focus}) =>
    AppScope(
      api: api,
      auth: AuthState(api),
      child: FFLocaleScope(
        notifier: FFLocale()..set(Locale(lang)),
        child: MaterialApp(home: MemberSessionsPage(focusBookingId: focus)),
      ),
    );

// ── Inbox ───────────────────────────────────────────────────────────────────

class _InboxApi extends ApiClient {
  _InboxApi() : super(baseUrl: 'http://localhost:0');

  @override
  Future<Map<String, dynamic>> notifications() async => {
    'notifications': [
      {
        'id': 'ntf_ns',
        'type': 'trainer_booking_no_show',
        'title': 'Missed session',
        'body':
            'Coach Juma recorded that you missed your session: 18 Oct 10:00.',
        'createdAt': DateTime.now().toIso8601String(),
        'readAt': null,
        'data': {
          'bookingGroupId': 'tbg_1',
          'trainerId': 'trn_1',
          'bookingId': 'tbk_9',
          'titleSw': 'Hukuhudhuria kipindi',
          'bodySw':
              'Coach Juma amerekodi kwamba hukuhudhuria kipindi chako: 18 Okt 10:00.',
        },
      },
    ],
    'unread': 1,
  };

  @override
  Future<void> markNotificationRead(String id) async {}

  @override
  Future<void> clickNotification(String id, {String via = 'inbox'}) async {}
}

void main() {
  setUp(() => debugLocalOffsetOverride = const Duration(hours: 3));
  tearDown(() => debugLocalOffsetOverride = null);

  group('trainer: session outcomes', () {
    testWidgets('no actions from the server (flag off): no buttons', (
      tester,
    ) async {
      _size(tester);
      final api = _TrainerApi();
      await tester.pumpWidget(_trainerApp(api));
      await tester.pumpAndSettle();
      expect(find.text('Asha Mushi'), findsOneWidget);
      expect(api.calls, ['bookings']);
      expect(find.byKey(const Key('trainer-complete-tbk_1')), findsNothing);
      expect(find.byKey(const Key('trainer-noshow-tbk_1')), findsNothing);
      expect(find.byKey(const Key('trainer-complete-tss_1')), findsNothing);
    });

    testWidgets('actions both false: no buttons', (tester) async {
      _size(tester);
      final api = _TrainerApi(
        actions: {'canComplete': false, 'canMarkNoShow': false},
      );
      await tester.pumpWidget(_trainerApp(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trainer-complete-tbk_1')), findsNothing);
      expect(find.byKey(const Key('trainer-noshow-tbk_1')), findsNothing);
    });

    testWidgets('only the action the server allows is shown', (tester) async {
      _size(tester);
      // Past the 48-hour window: can still complete, can't record a no-show.
      final api = _TrainerApi(
        actions: {'canComplete': true, 'canMarkNoShow': false},
      );
      await tester.pumpWidget(_trainerApp(api));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('trainer-complete-tbk_1')), findsOneWidget);
      expect(find.byKey(const Key('trainer-noshow-tbk_1')), findsNothing);
    });

    testWidgets('mark completed: confirm says what follows, list updates', (
      tester,
    ) async {
      _size(tester);
      final api = _TrainerApi(actions: Map.of(_both));
      await tester.pumpWidget(_trainerApp(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trainer-complete-tbk_1')));
      await tester.pumpAndSettle();
      expect(find.textContaining('added to your payouts'), findsOneWidget);
      // Closing the confirm changes nothing.
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.startsWith('complete')), isEmpty);

      await tester.tap(find.byKey(const Key('trainer-complete-tbk_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trainer-complete-confirm')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('complete:tbk_1'));
      expect(find.text('Session marked completed.'), findsOneWidget);
      expect(find.byKey(const Key('trainer-complete-tbk_1')), findsNothing);
      expect(find.byKey(const Key('trainer-noshow-tbk_1')), findsNothing);
    });

    testWidgets("client didn't come: paid as booked, client told", (
      tester,
    ) async {
      _size(tester);
      final api = _TrainerApi(actions: Map.of(_both));
      await tester.pumpWidget(_trainerApp(api));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('trainer-noshow-tbk_1')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'The session is paid as booked; the client is told.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('trainer-noshow-confirm')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('noShow:tbk_1'));
      expect(find.text("Recorded: the client didn't come."), findsOneWidget);
      expect(find.byKey(const Key('trainer-status-tbk_1')), findsOneWidget);
      expect(find.text("Didn't attend"), findsOneWidget);
      expect(find.byKey(const Key('trainer-noshow-tbk_1')), findsNothing);
    });

    Future<void> refused(
      WidgetTester tester, {
      required bool noShow,
      required ApiException error,
      required String expected,
      String lang = 'en',
    }) async {
      _size(tester);
      final api = _TrainerApi(actions: Map.of(_both));
      if (noShow) {
        api.noShowError = error;
      } else {
        api.completeError = error;
      }
      await tester.pumpWidget(_trainerApp(api, lang: lang));
      await tester.pumpAndSettle();
      final which = noShow ? 'noshow' : 'complete';
      await tester.tap(find.byKey(Key('trainer-$which-tbk_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('trainer-$which-confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining(expected), findsOneWidget);
      // Nothing changed, so the list is reloaded and the buttons stay.
      expect(find.byKey(Key('trainer-$which-tbk_1')), findsOneWidget);
    }

    testWidgets('complete before the start shows the start time', (
      tester,
    ) async {
      await refused(
        tester,
        noShow: false,
        error: ApiException(409, {
          'error': 'session_not_started',
          'startsAt': '2026-10-20T07:00:00.000Z',
        }),
        expected: 'this session starts Tue 20 Oct · 10:00',
      );
    });

    testWidgets('no-show before the start, in Swahili, shows the time', (
      tester,
    ) async {
      await refused(
        tester,
        noShow: true,
        lang: 'sw',
        error: ApiException(409, {
          'error': 'session_not_started',
          'startsAt': '2026-10-20T07:00:00.000Z',
        }),
        expected: 'kinaanza Jumanne 20 Okt · 10:00 asubuhi',
      );
    });

    testWidgets('complete a session that is not confirmed', (tester) async {
      await refused(
        tester,
        noShow: false,
        error: ApiException(409, {'error': 'booking_not_confirmable'}),
        expected: 'only a confirmed session can be marked completed',
      );
    });

    testWidgets('no-show on a session that is not confirmed', (tester) async {
      await refused(
        tester,
        noShow: true,
        error: ApiException(409, {'error': 'booking_not_confirmed'}),
        expected: 'only a confirmed session can be recorded as missed',
      );
    });

    testWidgets('no-show after the 48-hour window says when it closed', (
      tester,
    ) async {
      await refused(
        tester,
        noShow: true,
        error: ApiException(409, {
          'error': 'no_show_window_passed',
          'closedAt': '2026-10-22T07:00:00.000Z',
        }),
        expected:
            'the time to record a missed session ended Thu 22 Oct · 10:00',
      );
    });

    testWidgets('no-show while the feature is off', (tester) async {
      await refused(
        tester,
        noShow: true,
        error: ApiException(404, {'error': 'feature_disabled'}),
        expected: "Recording session outcomes isn't available yet.",
      );
    });

    testWidgets('the bookings list failing hides the buttons', (tester) async {
      _size(tester);
      await tester.pumpWidget(_trainerApp(_FailingBookingsApi()));
      await tester.pumpAndSettle();
      expect(find.text('Asha Mushi'), findsOneWidget);
      expect(find.byKey(const Key('trainer-complete-tbk_1')), findsNothing);
    });

    testWidgets('Swahili at 360 wide: buttons fit, no overflow', (
      tester,
    ) async {
      _size(tester, width: 360, dpr: 1);
      final api = _TrainerApi(actions: Map.of(_both));
      await tester.pumpWidget(_trainerApp(api, lang: 'sw'));
      await tester.pumpAndSettle();
      expect(find.text('Kamilisha kipindi'), findsOneWidget);
      expect(find.text('Mteja hakuja'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const Key('trainer-noshow-tbk_1')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Kipindi kinalipwa kama kilivyowekwa'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('trainer-noshow-confirm')));
      await tester.pumpAndSettle();
      expect(find.text('Hakuhudhuria'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('member: a missed session', () {
    testWidgets("reads Didn't attend, has no cancel, and can be reviewed", (
      tester,
    ) async {
      _size(tester);
      final api = _MemberApi([
        // Even if a stale answer said it could be cancelled, it can't.
        _memberBooking('tbk_ns', 'no_show')
          ..['cancellation'] = {'canCancel': true, 'refundable': true},
        _memberBooking('tbk_done', 'completed'),
        _memberBooking('tbk_up', 'confirmed'),
      ]);
      await tester.pumpWidget(_memberApp(api));
      await tester.pumpAndSettle();

      expect(find.text("Didn't attend"), findsOneWidget);
      expect(find.byKey(const Key('session-cancel-tbk_ns')), findsNothing);
      expect(find.byKey(const Key('session-review-tbk_ns')), findsOneWidget);
      expect(find.byKey(const Key('session-review-tbk_done')), findsOneWidget);
      // A session still to come can't be reviewed from here.
      expect(find.byKey(const Key('session-review-tbk_up')), findsNothing);

      await tester.tap(find.byKey(const Key('session-review-tbk_ns')));
      await tester.pumpAndSettle();
      expect(api.reviewChecks, ['trainers:trn_1']);
      expect(find.byType(ReviewSheet), findsOneWidget);
    });

    testWidgets('in Swahili at 360 wide', (tester) async {
      _size(tester, width: 360, dpr: 1);
      final api = _MemberApi([_memberBooking('tbk_ns', 'no_show')]);
      await tester.pumpWidget(_memberApp(api, lang: 'sw', focus: 'tbk_ns'));
      await tester.pumpAndSettle();
      expect(find.text('Hakuhudhuria'), findsOneWidget);
      expect(find.text('Toa maoni kuhusu trainer'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('member: the no-show notice', () {
    test('links to that booking', () {
      expect(
        memberRouteFor(
          deepLink: '',
          type: 'trainer_booking_no_show',
          bookingId: 'tbk_9',
        ),
        '/member/sessions?booking=tbk_9',
      );
      // An id that isn't safe still lands on the sessions list.
      expect(
        memberRouteFor(
          deepLink: '',
          type: 'trainer_booking_no_show',
          bookingId: '../x',
        ),
        '/member/sessions',
      );
    });

    test('push text follows the app language', () {
      const data = {'titleSw': 'Hukuhudhuria kipindi', 'bodySw': 'Mwili'};
      expect(
        localisedNoticeText(
          lang: 'sw',
          data: data,
          title: 'Missed session',
          body: 'Body',
        ),
        (title: 'Hukuhudhuria kipindi', body: 'Mwili'),
      );
      expect(
        localisedNoticeText(
          lang: 'en',
          data: data,
          title: 'Missed session',
          body: 'Body',
        ),
        (title: 'Missed session', body: 'Body'),
      );
    });

    testWidgets('shows in Swahili and opens the session', (tester) async {
      _size(tester);
      final api = _InboxApi();
      final inbox = InboxController(api);
      String? opened;
      final router = GoRouter(
        initialLocation: '/inbox',
        routes: [
          GoRoute(path: '/inbox', builder: (_, _) => const InboxPage()),
          GoRoute(
            path: '/inbox/:id',
            builder: (_, s) =>
                InboxMessagePage(messageId: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/member/sessions',
            builder: (_, s) {
              opened = s.uri.toString();
              return const Scaffold(body: Text('SESSIONS'));
            },
          ),
        ],
      );
      await tester.pumpWidget(
        AppScope(
          api: api,
          auth: AuthState(api),
          inbox: inbox,
          child: FFLocaleScope(
            notifier: FFLocale()..set(const Locale('sw')),
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hukuhudhuria kipindi'), findsOneWidget);
      expect(find.text('Missed session'), findsNothing);

      await tester.tap(find.byKey(const Key('inbox-ntf_ns')));
      await tester.pumpAndSettle();
      expect(find.textContaining('amerekodi kwamba'), findsOneWidget);
      expect(find.text('Angalia kipindi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('inbox-cta')));
      await tester.pumpAndSettle();
      expect(opened, '/member/sessions?booking=tbk_9');
    });
  });

  test('every outcome refusal has plain words in English and Swahili', () {
    for (final lang in ['en', 'sw']) {
      final locale = FFLocale()..set(Locale(lang));
      for (final body in [
        {'error': 'session_not_started'},
        {'error': 'session_not_started', 'startsAt': '2026-10-20T07:00:00Z'},
        {'error': 'booking_not_confirmable'},
        {'error': 'booking_not_confirmed'},
        {'error': 'no_show_window_passed'},
        {'error': 'no_show_window_passed', 'closedAt': '2026-10-22T07:00:00Z'},
      ]) {
        final text = apiErrorMessage(locale, ApiException(409, body));
        expect(text.contains('_'), isFalse, reason: '$lang $body: $text');
        expect(text.contains('{time}'), isFalse, reason: '$lang $body');
        expect(text.contains('error.reason'), isFalse, reason: '$lang $body');
      }
      for (final key in [
        'trainer.completeSession',
        'trainer.completeSessionConfirm',
        'trainer.markNoShow',
        'trainer.markNoShowConfirm',
        'trainer.sessionCompleted',
        'trainer.noShowRecorded',
        'booking.status.no_show',
      ]) {
        expect(locale.t(key), isNot(key), reason: '$lang $key');
      }
    }
  });
}

class _FailingBookingsApi extends _TrainerApi {
  _FailingBookingsApi() : super(actions: _both);

  @override
  Future<List<Map<String, dynamic>>> trainerBookings() async =>
      throw ApiException(500, {'error': 'server_error'});
}
