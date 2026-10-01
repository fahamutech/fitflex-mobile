// My wellness benefits: the member sees what a sponsor gives them, how much
// is used and what is left. Every number comes from the server.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_benefits_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/i18n.dart';

class _FakeApi extends ApiClient {
  _FakeApi(this.benefits) : super(baseUrl: 'http://localhost:0');

  final List<Map<String, dynamic>> benefits;
  bool fail = false;

  @override
  Future<Map<String, dynamic>> myWellnessBenefits() async {
    if (fail) throw ApiException(500, 'server_error');
    return {'benefits': benefits, 'asOf': '2026-10-05'};
  }
}

Map<String, dynamic> _benefit({
  String id = 'b2bf_1',
  String name = '8 gym visits a month',
  String type = 'gym_access',
  String fundingType = 'full',
  int? usageLimit = 8,
  String usagePeriod = 'month',
  int used = 3,
  int? remaining = 5,
  Map<String, dynamic> funding = const {},
  String? endDate = '2026-10-31',
}) => {
  'organization': {
    'id': 'o1',
    'name': 'ABC Company',
    'organizationType': 'employer',
  },
  'program': {
    'id': 'p1',
    'name': 'ABC Wellness',
    'startDate': '2026-01-01',
    'endDate': endDate,
  },
  'benefit': {
    'id': id,
    'name': name,
    'benefitType': type,
    'fundingType': fundingType,
    'usageLimit': usageLimit,
    'usagePeriod': usagePeriod,
    'validity': {'startDate': '2026-01-01', 'endDate': endDate},
    ...funding,
  },
  'used': used,
  'remaining': remaining,
};

Widget _app(_FakeApi api) => AppScope(
  api: api,
  auth: AuthState(api),
  child: FFLocaleScope(
    notifier: FFLocale(),
    child: const MaterialApp(home: MemberBenefitsPage()),
  ),
);

void main() {
  testWidgets('shows allowance used and left, who pays and validity', (
    tester,
  ) async {
    final api = _FakeApi([
      _benefit(),
      _benefit(
        id: 'b2bf_2',
        name: 'Trainer sessions at 60%',
        type: 'trainer_session',
        fundingType: 'sponsor_percentage',
        funding: {'sponsorShareBps': 6000},
        usageLimit: null,
        usagePeriod: 'unlimited',
        used: 2,
        remaining: null,
        endDate: null,
      ),
    ]);
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();

    expect(find.text('ABC Company · ABC Wellness'), findsNWidgets(2));
    expect(find.text('8 gym visits a month'), findsOneWidget);
    expect(find.text('Used 3 of 8 this month'), findsOneWidget);
    expect(find.text('5 left'), findsOneWidget);
    expect(find.text('Your sponsor pays in full'), findsOneWidget);
    expect(find.text('Valid until 2026-10-31'), findsOneWidget);

    expect(find.text('No limit on how often you use it'), findsOneWidget);
    expect(
      find.text('Your sponsor pays 60%; you pay the rest'),
      findsOneWidget,
    );
    expect(find.text('No end date'), findsOneWidget);
  });

  testWidgets('a member with no sponsor sees an explanation, not an error', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_FakeApi([])));
    await tester.pumpAndSettle();
    expect(find.text('No wellness benefits yet'), findsOneWidget);
  });

  testWidgets('a failed load can be retried', (tester) async {
    final api = _FakeApi([_benefit()])..fail = true;
    await tester.pumpWidget(_app(api));
    await tester.pumpAndSettle();
    expect(find.text('8 gym visits a month'), findsNothing);
    api.fail = false;
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('5 left'), findsOneWidget);
  });
}
