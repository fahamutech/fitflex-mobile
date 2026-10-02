// Sessions & refunds: a member sees the trainer sessions they booked, cancels
// one where the server says they can, follows refunds, and asks for a pass
// payment back.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_sessions_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';

class _FakeApi extends ApiClient {
  _FakeApi({required this.bookings, List<Map<String, dynamic>>? refunds})
    : refunds = refunds ?? [],
      super(baseUrl: 'http://localhost:0');

  final List<Map<String, dynamic>> bookings;
  final List<Map<String, dynamic>> refunds;
  final cancelled = <String>[];
  final requests = <Map<String, dynamic>>[];
  ApiException? cancelError;

  @override
  Future<List<dynamic>> myTrainerBookings() async => bookings;

  @override
  Future<Map<String, dynamic>> myRefunds() async => {'refunds': refunds};

  @override
  Future<Map<String, dynamic>> cancelMyTrainerBooking(String bookingId) async {
    if (cancelError != null) throw cancelError!;
    cancelled.add(bookingId);
    final b = bookings.firstWhere((x) => x['id'] == bookingId);
    final paid = b['status'] == 'confirmed';
    b['status'] = 'cancelled';
    b['cancellation'] = {'canCancel': false, 'refundable': false};
    if (paid) {
      refunds.add({
        'id': 'rfd_1',
        'kind': 'trainer_booking',
        'status': 'approved',
        'amountTzs': b['amountTzs'],
      });
    }
    return {'booking': b};
  }

  @override
  Future<List<dynamic>> myPayments() async => [
    {
      'id': 'pay_1',
      'status': 'approved',
      'subscriptionId': 'sub_1',
      'tier': 'pro',
      'amountTzs': 150000,
      'decidedAt': '2026-10-01T09:00:00Z',
    },
    // A trainer-session payment: never offered for a refund request.
    {
      'id': 'pay_2',
      'status': 'approved',
      'subscriptionId': null,
      'amountTzs': 20000,
    },
  ];

  @override
  Future<Map<String, dynamic>> requestRefund({
    required String paymentRequestId,
    required String reasonCode,
    String? note,
  }) async {
    requests.add({
      'paymentRequestId': paymentRequestId,
      'reasonCode': reasonCode,
      'note': note,
    });
    refunds.add({
      'id': 'rfd_2',
      'kind': 'subscription',
      'status': 'requested',
      'amountTzs': 150000,
    });
    return {};
  }
}

Map<String, dynamic> _booking(
  String id, {
  String status = 'confirmed',
  bool canCancel = true,
  bool refundable = true,
  String? cancelBy = '2026-10-09T07:00:00.000Z',
}) => {
  'id': id,
  'date': '2026-10-10',
  'slot': '10:00',
  'status': status,
  'amountTzs': 20000,
  'trainer': {'displayName': 'Coach Juma'},
  'gym': {'name': 'Iron Paradise'},
  'cancellation': {
    'canCancel': canCancel,
    'refundable': refundable,
    'cancelBy': cancelBy,
  },
};

Widget _app(_FakeApi api, {String lang = 'en'}) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale()..set(Locale(lang)),
    child: const MaterialApp(home: MemberSessionsPage()),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('cancelling a paid session in time shows the refund', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi(bookings: [_booking('tbk_1')]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('Coach Juma'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.textContaining('No refunds'), findsOneWidget);

    await tester.tap(find.byKey(const Key('session-cancel-tbk_1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('refunded TZS 20,000 in full'), findsOneWidget);
    await tester.tap(find.byKey(const Key('session-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(api.cancelled, ['tbk_1']);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.byKey(const Key('session-cancel-tbk_1')), findsNothing);
    expect(find.byKey(const Key('refund-rfd_1')), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
  });

  testWidgets('inside 24 hours there is no cancel button, and it says why', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi(
      bookings: [
        _booking('tbk_late', canCancel: false),
        _booking('tbk_unpaid', status: 'payment_pending', refundable: false),
      ],
    );
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('session-cancel-tbk_late')), findsNothing);
    expect(find.textContaining('Less than 24 hours to go'), findsOneWidget);

    // An unpaid session can still be cancelled, with nothing to refund.
    await tester.tap(find.byKey(const Key('session-cancel-tbk_unpaid')));
    await tester.pumpAndSettle();
    expect(find.textContaining('nothing to refund'), findsOneWidget);
    await tester.tap(find.byKey(const Key('session-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(api.cancelled, ['tbk_unpaid']);
    expect(api.refunds, isEmpty);
  });

  testWidgets('a refusal from the server is explained', (tester) async {
    _tall(tester);
    final api = _FakeApi(
      bookings: [_booking('tbk_1')],
    )..cancelError = ApiException(409, {'error': 'cancellation_window_passed'});
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-cancel-tbk_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('session-cancel-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('can no longer be cancelled'), findsOneWidget);
  });

  testWidgets('refund statuses read plainly, in Swahili too', (tester) async {
    _tall(tester);
    final api = _FakeApi(
      bookings: [],
      refunds: [
        {
          'id': 'r1',
          'kind': 'shop_order',
          'status': 'paid',
          'amountTzs': 80000,
          'paymentReference': 'MPESA-QX12',
        },
        {
          'id': 'r2',
          'kind': 'subscription',
          'status': 'rejected',
          'amountTzs': 150000,
          'decisionNote': 'Your pass was used on 2 Oct.',
        },
      ],
    );
    await tester.pumpWidget(_app(api, lang: 'sw'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sessions-empty')), findsOneWidget);
    expect(find.text('Yamelipwa'), findsOneWidget);
    expect(find.textContaining('MPESA-QX12'), findsOneWidget);
    expect(find.text('Hayakuidhinishwa'), findsOneWidget);
    expect(find.text('Your pass was used on 2 Oct.'), findsOneWidget);
  });

  testWidgets('asking for a pass payment back offers only pass payments', (
    tester,
  ) async {
    _tall(tester);
    final api = _FakeApi(bookings: []);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refund-ask')));
    await tester.pumpAndSettle();
    expect(find.textContaining('TZS 150,000'), findsOneWidget);
    expect(find.textContaining('TZS 20,000'), findsNothing);

    await tester.enterText(
      find.byKey(const Key('refund-note')),
      'Paid twice on 1 October',
    );
    await tester.tap(find.byKey(const Key('refund-send')));
    await tester.pumpAndSettle();
    expect(api.requests, [
      {
        'paymentRequestId': 'pay_1',
        'reasonCode': 'charged_twice',
        'note': 'Paid twice on 1 October',
      },
    ]);
    expect(find.text('In review'), findsOneWidget);
  });

  test('the new refusals have plain words in English and Swahili', () {
    for (final lang in ['en', 'sw']) {
      final locale = FFLocale()..set(Locale(lang));
      for (final code in [
        'cancellation_window_passed',
        'session_already_started',
        'booking_not_cancellable',
        'order_already_dispatched',
        'order_cancelled',
        'refund_already_requested',
      ]) {
        final text = apiErrorMessage(
          locale,
          ApiException(409, {'error': code}),
        );
        expect(text.contains(code), isFalse, reason: '$lang $code: $text');
        expect(text.contains('error.reason'), isFalse, reason: '$lang $code');
      }
    }
  });
}
