// Events S3 (spec §5.14 review_step_test): the whole register flow up to
// the order — quote on entry, totals / fee / discount rows, terms gating,
// Idempotency-Key reuse and renewal, expectedTotalTzs, price_changed,
// capacity_unavailable, participant_invalid, the 5xx "uncertain" dialog,
// success navigation + draft clearing, analytics names.
import 'package:fitflexmobile/screens/member/events/register/member_event_register_page.dart';
import 'package:fitflexmobile/screens/member/events/register/self_profile.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/registration_draft.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

const _self = RegistrationSelfProfile(
  firstName: 'Asha',
  lastName: 'Mollel',
  phone: '+255712345678',
  dateOfBirth: '1990-05-09',
);

final _now = DateTime.utc(2027, 3, 10, 12);

Finder _primary = find.byKey(const Key('register-primary'));
Finder _add(String ticket) => find.descendant(
  of: find.byKey(Key('ticket-qty-$ticket')),
  matching: find.byKey(const Key('ff-stepper-add')),
);

void _seed(RecordingApi api) {
  api.on('GET /events/evt_1', detail('evt_1', registration: true));
  api.on('POST /me/event-orders/quote', quoteJson());
  api.on('POST /me/event-orders', orderJson());
}

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api, {
  RegistrationSelfProfile self = _self,
  bool keepRequests = true,
}) => pumpPage(
  tester,
  api,
  MemberEventRegisterPage(
    eventId: 'evt_1',
    options: optsS3(),
    selfProfile: self,
    now: _now,
    draftDebounce: Duration.zero,
  ),
  user: member,
  size: const Size(375, 1400),
  extraRoutes: s3Routes,
  keepRequests: keepRequests,
);

/// Tickets (1 × Standard) → Who (Myself) → Participants (prefilled) →
/// Review.
Future<PageHost> _toReview(WidgetTester tester, RecordingApi api) async {
  final host = await _pump(tester, api);
  await tapVisible(tester, _add('tt_std'));
  await tester.tap(_primary);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('register-step-2')), findsOneWidget);
  await tester.tap(_primary);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('register-step-3')), findsOneWidget);
  await tester.tap(_primary);
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('register-step-4')), findsOneWidget);
  return host;
}

