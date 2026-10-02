// Owner communications — Communication Center and the campaign flow.
// Controllers are tested with a fake repository; screens are pumped with
// the same fake so no network is involved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/screens/owner/communications/campaign_composer_page.dart';
import 'package:fitflexmobile/screens/owner/communications/communication_center_page.dart';
import 'package:fitflexmobile/screens/owner/communications/communication_controller.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_models.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

class _FakeRepo extends CommunicationRepository {
  _FakeRepo() : super(ApiClient(baseUrl: 'http://localhost:0'));

  int count = 3;
  final countCalls = <Map<String, dynamic>>[];
  final created = <Map<String, dynamic>>[];
  final updated = <Map<String, dynamic>>[];
  final sends = <String>[];
  final schedules = <DateTime>[];
  Object? sendError;
  Campaign? existing;
  List<Campaign> list = const [];
  ChannelAvailability channels = const ChannelAvailability(push: true);

  Campaign _c(String status) => Campaign(
    id: 'cmp_1',
    name: 'x',
    status: CampaignStatus.parse(status),
    scheduledAt: schedules.isEmpty ? null : schedules.last,
  );

  @override
  Future<CommunicationOverview> overview({String? gymId}) async =>
      CommunicationOverview(
        members: 42,
        campaigns: const {CampaignStatus.draft: 2, CampaignStatus.sent: 5},
        recent: list,
        channels: channels,
      );

  @override
  Future<List<Campaign>> campaigns({
    String? gymId,
    CampaignStatus? status,
  }) async => list.where((c) => status == null || c.status == status).toList();

  @override
  Future<CampaignDetail> campaign(String id) async =>
      CampaignDetail(campaign: existing!);

  @override
  Future<AudienceCount> audienceCount({
    String? gymId,
    required CampaignAudience audience,
    CampaignPurpose? purpose,
  }) async {
    countCalls.add(audience.toJson());
    return AudienceCount(count: count, sample: const ['Asha Mushi', 'Bakari']);
  }

  @override
  Future<CampaignPreview> preview(Map<String, dynamic> draft) async =>
      CampaignPreview(
        counts: CampaignCounts(
          targeted: count,
          queued: count,
          byChannel: {
            CommChannel.inApp: (queued: count, skipped: 0),
            CommChannel.push: (queued: 1, skipped: count - 1),
          },
        ),
        example: RenderedMessage(
          title: 'Hi Asha Mushi',
          body: 'Renew at Kilele',
          memberName: 'Asha Mushi',
          ctaLabel: 'Renew',
        ),
        largeSendThreshold: 200,
      );

  @override
  Future<Campaign> create(Map<String, dynamic> draft) async {
    created.add(draft);
    return _c('draft');
  }

  @override
  Future<Campaign> update(String id, Map<String, dynamic> draft) async {
    updated.add(draft);
    return _c('draft');
  }

  @override
  Future<Campaign> send(
    String id, {
    required String sendRequestId,
    bool confirmLargeSend = false,
  }) async {
    sends.add('$sendRequestId:$confirmLargeSend');
    final e = sendError;
    if (e != null) {
      sendError = null;
      throw e;
    }
    return _c('sending');
  }

  @override
  Future<Campaign> schedule(
    String id,
    DateTime at, {
    bool confirmLargeSend = false,
  }) async {
    schedules.add(at);
    return _c('scheduled');
  }
}

CampaignComposerController _composer(_FakeRepo repo, {DateTime? now}) =>
    CampaignComposerController(
      repo,
      gymId: 'gym_1',
      channelsAvailable: repo.channels,
      countDebounce: Duration.zero,
      clock: now == null ? null : () => now,
    );

void _fillMessage(CampaignComposerController c) {
  c.setPurpose(CampaignPurpose.renewal);
  c.setContent(
    const CampaignContent(
      title: 'Your {{plan_name}} plan',
      body: 'Hi {{member_name}}',
    ),
  );
}

