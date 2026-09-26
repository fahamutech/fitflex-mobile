// Owner communications — message templates: the model, starting a message
// from a template, the Templates tab, a template's preview and the editor.
// Screens are pumped with a fake repository so no network is involved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:fitflexmobile/screens/owner/communications/campaign_composer_page.dart';
import 'package:fitflexmobile/screens/owner/communications/communication_center_page.dart';
import 'package:fitflexmobile/screens/owner/communications/communication_controller.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_models.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_repository.dart';
import 'package:fitflexmobile/screens/owner/communications/template_pages.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

const _renewal = CommTemplate(
  id: 'tpl_sys_renewal_reminder',
  key: 'renewal_reminder',
  name: 'renewal_reminder',
  system: true,
  group: 'membership',
  purpose: CampaignPurpose.renewal,
  deepLink: DeepLink.renewal,
  bodies: {
    'en': MessageText(
      title: 'Time to renew',
      body: 'Hi {{member_name}}, renew your {{plan_name}} plan.',
      ctaLabel: 'Renew',
    ),
    'sw': MessageText(
      title: 'Wakati wa kuhuisha',
      body: 'Habari {{member_name}}, huisha mpango wako wa {{plan_name}}.',
      ctaLabel: 'Huisha',
    ),
  },
  variables: ['member_name', 'plan_name'],
);

const _discount = CommTemplate(
  id: 'tpl_sys_discount_offer',
  key: 'discount_offer',
  name: 'discount_offer',
  system: true,
  group: 'marketing',
  purpose: CampaignPurpose.promotion,
  bodies: {
    'en': MessageText(title: '{{discount}} off', body: '{{offer_name}} now'),
    'sw': MessageText(title: 'Punguzo {{discount}}', body: '{{offer_name}}'),
  },
  variables: ['discount', 'offer_name'],
);

const _own = CommTemplate(
  id: 'tpl_gym_1',
  key: 'custom',
  name: 'Holiday hours',
  system: false,
  group: 'general',
  purpose: CampaignPurpose.announcement,
  bodies: {'en': MessageText(title: 'Holiday hours', body: 'We close at 2pm.')},
);

class _FakeRepo extends CommunicationRepository {
  _FakeRepo() : super(ApiClient(baseUrl: 'http://localhost:0'));

  List<CommTemplate> list = const [_renewal, _discount, _own];
  final created = <Map<String, dynamic>>[];
  final updatedTemplates = <Map<String, dynamic>>[];
  final duplicated = <String>[];
  final archived = <String>[];

  @override
  Future<CommunicationOverview> overview({String? gymId}) async =>
      const CommunicationOverview(
        members: 10,
        campaigns: {},
        recent: [],
        channels: ChannelAvailability(push: true),
      );

  @override
  Future<List<Campaign>> campaigns({
    String? gymId,
    CampaignStatus? status,
  }) async => const [];

  @override
  Future<AudienceCount> audienceCount({
    String? gymId,
    required CampaignAudience audience,
    CampaignPurpose? purpose,
  }) async => const AudienceCount(count: 3, sample: ['Asha']);

  @override
  Future<List<CommTemplate>> templates({String? gymId, String? group}) async =>
      list;

  @override
  Future<CommTemplate> template(String id) async =>
      list.firstWhere((t) => t.id == id);

  @override
  Future<TemplatePreview> previewTemplate(
    String id, {
    String? gymId,
    Map<String, dynamic>? values,
  }) async {
    final t = list.firstWhere((t) => t.id == id);
    return TemplatePreview(
      senderName: 'Kilele Gym',
      byLocale: {
        for (final e in t.bodies.entries)
          e.key: TemplateChannelPreview(
            inApp: RenderedMessage(
              title: e.value.title.replaceAll('{{member_name}}', 'Amina'),
              body: e.value.body.replaceAll('{{member_name}}', 'Amina'),
              memberName: 'Amina',
            ),
            pushTitle: e.value.title,
            pushBody: e.value.body,
          ),
      },
      needsValues: t.senderVariables,
    );
  }

  @override
  Future<CommTemplate> createTemplate(Map<String, dynamic> body) async {
    created.add(body);
    return _own;
  }

  @override
  Future<CommTemplate> updateTemplate(
    String id,
    Map<String, dynamic> body,
  ) async {
    updatedTemplates.add(body);
    return _own;
  }

