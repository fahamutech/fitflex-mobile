import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/widgets/challenge_rewards.dart';
import 'package:fitflexmobile/shared/activity/challenge.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _challenge({
  Object? rewardItems,
  List<String> rewards = const [],
}) => {
  'id': 'c1',
  'name': 'FitFlex 50K Steps',
  'type': 'steps',
  'target': 50000,
  'startDate': '2026-09-20',
  'endDate': '2026-09-30',
  'creatorType': 'fitflex',
  'phase': 'active',
  'joined': true,
  'rewards': rewards,
  'rewardItems': ?rewardItems,
};

Map<String, dynamic> _earned(
  String id, {
  String challengeId = 'c1',
  String status = 'pending',
  String rule = 'finishers',
  String label = '7-day FitFlex Gym Pass',
  String? value = '7 days',
  int? rank,
  String? reference,
  String? note,
}) => {
  'id': id,
  'challenge': {'id': challengeId, 'name': 'FitFlex 50K Steps'},
  'reward': {
    'id': 'rwd_1',
    'type': 'gym_pass',
    'label': label,
    'value': value,
    'rule': rule,
  },
  'rank': rank,
  'status': status,
  'earnedAt': '2026-09-24T06:00:00.000Z',
  'issuedAt': status == 'issued' ? '2026-09-26T06:00:00.000Z' : null,
  'reference': reference,
  'note': note,
};

class _FakeApi extends ApiClient {
  _FakeApi(this.rows, {this.fail = false});
  final List<Map<String, dynamic>> rows;
  final bool fail;
  int calls = 0;

  @override
  Future<List<dynamic>> myRewards() async {
    calls += 1;
    if (fail) throw Exception('offline');
    return rows;
  }
}

Widget _app(ApiClient api, Widget child, {String locale = 'en'}) {
  final l = FFLocale()..set(Locale(locale));
  return AppScope(
    api: api,
    auth: AuthState(api),
    child: FFLocaleScope(
      notifier: l,
      child: MaterialApp(
        theme: buildTheme(),
        locale: Locale(locale),
        supportedLocales: const [Locale('en'), Locale('sw')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  test(
    'reward items parse; labels from older servers read as finisher rewards',
    () {
      final c = Challenge.tryParse(
        _challenge(
          rewardItems: [
            {
              'id': 'r1',
              'type': 'points',
              'label': 'FitFlex points',
              'value': '500',
              'rule': 'finishers',
            },
            {
              'id': 'r2',
              'type': 'trainer_session',
              'label': 'Free PT session',
              'rule': 'top',
              'topN': 3,
            },
            {
              'id': 'r3',
              'type': 'hovercraft',
              'label': 'Mystery',
              'rule': 'team',
            },
            {'type': 'badge'},
          ],
        ),
      )!;
      expect(c.rewardItems.map((r) => r.label), [
        'FitFlex points',
        'Free PT session',
        'Mystery',
      ]);
      expect(c.rewardItems[1].rule, RewardRule.top);
      expect(c.rewardItems[1].topN, 3);
      expect(
        c.rewardItems[2].type,
        'other',
        reason: 'unknown types show as other',
      );

      final legacy = Challenge.tryParse(
        _challenge(rewards: ['Finisher badge']),
      )!;
      expect(legacy.rewardItems.single.label, 'Finisher badge');
      expect(legacy.rewardItems.single.rule, RewardRule.finishers);
    },
  );

  test('earned rewards parse their status trail fields', () {
    final e = EarnedReward.tryParse(
      _earned('a', status: 'issued', reference: 'PASS-1'),
    )!;
    expect(e.status, RewardStatus.issued);
    expect(e.reference, 'PASS-1');
    expect(e.issuedAt, isNotNull);
    expect(EarnedReward.tryParse({'id': 'x'}), isNull);
    expect(
      EarnedReward.tryParse(_earned('b', status: 'weird'))!.status,
      RewardStatus.pending,
    );
  });

  testWidgets(
    'earned is shown apart from handed out, for this challenge only',
    (tester) async {
      final api = _FakeApi([
        _earned('a1'),
        _earned(
          'a2',
          status: 'issued',
          label: 'Finisher badge',
          value: null,
          reference: 'BDG-42',
        ),
        _earned(
          'a3',
          status: 'rejected',
          rule: 'top',
          rank: 2,
          label: 'Free PT session',
          value: null,
          note: 'Steps logged after the end date',
        ),
        _earned('a4', challengeId: 'other', label: 'Should not show'),
      ]);
      final c = Challenge.tryParse(_challenge())!;
      await tester.pumpWidget(_app(api, ChallengeEarnedRewards(challenge: c)));
      await tester.pumpAndSettle();

      expect(find.text('Your rewards'), findsOneWidget);
      expect(find.text('Challenge completed'), findsNWidgets(2));
      expect(
        find.text('Reward earned: 7-day FitFlex Gym Pass (7 days)'),
        findsOneWidget,
      );
      expect(find.text('Pending fulfilment'), findsOneWidget);
      expect(find.textContaining('checked, then handed out'), findsOneWidget);

      expect(find.text('Issued'), findsOneWidget);
      expect(find.text('Reference: BDG-42'), findsOneWidget);

      expect(find.text('You placed #2'), findsOneWidget);
      expect(find.text('Not approved'), findsOneWidget);
      expect(find.text('Steps logged after the end date'), findsOneWidget);

      expect(find.textContaining('Should not show'), findsNothing);
      expect(api.calls, 1);
    },
  );

  testWidgets('nothing earned, or rewards unavailable: nothing shown', (
    tester,
  ) async {
    final c = Challenge.tryParse(_challenge())!;
    await tester.pumpWidget(
      _app(_FakeApi([]), ChallengeEarnedRewards(challenge: c)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your rewards'), findsNothing);

    await tester.pumpWidget(
      _app(
        _FakeApi([_earned('a1')], fail: true),
        ChallengeEarnedRewards(key: const Key('x'), challenge: c),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your rewards'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('offered rewards say who earns them, in Swahili too', (
    tester,
  ) async {
    final c = Challenge.tryParse(
      _challenge(
        rewardItems: [
          {
            'id': 'r1',
            'type': 'gym_pass',
            'label': 'Gym pass',
            'value': '7 days',
            'rule': 'finishers',
          },
          {
            'id': 'r2',
            'type': 'trainer_session',
            'label': 'PT session',
            'rule': 'top',
            'topN': 3,
          },
          {
            'id': 'r3',
            'type': 'vendor_voucher',
            'label': 'Smoothie',
            'rule': 'team',
          },
        ],
      ),
    )!;
    await tester.pumpWidget(
      _app(_FakeApi([]), ChallengeRewardsOffered(challenge: c)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Gym pass · 7 days'), findsOneWidget);
    expect(find.text('Everyone who finishes'), findsOneWidget);
    expect(find.text('Top 3'), findsOneWidget);
    expect(find.text('Winning team'), findsOneWidget);

    await tester.pumpWidget(
      _app(
        _FakeApi([_earned('a1')]),
        Column(
          children: [
            ChallengeRewardsOffered(challenge: c),
            ChallengeEarnedRewards(challenge: c),
          ],
        ),
        locale: 'sw',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Kila anayekamilisha'), findsOneWidget);
    expect(find.text('Inasubiri kutolewa'), findsOneWidget);
    expect(find.text('Zawadi zako'), findsOneWidget);
  });
}
