// A trainer makes a training plan for a client: the builder, FitFlex's
// suggestion, sending it, and where it stands on the client page.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/trainer/trainer_client_page.dart';
import 'package:fitflexmobile/screens/trainer/trainer_training_plan_page.dart';
import 'package:fitflexmobile/shared/activity/trainer_connection.dart';
import 'package:fitflexmobile/shared/activity/training_plan.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

final _connection = TrainerConnection.fromJson({
  'id': 'tmr_1',
  'trainerId': 'trn_1',
  'memberId': 'm1',
  'status': 'active',
  'permissions': <String, bool>{},
  'requestedAt': '2026-09-24T06:00:00.000Z',
  'member': {'id': 'm1', 'displayName': 'Amina'},
});

final _saved = [
  TrainerPlan.fromJson({'id': 'wpl_a', 'name': 'Push day', 'exercises': []}),
  TrainerPlan.fromJson({'id': 'wpl_b', 'name': 'Leg day', 'exercises': []}),
];

class _FakeApi extends ApiClient {
  final calls = <(String, Object?)>[];
  List<Map<String, dynamic>> made = [];
  bool usedClientPreferences = false;
  String? offerError;

  @override
  Future<Map<String, dynamic>> trainerClientOverview(String id) async => {
    'client': {
      'id': 'tmr_1',
      'trainerId': 'trn_1',
      'memberId': 'm1',
      'status': 'active',
      'permissions': <String, bool>{},
      'member': {'id': 'm1', 'displayName': 'Amina'},
    },
    'workouts': [],
  };

  @override
  Future<List<dynamic>> trainerPlans() async => const [];

  @override
  Future<List<dynamic>> trainerClientTrainingPlans(String id) async => made;

