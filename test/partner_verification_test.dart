// Partner verification centre: the checklist from GET /me/kyc, the forms for
// identity, documents and payout accounts, and submitting for review.
// Screens are pumped with a fake repository and a fake file picker, so no
// network, camera or file system is involved.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitflexmobile/shared/tanzania_banks.dart';
import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/screens/vendor/vendor_home_page.dart';

import 'package:fitflexmobile/screens/partner/verification/verification_center_page.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_forms.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_models.dart';
import 'package:fitflexmobile/screens/partner/verification/verification_repository.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/i18n.dart';

Map<String, dynamic> _item(
  String key,
  String status, {
  String by = 'partner',
  String? requirementKey,
}) => {
  'key': key,
  'by': by,
  'status': status,
  'requirementKey': ?requirementKey,
};

/// A trainer's overview: identity done except the ID file, certification
/// details without a file, no payout account yet.
Map<String, dynamic> _trainer({
  String status = 'draft',
  bool ready = false,
  String? reasonNote,
}) => {
  'partnerType': 'trainer',
  'case': {
    'id': 'kyc_1',
    'status': status,
    'round': 1,
    if (reasonNote != null) 'reasonCode': 'document_unreadable',
    'reasonNote': ?reasonNote,
  },
  'people': [
    {
      'role': 'principal',
      'fullName': 'Neema Said',
      'idType': 'nida',
      'idNumber': '19950505111110000221',
      'nationality': 'TZ',
      'phone': '+255754000222',
      'email': 'neema@example.com',
      'address': {'line1': 'Mbezi', 'city': 'Dar es Salaam'},
    },
  ],
  'documents': [
    {
      'id': 'd_old',
      'requirementKey': 'certification',
      'docType': 'certification',
      'status': 'rejected',
      'hasFile': true,
      'reviewNote': 'Blurred',
      'createdAt': '2026-09-01T00:00:00Z',
    },
    {
      'id': 'd_new',
      'requirementKey': 'certification',
      'docType': 'certification',
      'status': 'pending',
      'hasFile': false,
      'issuer': 'ACE',
      'documentNumber': 'ACE1',
      'createdAt': '2026-09-20T00:00:00Z',
    },
  ],
  'settlementAccounts': [],
  'checklist': {
    'sections': [
      {
        'key': 'identity',
        'items': [
          _item('identity.fullName', 'complete'),
          _item(
            'identity.id_document',
            ready ? 'submitted' : 'missing',
            requirementKey: 'trainer_id',
          ),
        ],
      },
      {
        'key': 'professional',
        'items': [
          _item(
            'professional.certification',
            ready ? 'submitted' : 'file_missing',
            requirementKey: 'certification',
          ),
          _item('professional.specialisation', 'complete'),
        ],
      },
      {
        'key': 'settlement',
        'items': [
          _item('settlement.payout_account', ready ? 'submitted' : 'missing'),
        ],
      },
    ],
    'missing': ready
        ? []
        : [
            'identity.id_document',
            'professional.certification',
            'settlement.payout_account',
          ],
    'readyToSubmit': ready,
    'complete': false,
  },
};

class _FakeRepo extends VerificationRepository {
  _FakeRepo(this.json) : super(ApiClient(baseUrl: 'http://localhost:0'));

  Map<String, dynamic> json;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];
  List<int>? uploadedBytes;
  String? uploadedName;

  /// What GET /me/kyc/documents/:id/file returns; null makes it fail.
  Uint8List? fileBytes;
  final fileLoads = <String>[];

  @override
  Future<Uint8List> documentFile(String documentId) async {
    fileLoads.add(documentId);
    final bytes = fileBytes;
    if (bytes == null) throw ApiException(404, {'error': 'file_not_found'});
    return bytes;
  }

  KycOverview get _now => KycOverview.fromJson(json);

  @override
  Future<KycOverview> overview() async => _now;

  @override
  Future<KycOverview> updatePerson(
    String role,
    Map<String, dynamic> body,
  ) async {
    calls.add('person:$role');
    bodies.add(body);
    return _now;
  }

  @override
  Future<KycOverview> updateBusiness(Map<String, dynamic> body) async {
    calls.add('business');
    bodies.add(body);
    return _now;
  }

  @override
  Future<KycOverview> updateDocument(
    String requirementKey,
    Map<String, dynamic> body,
  ) async {
    calls.add('document:$requirementKey');
    bodies.add(body);
    return _now;
  }

  @override
  Future<KycOverview> uploadDocumentFile(
    String requirementKey, {
    required List<int> bytes,
    required String filename,
    String? docType,
  }) async {
    calls.add('upload:$requirementKey:$docType');
    uploadedBytes = bytes;
    uploadedName = filename;
    final docs = (json['documents'] as List).cast<Map<String, dynamic>>();
    final doc = docs.firstWhere(
      (d) => d['requirementKey'] == requirementKey && d['status'] == 'pending',
      orElse: () {
        final d = <String, dynamic>{
          'id': 'd_$requirementKey',
          'requirementKey': requirementKey,
          'docType': docType ?? '',
          'status': 'pending',
          'createdAt': '2026-09-27T00:00:00Z',
        };
        docs.add(d);
        return d;
      },
    );
    doc['hasFile'] = true;
    doc['fileName'] = filename;
    return _now;
  }

  @override
  Future<void> addPayoutAccount(Map<String, dynamic> body) async {
    calls.add('account:add');
    bodies.add(body);
    (json['settlementAccounts'] as List).add({
      'id': 'psa_1',
      'method': body['method'],
      'provider': body['provider'],
      'accountName': body['accountName'],
      'accountNumber': '255754000222',
      'status': 'pending_verification',
      'isPrimary': false,
    });
  }

  @override
  Future<void> removePayoutAccount(String id) async =>
      calls.add('account:remove:$id');

  @override
  Future<KycOverview> submit() async {
    calls.add('submit');
    json = _trainer(status: 'submitted', ready: true);
    return _now;
  }

  @override
  Future<KycOverview> withdraw() async {
    calls.add('withdraw');
    json = _trainer(ready: true);
    return _now;
  }

  String? agreementsLang;
  DateTime? termsAcceptedAt;

  @override
  Future<List<KycAgreement>> agreements(String lang) async {
    agreementsLang = lang;
    return [
      KycAgreement(
        agreementType: 'partner_agreement',
        version: '2026-09-29',
        reference: 'FFA-TPT-001 (online) v1.0',
        title: lang == 'sw'
            ? 'Masharti ya Wakufunzi Washirika wa FitFlex'
            : 'FitFlex Trainer Partner Terms',
        sections: const [
          (
            heading: 'Independent contractor',
            text: 'You offer your services as an independent contractor.',
          ),
        ],
        acceptedAt: termsAcceptedAt,
      ),
      const KycAgreement(
        agreementType: 'kyc_consent',
        version: '2026-09-29',
        title: 'Consent to verification and use of your details',
      ),
    ];
  }

  @override
  Future<KycOverview> acceptAgreement(KycAgreement agreement) async {
    calls.add('accept:${agreement.agreementType}:${agreement.version}');
    return _now;
  }
}