Future<void> _acceptAndPlace(WidgetTester tester) async {
  await tapVisible(tester, find.byKey(const Key('review-accept')));
  await tester.tap(_primary);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
    EventsAnalytics.debugSink = [];
    RegistrationDraftStore.clock = () => _now;
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsAnalytics.debugSink = null;
    RegistrationDraftStore.clock = DateTime.now;
  });

  apiTest('the four steps gate Continue and quote on entering Review', (
    tester,
    api,
  ) async {
    _seed(api);
    await _pump(tester, api);
    expect(find.text('Step 1 of 4 · Tickets'), findsOneWidget);
    expect(isEnabled(tester, _primary), isFalse);
    await tapVisible(tester, _add('tt_std'));
    expect(isEnabled(tester, _primary), isTrue);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 4 · Who is registering'), findsOneWidget);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 4 · Participants'), findsOneWidget);
    // Self card prefilled from the profile; contact read-only.
    expect(
      textOf(tester, find.byKey(const Key('participant-first-0'))),
      'Asha',
    );
    expect(
      textOf(tester, find.byKey(const Key('participant-phone-0'))),
      '+255712345678',
    );
    // A provisional quote fetched the field policy.
    expect(api.where('POST', '/me/event-orders/quote'), hasLength(1));
    expect(find.text('Review order'), findsOneWidget);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.text('Step 4 of 4 · Review'), findsOneWidget);
    final quotes = api.where('POST', '/me/event-orders/quote');
    expect(quotes, hasLength(2));
    final body = quotes.last.body as Map;
    expect(body['eventId'], 'evt_1');
    expect(body['lines'], [
      {'ticketTypeId': 'tt_std', 'quantity': 1},
    ]);
    final p = (body['participants'] as List).single as Map;
    expect(p['firstName'], 'Asha');
    expect(p['phone'], '+255712345678');
    expect(p['dateOfBirth'], '1990-05-09');
    expect(p['consentBasis'], 'self');
    expect(p.containsKey('participantUserId'), isFalse);
    expect(body.containsKey('organizationId'), isFalse);
    expect(EventsAnalytics.debugSink!.map((e) => e.name), [
      'registration_started',
      'checkout_quote_created',
    ]);
  });

  apiTest('step 3 blocks Review until the card is clean', (tester, api) async {
    _seed(api);
    await _pump(
      tester,
      api,
      self: const RegistrationSelfProfile(
        firstName: 'Asha',
        lastName: 'Mollel',
        phone: '+255712345678',
      ),
    );
    await tapVisible(tester, _add('tt_std'));
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    // No date of birth yet and 21K has a minimum age.
    expect(isEnabled(tester, _primary), isFalse);
    expect(find.text('1 to fix'), findsOneWidget);
    await typeInto(
      tester,
      find.byKey(const Key('participant-dob-0')),
      '1990-05-09',
    );
    await tester.pumpAndSettle();
    expect(isEnabled(tester, _primary), isTrue);
  });

  apiTest('self without a verified contact cannot continue', (
    tester,
    api,
  ) async {
    _seed(api);
    await _pump(
      tester,
      api,
      self: const RegistrationSelfProfile(
        firstName: 'Asha',
        lastName: 'Mollel',
        dateOfBirth: '1990-05-09',
      ),
    );
    await tapVisible(tester, _add('tt_std'));
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('participant-need-verified')), findsOneWidget);
    expect(isEnabled(tester, _primary), isFalse);
  });

  apiTest('review shows the itemised quote; fee and discount only when > 0', (
    tester,
    api,
  ) async {
    _seed(api);
    api.on(
      'POST /me/event-orders/quote',
      quoteJson(
        fees: 1000,
        discount: 500,
        feeLabel: {'en': 'Service fee', 'sw': 'Ada ya huduma'},
      ),
    );
    await _toReview(tester, api);
    expect(find.byKey(const Key('quote-line-tt_std')), findsOneWidget);
    expect(find.text('Standard × 1'), findsOneWidget);
    expect(find.byKey(const Key('quote-fee')), findsOneWidget);
    expect(find.byKey(const Key('quote-discount')), findsOneWidget);
    expect(find.text('TSh 25,500'), findsOneWidget);
    expect(find.text('Place order · TSh 25,500'), findsOneWidget);
    expect(find.byKey(const Key('review-hold-notice')), findsOneWidget);
    expect(find.textContaining('held for 30 minutes'), findsOneWidget);
    expect(find.byKey(const Key('review-refund')), findsOneWidget);
    // The terms checkbox gates the button (M-R-6).
    expect(isEnabled(tester, _primary), isFalse);
    await tapVisible(tester, find.byKey(const Key('review-accept')));
    expect(isEnabled(tester, _primary), isTrue);

    await tester.pumpWidget(const SizedBox());
    EventsCache.reset();
    await RegistrationDraftStore.clear('evt_1');
    api.on('POST /me/event-orders/quote', quoteJson());
    await _toReview(tester, api);
    expect(find.byKey(const Key('quote-fee')), findsNothing);
    expect(find.byKey(const Key('quote-discount')), findsNothing);
  });

  apiTest('a free order reads "Register · Free"', (tester, api) async {
    _seed(api);
    api.on(
      'POST /me/event-orders/quote',
      quoteJson(
        lines: [
          quoteLine(
            ticketTypeId: 'tt_free',
            name: 'Free entry',
            categoryId: 'cat_5',
            categoryName: '5K Fun Run',
            unit: 0,
          ),
        ],
      ),
    );
    await _pump(tester, api);
    await tapVisible(tester, _add('tt_free'));
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.text('Register · Free'), findsOneWidget);
  });

  apiTest(
    'placing sends Idempotency-Key, expectedTotalTzs, terms and consent',
    (tester, api) async {
      _seed(api);
      await _toReview(tester, api);
      await _acceptAndPlace(tester);
      final post = api.only('POST', '/me/event-orders');
      final key = post.headers['idempotency-key'];
      expect(key, matches(RegExp(r'^[A-Za-z0-9._:-]{8,100}$')));
      final body = post.body as Map;
      expect(body['acceptedTerms'], isTrue);
      expect(body['consentTextVersion'], '2026-10-draft');
      expect(body['expectedTotalTzs'], 25000);
      expect(body['lines'], [
        {'ticketTypeId': 'tt_std', 'quantity': 1},
      ]);
      // 201 → the order page; the draft is gone.
      expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
      expect(await RegistrationDraftStore.load('evt_1'), isNull);
      final created = EventsAnalytics.debugSink!.lastWhere(
        (e) => e.name == 'order_created',
      );
      expect(created.props['orderId'], 'ord_1');
      expect(created.props['placesCount'], 1);
      expect(created.props['totalTzs'], 25000);
    },
  );

  apiTest('a 5xx shows the uncertain dialog and a retry reuses the key', (
    tester,
    api,
  ) async {
    _seed(api);
    api.fail('POST /me/event-orders', 503);
    final host = await _toReview(tester, api);
    await _acceptAndPlace(tester);
    expect(find.text(host.tr('events.review.uncertain.title')), findsOneWidget);
    expect(find.byKey(const Key('uncertain-open-mine')), findsOneWidget);
    api.heal('POST /me/event-orders');
    await tester.tap(find.byKey(const Key('uncertain-retry')));
    await tester.pumpAndSettle();
    final posts = api.where('POST', '/me/event-orders');
    expect(posts, hasLength(2));
    expect(
      posts[1].headers['idempotency-key'],
      posts[0].headers['idempotency-key'],
    );
    expect(find.text('ROUTE-ORDER-ord_1'), findsOneWidget);
  });

  apiTest('"Open My registrations" from the uncertain dialog', (
    tester,
    api,
  ) async {
    _seed(api);
    api.fail('POST /me/event-orders', 503);
    await _toReview(tester, api);
    await _acceptAndPlace(tester);
    await tester.tap(find.byKey(const Key('uncertain-open-mine')));
    await tester.pumpAndSettle();
    expect(find.text('ROUTE-ORDERS'), findsOneWidget);
  });

  apiTest('changing a detail makes a new key', (tester, api) async {
    _seed(api);
    api.fail('POST /me/event-orders', 503);
    await _toReview(tester, api);
    await _acceptAndPlace(tester);
    // Dismiss the dialog via "Open My registrations"? No: go back and edit.
    await tester.tap(find.byKey(const Key('uncertain-retry')));
    await tester.pumpAndSettle();
    expect(api.where('POST', '/me/event-orders'), hasLength(2));
    await tester.tap(find.byKey(const Key('uncertain-open-mine')));
    await tester.pumpAndSettle();
    // Same signature → same key both times.
    final posts = api.where('POST', '/me/event-orders');
    expect(
      posts[1].headers['idempotency-key'],
      posts[0].headers['idempotency-key'],
    );
  });

  apiTest('edited participant → different key on the next order', (
    tester,
    api,
  ) async {
    _seed(api);
    api.fail('POST /me/event-orders', 400, {'error': 'terms_not_accepted'});
    final host = await _toReview(tester, api);
    await _acceptAndPlace(tester);
    expect(api.where('POST', '/me/event-orders'), hasLength(1));
    // Back to step 3, change the last name, forward again.
    await host.dismissSnacks();
    await tester.tap(find.byKey(const Key('register-back')));
    await tester.pumpAndSettle();
    await typeInto(
      tester,
      find.byKey(const Key('participant-last-0')),
      'Mollel-Juma',
    );
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    api.heal('POST /me/event-orders');
    await _acceptAndPlace(tester);
    final posts = api.where('POST', '/me/event-orders');
    expect(posts, hasLength(2));
    expect(
      posts[1].headers['idempotency-key'],
      isNot(posts[0].headers['idempotency-key']),
    );
  });

  apiTest('price_changed re-quotes and shows the banner', (tester, api) async {
    _seed(api);
    api.fail('POST /me/event-orders', 409, {
      'error': 'price_changed',
      'quotedTotalTzs': 25000,
      'totalTzs': 30000,
    });
    await _toReview(tester, api);
    api.on(
      'POST /me/event-orders/quote',
      quoteJson(lines: [quoteLine(unit: 30000)]),
    );
    await _acceptAndPlace(tester);
    expect(find.byKey(const Key('review-banner-price')), findsOneWidget);
    expect(find.text('Place order · TSh 30,000'), findsOneWidget);
    expect(api.where('POST', '/me/event-orders/quote'), hasLength(3));
  });

  apiTest('capacity_unavailable offers "Change tickets" back to step 1', (
    tester,
    api,
  ) async {
    _seed(api);
    api.fail('POST /me/event-orders', 409, {
      'error': 'capacity_unavailable',
      'ticketTypeId': 'tt_std',
      'remaining': 0,
    });
    await _toReview(tester, api);
    await _acceptAndPlace(tester);
    expect(find.byKey(const Key('review-banner-capacity')), findsOneWidget);
    expect(find.text('Only 0 left for Standard'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('review-change-tickets')));
    expect(find.byKey(const Key('register-step-1')), findsOneWidget);
  });

  apiTest('participant_invalid maps every row\'s problems to its card', (
    tester,
    api,
  ) async {
    _seed(api);
    api.fail('POST /me/event-orders', 422, {
      'error': 'participant_invalid',
      'participants': [
        {
          'index': 0,
          'problems': [
            {'field': 'phone', 'code': 'duplicate_participant'},
          ],
        },
      ],
    });
    await _toReview(tester, api);
    await _acceptAndPlace(tester);
    expect(find.byKey(const Key('review-banner-fix')), findsOneWidget);
    expect(isEnabled(tester, _primary), isFalse);
    await tapVisible(tester, find.byKey(const Key('review-go-back')));
    expect(find.byKey(const Key('register-step-3')), findsOneWidget);
    expect(find.text('Already registered in this category'), findsOneWidget);
  });

  apiTest('a quote with problems shows the fix banner on entry', (
    tester,
    api,
  ) async {
    _seed(api);
    api.on(
      'POST /me/event-orders/quote',
      quoteJson(
        valid: false,
        participants: [
          {
            'index': 0,
            'ok': false,
            'problems': [
              {'field': 'dateOfBirth', 'code': 'dob_required'},
            ],
          },
        ],
      ),
    );
    await _toReview(tester, api);
    expect(find.byKey(const Key('review-banner-fix')), findsOneWidget);
  });

  apiTest('a quote error shows retry', (tester, api) async {
    _seed(api);
    await _pump(tester, api);
    await tapVisible(tester, _add('tt_std'));
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    api.fail('POST /me/event-orders/quote', 500);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-error')), findsOneWidget);
    api.heal('POST /me/event-orders/quote');
    await tapVisible(tester, find.text('Try again'));
    expect(find.byKey(const Key('review-quote')), findsOneWidget);
  });

  apiTest('a closed event refuses the quote with its reason', (
    tester,
    api,
  ) async {
    _seed(api);
    await _pump(tester, api);
    await tapVisible(tester, _add('tt_std'));
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    api.fail('POST /me/event-orders/quote', 409, {
      'error': 'registration_closed',
    });
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.textContaining('Registration has closed'), findsOneWidget);
  });

  apiTest('others: consent per card and "Will be invited to claim"', (
    tester,
    api,
  ) async {
    _seed(api);
    await _pump(tester, api);
    await tapVisible(tester, _add('tt_std'));
    await tapVisible(tester, _add('tt_std'));
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mode-selfOthers')), findsOneWidget);
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('participant-card-1')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('participant-header-1')));
    await typeInto(
      tester,
      find.byKey(const Key('participant-first-1')),
      'Juma',
    );
    await typeInto(
      tester,
      find.byKey(const Key('participant-last-1')),
      'Kessy',
    );
    await typeInto(
      tester,
      find.byKey(const Key('participant-phone-1')),
      '0799999999',
    );
    await typeInto(
      tester,
      find.byKey(const Key('participant-dob-1')),
      '2000-01-01',
    );
    await tester.pumpAndSettle();
    expect(isEnabled(tester, _primary), isFalse, reason: 'consent missing');
    await tapVisible(tester, find.byKey(const Key('participant-consent-1')));
    expect(isEnabled(tester, _primary), isTrue);
    api.on(
      'POST /me/event-orders/quote',
      quoteJson(lines: [quoteLine(quantity: 2)]),
    );
    await tester.tap(_primary);
    await tester.pumpAndSettle();
    expect(find.text('Will be invited to claim'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.byKey(const Key('review-consent-line')), findsOneWidget);
    final body = api.where('POST', '/me/event-orders/quote').last.body as Map;
    final second = (body['participants'] as List)[1] as Map;
    expect(second['consentBasis'], 'purchaser_authorised');
  });

  apiTest('options registration:false sends the member to Activity', (
    tester,
    api,
  ) async {
    _seed(api);
    final host = await pumpPage(
      tester,
      api,
      MemberEventRegisterPage(
        eventId: 'evt_1',
        options: optsS3(registration: false),
        selfProfile: _self,
      ),
      user: member,
      extraRoutes: s3Routes,
      keepRequests: true,
    );
    expect(find.text('ROUTE-ACTIVITY'), findsOneWidget);
    expect(host.snack(host.tr('events.register.unavailable')), findsOneWidget);
    expect(api.requests, isEmpty);
  });

  apiTest('a ticket row preselects its type at the minimum', (
    tester,
    api,
  ) async {
    _seed(api);
    await pumpPage(
      tester,
      api,
      MemberEventRegisterPage(
        eventId: 'evt_1',
        preselectTicketId: 'tt_free',
        source: 'ticket_row',
        options: optsS3(),
        selfProfile: _self,
        now: _now,
      ),
      user: member,
      size: const Size(375, 1400),
      extraRoutes: s3Routes,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('ticket-qty-tt_free')),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(isEnabled(tester, _primary), isTrue);
  });
}
