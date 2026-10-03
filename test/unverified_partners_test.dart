import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/widgets/trainer_sharing.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/api_error_message.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/widgets/partner_not_verified.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Verification rule of 3 Oct 2026: trainers and gym owners are active at once
// and shown as not verified; an unverified trainer cannot be booked or
// connected with, and the partner sees what waits for verification.

class _FakeApi extends ApiClient {
  _FakeApi({this.partnerVerified}) : super(baseUrl: 'http://localhost:0');

  bool? partnerVerified;
  int connectRequests = 0;

  @override
  Future<Map<String, dynamic>> me() async => {
    'user': {'id': 'usr_1', 'userType': 'trainer'},
    'partnerVerified': ?partnerVerified,
  };

  @override
  Future<Map<String, dynamic>> requestTrainerConnection(
    String trainerId,
    Map<String, dynamic> permissions,
  ) async {
    connectRequests += 1;
    throw ApiException(403, {'error': 'trainer_not_verified'});
  }
}

Widget _app(AuthState auth, Widget child, {MemberData? data}) => AppScope(
  api: auth.api,
  auth: auth,
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
      home: Scaffold(
        body: data == null ? child : MemberDataScope(data: data, child: child),
      ),
    ),
  ),
);

Map<String, dynamic> _trainerJson(Map<String, dynamic> extra) => {
  'id': 'trn_1',
  'displayName': 'Coach Amani',
  'specialties': ['strength'],
  'hourlyRateTzs': 20000,
  'status': 'active',
  ...extra,
};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a trainer is bookable unless the backend says otherwise', () {
    expect(TrainerProfile.fromJson(_trainerJson({})).bookable, isTrue);
    expect(
      TrainerProfile.fromJson(_trainerJson({'bookable': true})).bookable,
      isTrue,
    );
    final unverified = TrainerProfile.fromJson(
      _trainerJson({'bookable': false, 'verified': false}),
    );
    expect(unverified.bookable, isFalse);
    expect(unverified.isVerified, isFalse);
    expect(unverified.withRating(4.5, 2).bookable, isFalse);
  });

  test('the refusals read as plain reasons', () {
    final locale = FFLocale();
    expect(
      apiErrorMessage(
        locale,
        ApiException(403, {'error': 'trainer_not_verified'}),
      ),
      contains('This trainer is not verified yet.'),
    );
    expect(
      apiErrorMessage(
        locale,
        ApiException(400, {'failure': 'gym_not_verified'}),
      ),
      contains('a FitFlex Pass cannot be used here'),
    );
  });

  testWidgets('Connect is switched off for an unverified trainer', (
    tester,
  ) async {
    final api = _FakeApi();
    await tester.pumpWidget(
      _app(
        AuthState(api),
        const TrainerConnectCard(
          trainerId: 'trn_1',
          trainerName: 'Coach Amani',
          canConnect: false,
        ),
        data: MemberData(),
      ),
    );
    expect(
      find.text(
        'You can connect with this trainer once FitFlex has verified them.',
      ),
      findsOneWidget,
    );
    final button = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('trainer-connect')),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.byKey(const Key('trainer-connect')));
    await tester.pumpAndSettle();
    expect(api.connectRequests, 0);
  });

  testWidgets('the partner notice shows only while they are not verified', (
    tester,
  ) async {
    Future<AuthState> signedIn(String userType, bool? verified) async {
      final auth = AuthState(_FakeApi(partnerVerified: verified));
      await auth.signIn('jwt', {'id': 'usr_1', 'userType': userType});
      await auth.refreshPartnerVerified();
      return auth;
    }

    final trainer = await signedIn('trainer', false);
    expect(trainer.partnerVerified, isFalse);
    await tester.pumpWidget(
      _app(trainer, ListView(children: const [PartnerNotVerifiedNotice()])),
    );
    expect(find.text('Not verified yet'), findsOneWidget);
    expect(
      find.textContaining('cannot book you or connect with you'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('partner-not-verified-cta')), findsOneWidget);

    final owner = await signedIn('gym_operator', false);
    await tester.pumpWidget(
      _app(owner, ListView(children: const [PartnerNotVerifiedNotice()])),
    );
    expect(
      find.textContaining('FitFlex Pass members cannot check in'),
      findsOneWidget,
    );

    for (final auth in [
      await signedIn('trainer', true),
      await signedIn('member', null),
    ]) {
      await tester.pumpWidget(
        _app(auth, ListView(children: const [PartnerNotVerifiedNotice()])),
      );
      expect(find.byKey(const Key('partner-not-verified')), findsNothing);
    }

    await trainer.signOut();
    expect(trainer.partnerVerified, isNull);
  });

  testWidgets('a list label marks what is not verified', (tester) async {
    await tester.pumpWidget(
      _app(AuthState(_FakeApi()), const NotVerifiedLabel()),
    );
    expect(find.text('Not Verified'), findsOneWidget);
  });
}
