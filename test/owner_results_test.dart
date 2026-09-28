// Owner communications — results (M10): delivery, engagement and business
// numbers like the September example, "—" where there's no data, and the
// overview by campaign and automation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/owner/communications/data/analytics_models.dart';
import 'package:fitflexmobile/screens/owner/communications/data/communication_repository.dart';
import 'package:fitflexmobile/screens/owner/communications/widgets/results_card.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

// The September example: 120 recipients … 24 renewed, TZS 1,920,000.
final _september = CommsResults.fromJson({
  'attribution': {
    'model': 'last_touch',
    'clickWindowDays': 7,
    'openWindowDays': 3,
  },
  'members': {
    'recipients': 120,
    'sent': 120,
    'delivered': 113,
    'failed': 0,
    'opened': 82,
    'clicked': 61,
    'ctaCompleted': 30,
    'renewed': 24,
    'paid': 26,
  },
  'revenue': {'currency': 'TZS', 'attributedTzs': 1920000, 'payments': 26},
  'conversions': [
    {
      'memberId': 'u1',
      'memberName': 'Asha',
      'amountTzs': 80000,
      'via': 'click',
      'renewal': true,
      'paidAt': '2026-09-12T08:00:00Z',
    },
  ],
});

class _Repo extends CommunicationRepository {
  _Repo() : super(ApiClient(baseUrl: 'http://localhost:0'));
  @override
  Future<CommsResults> campaignResults(String id) async => _september;
}

Widget _app(Widget child, {String lang = 'en'}) => FFLocaleScope(
  notifier: FFLocale()..set(Locale(lang)),
  child: MaterialApp(
    home: Scaffold(body: ListView(children: [child])),
  ),
);

String _value(WidgetTester tester, String key) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(Key('result-$key')),
        matching: find.byType(Text),
      ),
    )
    .last
    .data!;

void main() {
  test('no data is null, never zero', () {
    final r = CommsResults.fromJson({
      'members': {
        'recipients': 3,
        'sent': 3,
        'delivered': null,
        'ctaCompleted': null,
      },
    });
    expect(r.counts.delivered, isNull);
    expect(r.counts.ctaCompleted, isNull);
    expect(r.counts.renewed, 0);
  });

  testWidgets('a campaign\'s results read like the September example', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        ResultsCard(
          titleKey: 'comms.results.campaignTitle',
          repository: _Repo(),
          load: (r) => r.campaignResults('cmp_1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(_value(tester, 'recipients'), '120');
    expect(_value(tester, 'delivered'), '113');
    expect(_value(tester, 'opened'), '82 · 68%');
    expect(_value(tester, 'clicked'), '61 · 51%');
    expect(_value(tester, 'renewed'), '24');
    expect(find.text('TZS 1,920,000'), findsOneWidget);
    expect(find.textContaining('7 days before paying'), findsOneWidget);
    expect(
      find.textContaining('Asha · TZS 80,000 · renewal · after tapping'),
      findsOneWidget,
    );
  });

  testWidgets('a missing value shows "—"', (tester) async {
    final r = CommsResults.fromJson({
      'members': {
        'recipients': 2,
        'sent': 2,
        'delivered': null,
        'ctaCompleted': null,
      },
    });
    await tester.pumpWidget(_app(ResultsView(results: r)));
    expect(_value(tester, 'delivered'), '—');
    expect(_value(tester, 'ctaCompleted'), '—');
  });

  testWidgets(
    'the overview lists each campaign and automation with its revenue',
    (tester) async {
      final r = CommsResults.fromJson({
        'period': {'days': 30},
        'members': {'recipients': 10, 'sent': 10},
        'revenue': {'attributedTzs': 85000},
        'sources': [
          {
            'type': 'campaign',
            'id': 'c1',
            'name': 'September renewals',
            'recipients': 7,
            'opened': 6,
            'paid': 3,
            'attributedTzs': 60000,
          },
          {
            'type': 'automation',
            'id': 'a1',
            'trigger': 'membership_expiring',
            'offsetDays': 3,
            'recipients': 3,
            'opened': 2,
            'paid': 1,
            'attributedTzs': 25000,
          },
        ],
      });
      await tester.pumpWidget(
        _app(
          OverviewResults(
            results: r,
            sourceName: (s) => s.name ?? 'auto:${s.trigger}',
          ),
        ),
      );
      expect(find.text('September renewals'), findsOneWidget);
      expect(find.text('auto:membership_expiring'), findsOneWidget);
      expect(find.text('7 members · 6 opened · 3 paid'), findsOneWidget);
      expect(find.text('TZS 60,000'), findsOneWidget);
      expect(r.periodDays, 30);
    },
  );

  testWidgets('results in Swahili', (tester) async {
    await tester.pumpWidget(_app(ResultsView(results: _september), lang: 'sw'));
    expect(find.text('Mapato yanayohusishwa'), findsOneWidget);
    expect(find.text('Walihuisha'), findsOneWidget);
  });

  test('every results string has a Swahili translation', () {
    final en = FFLocale.keysOf(
      'en',
    ).where((k) => k.startsWith('comms.results.'));
    final sw = FFLocale.keysOf('sw');
    expect(en.length, greaterThan(20));
    expect(en.where((k) => !sw.contains(k)), isEmpty);
  });
}
