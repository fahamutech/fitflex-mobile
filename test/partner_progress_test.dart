// Partner progress tracker (journey audit Phase B · B4b) against the
// `progress` block of GET /me/kyc (fitflex-functions#236, flag
// PARTNER_PROGRESS). Absent progress keeps today's screens; present, the
// partner sees one story: registered → approved → verified → Ready to be paid.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/router.dart';
import 'package:fitflexmobile/screens/auth_screen.dart';
import 'package:fitflexmobile/screens/partner/verification/partner_progress_actions.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_center_page.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_forms.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_models.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/partner_progress.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/partner_progress_tracker.dart';

// ── Fixtures ────────────────────────────────────────────────────────────────

const _at = '2026-10-19T12:00:00Z';

Map<String, dynamic> _step(
  String key,
  String state, {
  String? at,
  String? reason,
}) => {'key': key, 'state': state, 'at': ?at, 'reason': ?reason};

Map<String, dynamic> _progress(
  List<Map<String, dynamic>> steps,
  String current,
  Map<String, dynamic> next, {
  List<Map<String, dynamic>>? gyms,
}) => {'steps': steps, 'current': current, 'nextAction': next, 'gyms': ?gyms};

/// A step list with [current] as the current step: earlier steps done,
/// later ones to do.
List<Map<String, dynamic>> _upTo(String current, {String state = 'current'}) {
  final out = <Map<String, dynamic>>[];
  var reached = false;
  for (final k in partnerStepKeys) {
    if (k == current) {
      reached = true;
      out.add(_step(k, state));
    } else {
      out.add(
        reached
            ? _step(k, 'todo')
            : _step(k, 'done', at: k == 'registered' ? _at : null),
      );
    }
  }
  return out;
}

Map<String, dynamic> _allDone() => _progress(
  [for (final k in partnerStepKeys) _step(k, 'done', at: _at)],
  'payoutReady',
  {'code': 'none'},
);

Map<String, dynamic> _item(String key, String status, {String? gymId}) => {
  'key': key,
  'by': 'partner',
  'status': status,
  'gymId': ?gymId,
};

/// A trainer's overview: name and payout account still missing.
Map<String, dynamic> _overview({
  Map<String, dynamic>? progress,
  String status = 'draft',
  String partnerType = 'trainer',
  String? reasonNote,
}) => {
  'partnerType': partnerType,
  'case': {
    'id': 'kyc_1',
    'status': status,
    'round': 1,
    'reasonNote': ?reasonNote,
  },
  'people': const [],
  'documents': const [],
  'settlementAccounts': <Map<String, dynamic>>[],
  'checklist': {
    'sections': [
      {
        'key': 'identity',
        'items': [_item('identity.fullName', 'missing')],
      },
      {
        'key': 'settlement',
        'items': [_item('settlement.payout_account', 'missing')],
      },
    ],
    'missing': ['identity.fullName', 'settlement.payout_account'],
    'readyToSubmit': false,
    'complete': false,
  },
  'progress': ?progress,
};

class _Repo extends VerificationRepository {
  _Repo(this.json) : super(ApiClient(baseUrl: 'http://localhost:0'));
  Map<String, dynamic> json;
  int loads = 0;

  @override
  Future<KycOverview> overview() async {
    loads++;
    return KycOverview.fromJson(json);
  }
}

