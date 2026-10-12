// Where a notification takes a trainer, a vendor or a gym when they tap it.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/inbox/inbox_controller.dart';
import 'package:fitflexmobile/shared/inbox/inbox_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String? _route(String side, String type, {String? gymId, String? memberId}) =>
    partnerRouteFor(side: side, type: type, gymId: gymId, memberId: memberId);

InboxMessage _message(String type, [Map<String, dynamic> data = const {}]) =>
    InboxMessage(id: 'n', type: type, title: 't', body: 'b', data: data);

Future<(String?, String)> _forRole(
  WidgetTester tester,
  String userType,
  InboxMessage message,
) async {
  final api = ApiClient();
  final auth = AuthState(api);
  await auth.signIn('jwt', {'id': 'u1', 'userType': userType});
  late (String?, String) out;
  await tester.pumpWidget(
    AppScope(
      key: UniqueKey(),
      api: api,
      auth: auth,
      child: FFLocaleScope(
        notifier: FFLocale(),
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) {
              out = (
                routeForMessage(context, message),
                inboxButtonLabel(context, message),
              );
              return const SizedBox();
            },
          ),
        ),
      ),
    ),
  );
  return out;
}

void main() {
  // Signing in saves the session to the phone's storage.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('account types map to the side of FitFlex they work on', () {
    expect(partnerSide('trainer'), 'trainer');
    expect(partnerSide('vendor'), 'vendor');
    expect(partnerSide('vendor_staff'), 'vendor');
    expect(partnerSide('gym_operator'), 'gym');
    expect(partnerSide('gym_staff'), 'gym');
    expect(partnerSide('member'), isNull);
    expect(partnerSide('admin'), isNull);
    expect(partnerSide(null), isNull);
  });

  test('a trainer is taken to the part of their home the news is about', () {
    for (final type in [
      'trainer_client_request',
      'training_plan_accepted',
      'training_plan_declined',
      'training_plan_stopped',
    ]) {
      expect(
        _route('trainer', type),
        '/trainer/home?open=clients',
        reason: type,
      );
    }
    for (final type in [
      'trainer_booking_requested',
      'trainer_booking_confirmed',
      'trainer_booking_cancelled',
    ]) {
      expect(
        _route('trainer', type),
        '/trainer/home?open=sessions',
        reason: type,
      );
    }
    expect(
      _route('trainer', 'trainer_enquiry'),
      '/trainer/home?open=enquiries',
    );
    expect(
      _route('trainer', 'trainer_interest'),
      '/trainer/home?open=enquiries',
    );
    expect(
      _route('trainer', 'trainer_payout_paid'),
      '/trainer/home?open=payouts',
    );
    // Verification messages have no screen of their own here: the message shows.
    expect(_route('trainer', 'kyc_approved'), isNull);
  });

  test('a vendor is taken to orders, questions, products or payments', () {
    expect(_route('vendor', 'vendor_new_order'), '/vendor/home?open=orders');
    expect(
      _route('vendor', 'vendor_order_cancelled'),
      '/vendor/home?open=orders',
    );
    expect(
      _route('vendor', 'vendor_customer_enquiry'),
      '/vendor/home?open=enquiries',
    );
    expect(
      _route('vendor', 'vendor_product_approved'),
      '/vendor/home?open=products',
    );
    expect(
      _route('vendor', 'vendor_product_rejected'),
      '/vendor/home?open=products',
    );
    expect(
      _route('vendor', 'vendor_payout_paid'),
      '/vendor/home?open=payments',
    );
    expect(_route('vendor', 'vendor_shop_approved'), isNull);
  });

  test('a gym is taken to the check-ins, the member, trainers or earnings', () {
    expect(
      _route('gym', 'gym_checkin', gymId: 'g1', memberId: 'm1'),
      '/owner/gyms/g1/checkins',
    );
    expect(
      _route('gym', 'gym_member_joined', gymId: 'g1', memberId: 'm1'),
      '/owner/members/m1',
    );
    expect(
      _route('gym', 'gym_trainer_request', gymId: 'g1'),
      '/owner/trainers',
    );
    expect(_route('gym', 'gym_review', gymId: 'g1'), '/owner/gyms');
    expect(_route('gym', 'gym_statement_approved'), '/owner/earnings');
    expect(_route('gym', 'gym_payout_paid'), '/owner/earnings');
    // Without the id, or with one that isn't an id, the message shows instead.
    expect(_route('gym', 'gym_checkin'), isNull);
    expect(_route('gym', 'gym_checkin', gymId: '../../admin'), isNull);
    expect(_route('gym', 'gym_member_joined', memberId: 'a/b'), isNull);
  });

  test("one side never follows another side's messages", () {
    expect(_route('trainer', 'vendor_new_order'), isNull);
    expect(_route('vendor', 'gym_checkin', gymId: 'g1'), isNull);
    expect(_route('gym', 'trainer_payout_paid'), isNull);
    expect(_route('gym', 'training_plan_offered'), isNull);
    expect(_route('nobody', 'gym_payout_paid'), isNull);
    // A member's phone still handles the member's own messages.
    expect(
      memberRouteFor(deepLink: '', type: 'training_plan_stopped'),
      '/member/activity/training',
    );
    expect(memberRouteFor(deepLink: '', type: 'gym_checkin'), isNull);
  });

  testWidgets('the inbox button follows who is signed in', (tester) async {
    expect(
      await _forRole(tester, 'trainer', _message('training_plan_accepted')),
      ('/trainer/home?open=clients', 'Open clients'),
    );
    expect(
      await _forRole(tester, 'vendor_staff', _message('vendor_new_order')),
      ('/vendor/home?open=orders', 'View orders'),
    );
    expect(
      await _forRole(
        tester,
        'gym_operator',
        _message('gym_checkin', {'gymId': 'g1', 'memberId': 'm1'}),
      ),
      ('/owner/gyms/g1/checkins', 'View check-ins'),
    );
    expect(
      await _forRole(
        tester,
        'gym_staff',
        _message('gym_member_joined', {'memberId': 'm1'}),
      ),
      ('/owner/members/m1', 'View member'),
    );
    // A message with nowhere to go has no button target.
    expect(
      (await _forRole(tester, 'trainer', _message('kyc_approved'))).$1,
      isNull,
    );
    // The same "plan stopped" message leads each side to its own screen.
    expect(
      (await _forRole(tester, 'member', _message('training_plan_stopped'))).$1,
      '/member/activity/training',
    );
    expect(
      (await _forRole(tester, 'trainer', _message('training_plan_stopped'))).$1,
      '/trainer/home?open=clients',
    );
  });

  test('every button has its words in English and Swahili', () {
    for (final link in [
      'clients',
      'sessions',
      'enquiries',
      'payouts',
      'orders',
      'customerQuestions',
      'products',
      'payments',
      'checkins',
      'member',
      'gymTrainers',
      'gyms',
      'earnings',
    ]) {
      for (final lang in ['en', 'sw']) {
        expect(
          FFLocale.keysOf(lang),
          contains('inbox.open.$link'),
          reason: '$lang $link',
        );
      }
    }
  });
}