class _CountingRepo extends _FakeRepo {
  _CountingRepo(_FakeRepo inner, this.onOverview) : super(inner.json);
  final void Function() onOverview;
  @override
  Future<KycOverview> overview() {
    onOverview();
    return super.overview();
  }
}

Widget _app(Widget home, {String lang = 'en'}) {
  final locale = FFLocale()..set(Locale(lang));
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp(home: home),
  );
}

class _FakeApi extends ApiClient {
  _FakeApi({this.profile = const {}}) : super(baseUrl: 'http://localhost:0');
  Map<String, dynamic> profile;
  final saved = <Map<String, dynamic>>[];
  Object? failWith;

  @override
  Future<Map<String, dynamic>> vendorProfile() async => profile;

  @override
  Future<Map<String, dynamic>> vendorSaveProfile(
    Map<String, dynamic> data,
  ) async {
    if (failWith != null) throw failWith!;
    saved.add(data);
    return data;
  }
}

Future<Widget> _scoped(
  Widget home,
  _FakeApi api,
  String userType, {
  Map<String, dynamic> user = const {},
}) async {
  SharedPreferences.setMockInitialValues({});
  final auth = AuthState(api);
  await auth.signIn('t', {
    'id': 'u1',
    'userType': userType,
    'status': 'active',
    ...user,
  });
  final locale = FFLocale()..set(const Locale('en'));
  return AppScope(
    api: api,
    auth: auth,
    child: FFLocaleScope(
      notifier: locale,
      child: MaterialApp(home: home),
    ),
  );
}

void _tall(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
}