void main() {
  test('a blank-placeholder warning says which value, and for how many', () {
    final some = CampaignWarning.fromJson({
      'code': 'empty_value',
      'variable': 'expiry_date',
      'count': 2,
      'of': 7,
    });
    expect((some.variable, some.count, some.of), ('expiry_date', 2, 7));
    expect(some.blankForAll, isFalse);
    final all = CampaignWarning.fromJson({
      'code': 'empty_value',
      'variable': 'expiry_date',
      'count': 7,
      'of': 7,
    });
    expect(all.blankForAll, isTrue);
    expect(
      CampaignWarning.fromJson({'code': 'large_send', 'count': 7}).blankForAll,
      isFalse,
    );
    final en = FFLocale();
    expect(
      en.t('comms.warn.empty_value_all'),
      contains('Type it into the message'),
    );
    expect(en.t('comms.var.expiry_date'), 'End date');
  });
  group('audience refinements', () {
    test('build the backend filter and read it back', () {
      const r = AudienceRefinements(
        expiresWithinDays: 7,
        noVisitForDays: 14,
        plans: {'weekly', 'monthly'},
        gender: 'female',
        minAge: 18,
        maxAge: 25,
      );
      final f = r.toFilter()!;
      final all = f['all'] as List;
      expect(all.first, {
        'field': 'daysUntilExpiry',
        'op': 'between',
        'value': [0, 7],
      });
      expect((all[1] as Map)['any'], isA<List>());
      expect(all[2], {
        'field': 'plan',
        'op': 'in',
        'value': ['monthly', 'weekly'],
      });
      final back = AudienceRefinements.fromFilter(f)!;
      expect(back.expiresWithinDays, 7);
      expect(back.noVisitForDays, 14);
      expect(back.plans, {'weekly', 'monthly'});
      expect(back.gender, 'female');
      expect((back.minAge, back.maxAge), (18, 25));
    });

    test(
      'no refinements means no filter; foreign filters are not guessed at',
      () {
        expect(const AudienceRefinements().toFilter(), isNull);
        expect(
          AudienceRefinements.fromFilter({
            'any': [
              {'field': 'age', 'op': 'gte', 'value': 1},
            ],
          }),
          isNull,
        );
      },
    );
  });

  group('composer', () {
    test('each step unlocks only when it is complete', () async {
      final repo = _FakeRepo();
      final c = _composer(repo);
      expect(c.canContinue(ComposerStep.purpose), isFalse);
      c.setPurpose(CampaignPurpose.promotion);
      expect(c.canContinue(ComposerStep.purpose), isTrue);

      await c.refreshCount();
      expect(c.canContinue(ComposerStep.audience), isTrue);
      repo.count = 0;
      await c.refreshCount();
      expect(
        c.canContinue(ComposerStep.audience),
        isFalse,
        reason: 'nobody to send to',
      );

      c.setContent(
        const CampaignContent(title: 'Deal', body: '{{discount}} off'),
      );
      expect(c.missingSenderValues, ['discount']);
      expect(c.canContinue(ComposerStep.message), isFalse);
      c.setContent(c.content.copyWith(discount: () => '20%'));
      expect(c.canContinue(ComposerStep.message), isTrue);
      c.setContent(c.content.copyWith(body: 'Hi {{shoe_size}}'));
      expect(c.unknownVariables, ['shoe_size']);
      expect(c.canContinue(ComposerStep.message), isFalse);
    });

    test(
      'changing the audience recounts with the preset and conditions',
      () async {
        final repo = _FakeRepo();
        final c = _composer(repo);
        c.setPreset('expiring');
        c.setRefinements(const AudienceRefinements(noVisitForDays: 14));
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);
        expect(repo.countCalls.last['preset'], 'expiring');
        expect(repo.countCalls.last['filter'], isNotNull);
      },
    );

    test('WhatsApp cannot be picked until it is set up', () {
      final c = _composer(_FakeRepo());
      c.toggleChannel(CommChannel.whatsapp, true);
      expect(c.channels, {CommChannel.inApp});
      c.toggleChannel(CommChannel.push, true);
      expect(c.channels, {CommChannel.inApp, CommChannel.push});
    });

    test(
      'Send saves then sends; retrying never creates or sends a second campaign',
      () async {
        final repo = _FakeRepo();
        final c = _composer(repo);
        _fillMessage(c);
        repo.sendError = Exception('connection lost');
        expect(await c.submit(), isNull);
        expect(c.submitError, isNotNull);
        final result = await c.submit();
        expect(result?.status, CampaignStatus.sending);
        expect(repo.created, hasLength(1), reason: 'the draft is created once');
        expect(
          repo.updated,
          isEmpty,
          reason: 'nothing changed, nothing to save',
        );
        expect(repo.sends, hasLength(2));
        expect(
          repo.sends.toSet(),
          hasLength(1),
          reason: 'the retry repeats the same send request',
        );
      },
    );

    test('a large audience must be confirmed before sending', () async {
      final repo = _FakeRepo();
      final c = _composer(repo);
      _fillMessage(c);
      repo.sendError = ApiException(409, {
        'error': 'confirm_large_send',
        'count': 250,
      });
      await c.submit();
      expect(c.needsLargeSendConfirm, isTrue);
      expect(c.canContinue(ComposerStep.confirm), isFalse);
      c.setConfirmLargeSend(true);
      expect(c.canContinue(ComposerStep.confirm), isTrue);
      await c.submit();
      expect(repo.sends.last, endsWith(':true'));
    });

    test('scheduling needs a time at least 5 minutes ahead', () async {
      final now = DateTime(2026, 10, 1, 9);
      final repo = _FakeRepo();
      final c = _composer(repo, now: now);
      _fillMessage(c);
      c.setScheduleLater(true);
      c.setScheduledAt(now.add(const Duration(minutes: 2)));
      expect(c.canContinue(ComposerStep.schedule), isFalse);
      c.setScheduledAt(now.add(const Duration(days: 1)));
      expect(c.canContinue(ComposerStep.schedule), isTrue);
      final r = await c.submit();
      expect(r?.status, CampaignStatus.scheduled);
      expect(repo.schedules.single, now.add(const Duration(days: 1)));
      expect(repo.sends, isEmpty);
    });

    test('editing a draft keeps its id and saves only what changed', () async {
      final repo = _FakeRepo();
      final c = CampaignComposerController(
        repo,
        existing: Campaign(
          id: 'cmp_9',
          name: 'Old',
          status: CampaignStatus.draft,
          gymId: 'gym_1',
          purpose: CampaignPurpose.announcement,
          audience: const CampaignAudience(
            preset: 'active',
            filter: {
              'all': [
                {
                  'field': 'daysUntilExpiry',
                  'op': 'between',
                  'value': [0, 3],
                },
              ],
            },
          ),
          content: const CampaignContent(
            title: 'Closed Friday',
            body: 'See you Saturday',
          ),
          channels: const [CommChannel.inApp],
        ),
      );
      expect(c.campaignId, 'cmp_9');
      expect(c.refinements.expiresWithinDays, 3);
      expect(await c.saveDraft(), 'cmp_9');
      expect(repo.created, isEmpty);
      expect(repo.updated, isEmpty);
      c.setContent(c.content.copyWith(title: 'Closed Friday afternoon'));
      await c.saveDraft();
      expect(
        repo.updated.single['content']['title'],
        'Closed Friday afternoon',
      );
      expect(repo.updated.single.containsKey('gymId'), isFalse);
    });
  });

  group('screens', () {
    Widget app(Widget home, {GoRouter? router}) {
      final locale = FFLocale();
      return FFLocaleScope(
        notifier: locale,
        child: router != null
            ? MaterialApp.router(routerConfig: router)
            : MaterialApp(home: home),
      );
    }

    testWidgets('Communication Center shows reach, channels and campaigns', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo()
        ..list = [
          const Campaign(
            id: 'c1',
            name: 'a',
            status: CampaignStatus.draft,
            title: 'October offer',
          ),
          const Campaign(
            id: 'c2',
            name: 'b',
            status: CampaignStatus.sent,
            title: 'Closed Friday',
          ),
        ];
      await tester.pumpWidget(
        app(CommunicationCenterPage(gymId: 'gym_1', repository: repo)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Messages to members'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(
        find.text('Coming soon'),
        findsOneWidget,
        reason: 'WhatsApp is not set up yet',
      );
      expect(find.text('October offer'), findsOneWidget);

      await tester.tap(find.text('Campaigns'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('filter-sent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-sent')));
      await tester.pumpAndSettle();
      expect(find.text('Closed Friday'), findsOneWidget);
      expect(find.text('October offer'), findsNothing);
    });

    testWidgets('the full flow: purpose → … → send', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(tester.view.reset);
      final repo = _FakeRepo();
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(
            path: '/new',
            builder: (_, _) =>
                CampaignComposerPage(gymId: 'gym_1', repository: repo),
          ),
          GoRoute(
            path: '/owner/communications/campaigns/:id',
            builder: (_, s) =>
                Scaffold(body: Text('detail ${s.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(app(const SizedBox(), router: router));
      await tester.pumpAndSettle();

      Future<void> next() async {
        await tester.tap(find.byKey(const Key('comms-next')));
        await tester.pumpAndSettle();
      }

      await tester.tap(find.byKey(const Key('purpose-renewal')));
      await tester.pumpAndSettle();
      await next();
      expect(find.text('3 members match this audience.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('preset-expiring')));
      await tester.pumpAndSettle();
      await next();

      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('msg-title-en')),
          matching: find.byType(TextField),
        ),
        'Your plan ends soon',
      );
      await tester.enterText(
        find.descendant(
          of: find.byKey(const Key('msg-body-en')),
          matching: find.byType(TextField),
        ),
        'Hi ',
      );
      await tester.tap(find.byKey(const Key('var-member_name')));
      await tester.pumpAndSettle();
      await next();

      expect(
        find.text('Coming soon — FitFlex is setting up WhatsApp.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('channel-push')));
      await tester.pumpAndSettle();
      await next(); // schedule: send now
      await next(); // preview
      expect(find.byKey(const Key('preview-in-app')), findsOneWidget);
      expect(find.byKey(const Key('preview-push')), findsOneWidget);
      expect(find.text('How Asha Mushi will see it'), findsOneWidget);
      await next(); // confirm
      expect(find.text('Reaches 1 of 3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('comms-submit')));
      await tester.pumpAndSettle();
      expect(repo.created.single['content']['body'], 'Hi {{member_name}}');
      expect(repo.created.single['audience']['preset'], 'expiring');
      expect(repo.created.single['channels'], ['in_app', 'push']);
      expect(repo.sends, hasLength(1));
      expect(find.text('detail cmp_1'), findsOneWidget);
    });
  });

  test('every communications string has a Swahili translation', () {
    final en = FFLocale.keysOf('en').where((k) => k.startsWith('comms.'));
    final sw = FFLocale.keysOf('sw');
    expect(en, isNotEmpty);
    expect(en.where((k) => !sw.contains(k)), isEmpty);
  });
}