  @override
  Future<Map<String, dynamic>> trainerSuggestTrainingPlan(
    String id,
    Map<String, dynamic> body,
  ) async {
    calls.add(('suggest', body));
    return {
      'usedClientPreferences': usedClientPreferences,
      'days': [
        {'day': 1, 'name': 'Full Body', 'exercises': []},
        {'day': 3, 'name': 'Cardio', 'exercises': []},
        {'day': 5, 'name': 'Full Body', 'exercises': []},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> trainerOfferTrainingPlan(
    String id,
    Map<String, dynamic> body,
  ) async {
    calls.add(('offer', body));
    if (offerError != null) throw ApiException(400, {'error': offerError});
    made = [
      {
        'id': 'tpn_1',
        'name': body['name'] ?? '4-week plan',
        'status': 'offered',
        'durationWeeks': body['durationWeeks'],
        'daysPerWeek': (body['days'] as List).length,
      },
    ];
    return {'plan': made.first};
  }

  @override
  Future<Map<String, dynamic>> trainerUpdateTrainingPlan(
    String planId,
    Map<String, dynamic> body,
  ) async {
    calls.add(('update', body));
    if (offerError != null) throw ApiException(400, {'error': offerError});
    made = [
      {...made.first, 'name': ?body['name']},
    ];
    return {'plan': made.first};
  }

  @override
  Future<void> trainerCancelTrainingPlan(String planId) async {
    calls.add(('cancel', planId));
    made = [
      {...made.first, 'status': 'cancelled'},
    ];
  }
}

Widget _app(ApiClient api, Widget home) => AppScope(
  api: api,
  auth: AuthState(api),
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
      home: home,
    ),
  ),
);

Future<void> _tall(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 9000);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _pick(WidgetTester tester, int day, String label) async {
  await tester.tap(find.byKey(Key('trainer-plan-day-$day')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Widget _builder() =>
    TrainerTrainingPlanPage(connection: _connection, savedWorkouts: _saved);

void main() {
  test('a made plan reads its status and, when shared, its progress', () {
    final open = TrainerMadePlan.tryParse({
      'id': 'p',
      'name': 'Block',
      'status': 'active',
      'durationWeeks': 4,
      'daysPerWeek': 2,
      'progress': {'sessions': 8, 'completed': 3},
    })!;
    expect(open.isOpen, isTrue);
    expect((open.completed, open.sessions), (3, 8));
    final closed = TrainerMadePlan.tryParse({'id': 'p', 'status': 'declined'})!;
    expect(closed.isOpen, isFalse);
    expect(closed.completed, isNull, reason: 'not shared');
  });

  testWidgets('lay out a week from saved workouts and send it', (tester) async {
    await _tall(tester);
    final api = _FakeApi();
    await tester.pumpWidget(_app(api, _builder()));
    await tester.pumpAndSettle();
    expect(find.text('A plan for Amina'), findsOneWidget);

    // Nothing chosen yet: it says what is needed, and sends nothing.
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();
    expect(find.text('Choose a workout for at least one day.'), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.enterText(
      find.byKey(const Key('trainer-plan-name')),
      'Strength block',
    );
    await tester.tap(find.byKey(const Key('trainer-plan-weeks-6')));
    await _pick(tester, 1, 'Push day');
    await _pick(tester, 4, 'Leg day');
    await tester.enterText(
      find.byKey(const Key('trainer-plan-note')),
      'Go steady in week one.',
    );
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();

    final body = api.calls.single.$2 as Map;
    expect(api.calls.single.$1, 'offer');
    expect(body['name'], 'Strength block');
    expect(body['note'], 'Go steady in week one.');
    expect(body['durationWeeks'], 6);
    expect(body['days'], [
      {'day': 1, 'planId': 'wpl_a'},
      {'day': 4, 'planId': 'wpl_b'},
    ]);
  });

  testWidgets("start from FitFlex's suggestion and swap a day", (tester) async {
    await _tall(tester);
    final api = _FakeApi();
    await tester.pumpWidget(_app(api, _builder()));
    await tester.pumpAndSettle();

    // A day chosen before asking stays if FitFlex has nothing for it.
    await _pick(tester, 2, 'Leg day');
    await tester.tap(find.byKey(const Key('trainer-plan-suggest-days-4')));
    await tester.tap(find.byKey(const Key('trainer-plan-suggest')));
    await tester.pumpAndSettle();
    expect((api.calls.single.$2 as Map)['preferences'], {'daysPerWeek': 4});
    expect(
      find.textContaining("Amina doesn't share goals with you"),
      findsOneWidget,
    );
    expect(find.text('FitFlex: Full Body'), findsNWidgets(2));
    expect(find.text('FitFlex: Cardio'), findsOneWidget);

    // Swap Wednesday's cardio for one of their own.
    await _pick(tester, 3, 'Push day');
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();
    expect((api.calls.last.$2 as Map)['days'], [
      {'day': 1, 'suggested': true},
      {'day': 2, 'planId': 'wpl_b'},
      {'day': 3, 'planId': 'wpl_a'},
      {'day': 5, 'suggested': true},
    ]);
  });

  testWidgets(
    'says whose choices the suggestion reflects, and explains errors',
    (tester) async {
      await _tall(tester);
      final api = _FakeApi()..usedClientPreferences = true;
      await tester.pumpWidget(_app(api, _builder()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('trainer-plan-suggest')));
      await tester.pumpAndSettle();
      expect(
        find.text("Built from Amina's own goal and preferences."),
        findsOneWidget,
      );

      api.offerError = 'no_suggestion_for_day';
      await tester.tap(find.byKey(const Key('trainer-plan-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining('suggestion has changed'), findsOneWidget);
      api.offerError = 'boom';
      await tester.tap(find.byKey(const Key('trainer-plan-send')));
      await tester.pumpAndSettle();
      expect(find.textContaining("Couldn't send the plan"), findsOneWidget);
      expect(find.byKey(const Key('trainer-plan-builder')), findsOneWidget);
    },
  );

  testWidgets('a week needs a rest day', (tester) async {
    await _tall(tester);
    final api = _FakeApi();
    await tester.pumpWidget(_app(api, _builder()));
    await tester.pumpAndSettle();
    for (var d = 1; d <= 7; d++) {
      await _pick(tester, d, 'Push day');
    }
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();
    expect(
      find.text('Leave at least one rest day in the week.'),
      findsOneWidget,
    );
    expect(api.calls, isEmpty);
  });

  testWidgets('the client page shows where the plan stands', (tester) async {
    await _tall(tester);
    final api = _FakeApi();
    await tester.pumpWidget(
      _app(api, TrainerClientPage(connection: _connection, plans: _saved)),
    );
    await tester.pumpAndSettle();
    expect(find.text("You haven't made a plan for Amina yet."), findsOneWidget);
    expect(find.text('Make a plan'), findsOneWidget);

    // Make one through the builder.
    await tester.tap(find.byKey(const Key('client-make-plan')));
    await tester.pumpAndSettle();
    await _pick(tester, 1, 'Push day');
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();
    expect(find.text('Plan sent to Amina.'), findsOneWidget);
    expect(find.text('Waiting for Amina'), findsOneWidget);
    expect(find.text('4 weeks · 1 days a week'), findsOneWidget);

    // Take it back.
    await tester.tap(find.byKey(const Key('client-plan-withdraw')));
    await tester.pumpAndSettle();
    expect(find.text('Take back this plan?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('trainer-plan-withdraw-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls.last, ('cancel', 'tpn_1'));
    expect(find.text('Stopped'), findsOneWidget);
    expect(find.byKey(const Key('client-plan-withdraw')), findsNothing);
  });

  testWidgets('progress shows only when the client shares it', (tester) async {
    await _tall(tester);
    final api = _FakeApi()
      ..made = [
        {
          'id': 'tpn_1',
          'name': 'Strength block',
          'status': 'active',
          'durationWeeks': 4,
          'daysPerWeek': 2,
        },
      ];
    await tester.pumpWidget(
      _app(api, TrainerClientPage(connection: _connection, plans: _saved)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Active'), findsOneWidget);
    expect(find.textContaining("so progress isn't shown"), findsOneWidget);

    api.made = [
      {
        ...api.made.first,
        'progress': {'sessions': 8, 'completed': 3},
      },
    ];
    await tester.pumpWidget(
      _app(
        api,
        TrainerClientPage(
          key: const ValueKey('again'),
          connection: _connection,
          plans: _saved,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('4 weeks · 2 days a week · 3 of 8 sessions done'),
      findsOneWidget,
    );
    expect(find.text('Stop plan'), findsOneWidget);
  });

  Map<String, dynamic> sent({String status = 'offered'}) => {
    'id': 'tpn_1',
    'name': 'Strength block',
    'note': 'Go steady.',
    'status': status,
    'durationWeeks': 3,
    'daysPerWeek': 3,
    'layout': [
      {'day': 1, 'name': 'Push day', 'planId': 'wpl_a'},
      {'day': 3, 'name': 'Cardio', 'suggested': true},
      // Made before the source was recorded: matched by name.
      {'day': 5, 'name': 'Leg day'},
    ],
  };

  Widget editor(Map<String, dynamic> plan) => TrainerTrainingPlanPage(
    connection: _connection,
    savedWorkouts: _saved,
    existing: TrainerMadePlan.tryParse(plan),
  );

  String? chosen(WidgetTester tester, int day) => tester
      .widget<DropdownButtonFormField<String>>(
        find.byKey(Key('trainer-plan-day-$day')),
      )
      .initialValue;

  testWidgets('editing opens on the plan as it was sent', (tester) async {
    await _tall(tester);
    final api = _FakeApi()..made = [sent()];
    await tester.pumpWidget(_app(api, editor(sent())));
    await tester.pumpAndSettle();
    expect(find.text("Edit Amina's plan"), findsOneWidget);
    expect(find.textContaining("hasn't answered yet"), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Strength block'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Go steady.'), findsOneWidget);
    expect(chosen(tester, 1), 'wpl_a');
    expect(chosen(tester, 2), 'rest');
    expect(chosen(tester, 3), 'suggested');
    expect(chosen(tester, 5), 'wpl_b', reason: 'matched by name');
    expect(find.text('FitFlex: Cardio'), findsOneWidget);
    // Three weeks isn't one of the usual lengths, but it is this plan's.
    expect(
      tester
          .widget<ChoiceChip>(find.byKey(const Key('trainer-plan-weeks-3')))
          .selected,
      isTrue,
    );
    expect(find.text('Save changes'), findsOneWidget);
  });

  testWidgets('a rename alone never sends the week', (tester) async {
    await _tall(tester);
    final api = _FakeApi()..made = [sent(status: 'active')];
    await tester.pumpWidget(_app(api, editor(sent(status: 'active'))));
    await tester.pumpAndSettle();
    expect(find.textContaining('apply from today'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('trainer-plan-name')),
      'Strength block v2',
    );
    await tester.enterText(find.byKey(const Key('trainer-plan-note')), '');
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();
    expect(api.calls.single.$1, 'update');
    expect(api.calls.single.$2, {'name': 'Strength block v2', 'note': null});
  });

  testWidgets('changing a day sends the whole week', (tester) async {
    await _tall(tester);
    final api = _FakeApi()..made = [sent(status: 'active')];
    await tester.pumpWidget(_app(api, editor(sent(status: 'active'))));
    await tester.pumpAndSettle();
    await _pick(tester, 2, 'Leg day');
    await _pick(tester, 5, 'Rest');
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();
    final body = api.calls.single.$2 as Map;
    expect(api.calls.single.$1, 'update');
    expect(body['durationWeeks'], 3);
    expect(body['days'], [
      {'day': 1, 'planId': 'wpl_a'},
      {'day': 2, 'planId': 'wpl_b'},
      {'day': 3, 'suggested': true},
    ]);
    expect(body['preferences'], {'daysPerWeek': 3});
  });

  testWidgets('a failed save keeps the editor open and says so', (
    tester,
  ) async {
    await _tall(tester);
    final api = _FakeApi()
      ..made = [sent()]
      ..offerError = 'boom';
    await tester.pumpWidget(_app(api, editor(sent())));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trainer-plan-weeks-6')));
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't save the changes"), findsOneWidget);
    expect(find.byKey(const Key('trainer-plan-builder')), findsOneWidget);
  });

  testWidgets('the client page offers Edit on a plan that is still open', (
    tester,
  ) async {
    await _tall(tester);
    final api = _FakeApi()..made = [sent(status: 'active')];
    await tester.pumpWidget(
      _app(api, TrainerClientPage(connection: _connection, plans: _saved)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('client-plan-edit')));
    await tester.pumpAndSettle();
    expect(find.text("Edit Amina's plan"), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('trainer-plan-name')),
      'Renamed block',
    );
    await tester.tap(find.byKey(const Key('trainer-plan-send')));
    await tester.pumpAndSettle();
    expect(find.text('Plan updated. Amina has been told.'), findsOneWidget);
    expect(find.text('Renamed block'), findsOneWidget);

    // A plan that is over can't be edited.
    api.made = [sent(status: 'declined')];
    await tester.pumpWidget(
      _app(
        api,
        TrainerClientPage(
          key: const ValueKey('closed'),
          connection: _connection,
          plans: _saved,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('client-plan-edit')), findsNothing);
  });
}
