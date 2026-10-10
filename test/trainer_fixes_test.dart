import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/owner/owner_trainers_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';
import 'package:fitflexmobile/shared/tanzania_regions.dart';
import 'package:fitflexmobile/shared/theme_notifier.dart';
import 'package:fitflexmobile/shared/widgets/ff_photo_gallery_field.dart';
import 'package:fitflexmobile/shared/widgets/terms_agreement.dart';
import 'package:fitflexmobile/shared/widgets/trainer_form_page.dart';

// A 1×1 PNG, as the app stores photos (base64 data-URL).
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

class _FakeApi extends ApiClient {
  _FakeApi({this.accepted = false}) : super(baseUrl: 'http://localhost:0');

  bool accepted;
  final acceptedVersions = <String>[];

  @override
  Future<Map<String, dynamic>> myTerms({String? lang, String? role}) async => {
    'required': true,
    'accepted': accepted,
    'version': '2026-10-09',
    'title': 'FitFlex Partner Agreement',
    'reference': 'FFA-PA-001',
    'sections': [
      {'heading': 'Your role', 'text': 'You train members.'},
    ],
  };

  @override
  Future<Map<String, dynamic>> acceptTerms(String version) async {
    acceptedVersions.add(version);
    accepted = true;
    return {'accepted': true};
  }

  @override
  Future<List<dynamic>> getSpecialties() async => ['Yoga', 'Boxing'];
}

Widget _wrap(Widget child, {required ApiClient api}) => AppScope(
  api: api,
  auth: AuthState(api),
  child: ThemeScope(
    notifier: ThemeNotifier(),
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
        home: Scaffold(body: child),
      ),
    ),
  ),
);

Map<String, dynamic> _trainer() => {
  'id': 'trn_1',
  'displayName': 'Asha Mushi',
  'email': 'asha@example.com',
  'phone': '+255700000001',
  'photoUrl': _png,
  'images': [_png, _png],
  'specialties': ['Yoga'],
  'bio': 'Ten years of coaching.',
  'hourlyRateTzs': 30000,
  'sessionRateCurrency': 'TZS',
  'availability': [
    {
      'day': 'Monday',
      'slots': ['08:00', '09:00'],
    },
  ],
  'socialLinks': {'instagram': 'asha.fit'},
  'status': 'active',
};

