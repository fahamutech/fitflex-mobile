// Owner communications — history (M8): the models, a member's Messages
// section and timeline, a campaign's numbers and recipients, and one message
// in full. Screens run on a fake repository, so no network is involved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/screens/owner/communications/campaign_detail_page.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_models.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_repository.dart';
import 'package:fitflexmobile/screens/owner/communications/data/history_models.dart';
import 'package:fitflexmobile/screens/owner/communications/history_pages.dart';
import 'package:fitflexmobile/screens/owner/communications/widgets/history_widgets.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

Map<String, dynamic> _msg(
  String id,
  String channel,
  String status, {
  String? failure,
  String? skip,
  Map<String, dynamic>? provider,
}) => {
  'id': id,
  'memberId': 'usr_n',
  'memberName': 'Neema Mushi',
  'campaignId': 'cmp_1',
  'campaignName': 'October renewals',
  'channel': channel,
  'category': 'transactional',
  'messageType': 'renewal',
  'title': 'Your plan ends soon',
  'body': 'Hi Neema, renew at Simba Gym.',
  'status': status,
  'failureReason': ?failure,
  'skipReason': ?skip,
  'failurePermanent': failure != null,
  'provider': provider ?? {'name': 'inbox', 'messageId': 'ntf_1'},
  'createdAt': '2026-09-20T08:00:00.000Z',
  'sentAt': status == 'failed' ? null : '2026-09-20T08:00:05.000Z',
  'failedAt': status == 'failed' ? '2026-09-20T08:01:00.000Z' : null,
};

final _item = CommunicationItem.fromJson({
  'key': 'cmp_1',
  'campaignId': 'cmp_1',
  'campaignName': 'October renewals',
  'category': 'transactional',
  'messageType': 'renewal',
  'title': 'Your plan ends soon',
  'body': 'Hi Neema, renew at Simba Gym.',
  'createdAt': '2026-09-20T08:00:00.000Z',
  'outcome': 'reached',
  'channels': [
    _msg('m_in', 'in_app', 'clicked'),
    _msg(
      'm_wa',
      'whatsapp',
      'failed',
      failure: 'invalid_recipient',
      provider: {
        'name': 'whatsapp',
        'templateName': 'fitflex_renewal_reminder',
        'language': 'sw',
      },
    ),
  ],
});

class _FakeRepo extends CommunicationRepository {
  _FakeRepo() : super(ApiClient(baseUrl: 'http://localhost:0'));

  final timelineCalls = <(HistoryFilter, String?)>[];
  final recipientCalls = <(HistoryFilter, String?)>[];
  Object? timelineError;
  final duplicated = <String>[];

  @override
  Future<Campaign> duplicate(String id) async {
    duplicated.add(id);
    return Campaign(
      id: 'cmp_copy',
      name: 'Renewal reminder (copy)',
      status: CampaignStatus.draft,
    );
  }

  @override
  Future<HistoryPage<CommunicationItem>> memberCommunications(
    String memberId, {
    HistoryFilter filter = const HistoryFilter(),
    String? cursor,
    int limit = 20,
  }) async {
    timelineCalls.add((filter, cursor));
    final e = timelineError;
    if (e != null) throw e;
    if (filter.channel == CommChannel.push) return const HistoryPage([], null);
    return cursor == null
        ? HistoryPage([_item], 'next')
        : HistoryPage([
            CommunicationItem.fromJson({
              'key': 'cmp_0',
              'title': 'Welcome',
              'outcome': 'skipped',
              'channels': [_msg('m_old', 'push', 'skipped', skip: 'no_device')],
            }),
          ], null);
  }

  @override
  Future<HistoryPage<Recipient>> recipients(
    String campaignId, {
    HistoryFilter filter = const HistoryFilter(),
    String? cursor,
    int limit = 20,
  }) async {
    recipientCalls.add((filter, cursor));
    final all = [
      Recipient.fromJson({
        'memberId': 'usr_j',
        'memberName': 'Juma Said',
        'outcome': 'pending',
        'channels': [_msg('m_j', 'in_app', 'queued')],
      }),
      Recipient.fromJson({
        'memberId': 'usr_n',
        'memberName': 'Neema Mushi',
        'outcome': 'reached',
        'channels': _item.channels
            .map(
              (m) => {
                'id': m.id,
                'memberId': 'usr_n',
                'channel': m.channel!.wire,
                'status': m.status,
                'failureReason': m.failureReason,
              },
            )
            .toList(),
      }),
    ];
    final search = filter.search?.toLowerCase();
    return HistoryPage(
      all
          .where(
            (r) =>
                search == null || r.memberName!.toLowerCase().contains(search),
          )
          .where(
            (r) =>
                filter.status != 'failed' ||
                r.channels.any((c) => c.status == 'failed'),
          )
          .toList(),
      null,
    );
  }

