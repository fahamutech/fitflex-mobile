// Gym and trainer reviews: members read the summary and published reviews,
// write one when eligible (gym: a visit; trainer: a completed session), edit
// or delete their own, and the cached gym/trainer rating follows. Trainers
// read theirs from the profile tab.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/app_scope.dart';
import 'package:fitflexmobile/screens/member/member_shell.dart';
import 'package:fitflexmobile/screens/trainer/trainer_reviews_page.dart';
import 'package:fitflexmobile/shared/api_client.dart';
import 'package:fitflexmobile/shared/auth_state.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/models.dart';

class _FakeApi extends ApiClient {
  _FakeApi({
    this.summary = const ReviewSummary(),
    this.list = const [],
    this.mine = const MyReviewState(eligible: true),
    this.failSubmitWith,
  }) : super(baseUrl: 'http://localhost:0');

  ReviewSummary summary;
  List<Review> list;
  MyReviewState mine;
  ApiException? failSubmitWith;
  final calls = <String>[];

  @override
  Future<ReviewSummary> reviewSummary(ReviewSubject subject, String id) async =>
      summary;

  @override
  Future<List<Review>> reviews(ReviewSubject subject, String id) async => list;

  @override
  Future<MyReviewState> myReviewState(ReviewSubject subject, String id) async =>
      mine;

  @override
  Future<({num average, int count})> submitReview(
    ReviewSubject subject,
    String id, {
    required int rating,
    String? text,
  }) async {
    calls.add('submit:${subject.path}:$id:$rating:${text ?? ''}');
    if (failSubmitWith != null) throw failSubmitWith!;
    mine = MyReviewState(eligible: true, rating: rating, text: text);
    summary = ReviewSummary(
      average: rating.toDouble(),
      count: 1,
      distribution: {rating: 1},
    );
    return (average: rating, count: 1);
  }

  @override
  Future<({num average, int count})> deleteMyReview(
    ReviewSubject subject,
    String id,
  ) async {
    calls.add('delete:${subject.path}:$id');
    mine = const MyReviewState(eligible: true);
    summary = const ReviewSummary();
    return (average: 0, count: 0);
  }

  @override
  Future<({ReviewSummary summary, List<Review> reviews})>
  myTrainerReviews() async => (summary: summary, reviews: list);

  @override
  Future<Map<String, dynamic>> trainerSchedule(
    String trainerId, {
    String? from,
    int? days,
    String? gymId,
  }) async => {'days': []};
}

Widget _wrap(Widget child, _FakeApi api, {MemberData? data}) => AppScope(
  api: api,
  auth: AuthState(api),
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
      home: data == null ? child : MemberDataScope(data: data, child: child),
    ),
  ),
);

Gym _gym({num rating = 0, int reviewCount = 0}) => Gym(
  id: 'gym1',
  name: 'Iron Paradise',
  tier: 'standard',
  location: 'Masaki',
  perVisitRate: 5000,
  commissionRate: 12,
  status: 'active',
  accessMode: 'paid_visit',
  rating: rating,
  reviewCount: reviewCount,
);

TrainerProfile _trainer({num? rating, int? reviewCount}) => TrainerProfile(
  id: 'trn1',
  displayName: 'Coach Mike',
  hourlyRateTzs: 20000,
  status: 'active',
  rating: rating,
  reviewCount: reviewCount,
);

final _published = [
  Review(
    id: 'r1',
    rating: 5,
    text: 'Clean and friendly',
    memberName: 'Aisha M.',
    createdAt: DateTime.utc(2026, 9, 20),
  ),
  const Review(id: 'r2', rating: 3, memberName: 'Juma'),
];