void main() {
  test('regions: the 31 regions of Tanzania, matched whatever the case', () {
    expect(tanzaniaRegions.length, 31);
    expect(tanzaniaRegions.toSet().length, 31);
    expect(matchTanzaniaRegion(' dar es salaam '), 'Dar es Salaam');
    expect(matchTanzaniaRegion('Atlantis'), isNull);
  });

  test('a trainer shows the whole gallery, or just the profile picture', () {
    expect(TrainerProfile.fromJson(_trainer()).photos.length, 2);
    final single = TrainerProfile.fromJson({..._trainer(), 'images': null});
    expect(single.photos, [_png]);
    final none = TrainerProfile.fromJson({
      ..._trainer(),
      'images': null,
      'photoUrl': null,
    });
    expect(none.photos, isEmpty);
  });

  testWidgets('terms on a sign-up form: must be ticked, then is recorded', (
    tester,
  ) async {
    final api = _FakeApi();
    final key = GlobalKey<TermsAgreementFieldState>();
    await tester.pumpWidget(_wrap(TermsAgreementField(key: key), api: api));
    await tester.pumpAndSettle();

    expect(find.text('I agree to the FitFlex Partner Agreement'), findsOne);
    expect(key.currentState!.agreed, isFalse);
    expect(await key.currentState!.record(), isFalse);
    expect(api.acceptedVersions, isEmpty);

    await tester.tap(find.byKey(const Key('terms-check')));
    await tester.pump();
    expect(key.currentState!.agreed, isTrue);
    await tester.runAsync(() => key.currentState!.record());
    await tester.pumpAndSettle();
    expect(api.acceptedVersions, ['2026-10-09']);
    expect(find.byKey(const Key('terms-field-accepted')), findsOneWidget);
  });

  testWidgets('terms already accepted are not asked for again', (tester) async {
    final api = _FakeApi(accepted: true);
    final key = GlobalKey<TermsAgreementFieldState>();
    await tester.pumpWidget(_wrap(TermsAgreementField(key: key), api: api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('terms-check')), findsNothing);
    expect(key.currentState!.agreed, isTrue);
  });

  testWidgets('the terms can be read in full from the form', (tester) async {
    await tester.pumpWidget(
      _wrap(const TermsAgreementField(), api: _FakeApi()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('terms-read')));
    await tester.pumpAndSettle();
    expect(find.text('1. Your role'), findsOneWidget);
    expect(find.text('You train members.'), findsOneWidget);
    // Reading is not agreeing: no Agree button on this page.
    expect(find.byKey(const Key('terms-page-agree')), findsNothing);
  });

  testWidgets('photo field: remove a photo, or make another the profile one', (
    tester,
  ) async {
    final a = _png, b = _png.replaceFirst('image/png', 'image/jpeg');
    var photos = <String>[a, b];
    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => FFPhotoGalleryField(
            values: photos,
            max: 2,
            onChanged: (v) => setState(() => photos = v),
          ),
        ),
        api: _FakeApi(),
      ),
    );
    await tester.pump();
    expect(find.text('Profile'), findsOneWidget);
    expect(
      find.byKey(const Key('photo-gallery-add')),
      findsNothing,
      reason: 'the limit is reached',
    );

    await tester.tap(find.byKey(const Key('photo-gallery-item-1')));
    await tester.pump();
    expect(photos, [b, a]);

    await tester.tap(find.byKey(const Key('photo-gallery-remove-0')));
    await tester.pump();
    expect(photos, [a]);
    expect(find.byKey(const Key('photo-gallery-add')), findsOneWidget);
  });

  testWidgets("a trainer's own edit sends their details, not account fields", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? payload;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => payload = await openTrainerForm(
              context,
              title: 'Edit professional details',
              initial: _trainer(),
              selfEdit: true,
            ),
            child: const Text('open'),
          ),
        ),
        api: _FakeApi(),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trainerFormEmail')), findsNothing);
    expect(find.byKey(const Key('photo-gallery-item-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('trainerFormSave')));
    await tester.pumpAndSettle();
    expect(payload, isNotNull);
    expect(payload!['displayName'], 'Asha Mushi');
    expect(payload!['phone'], '+255700000001');
    expect(payload!['images'], [_png, _png]);
    expect(payload!['photoUrl'], _png);
    expect(payload!['socialLinks'], containsPair('instagram', 'asha.fit'));
    expect(payload!['nickname'], '', reason: 'none chosen');
    for (final field in ['email', 'status', 'gymIds', 'initialPin']) {
      expect(payload!.containsKey(field), isFalse, reason: field);
    }
  });

  testWidgets('a trainer chooses the name clients see; their own name stays', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    Map<String, dynamic>? payload;
    await tester.pumpWidget(
      _wrap(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => payload = await openTrainerForm(
              context,
              title: 'Edit professional details',
              // As the server returns it once a nickname is set.
              initial: {
                ..._trainer(),
                'displayName': 'Coach Asha',
                'fullName': 'Asha Mushi',
                'nickname': 'Coach Asha',
              },
              selfEdit: true,
            ),
            child: const Text('open'),
          ),
        ),
        api: _FakeApi(),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Asha Mushi'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Coach Asha'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('trainerFormNickname')), '@');
    await tester.tap(find.byKey(const Key('trainerFormSave')));
    await tester.pumpAndSettle();
    expect(payload, isNull, reason: 'not a usable nickname');
    expect(find.textContaining('Use 2 to 30 letters'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('trainerFormNickname')),
      'Asha Fit',
    );
    await tester.tap(find.byKey(const Key('trainerFormSave')));
    await tester.pumpAndSettle();
    expect(payload!['displayName'], 'Asha Mushi');
    expect(payload!['nickname'], 'Asha Fit');
  });

  testWidgets('a gym owner adding a trainer is not asked for a nickname', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(const TrainerFormPage(title: 'Add trainer'), api: _FakeApi()),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trainerFormNickname')), findsNothing);
  });

  testWidgets("a trainer's own profile cannot be saved without a photo", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(
        TrainerFormPage(
          title: 'Edit',
          initial: {..._trainer(), 'images': <String>[], 'photoUrl': null},
          selfEdit: true,
        ),
        api: _FakeApi(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('trainerFormSave')));
    await tester.pump();
    expect(find.byKey(const Key('trainerFormPhotoError')), findsOneWidget);
  });

  testWidgets("gym owner sees a trainer's profile but cannot change it", (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _wrap(OwnerTrainerProfilePage(trainer: _trainer()), api: _FakeApi()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Asha Mushi'), findsOneWidget);
    expect(find.byKey(const Key('owner-trainer-gallery')), findsOneWidget);
    expect(
      find.byKey(const Key('owner-trainer-readonly-note')),
      findsOneWidget,
    );
    expect(find.text('+255700000001'), findsOneWidget);
    expect(find.text('asha@example.com'), findsOneWidget);
    expect(find.text('Monday · 08:00, 09:00'), findsOneWidget);
    expect(find.byKey(const Key('owner-trainer-socials')), findsOneWidget);
    expect(find.text('Ten years of coaching.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
  });

  testWidgets("gym owner sees the nickname, with the trainer's own name", (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        OwnerTrainerProfilePage(
          trainer: {
            ..._trainer(),
            'displayName': 'Coach Asha',
            'fullName': 'Asha Mushi',
            'nickname': 'Coach Asha',
          },
        ),
        api: _FakeApi(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coach Asha'), findsOneWidget);
    expect(find.byKey(const Key('owner-trainer-fullname')), findsOneWidget);
    expect(find.text('Asha Mushi'), findsOneWidget);
  });

  test('every new string exists in English and Swahili', () {
    const keys = [
      'owner.viewTrainer',
      'owner.trainerReadOnly',
      'owner.trainerSocial',
      'trainer.editProfessionalHint',
      'trainer.profileNotLoaded',
      'trainer.error.invalidPhone',
      'trainer.error.invalidRate',
      'trainer.error.tooManyPhotos',
      'trainer.error.nameRequired',
      'terms.agreeRead',
      'terms.agreeContinue',
      'terms.loadFailed',
      'terms.retry',
      'terms.read',
      'terms.accepted',
      'terms.agreeTo',
      'terms.mustAgree',
      'kyc.field.regionChoose',
      'photos.title',
      'photos.hint',
      'photos.max',
      'photos.profile',
      'photos.required',
      'trainer.nickname',
      'trainer.nicknameHint',
      'trainer.nicknameHelp',
      'trainer.nicknameInvalid',
    ];
    for (final lang in ['en', 'sw']) {
      expect(FFLocale.keysOf(lang), containsAll(keys), reason: lang);
    }
  });
}