void main() {
  group('models', () {
    test('parse the overview, status and checklist', () {
      final o = KycOverview.fromJson(
        _trainer(status: 'info_requested', reasonNote: 'Retake the photo'),
      );
      expect(o.partnerType, 'trainer');
      expect(o.status, KycStatus.infoRequested);
      expect(o.editable, isTrue);
      expect(o.kycCase!.reasonNote, 'Retake the photo');
      expect(o.sections.map((s) => s.key), [
        'identity',
        'professional',
        'settlement',
      ]);
      expect(o.itemsLeft, 3);
      expect(o.personFor('principal')!.address.complete, isTrue);
    });

    test(
      'the newest document that isn\'t superseded stands for a requirement',
      () {
        final o = KycOverview.fromJson(_trainer());
        expect(o.currentDocument('certification')!.id, 'd_new');
        expect(o.currentDocument('liability_insurance'), isNull);
      },
    );

    test('only draft and info-requested cases can be edited', () {
      expect(KycStatus.parse('submitted').editable, isFalse);
      expect(KycStatus.parse('approved').editable, isFalse);
      expect(KycStatus.parse(null), KycStatus.none);
      expect(KycStatus.none.editable, isTrue);
    });

    test('each partner type names the right person', () {
      expect(personRoleFor('vendor'), 'authorised_representative');
      expect(personRoleFor('trainer'), 'principal');
      expect(personFieldsFor('gym_owner'), contains('relationship'));
      expect(
        personFieldsFor('vendor'),
        containsAll([
          'fullName',
          'nationality',
          'idType',
          'idNumber',
          'position',
        ]),
      );
      expect(personFieldsFor('vendor'), isNot(contains('authority')));
      expect(documentSpecs.containsKey('representative_authority'), isFalse);
      expect(hasBusinessFor('trainer'), isFalse);
    });
  });

  group('verification centre', () {
    testWidgets('shows the checklist and what is left before submitting', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(_trainer());
      await tester.pumpWidget(_app(VerificationCenterPage(repository: repo)));
      await tester.pumpAndSettle();

      expect(find.text('Verification'), findsWidgets);
      expect(find.text('Identity'), findsOneWidget);
      expect(find.text('Professional'), findsOneWidget);
      expect(find.text('Add file'), findsOneWidget); // certification
      final submit = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const Key('kyc-submit')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(submit.onPressed, isNull);
      expect(find.text('3 items left to complete'), findsOneWidget);
    });

    testWidgets('submitting asks for confirmation, then locks the details', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(_trainer(ready: true));
      await tester.pumpWidget(_app(VerificationCenterPage(repository: repo)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('kyc-submit')));
      await tester.pumpAndSettle();
      expect(find.text('Submit for review?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('kyc-submit-confirm')));
      await tester.pumpAndSettle();

      expect(repo.calls, ['submit']);
      expect(
        find.textContaining('FitFlex will review your details soon'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('kyc-withdraw')), findsOneWidget);

      await tester.tap(find.byKey(const Key('kyc-item-identity.fullName')));
      await tester.pumpAndSettle();
      expect(find.textContaining('can’t be changed right now'), findsOneWidget);
    });

    testWidgets('a verified partner can renew documents but not details', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(_trainer(status: 'approved', ready: true));
      await tester.pumpWidget(_app(VerificationCenterPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('upload a renewed one any time'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('kyc-item-identity.fullName')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Contact FitFlex to change them'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('kyc-item-professional.certification')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DocumentPage), findsOneWidget);
    });

    testWidgets('partner terms: read, tick to agree, then accept', (
      tester,
    ) async {
      _tall(tester);
      final json = _trainer(status: 'submitted', ready: true);
      (json['checklist']['sections'] as List).add({
        'key': 'agreements',
        'items': [
          _item('agreements.partner_terms', 'missing'),
          _item('agreements.kyc_consent', 'missing'),
        ],
      });
      final repo = _FakeRepo(json);
      await tester.pumpWidget(
        _app(VerificationCenterPage(repository: repo), lang: 'sw'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Makubaliano'), findsOneWidget);

      // Open even though the case is submitted: agreements aren't locked.
      await tester.tap(
        find.byKey(const Key('kyc-item-agreements.partner_terms')),
      );
      await tester.pumpAndSettle();
      expect(repo.agreementsLang, 'sw');
      expect(
        find.text('Masharti ya Wakufunzi Washirika wa FitFlex'),
        findsOneWidget,
      );
      expect(find.textContaining('independent contractor'), findsOneWidget);

      final accept = find.descendant(
        of: find.byKey(const Key('kyc-agreement-accept')),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(accept).onPressed, isNull);
      await tester.tap(find.byKey(const Key('kyc-agreement-check')));
      await tester.pump();
      await tester.tap(accept);
      await tester.pumpAndSettle();
      expect(repo.calls, ['accept:partner_agreement:2026-09-29']);
      expect(find.byType(AgreementPage), findsNothing);
    });

    testWidgets('an accepted agreement says when, with nothing to accept', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(_trainer())
        ..termsAcceptedAt = DateTime.utc(2026, 9, 29, 8);
      await tester.pumpWidget(
        _app(
          AgreementPage(repository: repo, agreementType: 'partner_agreement'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kyc-agreement-accepted')), findsOneWidget);
      expect(find.text('You accepted this on 2026-09-29.'), findsOneWidget);
      expect(find.byKey(const Key('kyc-agreement-accept')), findsNothing);
    });

    testWidgets('a request for more information shows FitFlex\'s note', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(
        _trainer(
          status: 'info_requested',
          reasonNote: 'Your certificate is blurred.',
        ),
      );
      await tester.pumpWidget(_app(VerificationCenterPage(repository: repo)));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Your certificate is blurred.'),
        findsOneWidget,
      );
    });

    testWidgets('items kept elsewhere or done by FitFlex explain themselves', (
      tester,
    ) async {
      _tall(tester);
      final json = _trainer();
      (json['checklist']['sections'] as List).add({
        'key': 'operational',
        'items': [
          _item('operational.site_verification', 'missing', by: 'reviewer'),
        ],
      });
      await tester.pumpWidget(
        _app(VerificationCenterPage(repository: _FakeRepo(json))),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('kyc-item-professional.specialisation')),
      );
      await tester.pump();
      expect(find.textContaining('trainer profile'), findsOneWidget);

      await tester.ensureVisible(
        find.byKey(const Key('kyc-item-operational.site_verification')),
      );
      await tester.tap(
        find.byKey(const Key('kyc-item-operational.site_verification')),
      );
      // The previous message animates out, then this one replaces it.
      await tester.pumpAndSettle();
      expect(
        find.text('FitFlex completes this after you submit.'),
        findsOneWidget,
      );
      expect(find.textContaining('trainer profile'), findsNothing);
    });
  });

  group('forms', () {
    testWidgets(
      'identity: a Tanzanian trainer gives a NIDA number and their details are saved',
      (tester) async {
        _tall(tester);
        final json = _trainer();
        (json['people'] as List).clear();
        final repo = _FakeRepo(json);
        await tester.pumpWidget(_app(VerificationCenterPage(repository: repo)));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('kyc-item-identity.fullName')));
        await tester.pumpAndSettle();
        expect(find.text('Your identity'), findsOneWidget);

        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();
        expect(find.text('Required'), findsWidgets);
        expect(repo.calls, isEmpty);

        await tester.enterText(
          find.byKey(const Key('kyc-field-fullName')),
          'Neema Said',
        );
        await tester.enterText(
          find.byKey(const Key('kyc-field-idNumber')),
          '19950505-11111-00002-21',
        );
        await tester.enterText(
          find.byKey(const Key('kyc-field-phone')),
          '0754 000 222',
        );
        await tester.enterText(
          find.byKey(const Key('kyc-field-email')),
          'not-an-email',
        );
        await tester.enterText(
          find.byKey(const Key('kyc-field-addressLine1')),
          'Mbezi Beach',
        );
        // City is picked from the regions of Tanzania; there is no separate
        // region field any more.
        expect(find.byKey(const Key('kyc-field-addressRegion')), findsNothing);
        await tester.tap(find.byKey(const Key('kyc-field-addressCity')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dar es Salaam').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();
        expect(find.text('Enter a valid email address.'), findsOneWidget);

        await tester.enterText(
          find.byKey(const Key('kyc-field-email')),
          'neema@example.com',
        );
        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();

        expect(repo.calls, ['person:principal']);
        final body = repo.bodies.single;
        expect(body['fullName'], 'Neema Said');
        expect(body['idType'], 'nida');
        expect(body['nationality'], 'TZ');
        expect((body['address'] as Map)['city'], 'Dar es Salaam');
        expect(body.containsKey('relationship'), isFalse);
        expect(find.byKey(const Key('kyc-center')), findsOneWidget);
      },
    );

    testWidgets(
      'document: a picked file is uploaded with its type, and oversized files are refused',
      (tester) async {
        _tall(tester);
        final repo = _FakeRepo(_trainer());
        var next = PickedDocument(
          Uint8List.fromList(List.filled(2048, 1)),
          'ace certificate.pdf',
        );
        final picked = <DocumentSource>[];
        await tester.pumpWidget(
          _app(
            VerificationCenterPage(
              repository: repo,
              pickDocument: (source) async {
                picked.add(source);
                return next;
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('kyc-item-professional.certification')),
        );
        await tester.pumpAndSettle();
        // The pending document's details are carried into the form.
        expect(find.widgetWithText(TextFormField, 'ACE'), findsOneWidget);
        expect(find.text('No file yet'), findsOneWidget);

        await tester.ensureVisible(find.byKey(const Key('kyc-doc-pdf')));
        await tester.tap(find.byKey(const Key('kyc-doc-pdf')));
        await tester.pumpAndSettle();
        expect(picked, [DocumentSource.file]);
        expect(repo.calls, ['upload:certification:certification']);
        expect(repo.uploadedName, 'ace certificate.pdf');
        expect(repo.uploadedBytes!.length, 2048);
        expect(find.text('ace certificate.pdf'), findsOneWidget);

        next = PickedDocument(Uint8List(10 * 1024 * 1024 + 1), 'huge.pdf');
        await tester.tap(find.byKey(const Key('kyc-doc-camera')));
        await tester.pumpAndSettle();
        expect(
          find.text('That file is over 10 MB. Choose a smaller one.'),
          findsOneWidget,
        );
        expect(repo.calls.length, 1);
      },
    );

    testWidgets('document: a rejected document shows why and starts empty', (
      tester,
    ) async {
      _tall(tester);
      final json = _trainer();
      (json['documents'] as List).removeLast(); // only the rejected one remains
      final repo = _FakeRepo(json);
      await tester.pumpWidget(
        _app(
          DocumentPage(
            repository: repo,
            overview: KycOverview.fromJson(json),
            requirementKey: 'certification',
            pickDocument: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Blurred'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'ACE'), findsNothing);
      expect(find.text('Certification body *'), findsOneWidget);
      expect(find.text('Certificate number *'), findsOneWidget);
    });

    testWidgets(
      'payout: a mobile money account is added and shown as being checked',
      (tester) async {
        _tall(tester);
        final repo = _FakeRepo(_trainer());
        await tester.pumpWidget(_app(VerificationCenterPage(repository: repo)));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('kyc-item-settlement.payout_account')),
        );
        await tester.pumpAndSettle();
        expect(find.text('No payout account yet'), findsOneWidget);

        await tester.tap(find.byKey(const Key('kyc-account-add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('kyc-field-accountName')),
          'Neema Said',
        );
        await tester.enterText(
          find.byKey(const Key('kyc-field-mobileNumber')),
          '0754 000 222',
        );
        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();

        expect(repo.calls, ['account:add']);
        expect(repo.bodies.single, {
          'method': 'mobile_money',
          'provider': 'mpesa',
          'accountName': 'Neema Said',
          'accountNumber': '0754 000 222',
        });
        expect(find.text('Being checked'), findsOneWidget);
        expect(find.byTooltip('Remove'), findsOneWidget);
      },
    );

    testWidgets('payout: a bank is picked from the list of Tanzanian banks', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(_trainer());
      await tester.pumpWidget(_app(VerificationCenterPage(repository: repo)));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('kyc-item-settlement.payout_account')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kyc-account-add')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bank'));
      await tester.pumpAndSettle();

      // No bank chosen yet: saving asks for one, and nothing is typed.
      expect(find.byKey(const Key('kyc-field-bankName')), findsNothing);
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);

      await tester.tap(find.byKey(const Key('kyc-field-bank')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CRDB Bank').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('kyc-field-accountName')),
        'Neema Said',
      );
      await tester.enterText(
        find.byKey(const Key('kyc-field-accountNumber')),
        '0150123456789',
      );
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(repo.bodies.single, {
        'method': 'bank',
        'provider': 'CRDB Bank',
        'accountName': 'Neema Said',
        'accountNumber': '0150123456789',
      });
    });

    test('the bank list is alphabetical, with no bank twice', () {
      final sorted = [...tanzaniaBanks]
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      expect(tanzaniaBanks, sorted);
      expect(tanzaniaBanks.toSet().length, tanzaniaBanks.length);
      expect(tanzaniaBanks, containsAll(['CRDB Bank', 'NMB Bank']));
    });
  });

  group('optional items (vendors)', () {
    Map<String, dynamic> vendor() => {
      'partnerType': 'vendor',
      'case': {'id': 'kyc_v', 'status': 'draft'},
      'people': [],
      'documents': [],
      'settlementAccounts': [],
      'checklist': {
        'sections': [
          {
            'key': 'business',
            'items': [
              _item('business.tin', 'missing'),
              {
                ..._item(
                  'business.licence',
                  'missing',
                  requirementKey: 'business_licence',
                ),
                'optional': true,
              },
              {..._item('business.legalName', 'missing'), 'optional': true},
            ],
          },
        ],
        'missing': ['business.tin'],
        'readyToSubmit': false,
        'complete': false,
      },
    };

    testWidgets('optional items say so instead of "To do"', (tester) async {
      _tall(tester);
      await tester.pumpWidget(
        _app(VerificationCenterPage(repository: _FakeRepo(vendor()))),
      );
      await tester.pumpAndSettle();
      expect(find.text('Optional'), findsNWidgets(2));
      expect(find.text('To do'), findsOneWidget); // the TIN
      expect(find.text('1 items left to complete'), findsOneWidget);
      expect(
        KycOverview.fromJson(vendor()).sections.first.items[1].optional,
        isTrue,
      );
    });

    testWidgets('a vendor can save business details with just the TIN', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(vendor());
      await tester.pumpWidget(
        _app(
          BusinessFormPage(
            repository: repo,
            overview: KycOverview.fromJson(vendor()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget); // only the TIN
      await tester.enterText(
        find.byKey(const Key('kyc-field-tin')),
        '123-456-789',
      );
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['business']);
      expect(repo.bodies.single['tin'], '123-456-789');
    });
  });

  group('shared numbers and optional expiry', () {
    Map<String, dynamic> vendorWith({String? reg, String? tin}) => {
      'partnerType': 'vendor',
      'case': {
        'id': 'kyc_v',
        'status': 'draft',
        'registrationNumber': ?reg,
        'tin': ?tin,
      },
      'people': [],
      'documents': [],
      'settlementAccounts': [],
      'checklist': {'sections': [], 'missing': []},
    };

    Future<_FakeRepo> openDoc(
      WidgetTester tester,
      Map<String, dynamic> json,
      String key,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(json);
      await tester.pumpWidget(
        _app(
          DocumentPage(
            repository: repo,
            overview: KycOverview.fromJson(json),
            requirementKey: key,
            pickDocument: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('the ID number given on the person is prefilled and sent', (
      tester,
    ) async {
      final repo = await openDoc(tester, _trainer(), 'trainer_id');
      expect(
        find.widgetWithText(TextFormField, '19950505111110000221'),
        findsOneWidget,
      );
      expect(find.text('ID number'), findsOneWidget); // not marked required
      expect(find.text('Taken from the details you already gave.'), findsOne);
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['document:trainer_id']);
      expect(repo.bodies.single['documentNumber'], '19950505111110000221');
    });

    testWidgets('registration number and TIN from the business are prefilled', (
      tester,
    ) async {
      final json = vendorWith(reg: 'BRELA-77', tin: '123-456-789');
      await openDoc(tester, json, 'business_registration');
      expect(find.widgetWithText(TextFormField, 'BRELA-77'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await openDoc(tester, json, 'tin_certificate');
      expect(find.widgetWithText(TextFormField, '123-456-789'), findsOneWidget);
    });

    testWidgets('a vendor representative ID uses the representative number', (
      tester,
    ) async {
      final json = vendorWith();
      json['people'] = [
        {'role': 'authorised_representative', 'idNumber': 'REP-1'},
      ];
      await openDoc(tester, json, 'representative_id');
      expect(find.widgetWithText(TextFormField, 'REP-1'), findsOneWidget);
    });

    testWidgets('with nothing given anywhere the number is still required', (
      tester,
    ) async {
      final repo = await openDoc(tester, vendorWith(), 'tin_certificate');
      expect(find.text('TIN *'), findsOneWidget);
      expect(
        find.text('Taken from the details you already gave.'),
        findsNothing,
      );
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget);
      expect(repo.calls, isEmpty);
    });

    testWidgets('a licence saves without an expiry date, which is optional', (
      tester,
    ) async {
      final json = vendorWith();
      final repo = await openDoc(tester, json, 'business_licence');
      expect(find.text('Expiry date (optional)'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('kyc-field-issuingAuthority')),
        'TFRA',
      );
      await tester.enterText(
        find.byKey(const Key('kyc-field-licenceNumber')),
        'L-1',
      );
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, ['document:business_licence']);
      expect(repo.bodies.single['expiresOn'], isNull);
    });

    testWidgets('certification: issue date stays required; no expiry needed', (
      tester,
    ) async {
      final json = _trainer();
      (json['documents'] as List).clear();
      final repo = await openDoc(tester, json, 'certification');
      expect(find.text('Issue date *'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('kyc-field-certificationBody')),
        'ACE',
      );
      await tester.enterText(
        find.byKey(const Key('kyc-field-certificateNumber')),
        'C1',
      );
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsOneWidget); // only the issue date
      expect(repo.calls, isEmpty);
    });

    testWidgets('an expiry before the issue date is refused', (tester) async {
      final json = _trainer();
      final doc = (json['documents'] as List).last as Map<String, dynamic>;
      doc['issuedOn'] = '2026-05-01';
      doc['expiresOn'] = '2026-04-01';
      final repo = await openDoc(tester, json, 'certification');
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(
        find.text('The expiry date must be after the issue date.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'the person form shows an ID number that came from a document',
      (tester) async {
        _tall(tester);
        final json = _trainer();
        (json['people'] as List).first['idNumber'] = 'FROM-DOC-9';
        await tester.pumpWidget(
          _app(
            PersonFormPage(
              repository: _FakeRepo(json),
              overview: KycOverview.fromJson(json),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.widgetWithText(TextFormField, 'FROM-DOC-9'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the business form shows numbers that came from documents', (
      tester,
    ) async {
      _tall(tester);
      final json = vendorWith(reg: 'BRELA-77', tin: '123-456-789');
      await tester.pumpWidget(
        _app(
          BusinessFormPage(
            repository: _FakeRepo(json),
            overview: KycOverview.fromJson(json),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'BRELA-77'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '123-456-789'), findsOneWidget);
    });

    test('the new strings exist in English and Swahili', () {
      final en = FFLocale()..set(const Locale('en'));
      final sw = FFLocale()..set(const Locale('sw'));
      for (final k in ['kyc.field.optionalSuffix', 'kyc.doc.numberShared']) {
        expect(en.t(k), isNot(k));
        expect(sw.t(k), isNot(k));
        expect(sw.t(k), isNot(en.t(k)));
      }
    });
  });

  group('vendor business profile items', () {
    const profileKeys = ['business.contact', 'marketplace.product_categories'];

    Map<String, dynamic> vendor(String partnerType, {bool done = false}) => {
      'partnerType': partnerType,
      'case': {'id': 'kyc_v', 'status': 'draft'},
      'people': [],
      'documents': [],
      'settlementAccounts': [],
      'checklist': {
        'sections': [
          {
            'key': 'marketplace',
            'items': [
              for (final k in profileKeys)
                _item(k, done ? 'complete' : 'missing'),
              _item('marketplace.settlement', 'missing'),
            ],
          },
        ],
        'missing': profileKeys,
        'readyToSubmit': false,
        'complete': false,
      },
    };

    for (final key in profileKeys) {
      testWidgets('a vendor tapping $key opens the profile page', (
        tester,
      ) async {
        _tall(tester);
        final api = _FakeApi();
        await tester.pumpWidget(
          await _scoped(
            VerificationCenterPage(repository: _FakeRepo(vendor('vendor'))),
            api,
            'vendor',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('kyc-item-$key')));
        await tester.pumpAndSettle();
        expect(find.byType(VendorKycProfilePage), findsOneWidget);
        expect(find.textContaining('Business profile in'), findsNothing);
        expect(find.textContaining('Update this in'), findsNothing);
      });
    }

    testWidgets(
      'saving sends contact, email and the category keys, then reloads',
      (tester) async {
        _tall(tester);
        final api = _FakeApi(
          profile: {'contactNumber': '+255700000001', 'businessName': 'X'},
        );
        final repo = _FakeRepo(vendor('vendor'));
        var loads = 0;
        final counting = _CountingRepo(repo, () => loads++);
        await tester.pumpWidget(
          await _scoped(
            VerificationCenterPage(repository: counting),
            api,
            'vendor',
          ),
        );
        await tester.pumpAndSettle();
        final before = loads;
        await tester.tap(find.byKey(const Key('kyc-item-business.contact')));
        await tester.pumpAndSettle();
        // Prefilled from the saved profile.
        expect(find.text('+255700000001'), findsOneWidget);
        // No delivery areas or returns policy any more.
        expect(
          find.byKey(const Key('kyc-vendor-deliveryRegions')),
          findsNothing,
        );
        expect(find.byKey(const Key('kyc-vendor-returnsPolicy')), findsNothing);
        expect(find.text('Email (optional)'), findsOneWidget);

        // At least one category is required; the email is not.
        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();
        expect(api.saved, isEmpty);
        expect(
          find.byKey(const Key('kyc-vendor-category-error')),
          findsOneWidget,
        );

        // An email that is given must still look like an address.
        await tester.enterText(
          find.byKey(const Key('kyc-vendor-email')),
          'nope',
        );
        await tester.tap(
          find.byKey(const Key('kyc-vendor-category-equipment')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();
        expect(api.saved, isEmpty);

        await tester.enterText(find.byKey(const Key('kyc-vendor-email')), '');
        await tester.tap(
          find.byKey(const Key('kyc-vendor-category-supplements_nutrition')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();

        expect(api.saved, [
          {
            'contactNumber': '+255700000001',
            'email': '',
            'productCategories': ['equipment', 'supplements_nutrition'],
          },
        ]);
        expect(api.saved.single.containsKey('publish'), isFalse);
        expect(find.byType(VendorKycProfilePage), findsNothing);
        expect(loads, greaterThan(before));
      },
    );

    testWidgets('saved categories and older values are ticked on opening', (
      tester,
    ) async {
      _tall(tester);
      final api = _FakeApi(
        profile: {
          'contactNumber': '1',
          'productCategories': ['equipment', 'Food & drinks', 'Gear', 'events'],
        },
      );
      await tester.pumpWidget(
        await _scoped(
          VerificationCenterPage(repository: _FakeRepo(vendor('vendor'))),
          api,
          'vendor',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kyc-item-business.contact')));
      await tester.pumpAndSettle();
      bool ticked(String key) => tester
          .widget<CheckboxListTile>(find.byKey(Key('kyc-vendor-category-$key')))
          .value!;
      expect(ticked('equipment'), isTrue);
      expect(ticked('food_drinks'), isTrue); // from its English name
      expect(ticked('events'), isTrue);
      expect(ticked('other'), isFalse); // "Gear" matches nothing: ignored
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(api.saved.single['productCategories'], [
        'equipment',
        'food_drinks',
        'events',
      ]);
    });

    testWidgets('an API error is shown and the page stays open', (
      tester,
    ) async {
      _tall(tester);
      final api = _FakeApi(profile: {'contactNumber': '1', 'email': 'a@b.c'})
        ..failWith = ApiException(500, 'boom');
      await tester.pumpWidget(
        await _scoped(
          VerificationCenterPage(repository: _FakeRepo(vendor('vendor'))),
          api,
          'vendor',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('kyc-item-marketplace.product_categories')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kyc-vendor-category-other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(find.byType(VendorKycProfilePage), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    for (final type in ['gym_owner', 'trainer']) {
      testWidgets('a $type still sees the hint', (tester) async {
        _tall(tester);
        await tester.pumpWidget(
          await _scoped(
            VerificationCenterPage(repository: _FakeRepo(vendor(type))),
            _FakeApi(),
            type,
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('kyc-item-business.contact')));
        await tester.pump();
        expect(find.byType(VendorKycProfilePage), findsNothing);
        expect(find.textContaining('business profile'), findsOneWidget);
      });
    }

    testWidgets('a vendor tapping the payout item opens payout accounts', (
      tester,
    ) async {
      _tall(tester);
      await tester.pumpWidget(
        await _scoped(
          VerificationCenterPage(repository: _FakeRepo(vendor('vendor'))),
          _FakeApi(),
          'vendor',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('kyc-item-marketplace.settlement')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PayoutAccountsPage), findsOneWidget);
    });

    testWidgets(
      'VendorProfileForm: email optional, no delivery or returns, categories as keys',
      (tester) async {
        _tall(tester);
        Map<String, dynamic>? result;
        Future<void> open(WidgetTester t, Map<String, dynamic> profile) async {
          result = null;
          await t.pumpWidget(const SizedBox());
          await t.pumpWidget(
            FFLocaleScope(
              notifier: FFLocale()..set(const Locale('en')),
              child: MaterialApp(
                home: Builder(
                  builder: (ctx) => Scaffold(
                    body: TextButton(
                      onPressed: () async {
                        result =
                            await showModalBottomSheet<Map<String, dynamic>>(
                              context: ctx,
                              isScrollControlled: true,
                              builder: (_) =>
                                  VendorProfileForm(profile: profile),
                            );
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          );
          await t.tap(find.text('open'));
          await t.pumpAndSettle();
        }

        Future<void> publish(WidgetTester t) async {
          final b = find.byKey(const Key('vendor-profile-publish'));
          await t.ensureVisible(b);
          await t.tap(b);
          await t.pumpAndSettle();
        }

        // Missing logo/banner keeps the original gate: nothing is returned.
        await open(tester, {'businessName': 'a'});
        await publish(tester);
        expect(result, isNull);
        // The free-text, delivery and returns fields are gone.
        for (final k in [
          'vendor-profile-returnsPolicy',
          'vendor-profile-deliveryRegions',
          'vendor-profile-productCategories',
          'vendor-profile-businessCategory',
        ]) {
          expect(find.byKey(Key(k)), findsNothing, reason: k);
        }
        expect(
          find.byKey(const Key('vendor-profile-category-equipment')),
          findsOneWidget,
        );
        expect(find.text('Email (optional)'), findsOneWidget);

        // No email, no categories ticked, no older category: not publishable.
        final full = {
          'businessName': 'a',
          'logo': 'l',
          'banner': 'b',
          'description': 'd',
          'contactNumber': '1',
          'address': 'ad',
          'businessHours': {'summary': 'h'},
          'settlementAccount': {'account': 's'},
        };
        await open(tester, full);
        await publish(tester);
        expect(result, isNull);

        // Tick two categories: email may stay empty.
        for (final k in ['food_drinks', 'equipment']) {
          final tile = find.byKey(Key('vendor-profile-category-$k'));
          await tester.ensureVisible(tile);
          await tester.tap(tile);
          await tester.pumpAndSettle();
        }
        await tester.pumpAndSettle();
        await publish(tester);
        expect(result, isNotNull);
        expect(result!['publish'], isTrue);
        expect(result!['email'], '');
        expect(result!['productCategories'], ['food_drinks', 'equipment']);
        // The server still asks for one business category: first pick's name.
        expect(result!['businessCategory'], 'Food & drinks');
        expect(result!.containsKey('deliveryRegions'), isFalse);
        expect(result!.containsKey('returnsPolicy'), isFalse);

        // An older business category that matches nothing still publishes.
        await open(tester, {...full, 'businessCategory': 'Gear shop'});
        await publish(tester);
        expect(result!['businessCategory'], 'Gear shop');
        expect(result!.containsKey('productCategories'), isFalse);

        // One that matches a name is ticked.
        await open(tester, {...full, 'businessCategory': 'equipment'});
        await publish(tester);
        expect(result!['productCategories'], ['equipment']);
      },
    );
  });

  group('vendor details and photo preview', () {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
    );

    Map<String, dynamic> vendorOverview({
      Map<String, dynamic>? person,
      List<Map<String, dynamic>>? documents,
    }) => {
      'partnerType': 'vendor',
      'case': {'id': 'kyc_v', 'status': 'draft'},
      'people': [?person],
      'documents': [...?documents],
      'settlementAccounts': [],
      'checklist': {
        'sections': [
          {
            'key': 'representative',
            'items': [
              _item('representative.fullName', 'missing'),
              _item('representative.nationality', 'missing'),
              _item('representative.idNumber', 'missing'),
              _item('representative.position', 'missing'),
              _item(
                'representative.id_document',
                'missing',
                requirementKey: 'representative_id',
              ),
            ],
          },
        ],
        'missing': ['representative.fullName'],
        'readyToSubmit': false,
        'complete': false,
      },
    };

    testWidgets(
      'the vendor gives their own details: nationality and a position list, no authority',
      (tester) async {
        _tall(tester);
        final repo = _FakeRepo(vendorOverview());
        await tester.pumpWidget(
          await _scoped(
            VerificationCenterPage(repository: repo),
            _FakeApi(),
            'vendor',
            user: {'displayName': 'Asha Mushi'},
          ),
        );
        await tester.pumpAndSettle();
        // The section is called "Your details", not "Representative".
        expect(find.text('Your details'), findsOneWidget);
        expect(find.text('Representative'), findsNothing);

        await tester.tap(
          find.byKey(const Key('kyc-item-representative.fullName')),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your details'), findsWidgets);
        // Name comes from the account; nothing else is guessed.
        expect(
          find.widgetWithText(TextFormField, 'Asha Mushi'),
          findsOneWidget,
        );
        expect(find.byKey(const Key('kyc-field-nationality')), findsOneWidget);
        expect(find.byKey(const Key('kyc-field-position')), findsOneWidget);
        expect(find.byKey(const Key('kyc-field-authority')), findsNothing);
        expect(find.byKey(const Key('kyc-field-phone')), findsNothing);
        expect(find.byKey(const Key('kyc-field-email')), findsNothing);

        await tester.enterText(
          find.byKey(const Key('kyc-field-idNumber')),
          '19900101-11111-00001-11',
        );
        // Nationality and position are mandatory.
        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();
        expect(repo.calls, isEmpty);
        expect(find.text('Required'), findsNWidgets(2));

        await tester.tap(find.byKey(const Key('kyc-field-nationality')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Kenya').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('kyc-field-position')));
        await tester.pumpAndSettle();
        expect(find.text('Owner'), findsWidgets);
        expect(find.text('Co-owner'), findsWidgets);
        expect(find.text('Employee'), findsWidgets);
        await tester.tap(find.text('Co-owner').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('kyc-form-save')));
        await tester.pumpAndSettle();

        expect(repo.calls, ['person:authorised_representative']);
        final body = repo.bodies.single;
        expect(body['fullName'], 'Asha Mushi');
        expect(body['nationality'], 'KE');
        expect(body['position'], 'co_owner');
        expect(body['idNumber'], '19900101-11111-00001-11');
        for (final k in ['authority', 'phone', 'email', 'address']) {
          expect(body.containsKey(k), isFalse, reason: k);
        }
      },
    );

    testWidgets('a saved position and nationality are kept', (tester) async {
      _tall(tester);
      final repo = _FakeRepo(
        vendorOverview(
          person: {
            'role': 'authorised_representative',
            'fullName': 'Juma Bakari',
            'nationality': 'UG',
            'idType': 'passport',
            'idNumber': 'P123',
            'position': 'employee',
          },
        ),
      );
      await tester.pumpWidget(
        _app(
          PersonFormPage(
            repository: repo,
            overview: KycOverview.fromJson(repo.json),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('kyc-form-save')));
      await tester.pumpAndSettle();
      expect(repo.bodies.single['position'], 'employee');
      expect(repo.bodies.single['nationality'], 'UG');
      expect(repo.bodies.single['idType'], 'passport');
    });

    testWidgets('a picture shows as a thumbnail right after it is uploaded', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(vendorOverview());
      await tester.pumpWidget(
        _app(
          DocumentPage(
            repository: repo,
            overview: KycOverview.fromJson(repo.json),
            requirementKey: 'representative_id',
            pickDocument: (_) async => PickedDocument(png, 'my id.png'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kyc-doc-preview')), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('kyc-doc-gallery')));
      await tester.tap(find.byKey(const Key('kyc-doc-gallery')));
      await tester.pumpAndSettle();

      final preview = find.byKey(const Key('kyc-doc-preview'));
      expect(preview, findsOneWidget);
      expect(
        find.descendant(of: preview, matching: find.byType(Image)),
        findsOneWidget,
      );
      expect(tester.getSize(preview), const Size(72, 72));
      // The picture is not fetched again, and the file name is not the label.
      expect(repo.fileLoads, isEmpty);
      expect(find.text('my id.png'), findsNothing);
      expect(find.text('File attached'), findsOneWidget);
    });

    Map<String, dynamic> withFile(String fileName, {String? mime}) =>
        vendorOverview(
          documents: [
            {
              'id': 'doc_9',
              'requirementKey': 'representative_id',
              'docType': 'national_id',
              'status': 'pending',
              'hasFile': true,
              'fileName': fileName,
              'mimeType': ?mime,
              'createdAt': '2026-10-01T00:00:00Z',
            },
          ],
        );

    testWidgets('an uploaded picture is loaded through the repository', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(withFile('id.jpg', mime: 'image/jpeg'))
        ..fileBytes = Uint8List.fromList(png);
      await tester.pumpWidget(
        _app(
          DocumentPage(
            repository: repo,
            overview: KycOverview.fromJson(repo.json),
            requirementKey: 'representative_id',
            pickDocument: (_) async => null,
          ),
        ),
      );
      // Progress first, then the picture.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpAndSettle();
      expect(repo.fileLoads, ['doc_9']);
      expect(
        find.descendant(
          of: find.byKey(const Key('kyc-doc-preview')),
          matching: find.byType(Image),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a picture that cannot be loaded falls back to an icon', (
      tester,
    ) async {
      _tall(tester);
      final repo = _FakeRepo(withFile('id.jpg', mime: 'image/jpeg'));
      await tester.pumpWidget(
        _app(
          DocumentPage(
            repository: repo,
            overview: KycOverview.fromJson(repo.json),
            requirementKey: 'representative_id',
            pickDocument: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('kyc-doc-preview')), findsOneWidget);
      expect(find.byIcon(Icons.image_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a PDF shows an icon with its file name', (tester) async {
      _tall(tester);
      final repo = _FakeRepo(withFile('licence.pdf', mime: 'application/pdf'));
      await tester.pumpWidget(
        _app(
          DocumentPage(
            repository: repo,
            overview: KycOverview.fromJson(repo.json),
            requirementKey: 'representative_id',
            pickDocument: (_) async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.picture_as_pdf_outlined), findsWidgets);
      expect(find.text('licence.pdf'), findsOneWidget);
      expect(repo.fileLoads, isEmpty);
    });
  });

  group('strings', () {
    test('every verification string exists in English and Swahili', () {
      final dir = Directory('lib/screens/partner/verification');
      final keys = <String>{};
      for (final f in dir.listSync().whereType<File>()) {
        keys.addAll(
          RegExp(
            r"tr\('(kyc\.[A-Za-z0-9_.]+)'\)",
          ).allMatches(f.readAsStringSync()).map((m) => m.group(1)!),
        );
      }
      // Keys built at runtime from the API's vocabulary.
      for (final s in [
        'identity',
        'business',
        'operational',
        'settlement',
        'professional',
        'representative',
        'yourDetails',
        'marketplace',
        'agreements',
      ]) {
        keys.add('kyc.section.$s');
      }
      for (final f in [
        'fullName',
        'idNumber',
        'phone',
        'email',
        'address',
        'relationship',
        'position',
        'authority',
        'id_document',
        'legalName',
        'tradingName',
        'registrationNumber',
        'tin',
        'registeredAddress',
        'registration_certificate',
        'tin_certificate',
        'licence',
        'gym_location',
        'partner_terms',
        'kyc_consent',
        'gym_profile',
        'rate_card',
        'site_verification',
        'vetting_score',
        'gym_tier',
        'payout_account',
        'certification',
        'specialisation',
        'liability_cover',
        'contact',
        'authority_document',
        'nationality',
        'product_categories',
        'delivery',
        'returns',
        'settlement',
      ]) {
        keys.add('kyc.item.$f');
      }
      for (final r in documentSpecs.keys) {
        keys.add('kyc.doc.intro.$r');
      }
      for (final o in [
        ...relationships,
        ...entityTypes,
        ...mobileMoneyProviders,
        'nida',
        'passport',
        'national_id',
        'letter_of_authority',
        'board_resolution',
        'mobile_money',
        'bank',
      ]) {
        keys.add('kyc.option.$o');
      }
      for (final a in [
        'pending_verification',
        'verified',
        'rejected',
        'disabled',
      ]) {
        keys.add('kyc.account.$a');
      }
      for (final f in [
        'fullName',
        'nationality',
        'idType',
        'idNumber',
        'position',
        'relationship',
        'authority',
        'phone',
        'email',
        'address',
        'addressLine1',
        'addressCity',
        'addressRegion',
        'legalName',
        'tradingName',
        'entityType',
        'registrationNumber',
        'tin',
        'registeredAddress',
        'docType',
        'certificationBody',
        'insurer',
        'issuingAuthority',
        'licenceNumber',
        'certificateNumber',
        'policyNumber',
        'documentNumber',
        'issuedOn',
        'expiresOn',
        'provider',
        'bank',
        'accountName',
        'accountNumber',
        'mobileNumber',
        'branch',
      ]) {
        keys.add('kyc.field.$f');
      }
      final en = FFLocale()..set(const Locale('en'));
      final sw = FFLocale()..set(const Locale('sw'));
      const sameInBoth = {
        'TIN',
        'M-Pesa',
        'Airtel Money',
        'Mixx by Yas',
        'HaloPesa',
      };
      final missing = [
        for (final k in keys)
          if (en.t(k) == k ||
              sw.t(k) == k ||
              (sw.t(k) == en.t(k) && !sameInBoth.contains(en.t(k))))
            k,
      ];
      expect(missing, isEmpty);
      expect(keys.length, greaterThan(140));
    });
  });
}
