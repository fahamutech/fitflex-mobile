// Partner verification centre: the checklist from GET /me/kyc, the forms for
// identity, documents and payout accounts, and submitting for review.
// Screens are pumped with a fake repository and a fake file picker, so no
// network, camera or file system is involved.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
}

Widget _app(Widget home, {String lang = 'en'}) {
  final locale = FFLocale()..set(Locale(lang));
  return FFLocaleScope(
    notifier: locale,
    child: MaterialApp(home: home),
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
      expect(personFieldsFor('vendor'), containsAll(['position', 'authority']));
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
        find.byKey(const Key('kyc-submit')),
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
        await tester.enterText(
          find.byKey(const Key('kyc-field-addressCity')),
          'Dar es Salaam',
        );
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
        'marketplace',
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
        ...authorities,
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
