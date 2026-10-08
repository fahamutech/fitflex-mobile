// Trainer/gym challenge management: drafts, publishing, pausing, editing,
// closing and archiving.
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/shared/activity/challenge.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/widgets/challenge_manager_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

// Thursday 24 Sep 2026.
final _now = DateTime(2026, 9, 24, 9);

Map<String, dynamic> _json({
  String id = 'c1',
  String name = '50K Steps',
  String status = 'active',
  String phase = 'active',
  String start = '2026-09-20',
  String end = '2026-09-30',
  int participantCount = 2,
  List<String> rewards = const ['Finisher badge'],
}) => {
  'id': id,
  'name': name,
  'type': 'steps',
  'target': 50000,
  'startDate': start,
  'endDate': end,
  'creatorType': 'trainer',
  'creatorId': 't1',
  'rewards': rewards,
  'visibility': 'audience',
  'mode': 'individual',
  'status': status,
  'phase': phase,
  'participantCount': participantCount,
};

/// A small stand-in for the server's challenge states.
class _FakeApi extends ApiClient {
  _FakeApi(this.rows);

  final List<Map<String, dynamic>> rows;
  final calls = <(String, Object?)>[];
  String? failWith;

  @override
  Future<List<dynamic>> creatorChallenges(
    String scope, {
    String? gymId,
  }) async => rows;

  @override
  Future<Map<String, dynamic>> createChallenge(
    String scope,
    Map<String, dynamic> body, {
    String? gymId,
  }) async {
    calls.add(('create', body));
    final draft = body['draft'] == true;
    rows.add(
      _json(
        id: 'new',
        name: body['name'] as String,
        status: draft ? 'draft' : 'active',
        phase: draft ? 'draft' : 'active',
        participantCount: 0,
      ),
    );
    return {'challenge': rows.last};
  }

  @override
  Future<Map<String, dynamic>> updateChallenge(
    String scope,
    String id,
    Map<String, dynamic> body, {
    String? gymId,
  }) async {
    calls.add(('update', body));
    if (failWith != null) throw ApiException(409, {'error': failWith});
    final row = rows.firstWhere((r) => r['id'] == id)..addAll(body);
    return {'challenge': row};
  }

  @override
  Future<Map<String, dynamic>> challengeAction(
    String scope,
    String id,
    String action, {
    String? gymId,
  }) async {
    calls.add((action, id));
    final row = rows.firstWhere((r) => r['id'] == id);
    row.addAll(switch (action) {
      'publish' => {'status': 'active', 'phase': 'active'},
      'pause' => {'status': 'paused'},
      'resume' => {'status': 'active'},
      'close' => {'status': 'closed', 'phase': 'ended'},
      'archive' => {'status': 'archived', 'phase': 'ended'},
      _ => {'status': 'cancelled', 'phase': 'cancelled'},
    });
    return {'challenge': row};
  }

  @override
  Future<Map<String, dynamic>> challengeParticipants(
    String scope,
    String id, {
    String? gymId,
  }) async => {'participants': []};
}

Widget _app(ApiClient api) => AppScope(
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
      home: ChallengeManagerPage(scope: 'trainer', now: _now),
    ),
  ),
);

Future<void> _pump(WidgetTester tester, _FakeApi api) async {
  tester.view.physicalSize = const Size(1080, 3600);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(api));
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String action) async {
  await tester.tap(find.byKey(const Key('challenge-actions')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('challenge-$action')));
  await tester.pumpAndSettle();
}

Finder _item(String action) => find.byKey(Key('challenge-$action'));

