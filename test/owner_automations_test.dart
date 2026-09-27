// Owner communications — automations (M9): the Automations tab (titles in
// both languages, on/off, paused), and one automation's page (channels,
// template, preview, recent firings). Fake repository, no network.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/screens/owner/communications/automation_pages.dart';
import 'package:fitflexmobile/screens/owner/communications/data/automation_models.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_models.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

Map<String, dynamic> _auto(
  String key,
  String trigger,
  int offset, {
  String status = 'disabled',
  String? paused,
  String template = 'membership_expiring',
  List<String> channels = const ['in_app', 'push', 'whatsapp'],
  Map<String, dynamic> stats = const {},
}) => {
  'id': 'aut_g_$key',
  'gymId': 'gym_1',
  'name': key,
  'trigger': trigger,
  'offsetDays': offset,
  'channels': channels,
  'status': status,
  'pausedReason': paused,
  'template': {
    'id': 'tpl_sys_$template',
    'key': template,
    'name': template,
    'system': true,
  },
  'stats': stats,
};

class _FakeRepo extends CommunicationRepository {
  _FakeRepo() : super(ApiClient(baseUrl: 'http://localhost:0'));

  final updates = <Map<String, Object?>>[];
  Object? updateError;
  late List<Map<String, dynamic>> rows = [
    _auto('payment_failed', 'payment_failed', 0, template: 'payment_failed'),
    _auto(
      'expiring_7',
      'membership_expiring',
      7,
      status: 'enabled',
      stats: {'fired': 4, 'failed': 1},
    ),
    _auto(
      'expiring_3',
      'membership_expiring',
      3,
      status: 'paused',
      paused: 'too_many_members:512',
      template: 'renewal_reminder',
    ),
    _auto(
      'expiring_1',
      'membership_expiring',
      1,
      template: 'membership_final_reminder',
    ),
    _auto('inactive_14', 'member_inactive', 14, template: 'we_miss_you'),
  ];

  @override
  Future<List<Automation>> automations({String? gymId}) async =>
      rows.map(Automation.fromJson).toList();

  @override
  Future<Automation> updateAutomation(
    String id, {
    bool? enabled,
    List<CommChannel>? channels,
    String? templateId,
  }) async {
    updates.add({
      'id': id,
      'enabled': enabled,
      'channels': channels,
      'templateId': templateId,
    });
    final e = updateError;
    if (e != null) {
      updateError = null;
      throw e;
    }
    final i = rows.indexWhere((r) => r['id'] == id);
    rows[i] = {
      ...rows[i],
      if (enabled != null) 'status': enabled ? 'enabled' : 'disabled',
      if (enabled != null) 'pausedReason': null,
      if (channels != null) 'channels': channels.map((c) => c.wire).toList(),
    };
    return Automation.fromJson(rows[i]);
  }

  @override
  Future<List<AutomationFiring>> automationRuns(String id) async => [
    AutomationFiring.fromJson({
      'id': 'run_1',
      'memberName': 'Neema Mushi',
      'status': 'queued',
      'createdAt': '2026-09-20T08:00:00.000Z',
      'channels': [
        {'channel': 'in_app', 'status': 'delivered'},
        {
          'channel': 'whatsapp',
          'status': 'skipped',
          'reason': 'whatsapp_not_configured',
        },
      ],
    }),
  ];

  @override
  Future<TemplatePreview> automationPreview(String id) async =>
      const TemplatePreview(
        senderName: 'Simba Gym',
        byLocale: {
          'en': TemplateChannelPreview(
            inApp: RenderedMessage(
              title: 'Your plan ends soon',
              body: 'Hi Amina, renew.',
            ),
            pushTitle: 'Your plan ends soon',
            pushBody: 'Hi Amina, renew.',
          ),
        },
      );

  @override
  Future<List<CommTemplate>> templates({String? gymId, String? group}) async =>
      const [
        CommTemplate(
          id: 'tpl_sys_discount_offer',
          key: 'discount_offer',
          name: 'discount_offer',
          system: true,
          group: 'marketing',
        ),
      ];
}