  @override
  Future<CommTemplate> duplicateTemplate(String id, {String? gymId}) async {
    duplicated.add(id);
    return _own;
  }

  @override
  Future<void> archiveTemplate(String id) async => archived.add(id);
}

Widget _app(GoRouter router, {String lang = 'en'}) {
  final locale = FFLocale()..set(Locale(lang));
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp.router(routerConfig: router),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

Finder _field(String key) =>
    find.descendant(of: find.byKey(Key(key)), matching: find.byType(TextField));

void main() {
  group('template model', () {
    test('a template becomes a message in the owner\'s language, with the '
        'other language as a translation', () {
      final sw = _renewal.toContent('sw');
      expect(sw.locale, 'sw');
      expect(sw.title, 'Wakati wa kuhuisha');
      expect(sw.translations['en']!.title, 'Time to renew');
      expect(sw.deepLink, DeepLink.renewal);
      final json = sw.toJson();
      expect(json['locale'], 'sw');
      expect((json['translations'] as Map)['en']['ctaLabel'], 'Renew');

      // A template in one language only starts in that language.
      final only = _own.toContent('sw');
      expect(only.locale, 'en');
      expect(only.translations, isEmpty);
    });

    test('variables are read from every language', () {
      const c = CampaignContent(
        title: 'Hi',
        body: 'Hello',
        translations: {
          'sw': MessageText(title: 'Habari', body: '{{member_name}}'),
        },
      );
      expect(c.variables, {'member_name'});
    });

    test('template JSON is read from the server shape', () {
      final t = CommTemplate.fromJson({
        'id': 'tpl_sys_we_miss_you',
        'key': 'we_miss_you',
        'name': 'We miss you',
        'system': true,
        'group': 'engagement',
        'purpose': 'win_back',
        'deepLink': 'gym',
        'bodies': {
          'en': {'title': 'We miss you', 'body': 'Come back, {{member_name}}'},
        },
        'variables': ['member_name'],
      });
      expect(t.system, isTrue);
      expect(t.group, 'engagement');
      expect(t.textIn('sw').title, 'We miss you', reason: 'falls back');
      final p = TemplatePreview.fromJson({
        'senderName': 'Kilele',
        'byLocale': {
          'en': {
            'in_app': {'title': 'A', 'body': 'B'},
            'push': {'title': 'A', 'body': 'B…', 'truncated': true},
          },
        },
        'whatsapp': {
          'byLocale': {
            'en': {'ready': false},
          },
        },
        'needsValues': ['discount'],
      });
      expect(p.byLocale['en']!.pushTruncated, isTrue);
      expect(p.whatsappReady['en'], isFalse);
      expect(p.needsValues, ['discount']);
    });
  });

  group('composer with templates', () {
    CampaignComposerController composer(_FakeRepo repo, {String lang = 'en'}) =>
        CampaignComposerController(
          repo,
          gymId: 'gym_1',
          channelsAvailable: const ChannelAvailability(push: true),
          writingLocale: lang,
          countDebounce: Duration.zero,
        );

    test('applying a template fills the message, purpose and templateId', () {
      final c = composer(_FakeRepo(), lang: 'sw');
      final before = c.contentRevision;
      c.applyTemplate(_renewal);
      expect(c.templateId, _renewal.id);
      expect(c.purpose, CampaignPurpose.renewal);
      expect(c.content.locale, 'sw');
      expect(c.content.title, 'Wakati wa kuhuisha');
      expect(c.content.translations['en']!.body, contains('renew'));
      expect(c.contentRevision, greaterThan(before));
      expect(c.draftJson()['templateId'], _renewal.id);
      expect(c.canContinue(ComposerStep.message), isTrue);
    });

    test('offer values survive switching templates; clearing starts blank', () {
      final c = composer(_FakeRepo());
      c.applyTemplate(_discount);
      expect(c.missingSenderValues, containsAll(['discount', 'offer_name']));
      c.setContent(
        c.content.copyWith(offerName: () => 'Ramadan', discount: () => '20%'),
      );
      expect(c.canContinue(ComposerStep.message), isTrue);
      c.applyTemplate(_renewal);
      expect(c.content.offerName, 'Ramadan');
      c.clearTemplate();
      expect(c.templateId, isNull);
      expect(c.content.title, isEmpty);
      expect(c.content.translations, isEmpty);
      expect(c.content.discount, '20%');
      expect(c.draftJson()['templateId'], isNull);
    });

    test('a half-written translation blocks the message step', () {
      final c = composer(_FakeRepo());
      c.applyTemplate(_own);
      expect(c.canContinue(ComposerStep.message), isTrue);
      c.setText('sw', const MessageText(title: 'Saa za sikukuu'));
      expect(c.translationsValid, isFalse);
      expect(c.canContinue(ComposerStep.message), isFalse);
      c.removeTranslation('sw');
      expect(c.canContinue(ComposerStep.message), isTrue);
    });
  });

  group('screens', () {
    testWidgets('the composer starts from a picked template, in both '
        'languages', (tester) async {
      _tall(tester);
      final repo = _FakeRepo();
      final router = GoRouter(
        initialLocation: '/new',
        routes: [
          GoRoute(
            path: '/new',
            builder: (_, _) =>
                CampaignComposerPage(gymId: 'gym_1', repository: repo),
          ),
        ],
      );
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('purpose-renewal')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comms-next')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('comms-next')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('msg-pick-template')));
      await tester.pumpAndSettle();
      // The message's purpose is listed first; the group pills filter.
      await tester.tap(find.byKey(const Key('tpl-group-marketing')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-renewal_reminder')), findsNothing);
      await tester.tap(find.byKey(const Key('tpl-group-membership')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('template-renewal_reminder')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('msg-change-template')), findsOneWidget);
      final title = tester.widget<TextField>(_field('msg-title-en'));
      expect(title.controller!.text, 'Time to renew');
      await tester.tap(find.text('Swahili'));
      await tester.pumpAndSettle();
      final sw = tester.widget<TextField>(_field('msg-title-sw'));
      expect(sw.controller!.text, 'Wakati wa kuhuisha');

      await tester.tap(find.byKey(const Key('msg-clear-template')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('msg-pick-template')), findsOneWidget);
      expect(
        tester.widget<TextField>(_field('msg-title-en')).controller!.text,
        isEmpty,
      );
    });

    testWidgets('the Templates tab lists FitFlex and gym templates by '
        'category', (tester) async {
      _tall(tester);
      final repo = _FakeRepo();
      final router = GoRouter(
        initialLocation: '/c',
        routes: [
          GoRoute(
            path: '/c',
            builder: (_, _) =>
                CommunicationCenterPage(gymId: 'gym_1', repository: repo),
          ),
          GoRoute(
            path: '/owner/communications/templates/:id',
            builder: (_, s) =>
                Scaffold(body: Text('template ${s.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Templates'));
      await tester.pumpAndSettle();
      expect(find.text('Renewal reminder'), findsWidgets);
      expect(find.text('Holiday hours'), findsOneWidget);
      expect(find.text('Your gym'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tpl-filter-marketing')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('template-discount_offer')), findsOneWidget);
      expect(find.byKey(const Key('template-custom')), findsNothing);

      await tester.tap(find.byKey(const Key('template-discount_offer')));
      await tester.pumpAndSettle();
      expect(find.text('template tpl_sys_discount_offer'), findsOneWidget);
    });

    testWidgets('Swahili owners see template names in Swahili', (tester) async {
      _tall(tester);
      final router = GoRouter(
        initialLocation: '/c',
        routes: [
          GoRoute(
            path: '/c',
            builder: (_, _) => CommunicationCenterPage(
              gymId: 'gym_1',
              repository: _FakeRepo(),
            ),
          ),
        ],
      );
      await tester.pumpWidget(_app(router, lang: 'sw'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Violezo'));
      await tester.pumpAndSettle();
      expect(find.text('Kikumbusho cha kuhuisha'), findsWidgets);
      expect(find.textContaining('Habari'), findsOneWidget);
    });

    testWidgets('a FitFlex template previews per language and can be copied', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo();
      final router = GoRouter(
        initialLocation: '/t',
        routes: [
          GoRoute(
            path: '/t',
            builder: (_, _) => TemplateDetailPage(
              templateId: _renewal.id,
              gymId: 'gym_1',
              repository: repo,
            ),
          ),
          GoRoute(
            path: '/owner/communications/templates/:id/edit',
            builder: (_, s) =>
                Scaffold(body: Text('edit ${s.pathParameters['id']}')),
          ),
        ],
      );
      await tester.pumpWidget(_app(router));
      await tester.pumpAndSettle();
      expect(find.text('Time to renew'), findsWidgets);
      expect(find.byKey(const Key('tpl-whatsapp')), findsOneWidget);
      expect(find.byKey(const Key('tpl-edit')), findsNothing);
      await tester.tap(find.text('Swahili'));
      await tester.pumpAndSettle();
      expect(find.text('Wakati wa kuhuisha'), findsWidgets);

      await tester.tap(find.byKey(const Key('tpl-copy')));
      await tester.pumpAndSettle();
      expect(repo.duplicated, [_renewal.id]);
      expect(find.text('edit tpl_gym_1'), findsOneWidget);
    });

    testWidgets('a gym template says which values are filled in when sending '
        'and can be archived', (tester) async {
      _tall(tester);
      final repo = _FakeRepo()
        ..list = [
          const CommTemplate(
            id: 'tpl_gym_2',
            key: 'custom',
            name: 'Flash sale',
            system: false,
            group: 'marketing',
            bodies: {
              'en': MessageText(title: 'Sale', body: '{{discount}} off'),
            },
            variables: ['discount'],
          ),
        ];
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home')),
            routes: [
              GoRoute(
                path: 't',
                builder: (_, _) => TemplateDetailPage(
                  templateId: 'tpl_gym_2',
                  repository: repo,
                ),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(_app(router));
      router.push('/t');
      await tester.pumpAndSettle();
      expect(find.textContaining('You fill in when sending'), findsOneWidget);
      expect(find.byKey(const Key('tpl-copy')), findsNothing);
      await tester.tap(find.byKey(const Key('tpl-archive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('dialog-confirm')));
      await tester.pumpAndSettle();
      expect(repo.archived, ['tpl_gym_2']);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('the editor saves a new bilingual template', (tester) async {
      _tall(tester);
      final repo = _FakeRepo();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('home')),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, _) =>
                    TemplateEditorPage(gymId: 'gym_1', repository: repo),
              ),
            ],
          ),
        ],
      );
      await tester.pumpWidget(_app(router));
      router.push('/new');
      await tester.pumpAndSettle();

      bool canSave() =>
          tester
              .widget<FilledButton>(find.byKey(const Key('tpl-save')))
              .onPressed !=
          null;
      expect(canSave(), isFalse);
      await tester.enterText(_field('tpl-name'), 'Closed Friday');
      await tester.enterText(_field('tpl-title-en'), 'Closed Friday');
      await tester.enterText(_field('tpl-body-en'), 'Hi ');
      await tester.tap(find.byKey(const Key('tpl-var-member_name')));
      await tester.pumpAndSettle();
      expect(canSave(), isTrue);

      // A half-written Swahili version can't be saved.
      await tester.tap(find.text('Swahili'));
      await tester.pumpAndSettle();
      await tester.enterText(_field('tpl-title-sw'), 'Tumefunga Ijumaa');
      await tester.pumpAndSettle();
      expect(canSave(), isFalse);
      await tester.enterText(_field('tpl-body-sw'), 'Habari {{member_name}}');
      await tester.pumpAndSettle();
      expect(canSave(), isTrue);

      await tester.tap(find.byKey(const Key('tpl-save')));
      await tester.pumpAndSettle();
      final body = repo.created.single;
      expect(body['gymId'], 'gym_1');
      expect(body['name'], 'Closed Friday');
      expect(body['bodies']['en']['body'], 'Hi {{member_name}}');
      expect(body['bodies']['sw']['title'], 'Tumefunga Ijumaa');
      expect(find.text('home'), findsOneWidget);
    });
  });

  test('every template name and category has a Swahili translation', () {
    final en = FFLocale.keysOf('en');
    final sw = FFLocale.keysOf('sw');
    for (final key in [
      'renewal_reminder',
      'welcome_member',
      'member_milestone',
      'we_miss_you',
    ]) {
      expect(en, contains('comms.tpl.$key'));
      expect(sw, contains('comms.tpl.$key'));
    }
    for (final g in kTemplateGroups) {
      expect(sw, contains('comms.group.$g'));
    }
  });
}