Future<void> _openGym(
  WidgetTester tester,
  _FakeApi api,
  MemberData data,
) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _wrap(const MemberGymDetailPage(gymId: 'gym1'), api, data: data),
  );
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(
    find.byKey(const Key('reviews-section')),
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('gym page shows the real rating, summary and published reviews', (
    tester,
  ) async {
    final api = _FakeApi(
      summary: const ReviewSummary(
        average: 4,
        count: 2,
        distribution: {5: 1, 3: 1},
      ),
      list: _published,
    );
    final data = MemberData()..gyms = [_gym(rating: 4, reviewCount: 2)];
    await _openGym(tester, api, data);

    expect(find.byKey(const Key('reviews-summary')), findsOneWidget);
    expect(find.text('2 reviews'), findsWidgets);
    expect(find.text('Aisha M.'), findsOneWidget);
    expect(find.text('Clean and friendly'), findsOneWidget);
    expect(find.text('20 Sep 2026'), findsOneWidget);
    expect(find.byKey(const Key('review-write')), findsOneWidget);
  });

  testWidgets('an eligible member rates a gym and the cached rating updates', (
    tester,
  ) async {
    final api = _FakeApi();
    final data = MemberData()..gyms = [_gym()];
    await _openGym(tester, api, data);
    expect(find.byKey(const Key('reviews-empty')), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-write')));
    await tester.pumpAndSettle();
    expect(find.text('Rate this gym'), findsOneWidget);
    // Nothing to post until a star is chosen.
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('review-submit')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('review-star-4')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('review-text')),
        matching: find.byType(TextField),
      ),
      'Great showers',
    );
    await tester.tap(find.byKey(const Key('review-submit')));
    await tester.pumpAndSettle();

    expect(api.calls, ['submit:gyms:gym1:4:Great showers']);
    expect(data.gyms.single.rating, 4);
    expect(data.gyms.single.reviewCount, 1);
    expect(find.text('Thanks — your review is live.'), findsOneWidget);
    expect(find.byKey(const Key('review-mine')), findsOneWidget);
  });

  testWidgets('a too-short comment is caught before posting', (tester) async {
    final api = _FakeApi();
    await _openGym(tester, api, MemberData()..gyms = [_gym()]);
    await tester.tap(find.byKey(const Key('review-write')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-star-2')));
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('review-text')),
        matching: find.byType(TextField),
      ),
      'ok',
    );
    await tester.tap(find.byKey(const Key('review-submit')));
    await tester.pumpAndSettle();
    expect(api.calls, isEmpty);
    expect(
      find.text('Write at least 3 characters, or leave it empty.'),
      findsOneWidget,
    );
  });

  testWidgets('a declined review shows the reason in the sheet', (
    tester,
  ) async {
    final api = _FakeApi(
      failSubmitWith: ApiException(403, {
        'error': 'no_checkin_or_direct_subscription',
      }),
    );
    await _openGym(tester, api, MemberData()..gyms = [_gym()]);
    await tester.tap(find.byKey(const Key('review-write')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-star-5')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-submit')));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('you can review a gym after checking in there'),
      findsOneWidget,
    );
    expect(find.text('Rate this gym'), findsOneWidget);
  });

  testWidgets('members who have not visited see why they cannot review yet', (
    tester,
  ) async {
    final api = _FakeApi(
      mine: const MyReviewState(
        eligible: false,
        reason: 'no_checkin_or_direct_subscription',
      ),
    );
    await _openGym(tester, api, MemberData()..gyms = [_gym()]);
    expect(find.byKey(const Key('review-write')), findsNothing);
    expect(
      find.text('Check in at this gym to leave a review.'),
      findsOneWidget,
    );
  });

  testWidgets('a member edits, then deletes, their own review', (tester) async {
    final api = _FakeApi(
      summary: const ReviewSummary(average: 2, count: 1, distribution: {2: 1}),
      mine: const MyReviewState(eligible: true, rating: 2, text: 'Crowded'),
    );
    final data = MemberData()..gyms = [_gym(rating: 2, reviewCount: 1)];
    await _openGym(tester, api, data);
    expect(find.byKey(const Key('review-mine')), findsOneWidget);
    expect(find.text('Crowded'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-edit')));
    await tester.pumpAndSettle();
    expect(find.text('Update review'), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-star-3')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-submit')));
    await tester.pumpAndSettle();
    expect(api.calls.single, 'submit:gyms:gym1:3:Crowded');
    expect(data.gyms.single.rating, 3);

    await tester.ensureVisible(find.byKey(const Key('review-delete')));
    await tester.tap(find.byKey(const Key('review-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-delete-confirm')));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'delete:gyms:gym1');
    expect(data.gyms.single.reviewCount, 0);
    expect(find.byKey(const Key('review-write')), findsOneWidget);
  });

  testWidgets('trainer page shows the rating badge and trainer reviews', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = _FakeApi(
      summary: const ReviewSummary(average: 4.5, count: 2),
      list: _published,
      mine: const MyReviewState(
        eligible: false,
        reason: 'no_completed_booking',
      ),
    );
    final data = MemberData()
      ..trainers = [_trainer(rating: 4.5, reviewCount: 2)];
    await tester.pumpWidget(
      _wrap(const MemberTrainerDetailPage(trainerId: 'trn1'), api, data: data),
    );
    await tester.pumpAndSettle();
    expect(find.text('★ 4.5 · 2 reviews'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('review-not-eligible')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('You can review this trainer after a completed session.'),
      findsOneWidget,
    );
    expect(find.text('Aisha M.'), findsOneWidget);
  });

  testWidgets('a trainer reads their reviews, or a hint when there are none', (
    tester,
  ) async {
    final api = _FakeApi(
      summary: const ReviewSummary(average: 4, count: 2),
      list: _published,
    );
    await tester.pumpWidget(_wrap(const TrainerReviewsPage(), api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reviews-summary')), findsOneWidget);
    expect(find.text('Clean and friendly'), findsOneWidget);

    // A fresh page, not the previous one's State reused.
    final empty = _FakeApi();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_wrap(const TrainerReviewsPage(), empty));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('trainer-reviews-empty')), findsOneWidget);
  });

  test('ratings parse from numbers or legacy decimal strings', () {
    final gym = Gym.fromJson({'id': 'g', 'rating': '4.50', 'reviewCount': 3});
    expect(gym.rating, 4.5);
    expect(gym.reviewCount, 3);
    expect(Gym.fromJson({'id': 'g'}).rating, 0);
    final trainer = TrainerProfile.fromJson({
      'id': 't',
      'rating': 3.5,
      'reviewCount': 2,
    });
    expect(trainer.withRating(4, 3).rating, 4);
    expect(trainer.withRating(4, 3).displayName, trainer.displayName);

    final summary = ReviewSummary.fromJson({
      'averageRating': null,
      'reviewCount': 0,
      'distribution': {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0},
    });
    expect(summary.average, isNull);
    expect(summary.distribution[5], 0);
    final review = Review.fromJson({
      'id': 'r',
      'rating': 4,
      'memberName': 'Aisha M.',
      'createdAt': '2026-09-20T10:00:00.000Z',
    });
    expect(review.createdAt, DateTime.utc(2026, 9, 20, 10));
  });

  test('every review string exists in English and Swahili', () {
    final en = FFLocale.keysOf('en').where((k) => k.startsWith('reviews.'));
    final sw = FFLocale.keysOf('sw').where((k) => k.startsWith('reviews.'));
    expect(en.toSet(), sw.toSet());
    expect(en, isNotEmpty);
  });
}