  @override
  Future<CommMessage> message(String id) async => id == 'm_retry'
      ? CommMessage.fromJson({
          ..._msg(id, 'push', 'queued', failure: 'push_failed'),
          'failurePermanent': false,
          'nextAttemptAt': '2026-09-20T08:06:00.000Z',
        })
      : CommMessage.fromJson({
          ..._msg(
            id,
            'whatsapp',
            'failed',
            failure: 'invalid_recipient',
            provider: {
              'name': 'whatsapp',
              'messageId': 'wamid.HBgM',
              'templateName': 'fitflex_renewal_reminder',
              'language': 'sw',
            },
          ),
          'template': {
            'id': 'tpl_sys_renewal_reminder',
            'key': 'renewal_reminder',
            'name': 'renewal_reminder',
            'system': true,
          },
        });

  @override
  Future<CampaignDetail> campaign(String id) async => CampaignDetail.fromJson({
    'campaign': {
      'id': id,
      'name': 'October renewals',
      'status': 'sent',
      'purpose': 'renewal',
      'channels': ['in_app', 'whatsapp'],
      'content': {'title': 'Your plan ends soon', 'body': 'Hi'},
      'createdByName': 'Owner Asha',
      'template': {'key': 'renewal_reminder', 'name': 'x', 'system': true},
      'createdAt': '2026-09-20T08:00:00.000Z',
    },
    'progress': {
      'in_app': {'clicked': 1, 'queued': 1},
      'whatsapp': {'failed': 1},
    },
    'stats': {
      'targeted': 2,
      'messages': 3,
      'totals': {
        'pending': 1,
        'sent': 1,
        'delivered': 1,
        'opened': 1,
        'clicked': 1,
        'failed': 1,
        'skipped': 0,
      },
    },
  });
}

Widget _app(GoRouter router) => FFLocaleScope(
  notifier: FFLocale(),
  child: MaterialApp.router(routerConfig: router),
);

