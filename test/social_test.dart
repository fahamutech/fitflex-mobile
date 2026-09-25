import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_community_page.dart';
import 'package:fitflexmobile/screens/member/member_group_page.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/member/member_shared_activity_page.dart';
import 'package:fitflexmobile/screens/member/widgets/share_picker.dart';
import 'package:fitflexmobile/shared/activity/manual_activity_log.dart';
import 'package:fitflexmobile/shared/activity/activity.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _item({
  String id = 'a1',
  String owner = 'ben',
  String rel = 'friends',
  int kudos = 0,
  bool mine = false,
}) => {
  'activity': {
    'id': id,
    'userId': owner,
    'type': 'running',
    'startedAt': '2026-09-25T05:00:00.000Z',
    'durationMinutes': 28,
    'distanceKm': 5.2,
    'movingSeconds': 1680,
    'elevationGainM': 12,
    'splits': [330, 320, 340, 330, 340],
    'title': 'Morning run',
  },
  'owner': {
    'id': owner,
    'displayName': owner == 'ben' ? 'Ben Mushi' : 'Ana',
    'relationship': mine ? 'you' : rel,
  },
  'kudos': kudos,
  'youKudoed': false,
  'comments': 1,
};

class _Api extends ApiClient {
  final calls = <String>[];
  List<Map<String, dynamic>> feedItems = [_item()];
  List<Map<String, dynamic>> groups = [];
  Map<String, dynamic> conn = {
    'friends': [
      {'id': 'ben', 'displayName': 'Ben Mushi', 'relationship': 'friends'},
    ],
    'following': [],
    'followers': [
      {'id': 'cy', 'displayName': 'Cy Juma', 'relationship': 'follows_you'},
    ],
  };

  @override
  Future<Map<String, dynamic>> feed({String? before}) async => {
    'items': feedItems,
    'next': null,
  };
  @override
  Future<Map<String, dynamic>> kudos(String id, bool on) async {
    calls.add('kudos:$id:$on');
    return {'kudos': on ? 1 : 0, 'youKudoed': on, 'comments': 1};
  }

  @override
  Future<Map<String, dynamic>> connections() async => conn;
  @override
  Future<Map<String, dynamic>> socialSettings() async => {
    'defaultShare': null,
    'inviteCode': 'AB12CD34',
    'hasCompany': true,
    'blocked': [],
  };
  @override
  Future<Map<String, dynamic>> follow(String userId) async {
    calls.add('follow:$userId');
    conn = {
      ...conn,
      'followers': [],
      'friends': [
        ...(conn['friends'] as List),
        {'id': userId, 'displayName': 'Cy Juma', 'relationship': 'friends'},
      ],
    };
    return {};
  }