void main() {
  test('a challenge knows when it is a draft, live or paused', () {
    final draft = Challenge.tryParse(_json(status: 'draft', phase: 'draft'))!;
    expect(draft.isDraft, isTrue);
    expect(draft.isLive, isFalse);
    final paused = Challenge.tryParse(_json(status: 'paused'))!;
    expect(paused.isLive, isTrue);
    expect(paused.isPaused, isTrue);
    // Paused, but its end date has passed: simply ended.
    expect(
      Challenge.tryParse(_json(status: 'paused', phase: 'ended'))!.isPaused,
      isFalse,
    );
    // Servers from before drafts send no status.
    expect(Challenge.tryParse(_json()..remove('status'))!.isLive, isTrue);
  });

  testWidgets('save a draft, then publish it', (tester) async {
    final api = _FakeApi([]);
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('challenge-new')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('challenge-name')), 'October');
    await tester.tap(find.byKey(const Key('challenge-save-draft')));
    await tester.pumpAndSettle();
    final body = api.calls.single.$2 as Map;
    expect(body['draft'], true);
    expect(body['name'], 'October');
    expect(find.textContaining('Draft'), findsOneWidget);

    await tester.tap(find.byKey(const Key('managed-challenge-new')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Nobody can see or join it'), findsOneWidget);
    await tester.tap(find.byKey(const Key('challenge-actions')));
    await tester.pumpAndSettle();
    expect(_item('edit'), findsOneWidget);
    expect(_item('discard'), findsOneWidget);
    expect(_item('pause'), findsNothing);
    expect(_item('close'), findsNothing);
    await tester.tap(_item('publish'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('challenge-publish-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls.last, ('publish', 'new'));
    expect(find.byKey(const Key('challenge-state-note')), findsNothing);
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets('pause stops new joins and can be resumed', (tester) async {
    final api = _FakeApi([_json()]);
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('managed-challenge-c1')));
    await tester.pumpAndSettle();
    await _choose(tester, 'pause');
    expect(find.textContaining('Dates and rewards stay the same'), findsOne);
    await tester.tap(find.byKey(const Key('challenge-pause-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls.last, ('pause', 'c1'));
    expect(find.text('Paused'), findsOneWidget);
    expect(
      find.textContaining('People already taking part carry on'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('challenge-actions')));
    await tester.pumpAndSettle();
    expect(_item('pause'), findsNothing);
    expect(_item('edit'), findsOneWidget);
    expect(_item('close'), findsOneWidget);
    await tester.tap(_item('resume'));
    await tester.pumpAndSettle();
    expect(api.calls.last, ('resume', 'c1'));
    expect(find.text('Running'), findsOneWidget);
    expect(find.byKey(const Key('challenge-state-note')), findsNothing);
  });

  testWidgets('edit a running challenge: what is locked is left alone', (
    tester,
  ) async {
    final api = _FakeApi([_json()]);
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('managed-challenge-c1')));
    await tester.pumpAndSettle();
    await _choose(tester, 'edit');
    expect(find.text('Edit challenge'), findsOneWidget);
    expect(find.byKey(const Key('challenge-locked-note')), findsOneWidget);
    expect(find.byKey(const Key('challenge-teams')), findsNothing);
    expect(find.byKey(const Key('challenge-save-draft')), findsNothing);
    expect(find.widgetWithText(TextFormField, '50K Steps'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('challenge-name')), '60K');
    await tester.enterText(find.byKey(const Key('challenge-target')), '60000');
    await tester.tap(find.byKey(const Key('challenge-save')));
    await tester.pumpAndSettle();
    final body = api.calls.single.$2 as Map;
    expect(body['name'], '60K');
    expect(body['target'], 60000);
    expect(body['endDate'], '2026-09-30');
    for (final locked in ['type', 'mode', 'startDate', 'rewards', 'draft']) {
      expect(body.containsKey(locked), isFalse, reason: locked);
    }
    expect(find.text('60K'), findsOneWidget);
  });

  testWidgets('a draft is fully editable; a refusal is explained', (
    tester,
  ) async {
    final api = _FakeApi([
      _json(status: 'draft', phase: 'draft', participantCount: 0),
    ]);
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('managed-challenge-c1')));
    await tester.pumpAndSettle();
    await _choose(tester, 'edit');
    expect(find.byKey(const Key('challenge-locked-note')), findsNothing);
    await tester.tap(find.byKey(const Key('challenge-type-workouts')));
    await tester.enterText(find.byKey(const Key('challenge-rewards')), '');
    api.failWith = 'reward_locked';
    await tester.tap(find.byKey(const Key('challenge-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('already earned'), findsOneWidget);

    api.failWith = null;
    await tester.tap(find.byKey(const Key('challenge-save')));
    await tester.pumpAndSettle();
    final body = api.calls.last.$2 as Map;
    expect(body['type'], 'workouts');
    expect(body['startDate'], '2026-09-20');
    expect(body['rewards'], isEmpty);
  });

  testWidgets('close now, then archive', (tester) async {
    final api = _FakeApi([_json()]);
    await _pump(tester, api);
    await tester.tap(find.byKey(const Key('managed-challenge-c1')));
    await tester.pumpAndSettle();
    await _choose(tester, 'close');
    await tester.tap(find.byKey(const Key('challenge-close-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls.last, ('close', 'c1'));
    expect(find.text('Closed early'), findsOneWidget);

    await tester.tap(find.byKey(const Key('challenge-actions')));
    await tester.pumpAndSettle();
    expect(_item('edit'), findsNothing);
    expect(_item('cancel'), findsNothing);
    await tester.tap(_item('archive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('challenge-archive-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls.last, ('archive', 'c1'));
    // Back on the list, where it now reads as archived.
    expect(find.textContaining('Archived'), findsOneWidget);
  });

  test('every new line exists in English and Swahili', () {
    for (final key in [
      'challenge.phase.draft',
      'challenge.status.paused',
      'challenge.pausedNoJoin',
      'challenge.pauseBody',
      'challenge.err.reward_locked',
    ]) {
      for (final lang in ['en', 'sw']) {
        expect(FFLocale.keysOf(lang), contains(key), reason: '$lang $key');
      }
    }
  });
}
