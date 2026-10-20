// B7a: a gym owner sees FitFlex's inspection on the vetting score item of the
// Verification centre — total out of maximum, vetted tier and visit date,
// joined from the gym's reviewer items in GET /me/kyc. Nothing changes when
// the fields are absent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/screens/partner/verification/verification_center_page.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_models.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

class _Repo extends VerificationRepository {
  _Repo(this.json) : super(ApiClient(baseUrl: 'http://localhost:0'));
  final Map<String, dynamic> json;

  @override
  Future<KycOverview> overview() async => KycOverview.fromJson(json);
}

/// A gym owner's overview with the operational items the backend sends for
/// one gym (src/shared/partner-kyc-requirements.mjs gymItems).
Map<String, dynamic> _owner({
  num? score,
  Object? maxScore,
  String? vettedTier,
  String? visitedOn,
  bool visited = true,
}) {
  Map<String, dynamic> item(String key, String status, [Map? extra]) => {
    'key': key,
    'by': 'reviewer',
    'gymId': 'gym_1',
    'gymName': 'Msasani Fitness',
    'status': status,
    ...?extra?.cast<String, dynamic>(),
  };
  return {
    'partnerType': 'gym_owner',
    'case': {'id': 'kyc_1', 'status': 'in_review', 'round': 1},
    'people': [],
    'documents': [],
    'settlementAccounts': [],
    'checklist': {
      'sections': [
        {
          'key': 'operational',
          'items': [
            item(
              'operational.site_verification',
              visited ? 'complete' : 'missing',
              visited
                  ? {'checkId': 'pchk_1', 'visitedOn': visitedOn}
                  : const {},
            ),
            item(
              'operational.vetting_score',
              score == null ? 'missing' : 'complete',
              score == null ? null : {'score': score, 'maxScore': maxScore},
            ),
            item(
              'operational.gym_tier',
              vettedTier == null ? 'missing' : 'complete',
              {'gymTier': 'premium', 'vettedTier': ?vettedTier},
            ),
          ],
        },
      ],
      'missing': [],
    },
  };
}

Widget _app(Map<String, dynamic> json, {String lang = 'en', double scale = 1}) {
  final locale = FFLocale()..set(Locale(lang));
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: VerificationCenterPage(repository: _Repo(json)),
    ),
  );
}

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

const _line = Key('kyc-inspection-gym_1');

void main() {
  testWidgets('score, tier and visit date in English at 360', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        _owner(
          score: 42,
          maxScore: 50,
          vettedTier: 'premium',
          visitedOn: '2026-10-12',
        ),
        scale: 1.3,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(_line)).data,
      '42 / 50 · Premium tier · Visited 12 Oct 2026',
    );
    // Said once: only the vetting score item carries the line.
    expect(find.textContaining('42 / 50'), findsOneWidget);
    expect(find.textContaining('12 Oct 2026'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the same in Swahili at 360 with text scale 1.3', (tester) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(
        _owner(
          score: 42,
          maxScore: 50,
          vettedTier: 'luxury_executive',
          visitedOn: '2026-10-12',
        ),
        lang: 'sw',
        scale: 1.3,
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<Text>(find.byKey(_line)).data,
      '42 kati ya 50 · Daraja la Luxury / Executive · Ilitembelewa 12 Okt 2026',
    );
    // Wraps inside the tile instead of overflowing.
    expect(tester.takeException(), isNull);
    final line = tester.getRect(find.byKey(_line));
    expect(line.right, lessThanOrEqualTo(360));
    expect(find.text('Alama za ukaguzi'), findsOneWidget);
  });

  testWidgets('no score: the item shows only its state, as before', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(_app(_owner(visited: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(_line), findsNothing);
    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('0 / 0'), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const Key('kyc-item-operational.vetting_score-gym_1')),
        matching: find.text('Msasani Fitness · Done by FitFlex'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('partial: score without maximum, tier or date', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(_owner(score: 38)));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(_line)).data, '38');
    expect(find.textContaining('null'), findsNothing);
    expect(find.textContaining('/'), findsNothing);
  });

  testWidgets('partial: zero maximum and bad date are left out', (
    tester,
  ) async {
    _phone(tester);
    await tester.pumpWidget(
      _app(_owner(score: 40.5, maxScore: 0, visitedOn: 'soon')),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(_line)).data, '40.5');
    expect(find.textContaining('0 / 0'), findsNothing);
  });

  test('inspection is joined from items of the same gym only', () {
    final json = _owner(
      score: 42,
      maxScore: 50,
      vettedTier: 'premium',
      visitedOn: '2026-10-12',
    );
    final items = (json['checklist']['sections'][0]['items'] as List)
        .cast<Map<String, dynamic>>();
    // A second gym's visit and tier must not leak into gym_1's line.
    items.addAll([
      {
        'key': 'operational.site_verification',
        'gymId': 'gym_2',
        'status': 'complete',
        'visitedOn': '2026-01-01',
      },
      {
        'key': 'operational.gym_tier',
        'gymId': 'gym_2',
        'status': 'complete',
        'vettedTier': 'standard',
      },
    ]);
    final overview = KycOverview.fromJson(json);
    final vetting = overview.sections.first.items.firstWhere(
      (i) => i.key == 'operational.vetting_score',
    );
    final inspection = overview.inspectionFor(vetting)!;
    expect(inspection.score, 42);
    expect(inspection.maxScore, 50);
    expect(inspection.vettedTier, 'premium');
    expect(inspection.visitedOn, '2026-10-12');

    final tier = overview.sections.first.items.firstWhere(
      (i) => i.key == 'operational.gym_tier',
    );
    expect(overview.inspectionFor(tier), isNull);
  });
}