Widget _app(Widget home, {String lang = 'en', double textScale = 1}) {
  final locale = FFLocale()..set(Locale(lang));
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp(
      theme: buildTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

Widget _tracker(
  Map<String, dynamic> progress, {
  bool compact = false,
  void Function(PartnerNextAction)? onAction,
}) => Scaffold(
  body: SingleChildScrollView(
    padding: const EdgeInsets.all(FFTokens.spacingLg),
    child: PartnerProgressTracker(
      progress: PartnerProgress.tryParse(progress)!,
      compact: compact,
      onAction: onAction ?? (_) {},
    ),
  ),
);

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(360 * 3, 800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('model', () {
    test('absent or unusable progress is null (old screens)', () {
      expect(KycOverview.fromJson(_overview()).progress, isNull);
      expect(PartnerProgress.tryParse(null), isNull);
      expect(PartnerProgress.tryParse('x'), isNull);
      expect(PartnerProgress.tryParse({'steps': []}), isNull);
      expect(
        PartnerProgress.tryParse({
          'steps': [_step('somethingNew', 'done')],
        }),
        isNull,
      );
    });

    test('parses steps, the next action and gym items', () {
      final p = KycOverview.fromJson(
        _overview(
          progress: _progress(_upTo('verified'), 'verified', {
            'code': 'kyc_changes_requested',
            'reasonCode': 'document_unreadable',
            'missing': ['identity.fullName', 'operational.rate_card@g2'],
          }),
        ),
      ).progress!;
      expect(p.steps.map((s) => s.state), [
        PartnerStepState.done,
        PartnerStepState.done,
        PartnerStepState.current,
        PartnerStepState.todo,
      ]);
      expect(p.current, 'verified');
      expect(p.currentNumber, 3);
      expect(p.steps.first.at, _at);
      expect(p.nextAction.reasonCode, 'document_unreadable');
      expect(p.nextAction.missing, [
        const PartnerItemRef('identity.fullName'),
        const PartnerItemRef('operational.rate_card', gymId: 'g2'),
      ]);
      expect(p.nextAction.missing.last.field, 'rate_card');
      expect(p.finished, isFalse);
      expect(PartnerProgress.tryParse(_allDone())!.finished, isTrue);
    });

    test('a later step may be done before an earlier one', () {
      final p = PartnerProgress.tryParse(
        _progress(
          [
            _step('registered', 'done'),
            _step('approved', 'done'),
            _step('verified', 'current'),
            _step('payoutReady', 'done'),
          ],
          'verified',
          {'code': 'submit_kyc'},
        ),
      )!;
      expect(p.steps.last.state, PartnerStepState.done);
      expect(p.finished, isFalse);
    });

    test('every progress string exists in English and Swahili', () {
      final en = FFLocale.keysOf('en').where((k) => k.startsWith('progress.'));
      final sw = FFLocale.keysOf('sw').where((k) => k.startsWith('progress.'));
      expect(en.toSet(), sw.toSet());
      expect(en.length, greaterThan(40));
    });
  });

  group('tracker states', () {
    testWidgets('each step shows its own state with words, and its date', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _tracker(
            _progress(
              [
                _step('registered', 'done', at: _at),
                _step('approved', 'done'),
                _step('verified', 'current'),
                _step('payoutReady', 'done'),
              ],
              'verified',
              {'code': 'submit_kyc'},
            ),
          ),
        ),
      );
      expect(find.text('Registered'), findsOneWidget);
      expect(find.text('Ready to be paid'), findsOneWidget);
      expect(find.text('Done · 19 Oct 2026'), findsOneWidget);
      expect(find.text('Current'), findsOneWidget);
      // payoutReady done ahead of verified is drawn as done.
      expect(find.text('Done'), findsNWidgets(2));
      expect(
        find.text('Everything is in. Send your details to FitFlex for review.'),
        findsOneWidget,
      );
      expect(find.text('Submit for review'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsNWidgets(3));
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });

    final cases =
        <
          ({
            String name,
            Map<String, dynamic> progress,
            String message,
            String? button,
          })
        >[
          (
            name: 'trainer with items left',
            progress: _progress(_upTo('verified'), 'verified', {
              'code': 'complete_kyc_items',
              'missing': ['identity.fullName', 'settlement.payout_account'],
            }),
            message: 'Still needed: Full legal name, Payout account',
            button: 'Complete verification',
          ),
          (
            name: 'many items left are summarised',
            progress: _progress(_upTo('verified'), 'verified', {
              'code': 'complete_kyc_items',
              'missing': [
                'identity.fullName',
                'identity.idNumber',
                'identity.phone',
                'identity.email',
                'identity.somethingNew',
              ],
            }),
            message: 'Still needed: Full legal name, ID number, Phone, 2 more',
            button: 'Complete verification',
          ),
          (
            name: 'legacy partner waiting for approval',
            progress: _progress(_upTo('approved'), 'approved', {
              'code': 'wait_for_approval',
            }),
            message:
                'FitFlex is reviewing your partner profile. We’ll let you know once it’s approved.',
            button: null,
          ),
          (
            name: 'vendor under review',
            progress: _progress(_upTo('approved'), 'approved', {
              'code': 'kyc_under_review',
            }),
            message: 'FitFlex is reviewing your details.',
            button: null,
          ),
          (
            name: 'changes requested with a reason',
            progress: _progress(_upTo('verified'), 'verified', {
              'code': 'kyc_changes_requested',
              'reasonCode': 'document_unreadable',
              'missing': ['documents.certification'],
            }),
            message:
                'FitFlex asked for changes: a document can’t be read.\nStill needed: Certification',
            button: 'Make changes',
          ),
          (
            name: 'changes requested, reason "other"',
            progress: _progress(_upTo('verified'), 'verified', {
              'code': 'kyc_changes_requested',
              'reasonCode': 'other',
              'missing': <String>[],
            }),
            message: 'FitFlex asked for changes to your details.',
            button: 'Make changes',
          ),
          (
            name: 'payout account needed',
            progress: _progress(_upTo('payoutReady'), 'payoutReady', {
              'code': 'add_payout_account',
            }),
            message: 'Add a payout account so FitFlex can pay you.',
            button: 'Add payout account',
          ),
          (
            name: 'payout account rejected',
            progress: _progress(_upTo('payoutReady'), 'payoutReady', {
              'code': 'add_payout_account',
              'reason': 'payout_account_rejected',
            }),
            message: 'Your payout account was not accepted. Add another one.',
            button: 'Add payout account',
          ),
          (
            name: 'payout account under review',
            progress: _progress(_upTo('payoutReady'), 'payoutReady', {
              'code': 'payout_account_under_review',
            }),
            message: 'FitFlex is checking your payout account.',
            button: null,
          ),
          (
            name: 'cooling off with no end date',
            progress: _progress(_upTo('payoutReady'), 'payoutReady', {
              'code': 'payout_account_cooling_off',
              'until': null,
            }),
            message: 'Your new payout account can be paid soon.',
            button: null,
          ),
          (
            name: 'payout not ready for another reason',
            progress: _progress(_upTo('payoutReady'), 'payoutReady', {
              'code': 'payout_not_ready',
              'reason': 'legacy_payout_details_missing',
            }),
            message: 'Payouts aren’t ready yet. Contact FitFlex support.',
            button: 'Contact support',
          ),
          (
            name: 'gym owner with no gym',
            progress: _progress(_upTo('payoutReady'), 'payoutReady', {
              'code': 'add_gym',
            }),
            message: 'Add your first gym.',
            button: 'Add gym',
          ),
          (
            name: 'all done',
            progress: _allDone(),
            message: 'You’re all set. FitFlex can pay you.',
            button: null,
          ),
          (
            name: 'a code from a newer server',
            progress: _progress(_upTo('verified'), 'verified', {
              'code': 'brand_new_code',
            }),
            message: 'FitFlex is working on your next step.',
            button: null,
          ),
        ];
    for (final c in cases) {
      testWidgets('next action: ${c.name}', (tester) async {
        PartnerNextAction? pressed;
        await tester.pumpWidget(
          _app(_tracker(c.progress, onAction: (a) => pressed = a)),
        );
        expect(find.text(c.message), findsOneWidget);
        final button = find.byKey(const Key('partner-progress-action'));
        if (c.button == null) {
          expect(button, findsNothing);
        } else {
          expect(
            find.descendant(of: button, matching: find.text(c.button!)),
            findsOneWidget,
          );
          await tester.tap(button);
          expect(pressed?.code, c.progress['nextAction']['code']);
        }
      });
    }

    testWidgets('cooling off names the date the hold ends', (tester) async {
      await tester.pumpWidget(
        _app(
          _tracker(
            _progress(_upTo('payoutReady'), 'payoutReady', {
              'code': 'payout_account_cooling_off',
              'until': '2026-10-21T12:00:00Z',
            }),
          ),
        ),
      );
      expect(
        find.textContaining(
          'Your new payout account can be paid from 21 Oct 2026',
        ),
        findsOneWidget,
      );
    });
  });

  group('blocked', () {
    for (final (reason, step, text) in [
      ('account_suspended', 'approved', 'Your account is suspended.'),
      (
        'role_rejected',
        'approved',
        'Your partner application was not approved.',
      ),
      ('kyc_rejected', 'verified', 'Your verification was not approved.'),
      ('kyc_suspended', 'verified', 'Your verification is suspended.'),
    ]) {
      testWidgets('$reason: the step says Blocked, the line says why once', (
        tester,
      ) async {
        final steps = _upTo(step, state: 'blocked');
        steps.firstWhere((s) => s['key'] == step)['reason'] = reason;
        await tester.pumpWidget(
          _app(
            _tracker(
              _progress(steps, step, {
                'code': 'contact_support',
                'reason': reason,
              }),
            ),
          ),
        );
        expect(find.text('Blocked'), findsOneWidget);
        expect(find.byIcon(Icons.block), findsOneWidget);
        expect(find.text(text), findsOneWidget);
        expect(find.text('Contact support'), findsOneWidget);
      });
    }

    testWidgets('a later blocked step that is not current shows its reason', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _tracker(
            _progress(
              [
                _step('registered', 'done'),
                _step('approved', 'done'),
                _step('verified', 'current'),
                _step('payoutReady', 'blocked', reason: 'kyc_suspended'),
              ],
              'verified',
              {'code': 'kyc_under_review'},
            ),
          ),
        ),
      );
      expect(
        find.text('Blocked · Your verification is suspended.'),
        findsOneWidget,
      );
    });
  });

  group('gym owner with several gyms', () {
    Map<String, dynamic> gym(
      String id,
      String? name,
      Map<String, dynamic> progress,
    ) => {'gymId': id, 'name': ?name, 'progress': progress};

    testWidgets('one row per gym; a gym payout action is said on its row', (
      tester,
    ) async {
      final ready = _allDone();
      final waiting = _progress(_upTo('payoutReady'), 'payoutReady', {
        'code': 'add_payout_account',
      });
      PartnerNextAction? pressed;
      await tester.pumpWidget(
        _app(
          _tracker(
            _progress(
              _upTo('payoutReady'),
              'payoutReady',
              {'code': 'add_payout_account', 'gymId': 'g2'},
              gyms: [gym('g1', 'Mbezi Fit', ready), gym('g2', null, waiting)],
            ),
            onAction: (a) => pressed = a,
          ),
        ),
      );
      expect(find.text('Your gyms'), findsOneWidget);
      expect(find.byKey(const Key('partner-progress-gym-g1')), findsOneWidget);
      expect(find.text('Mbezi Fit'), findsOneWidget);
      // A gym with no name still gets a row.
      expect(find.text('Your gym'), findsOneWidget);
      // The overall line is left out: g2's row says it, once.
      expect(find.byKey(const Key('partner-progress-next')), findsNothing);
      expect(
        find.text('Add a payout account so FitFlex can pay you.'),
        findsOneWidget,
      );
      expect(
        find.text('Step 4 of 4: Ready to be paid · Current'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('partner-progress-gym-action-g2')));
      expect(pressed?.code, 'add_payout_account');
    });

    testWidgets('owner-wide items are said once, each gym item with its gym', (
      tester,
    ) async {
      final kyc = {
        'code': 'complete_kyc_items',
        'missing': ['identity.fullName', 'operational.rate_card@g2'],
      };
      await tester.pumpWidget(
        _app(
          _tracker(
            _progress(
              _upTo('verified'),
              'verified',
              kyc,
              gyms: [
                gym(
                  'g1',
                  'Mbezi Fit',
                  _progress(_upTo('verified'), 'verified', {
                    'code': 'complete_kyc_items',
                    'missing': ['identity.fullName'],
                  }),
                ),
                gym(
                  'g2',
                  'Sinza Strong',
                  _progress(_upTo('verified'), 'verified', kyc),
                ),
              ],
            ),
          ),
        ),
      );
      expect(
        find.text('Still needed: Full legal name, Rates (Sinza Strong)'),
        findsOneWidget,
      );
      expect(find.textContaining('Still needed'), findsOneWidget);
      expect(find.text('Step 3 of 4: Verified · Current'), findsNWidgets(2));
    });
  });

  group('semantics', () {
    testWidgets('each step is announced as "Step n of 4, label, state"', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          _tracker(
            _progress(_upTo('approved'), 'approved', {
              'code': 'kyc_under_review',
            }),
          ),
        ),
      );
      expect(
        find.bySemanticsLabel('Step 2 of 4, Approved, current'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Step 1 of 4, Registered, done, 19 Oct 2026'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Step 4 of 4, Ready to be paid, to do'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the compact banner announces the current step', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          _tracker(
            _progress(_upTo('approved'), 'approved', {
              'code': 'kyc_under_review',
            }),
            compact: true,
          ),
          lang: 'sw',
        ),
      );
      expect(
        find.bySemanticsLabel('Hatua 2 kati ya 4, Umeidhinishwa, sasa'),
        findsOneWidget,
      );
      expect(find.text('Hatua 2 kati ya 4: Umeidhinishwa'), findsOneWidget);
      handle.dispose();
    });
  });

  group('fits 360 wide in Swahili at text scale 1.3', () {
    final fixtures = <String, Map<String, dynamic>>{
      'changes requested': _progress(_upTo('verified'), 'verified', {
        'code': 'kyc_changes_requested',
        'reasonCode': 'settlement_unverified',
        'missing': [
          'identity.fullName',
          'business.registeredAddress',
          'operational.rate_card@g2',
          'documents.registration_certificate',
        ],
      }),
      'blocked': _progress(
        _upTo('approved', state: 'blocked')..[1]['reason'] = 'role_rejected',
        'approved',
        {'code': 'contact_support', 'reason': 'role_rejected'},
      ),
      'several gyms': _progress(
        _upTo('payoutReady'),
        'payoutReady',
        {'code': 'payout_not_ready', 'reason': 'x', 'gymId': 'g2'},
        gyms: [
          {
            'gymId': 'g1',
            'name': 'Mbezi Beach Fitness Centre',
            'progress': _allDone(),
          },
          {
            'gymId': 'g2',
            'name': 'Sinza Strength and Conditioning Club',
            'progress': _progress(_upTo('payoutReady'), 'payoutReady', {
              'code': 'payout_account_cooling_off',
              'until': '2026-10-21T12:00:00Z',
            }),
          },
        ],
      ),
    };
    for (final MapEntry(key: name, value: p) in fixtures.entries) {
      for (final compact in [false, true]) {
        testWidgets('$name${compact ? ' (compact)' : ''}', (tester) async {
          _phone(tester);
          await tester.pumpWidget(
            _app(_tracker(p, compact: compact), lang: 'sw', textScale: 1.3),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    }
  });

  group('Verification centre', () {
    testWidgets('without progress the centre is as before', (tester) async {
      await tester.pumpWidget(
        _app(VerificationCenterPage(repository: _Repo(_overview()))),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partner-progress')), findsNothing);
      expect(find.byKey(const Key('kyc-status')), findsOneWidget);
    });

    testWidgets('with progress the tracker leads and the status is said once', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          VerificationCenterPage(
            repository: _Repo(
              _overview(
                status: 'submitted',
                progress: _progress(_upTo('verified'), 'verified', {
                  'code': 'kyc_under_review',
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('partner-progress')), findsOneWidget);
      expect(find.text('FitFlex is reviewing your details.'), findsOneWidget);
      expect(find.byKey(const Key('kyc-status')), findsNothing);
    });

    testWidgets('the reviewer note still shows beside the tracker', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          VerificationCenterPage(
            repository: _Repo(
              _overview(
                status: 'info_requested',
                reasonNote: 'Retake the ID photo',
                progress: _progress(_upTo('verified'), 'verified', {
                  'code': 'kyc_changes_requested',
                  'reasonCode': 'document_unreadable',
                  'missing': ['identity.fullName'],
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kyc-status')), findsOneWidget);
      expect(find.text('Retake the ID photo'), findsOneWidget);
      expect(find.textContaining('FitFlex needs'), findsNothing);
    });

    testWidgets('complete items opens the first missing item', (tester) async {
      await tester.pumpWidget(
        _app(
          VerificationCenterPage(
            repository: _Repo(
              _overview(
                progress: _progress(_upTo('verified'), 'verified', {
                  'code': 'complete_kyc_items',
                  'missing': ['identity.fullName'],
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('partner-progress-action')));
      await tester.pumpAndSettle();
      expect(find.byType(PersonFormPage), findsOneWidget);
    });

    testWidgets('add payout account opens the payout account screen', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          VerificationCenterPage(
            repository: _Repo(
              _overview(
                status: 'approved',
                progress: _progress(_upTo('payoutReady'), 'payoutReady', {
                  'code': 'add_payout_account',
                }),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('partner-progress-action')));
      await tester.pumpAndSettle();
      expect(find.byType(PayoutAccountsPage), findsOneWidget);
    });

    testWidgets('opened for an item, it opens that item once loaded', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          VerificationCenterPage(
            repository: _Repo(_overview(progress: _allDone())),
            openItem: const PartnerItemRef('settlement.payout_account'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PayoutAccountsPage), findsOneWidget);
    });
  });

  group('vendor home banner', () {
    const fallback = Text('old pending banner');

    testWidgets('without progress the old banner shows', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PartnerProgressBanner(
              repository: _Repo(_overview(partnerType: 'vendor')),
              fallback: fallback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('old pending banner'), findsOneWidget);
      expect(find.byKey(const Key('partner-progress-compact')), findsNothing);
    });

    testWidgets('while not finished the compact tracker replaces it', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PartnerProgressBanner(
              repository: _Repo(
                _overview(
                  partnerType: 'vendor',
                  progress: _progress(_upTo('approved'), 'approved', {
                    'code': 'complete_kyc_items',
                    'missing': ['business.legalName'],
                  }),
                ),
              ),
              fallback: fallback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('old pending banner'), findsNothing);
      expect(find.byKey(const Key('partner-progress-compact')), findsOneWidget);
      expect(find.text('Step 2 of 4: Approved'), findsOneWidget);
      expect(
        find.text('Still needed: Registered business name'),
        findsOneWidget,
      );
      // Complete verification leads into the Verification centre.
      await tester.tap(find.byKey(const Key('partner-progress-action')));
      await tester.pumpAndSettle();
      expect(find.byType(VerificationCenterPage), findsOneWidget);
    });

    testWidgets('once finished the banner goes away', (tester) async {
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: PartnerProgressBanner(
              repository: _Repo(
                _overview(partnerType: 'vendor', progress: _allDone()),
              ),
              fallback: fallback,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('old pending banner'), findsNothing);
      expect(find.byKey(const Key('partner-progress-compact')), findsNothing);
    });

    testWidgets('vendor staff do not load the vendor verification', (
      tester,
    ) async {
      final api = _KycApi(null);
      final auth = AuthState(api);
      await auth.signIn('t', {'id': 's1', 'userType': 'vendor_staff'});
      await tester.pumpWidget(
        AppScope(
          api: api,
          auth: auth,
          child: _app(
            const Scaffold(body: PartnerProgressBanner(fallback: fallback)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.kycLoads, 0);
      expect(find.text('old pending banner'), findsOneWidget);
    });
  });

  group('pending screen', () {
    Future<void> pumpPending(WidgetTester tester, _KycApi api) async {
      final auth = AuthState(api);
      await auth.signIn('jwt-vendor', {
        'id': 'usr_vendor',
        'userType': 'vendor',
        'approvalStatus': 'pending_approval',
        'onboardingCompleted': true,
      });
      final router = GoRouter(
        initialLocation: AppRoutes.pending,
        routes: [
          GoRoute(
            path: AppRoutes.pending,
            builder: (_, _) => const PendingApprovalScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        AppScope(
          api: api,
          auth: auth,
          child: ThemeScope(
            notifier: ThemeNotifier(),
            child: FFLocaleScope(
              notifier: FFLocale()..set(Locale(api.lang)),
              child: MaterialApp.router(
                theme: buildTheme(),
                routerConfig: router,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(api.textScale)),
                  child: child!,
                ),
                supportedLocales: const [Locale('en'), Locale('sw')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> stopPolling(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    }

    testWidgets('without progress the old wording and button show', (
      tester,
    ) async {
      final api = _KycApi(_overview(partnerType: 'vendor'));
      await pumpPending(tester, api);
      expect(find.text('Profile waiting for admin approval'), findsOneWidget);
      expect(find.byKey(const Key('pending-verification')), findsOneWidget);
      expect(find.byKey(const Key('partner-progress')), findsNothing);
      await stopPolling(tester);
    });

    testWidgets('with progress one tracker tells the whole story', (
      tester,
    ) async {
      final api = _KycApi(
        _overview(
          partnerType: 'vendor',
          progress: _progress(_upTo('approved'), 'approved', {
            'code': 'complete_kyc_items',
            'missing': ['business.legalName'],
          }),
        ),
      );
      await pumpPending(tester, api);
      expect(find.byKey(const Key('partner-progress')), findsOneWidget);
      expect(find.text('Profile waiting for admin approval'), findsNothing);
      expect(find.byKey(const Key('pending-verification')), findsNothing);
      expect(
        find.text(
          'FitFlex approves partners once their verification is complete.',
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('partner-progress-action')));
      await tester.pumpAndSettle();
      expect(find.byType(VerificationCenterPage), findsOneWidget);
      await stopPolling(tester);
    });

    testWidgets('fits 360 wide in Swahili at text scale 1.3', (tester) async {
      _phone(tester);
      final api =
          _KycApi(
              _overview(
                partnerType: 'vendor',
                progress: _progress(_upTo('approved'), 'approved', {
                  'code': 'kyc_changes_requested',
                  'reasonCode': 'document_mismatch',
                  'missing': [
                    'business.legalName',
                    'business.registeredAddress',
                  ],
                }),
              ),
            )
            ..lang = 'sw'
            ..textScale = 1.3;
      await pumpPending(tester, api);
      expect(tester.takeException(), isNull);
      expect(find.text('Hatua zako'), findsOneWidget);
      await stopPolling(tester);
    });
  });
}

/// An API whose GET /me/kyc returns [kyc] (or fails when null).
class _KycApi extends ApiClient {
  _KycApi(this.kyc) : super(baseUrl: 'http://localhost:0');
  final Map<String, dynamic>? kyc;
  int kycLoads = 0;
  String lang = 'en';
  double textScale = 1;

  @override
  Future<Map<String, dynamic>> myKyc() async {
    kycLoads++;
    if (kyc == null) throw ApiException(403, {'error': 'forbidden'});
    return kyc!;
  }

  @override
  Future<Map<String, dynamic>> myPersonas() async => {
    'personas': const <Map<String, dynamic>>[],
    'activePersonaId': null,
    'addablePersonaTypes': const <String>[],
  };
}