Widget _app(Widget home, {String lang = 'en', List<GoRoute> extra = const []}) {
  final locale = FFLocale()..set(Locale(lang));
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp.router(
      routerConfig: GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(body: ListView(children: [home])),
          ),
          ...extra,
        ],
      ),
    ),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  test('an automation paused for being too big says how many', () {
    final a = Automation.fromJson(
      _auto(
        'x',
        'membership_expiring',
        3,
        status: 'paused',
        paused: 'too_many_members:512',
      ),
    );
    expect(a.paused, isTrue);
    expect(a.pausedFor, 512);
    expect(
      Automation.fromJson(_auto('y', 'membership_expired', 0)).pausedFor,
      isNull,
    );
  });

  testWidgets(
    'the tab lists automations with titles, numbers, switches and pauses',
    (tester) async {
      _tall(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(_app(AutomationsTab(repository: repo)));
      await tester.pumpAndSettle();
      expect(find.text('Payment didn’t go through'), findsOneWidget);
      expect(find.text('Membership ends in 7 days'), findsOneWidget);
      expect(find.text('Membership ends tomorrow'), findsWidgets);
      expect(find.text('No visit for 14 days'), findsOneWidget);
      expect(find.textContaining('Last 30 days: sent to 4'), findsOneWidget);
      expect(
        find.byKey(const Key('automation-paused-membership_expiring-3')),
        findsOneWidget,
      );
      expect(find.textContaining('512 members at once'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('automation-switch-member_inactive-14')),
      );
      await tester.pumpAndSettle();
      expect(repo.updates.last, {
        'id': 'aut_g_inactive_14',
        'enabled': true,
        'channels': null,
        'templateId': null,
      });
      expect(
        tester
            .widget<Switch>(
              find.byKey(const Key('automation-switch-member_inactive-14')),
            )
            .value,
        isTrue,
      );

      await tester.tap(
        find.byKey(const Key('automation-switch-membership_expiring-3')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('automation-paused-membership_expiring-3')),
        findsNothing,
        reason: 'turning it on clears the pause',
      );
    },
  );

  testWidgets('titles are in Swahili for Swahili owners', (tester) async {
    _tall(tester);
    await tester.pumpWidget(
      _app(AutomationsTab(repository: _FakeRepo()), lang: 'sw'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Uanachama unaisha baada ya siku 7'), findsOneWidget);
    expect(find.text('Hajaja kwa siku 14'), findsOneWidget);
  });

  testWidgets(
    'one automation: channels, template, preview and who it went to',
    (tester) async {
      _tall(tester);
      final repo = _FakeRepo();
      await tester.pumpWidget(
        FFLocaleScope(
          notifier: FFLocale(),
          child: MaterialApp(
            home: AutomationDetailPage(
              automationId: 'aut_g_expiring_7',
              repository: repo,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('7 day(s) before'), findsOneWidget);
      expect(
        find.textContaining('FitFlex doesn’t send its own renewal reminder'),
        findsOneWidget,
      );
      expect(find.text('Your plan ends soon'), findsWidgets);
      expect(find.textContaining('Neema Mushi'), findsOneWidget);
      expect(find.textContaining('WhatsApp not set up yet'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('automation-channel-push')),
      );
      await tester.tap(find.byKey(const Key('automation-channel-push')));
      await tester.pumpAndSettle();
      expect(repo.updates.last['channels'], [
        CommChannel.inApp,
        CommChannel.whatsapp,
      ]);

      repo.updateError = ApiException(400, {'error': 'template_needs_values'});
      await tester.ensureVisible(
        find.byKey(const Key('automation-change-template')),
      );
      await tester.tap(find.byKey(const Key('automation-change-template')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template-discount_offer')));
      await tester.pumpAndSettle();
      expect(repo.updates.last['templateId'], 'tpl_sys_discount_offer');
      expect(
        find.textContaining('can’t be sent automatically'),
        findsOneWidget,
      );
    },
  );

  test('every automation string has a Swahili translation', () {
    final en = FFLocale.keysOf('en').where(
      (k) =>
          k.startsWith('comms.auto.') ||
          k == 'comms.tab.automations' ||
          k == 'comms.tpl.membership_final_reminder',
    );
    final sw = FFLocale.keysOf('sw');
    expect(en.length, greaterThan(20));
    expect(en.where((k) => !sw.contains(k)), isEmpty);
  });
}