  @override
  Future<Map<String, dynamic>> findPeople({String? q, String? code}) async {
    calls.add('find:${q ?? ''}:${code ?? ''}');
    return {
      'people': [
        {'id': 'dee', 'displayName': 'Dee Kweka', 'relationship': 'none'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> myGroups() async => {'groups': groups};
  @override
  Future<Map<String, dynamic>> discoverGroups({String q = ''}) async => {
    'groups': [
      {
        'id': 'g_open',
        'name': 'Dar Runners',
        'joinPolicy': 'open',
        'discoverable': true,
        'memberCount': 12,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> joinGroup({
    String? groupId,
    String? inviteCode,
  }) async {
    calls.add('join:${groupId ?? ''}:${inviteCode ?? ''}');
    return {
      'group': {
        'id': groupId ?? 'g_code',
        'name': 'Club',
        'you': {'role': 'member', 'status': 'active'},
      },
    };
  }

  @override
  Future<Map<String, dynamic>> sharedActivity(String id) async => {
    'item': _item(id: id),
    'comments': [
      {
        'id': 'c1',
        'text': 'Strong pace!',
        'createdAt': '2026-09-25T06:00:00.000Z',
        'author': {'id': 'ana', 'displayName': 'Ana'},
        'canDelete': true,
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> addComment(String id, String text) async {
    calls.add('comment:$id:$text');
    return {};
  }

  @override
  Future<Map<String, dynamic>> groupDetail(
    String id, {
    String? scope,
    String? gymId,
  }) async => {
    'group': {
      'id': id,
      'name': 'PT clients',
      'joinPolicy': 'approval',
      'memberCount': 1,
      'inviteCode': 'ZX98YW76',
      'canManage': scope == null,
    },
    'members': [
      {
        'id': 'ben',
        'displayName': 'Ben Mushi',
        'role': 'member',
        'status': 'active',
      },
      {
        'id': 'cy',
        'displayName': 'Cy Juma',
        'role': 'member',
        'status': 'pending',
      },
    ],
  };
  @override
  Future<Map<String, dynamic>> groupMemberAction(
    String id,
    String userId,
    String action, {
    String? scope,
    String? gymId,
  }) async {
    calls.add('member:$scope:$userId:$action');
    return {};
  }

  @override
  Future<Map<String, dynamic>> shareActivity(
    String activityId,
    Object? shareWith,
  ) async {
    calls.add('share:$activityId:$shareWith');
    return {'activityId': activityId, 'shareWith': shareWith};
  }
}

Widget _app(ApiClient api, Widget child, {MemberData? data}) => AppScope(
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
      home: MemberDataScope(data: data ?? MemberData(), child: child),
    ),
  ),
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 4200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  test('models: private is null; share round-trips', () {
    expect(ShareWith.fromJson(null), isNull);
    expect(
      ShareWith.fromJson({'followers': false, 'groups': [], 'company': false}),
      isNull,
    );
    final s = ShareWith.fromJson({
      'followers': true,
      'groups': ['g1'],
      'company': false,
    })!;
    expect(s.groups, ['g1']);
    expect(ShareWith.wire(s), {
      'followers': true,
      'groups': ['g1'],
      'company': false,
    });
    expect(ShareWith.wire(const ShareWith()), isNull);
    final item = FeedItem.fromJson(_item());
    expect(item.owner.relationship, Relationship.friends);
    expect(item.activity.distanceKm, 5.2);
    expect(Relationship.fromWire('follows_you'), Relationship.followsYou);
    final g = SocialGroup.fromJson({
      'id': 'g',
      'name': 'X',
      'you': {'role': 'admin', 'status': 'pending'},
    });
    expect(g.isPending, isTrue);
  });

  test('a manual log sends who can see it only when chosen', () {
    final base = ManualActivityDraft(
      type: ActivityType.walking,
      startedAt: DateTime(2026, 9, 25),
      steps: 100,
    );
    expect(
      base.toJson().containsKey('shareWith'),
      isFalse,
      reason: 'left out: the default applies',
    );
    final private = ManualActivityDraft(
      type: ActivityType.walking,
      startedAt: DateTime(2026, 9, 25),
      steps: 100,
      shareChosen: true,
    );
    expect(private.toJson()['shareWith'], isNull);
    expect(private.toJson().containsKey('shareWith'), isTrue);
  });

  testWidgets('feed: what friends shared, with kudos', (tester) async {
    _tall(tester);
    final api = _Api();
    await tester.pumpWidget(_app(api, const MemberCommunityPage()));
    await tester.pumpAndSettle();
    expect(find.text('Ben Mushi'), findsOneWidget);
    expect(find.text('Morning run'), findsOneWidget);
    expect(find.textContaining('5.20 km'), findsOneWidget);
    expect(find.textContaining('5:23 /km'), findsOneWidget);
    await tester.tap(find.byKey(const Key('kudos-a1')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('kudos:a1:true'));
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('empty feed explains how to start', (tester) async {
    final api = _Api()..feedItems = [];
    await tester.pumpWidget(_app(api, const MemberCommunityPage()));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('feed-empty')), findsOneWidget);
  });

  testWidgets('people: invite code, follow back, search by code', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api();
    await tester.pumpWidget(
      _app(api, const MemberCommunityPage(initialTab: 1)),
    );
    await tester.pumpAndSettle();
    expect(find.text('AB12CD34'), findsOneWidget);
    expect(find.text('Follow back'), findsOneWidget);
    await tester.tap(find.byKey(const Key('follow-cy')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('follow:cy'));
    expect(find.text('Follow back'), findsNothing);

    await tester.enterText(find.byKey(const Key('people-search')), 'QW12ER34');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(
      api.calls,
      contains('find::QW12ER34'),
      reason: 'eight letters and digits are an invite code',
    );
    expect(find.text('Dee Kweka'), findsOneWidget);
  });

  testWidgets('groups: join a listed group, or by code', (tester) async {
    _tall(tester);
    final api = _Api();
    await tester.pumpWidget(
      _app(api, const MemberCommunityPage(initialTab: 2)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dar Runners'), findsOneWidget);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(api.calls, contains('join:g_open:'));

    await tester.tap(find.byKey(const Key('group-join-code')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('ask-text')), 'ZX98YW76');
    await tester.tap(find.byKey(const Key('ask-text-ok')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('join::ZX98YW76'));
  });

  testWidgets('shared activity: comments and adding one', (tester) async {
    _tall(tester);
    final api = _Api();
    await tester.pumpWidget(
      _app(api, const MemberSharedActivityPage(activityId: 'a1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Strong pace!'), findsOneWidget);
    expect(find.byKey(const Key('run-splits')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('comment-input')), 'Nice one');
    await tester.tap(find.byKey(const Key('comment-send')));
    await tester.pumpAndSettle();
    expect(api.calls, contains('comment:a1:Nice one'));
  });

  testWidgets(
    'a trainer manages their group but is told they see no activity',
    (tester) async {
      _tall(tester);
      final api = _Api();
      await tester.pumpWidget(
        _app(api, const GroupPage(groupId: 'g1', scope: 'trainer')),
      );
      await tester.pumpAndSettle();
      expect(find.text('ZX98YW76'), findsOneWidget);
      expect(
        find.textContaining('you don\'t see anyone\'s activity'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('approve-cy')));
      await tester.pumpAndSettle();
      expect(api.calls, contains('member:trainer:cy:approve'));
    },
  );

  testWidgets('who can see this: pick friends, a group and the company', (
    tester,
  ) async {
    _tall(tester);
    final api = _Api()
      ..groups = [
        {
          'id': 'g1',
          'name': 'Dar Runners',
          'memberCount': 3,
          'you': {'role': 'member', 'status': 'active'},
        },
      ];
    ({ShareWith? share, bool cancelled})? result;
    await tester.pumpWidget(
      _app(
        api,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await pickShare(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.textContaining('never shared'), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-friends')));
    await tester.tap(find.byKey(const Key('share-group-g1')));
    await tester.tap(find.byKey(const Key('share-company')));
    await tester.tap(find.byKey(const Key('share-done')));
    await tester.pumpAndSettle();
    expect(result!.cancelled, isFalse);
    expect(result!.share!.toJson(), {
      'followers': true,
      'groups': ['g1'],
      'company': true,
    });
  });
}
