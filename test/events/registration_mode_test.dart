// Events S3 (spec §5.14 registration_mode_test): options by N, the team
// sub-card (create / join by code), the corporate card, `teams:false`.
import 'package:fitflexmobile/screens/member/events/register/registration_mode_tiles.dart';
import 'package:fitflexmobile/shared/events/events_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 's3_support.dart';

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  int places = 1,
  bool teams = true,
  bool corporate = true,
  List<RegistrationWho>? changes,
}) async {
  var who = const RegistrationWho();
  return pumpPage(
    tester,
    api,
    StatefulBuilder(
      builder: (context, setState) => SingleChildScrollView(
        child: RegistrationModeTiles(
          eventId: 'evt_1',
          places: places,
          value: who,
          teamsEnabled: teams,
          corporateEnabled: corporate,
          onChanged: (v) => setState(() {
            who = v;
            changes?.add(v);
          }),
        ),
      ),
    ),
    user: member,
    size: const Size(375, 1400),
  );
}

void main() {
  group('team code helpers', () {
    test('normalise, format and validate', () {
      expect(normalizeTeamCode('ab12-cd34'), 'AB12CD34');
      expect(normalizeTeamCode(' Ab12 cd34 '), 'AB12CD34');
      expect(formatTeamCode('AB12CD34'), 'AB12-CD34');
      expect(formatTeamCode('AB1'), 'AB1');
      expect(teamCodeLooksValid('AB12-CD34'), isTrue);
      expect(teamCodeLooksValid('AB12'), isFalse);
    });
  });

  apiTest('one place: Myself and Other people; two: Myself and others', (
    tester,
    api,
  ) async {
    await _pump(tester, api, places: 1);
    expect(find.byKey(const Key('mode-self')), findsOneWidget);
    expect(find.byKey(const Key('mode-selfOthers')), findsNothing);
    expect(find.byKey(const Key('mode-others')), findsOneWidget);
    expect(find.byKey(const Key('mode-team')), findsOneWidget);
    expect(find.byKey(const Key('mode-corporate')), findsOneWidget);
    expect(find.text('Prefilled from your profile'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await _pump(tester, api, places: 2);
    expect(find.byKey(const Key('mode-self')), findsNothing);
    expect(find.byKey(const Key('mode-selfOthers')), findsOneWidget);
    expect(find.text('You take one place; add the rest'), findsOneWidget);
  });

  apiTest('tiles are radios in a group; selecting reports the mode', (
    tester,
    api,
  ) async {
    final changes = <RegistrationWho>[];
    await _pump(tester, api, changes: changes);
    final sem = tester.getSemantics(find.byKey(const Key('mode-others')));
    expect(sem.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
    await tapVisible(tester, find.byKey(const Key('mode-others')));
    expect(changes.last.mode, 'others');
  });

  apiTest('teams:false hides the Team tile; corporate:false the card', (
    tester,
    api,
  ) async {
    await _pump(tester, api, teams: false, corporate: false);
    expect(find.byKey(const Key('mode-team')), findsNothing);
    expect(find.byKey(const Key('mode-corporate')), findsNothing);
  });

  apiTest('Team reveals create (name + type) and join (code + Check)', (
    tester,
    api,
  ) async {
    api.on('POST /me/event-teams/lookup', {
      'team': {
        'id': 'team_1',
        'name': 'Coco Runners',
        'teamType': 'community',
        'memberCount': 3,
        'maxMembers': 50,
        'captain': {'firstName': 'Asha', 'lastInitial': 'M'},
      },
    });
    final changes = <RegistrationWho>[];
    await _pump(tester, api, changes: changes);
    await tapVisible(tester, find.byKey(const Key('mode-team')));
    expect(find.byKey(const Key('team-card')), findsOneWidget);
    expect(find.byKey(const Key('team-name')), findsOneWidget);
    await typeInto(tester, find.byKey(const Key('team-name')), 'Coco Runners');
    expect(changes.last.team?.isCreate, isTrue);
    expect(changes.last.team?.name, 'Coco Runners');
    expect(changes.last.teamIncomplete, isFalse);

    await tapVisible(tester, find.text('Join with a code'));
    expect(find.byKey(const Key('team-code')), findsOneWidget);
    // Join without a checked code is incomplete.
    expect(changes.last.teamIncomplete, isTrue);
    await typeInto(tester, find.byKey(const Key('team-code')), 'ab12cd34');
    expect(textOf(tester, find.byKey(const Key('team-code'))), 'AB12-CD34');
    await tapVisible(tester, find.byKey(const Key('team-check')));
    final req = api.only('POST', '/me/event-teams/lookup');
    expect(req.body, {'eventId': 'evt_1', 'joinCode': 'AB12CD34'});
    expect(find.text('Coco Runners · 3/50 members'), findsOneWidget);
    expect(changes.last.team?.joinCode, 'AB12CD34');
    expect(changes.last.teamIncomplete, isFalse);
  });

  apiTest('a wrong code shows the team-not-found copy', (tester, api) async {
    api.fail('POST /me/event-teams/lookup', 404, {'error': 'team_not_found'});
    await _pump(tester, api);
    await tapVisible(tester, find.byKey(const Key('mode-team')));
    await tapVisible(tester, find.text('Join with a code'));
    await typeInto(tester, find.byKey(const Key('team-code')), 'ab12cd34');
    await tapVisible(tester, find.byKey(const Key('team-check')));
    expect(
      find.textContaining('No team with that code for this event'),
      findsOneWidget,
    );
  });

  apiTest('the corporate card copies the portal link', (tester, api) async {
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
    final host = await _pump(tester, api);
    await tapVisible(tester, find.byKey(const Key('corporate-copy')));
    expect(copied, kFitFlexPortalUrl);
    expect(host.snack(host.tr('common.copied')), findsOneWidget);
  });
}
