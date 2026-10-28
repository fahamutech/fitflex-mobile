// Events S3 (spec §5.14 event_team_test): the team page lists members by
// first name + initial, marks the captain, shows the code to the captain
// only, and copies it; create goes through the order body.
import 'package:fitflexmobile/screens/member/events/event_team_page.dart';
import 'package:fitflexmobile/shared/events/event_order.dart';
import 'package:fitflexmobile/shared/events/events_checkout.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Future<PageHost> _pump(WidgetTester tester, RecordingApi api) => pumpPage(
  tester,
  api,
  EventTeamPage(teamId: 'team_1', options: optsS3()),
  user: member,
  size: const Size(375, 1200),
  extraRoutes: s3Routes,
  keepRequests: true,
);

void main() {
  setUp(() => debugEventsDiscoveryOverride = true);
  tearDown(() => debugEventsDiscoveryOverride = null);

  test('the order body carries create or join exactly as §3.4', () {
    final create = registrationBody(
      eventId: 'evt_1',
      lines: const {'tt_std': 1},
      participants: const [],
      fields: const ParticipantFields(),
      team: const TeamChoice.create(name: ' Coco Runners ', teamType: 'club'),
    );
    expect(create['team'], {
      'create': {'name': 'Coco Runners', 'teamType': 'club'},
    });
    final join = registrationBody(
      eventId: 'evt_1',
      lines: const {'tt_std': 1},
      participants: const [],
      fields: const ParticipantFields(),
      team: const TeamChoice.join('ab12-cd34'),
    );
    expect(join['team'], {'joinCode': 'AB12CD34'});
    expect(
      registrationBody(
        eventId: 'evt_1',
        lines: const {'tt_std': 1},
        participants: const [],
        fields: const ParticipantFields(),
      ).containsKey('team'),
      isFalse,
    );
  });

  test('EventTeam parses the lookup and the detail shapes', () {
    final t = EventTeam.fromJson(teamJson());
    expect(t.name, 'Coco Runners');
    expect(t.joinCode, 'AB12CD34');
    expect(t.captainName, 'Asha M.');
    expect(t.members.map((m) => m.name), ['Asha M.', 'Juma K.']);
    expect(t.members.first.role, 'captain');
    expect(EventTeam.fromJson(teamJson(joinCode: null)).joinCode, isNull);
  });

  apiTest('captain sees members, the code and can copy it', (
    tester,
    api,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    api.on('GET /me/event-teams/team_1', {'team': teamJson()});
    final host = await _pump(tester, api);
    expect(find.text('Coco Runners'), findsOneWidget);
    expect(find.text('Community / friends · 2/50 members'), findsOneWidget);
    expect(find.text('AB12-CD34'), findsOneWidget);
    expect(find.byKey(const Key('team-member-reg_1')), findsOneWidget);
    expect(find.text('Asha M.'), findsOneWidget);
    expect(find.text('Juma K.'), findsOneWidget);
    expect(find.text('Captain'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('team-code-copy')));
    expect(copied, 'AB12-CD34');
    expect(host.snack(host.tr('common.copied')), findsOneWidget);
  });

  apiTest('a member (not captain) sees no code', (tester, api) async {
    api.on(
      'GET /me/event-teams/team_1',
      teamJson(joinCode: null, isCaptain: false),
    );
    await _pump(tester, api);
    expect(find.byKey(const Key('team-code-card')), findsNothing);
    expect(find.text('Juma K.'), findsOneWidget);
  });

  apiTest('404 → not found', (tester, api) async {
    api.fail('GET /me/event-teams/team_1', 404, {'error': 'team_not_found'});
    await _pump(tester, api);
    expect(find.byKey(const Key('team-gone')), findsOneWidget);
  });
}