GoRouter _router(Widget home, {List<GoRoute> extra = const []}) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    ...extra,
  ],
);

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  group('models', () {
    test('a message keeps its provider reference, failure and times', () {
      final m = _item.channels[1];
      expect(m.channel, CommChannel.whatsapp);
      expect(m.isFailed, isTrue);
      expect(m.failureReason, 'invalid_recipient');
      expect(m.provider.templateName, 'fitflex_renewal_reminder');
      expect(m.failedAt, isNotNull);
      expect(_item.messageType, CampaignPurpose.renewal);
    });

    test('campaign stats and the campaign\'s creator and template', () {
      final c = Campaign.fromJson({
        'id': 'c',
        'name': 'n',
        'status': 'sent',
        'createdByName': 'Owner Asha',
        'stats': {
          'targeted': 4,
          'totals': {'sent': 3, 'failed': 1},
        },
      });
      expect(c.createdByName, 'Owner Asha');
      expect(c.stats!.targeted, 4);
      expect(c.stats!.totals.failed, 1);
      expect(Campaign.fromJson({'id': 'd', 'status': 'draft'}).stats, isNull);
    });

    test('filters become query parameters; dates are whole days', () {
      final f = HistoryFilter(
        channel: CommChannel.whatsapp,
        status: 'failed',
        category: 'marketing',
        from: DateTime(2026, 9, 1),
        to: DateTime(2026, 9, 7, 18),
        search: ' neema ',
      );
      expect(f.toQuery(), {
        'channel': 'whatsapp',
        'status': 'failed',
        'category': 'marketing',
        'from': '2026-09-01',
        'to': '2026-09-07',
        'search': 'neema',
      });
      expect(const HistoryFilter().isEmpty, isTrue);
      expect(f.copyWith(status: () => null).status, isNull);
    });
  });

  group('screens', () {
    testWidgets('the member timeline filters, loads more and opens a message', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        _app(
          _router(
            MemberCommunicationsPage(memberId: 'usr_n', repository: repo),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your plan ends soon'), findsOneWidget);
      expect(find.text('Reached'), findsWidgets);
      expect(
        find.text('The number can’t receive WhatsApp'),
        findsOneWidget,
        reason: 'why a channel failed shows in the timeline',
      );

      await tester.tap(find.byKey(const Key('history-more')));
      await tester.pumpAndSettle();
      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('No phone with the app'), findsOneWidget);
      expect(repo.timelineCalls.last.$2, 'next');

      await tester.tap(find.byKey(const Key('hist-channel-push')));
      await tester.pumpAndSettle();
      expect(repo.timelineCalls.last.$1.channel, CommChannel.push);
      expect(
        repo.timelineCalls.last.$2,
        isNull,
        reason: 'a new filter starts over',
      );
      expect(find.byKey(const Key('history-empty')), findsOneWidget);
      expect(find.text('Try other filters.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('hist-channel-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('msg-m_wa')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('message-detail')), findsOneWidget);
      expect(find.byKey(const Key('message-why')), findsOneWidget);
      expect(find.textContaining('won’t be tried again'), findsOneWidget);
      expect(find.text('wamid.HBgM'), findsOneWidget);
      expect(find.text('Renewal reminder'), findsWidgets);
    });

    testWidgets('the Messages card shows the latest messages, or nothing '
        'without permission', (tester) async {
      _tall(tester);
      final repo = _FakeRepo();
      final router = _router(
        Scaffold(
          body: ListView(
            children: [MemberMessagesCard(memberId: 'usr_n', repository: repo)],
          ),
        ),
        extra: [
          GoRoute(
            path: '/owner/members/:id/messages',
            builder: (_, s) =>
                Scaffold(body: Text('all ${s.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member-messages')), findsOneWidget);
      expect(find.text('Your plan ends soon'), findsOneWidget);
      await tester.tap(find.byKey(const Key('member-messages-all')));
      await tester.pumpAndSettle();
      expect(find.text('all usr_n'), findsOneWidget);

      final denied = _FakeRepo()
        ..timelineError = ApiException(403, {'error': 'forbidden'});
      await tester.pumpWidget(
        _app(
          _router(
            Scaffold(
              body: ListView(
                children: [
                  MemberMessagesCard(memberId: 'usr_x', repository: denied),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('member-messages')), findsNothing);
    });

    testWidgets(
      'a sent campaign can be used again: copied, then opened to edit',
      (tester) async {
        _tall(tester);
        final repo = _FakeRepo();
        final router = _router(
          CampaignDetailPage(campaignId: 'cmp_1', repository: repo),
          extra: [
            GoRoute(
              path: '/owner/communications/campaigns/:id/edit',
              builder: (_, s) =>
                  Scaffold(body: Text('editing ${s.pathParameters['id']}')),
            ),
          ],
        );
        await tester.pumpWidget(_app(router));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.byKey(const Key('detail-duplicate')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('detail-duplicate')));
        await tester.pumpAndSettle();
        expect(repo.duplicated, ['cmp_1']);
        expect(find.text('editing cmp_copy'), findsOneWidget);
      },
    );

    testWidgets('a campaign shows its numbers, who made it, and who got it', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo();
      final router = _router(
        CampaignDetailPage(campaignId: 'cmp_1', repository: repo),
        extra: [
          GoRoute(
            path: '/owner/communications/campaigns/:id/recipients',
            builder: (_, s) => CampaignRecipientsPage(
              campaignId: s.pathParameters['id']!,
              repository: repo,
            ),
          ),
        ],
      );
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('detail-stats')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('stat-failed')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('Created by Owner Asha'), findsOneWidget);
      expect(find.textContaining('Renewal reminder'), findsWidgets);

      await tester.ensureVisible(find.byKey(const Key('detail-recipients')));
      await tester.tap(find.byKey(const Key('detail-recipients')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('recipient-usr_j')), findsOneWidget);
      expect(find.byKey(const Key('recipient-usr_n')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('hist-status-failed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hist-status-failed')));
      await tester.pumpAndSettle();
      expect(repo.recipientCalls.last.$1.status, 'failed');
      expect(find.byKey(const Key('recipient-usr_j')), findsNothing);

      await tester.ensureVisible(find.byKey(const Key('hist-status-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('hist-status-all')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('recipients-search')),
          matching: find.byType(TextField),
        ),
        'jum',
      );
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(repo.recipientCalls.last.$1.search, 'jum');
      expect(find.byKey(const Key('recipient-usr_n')), findsNothing);
    });
  });

  testWidgets('a message waiting to retry says why the last try failed', (
    tester,
  ) async {
    _tall(tester);
    late BuildContext ctx;
    await tester.pumpWidget(
      _app(
        _router(
          Builder(
            builder: (c) {
              ctx = c;
              return const Scaffold();
            },
          ),
        ),
      ),
    );
    showMessageDetail(ctx, repository: _FakeRepo(), messageId: 'm_retry');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('message-retrying')), findsOneWidget);
    expect(
      find.textContaining('The phone didn’t accept the notification'),
      findsOneWidget,
    );
    expect(find.text('Next try'), findsOneWidget);
  });

  test('every history string has a Swahili translation', () {
    final en = FFLocale.keysOf('en').where(
      (k) =>
          k.startsWith('comms.history') ||
          k.startsWith('comms.stat.') ||
          k.startsWith('comms.outcome.') ||
          k.startsWith('comms.failure.') ||
          k.startsWith('comms.provider.'),
    );
    final sw = FFLocale.keysOf('sw');
    expect(en.length, greaterThan(50));
    expect(en.where((k) => !sw.contains(k)), isEmpty);
  });
}
