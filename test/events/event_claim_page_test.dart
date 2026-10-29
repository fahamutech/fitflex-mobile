// Events S3 (spec §5.14 event_claim_page_test): link mode keeps the token
// from `/event-claim/#tok` and the legacy path, preview card (masked only),
// claim success, claim_not_verified with verifiable true/false, expired /
// invalid, in-app mode, signed-out link.
import 'package:fitflexmobile/screens/member/events/event_claim_page.dart';
import 'package:fitflexmobile/shared/events/event_claim_link.dart';
import 'package:fitflexmobile/shared/events/events_analytics.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

const _tok = 'AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcdefg';

Future<PageHost> _pumpLink(
  WidgetTester tester,
  RecordingApi api, {
  bool smsCodes = true,
}) => pumpPage(
  tester,
  api,
  EventClaimPage.link(options: optsS3(smsCodes: smsCodes)),
  user: member,
  size: const Size(375, 1200),
  extraRoutes: s3Routes,
  keepRequests: true,
);

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsAnalytics.debugSink = [];
    PendingEventClaim.resetMemory();
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    EventsAnalytics.debugSink = null;
  });

  group('link parsing', () {
    test('fragment, full address and legacy path carry a token', () {
      expect(eventClaimLinkFrom(Uri.parse('/event-claim/#$_tok'))?.token, _tok);
      expect(
        eventClaimLinkFrom(
          Uri.parse('https://fitflex-af-app.web.app/event-claim/#$_tok'),
        )?.token,
        _tok,
      );
      expect(eventClaimLinkFrom(Uri.parse('/event-claim/$_tok'))?.token, _tok);
      expect(eventClaimLinkFrom(Uri.parse('/event-claim/#bad!')), isNotNull);
      expect(
        eventClaimLinkFrom(Uri.parse('/event-claim/#bad!'))?.token,
        isNull,
      );
      expect(eventClaimLinkFrom(Uri.parse('/event-claim')), isNull);
      expect(eventClaimLinkFrom(Uri.parse('/member/events/e1')), isNull);
    });

    test('the kept token survives a reload for a day, then expires', () async {
      SharedPreferences.setMockInitialValues({});
      var now = DateTime.utc(2027, 3, 10, 12);
      PendingEventClaim.clock = () => now;
      await PendingEventClaim.save(_tok);
      PendingEventClaim.resetMemory();
      PendingEventClaim.clock = () => now;
      expect(await PendingEventClaim.peek(), _tok);
      now = now.add(const Duration(hours: 25));
      PendingEventClaim.resetMemory();
      PendingEventClaim.clock = () => now;
      expect(await PendingEventClaim.peek(), isNull);
    });
  });

  apiTest('link mode: masked preview, then claim by token', (
    tester,
    api,
  ) async {
    await PendingEventClaim.save(_tok);
    api.on('GET /event-claims/preview/$_tok', claimPreviewJson());
    api.on('POST /me/event-registrations/claim', {
      'registration': registrationJson(id: 'reg_9', relation: 'claimed'),
    });
    final host = await _pumpLink(tester, api);
    expect(api.only('GET', '/event-claims/preview/$_tok'), isNotNull);
    expect(find.byKey(const Key('claim-card')), findsOneWidget);
    expect(
      find.textContaining('N**** A******* registered A*** M.'),
      findsOneWidget,
    );
    expect(find.textContaining('10K, Sun 14 Mar 2027'), findsOneWidget);
    expect(
      find.text(
        'To claim it, the number ending ••• 678 must be verified on your account.',
      ),
      findsOneWidget,
    );
    expect(find.text('Yes, this is me — claim my place'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('claim-confirm')));
    expect(api.only('POST', '/me/event-registrations/claim').body, {
      'token': _tok,
    });
    expect(host.snack(host.tr('events.claim.done')), findsOneWidget);
    expect(find.text('ROUTE-REG-reg_9'), findsOneWidget);
    expect(await PendingEventClaim.peek(), isNull);
    final a = EventsAnalytics.debugSink!.single;
    expect(a.name, 'registration_claimed');
    expect(a.props['via'], 'link');
  });

  apiTest('claim_not_verified with a verifiable contact offers Verify now', (
    tester,
    api,
  ) async {
    await PendingEventClaim.save(_tok);
    api.on('GET /event-claims/preview/$_tok', claimPreviewJson());
    api.fail('POST /me/event-registrations/claim', 403, {
      'error': 'claim_not_verified',
    });
    await _pumpLink(tester, api);
    await tapVisible(tester, find.byKey(const Key('claim-confirm')));
    expect(find.byKey(const Key('claim-not-verified')), findsOneWidget);
    expect(find.text('Verify ••• 678 to claim'), findsOneWidget);
    expect(find.byKey(const Key('claim-verify-now')), findsOneWidget);
    expect(find.byKey(const Key('claim-email-not-yet')), findsNothing);
    expect(
      await PendingEventClaim.peek(),
      _tok,
      reason: 'kept for after verifying',
    );
  });

  apiTest('claim_not_verified for email (not verifiable) explains', (
    tester,
    api,
  ) async {
    await PendingEventClaim.save(_tok);
    api.on('GET /event-claims/preview/$_tok', claimPreviewJson(type: 'email'));
    api.fail('POST /me/event-registrations/claim', 403, {
      'error': 'claim_not_verified',
    });
    await _pumpLink(tester, api);
    await tapVisible(tester, find.byKey(const Key('claim-confirm')));
    expect(find.byKey(const Key('claim-verify-now')), findsNothing);
    expect(find.byKey(const Key('claim-email-not-yet')), findsOneWidget);
    expect(
      find.textContaining('ask N**** to use your phone number instead'),
      findsOneWidget,
    );
  });

  apiTest(
    'phone not verifiable (smsCodes off): explains instead of Verify now',
    (tester, api) async {
      await PendingEventClaim.save(_tok);
      api.on('GET /event-claims/preview/$_tok', claimPreviewJson());
      api.fail('POST /me/event-registrations/claim', 403, {
        'error': 'claim_not_verified',
      });
      await _pumpLink(tester, api, smsCodes: false);
      await tapVisible(tester, find.byKey(const Key('claim-confirm')));
      expect(find.byKey(const Key('claim-verify-now')), findsNothing);
      expect(find.byKey(const Key('claim-email-not-yet')), findsOneWidget);
    },
  );

  apiTest('expired (410) and invalid (404) links', (tester, api) async {
    await PendingEventClaim.save(_tok);
    api.fail('GET /event-claims/preview/$_tok', 410, {
      'error': 'claim_token_expired',
    });
    await _pumpLink(tester, api);
    expect(
      find.byKey(const Key('claim-refused-claim_token_expired')),
      findsOneWidget,
    );
    expect(find.textContaining('This link has expired'), findsOneWidget);
    expect(find.byKey(const Key('claim-confirm')), findsNothing);
    expect(await PendingEventClaim.peek(), isNull);

    await tester.pumpWidget(const SizedBox());
    await PendingEventClaim.save(_tok);
    api.fail('GET /event-claims/preview/$_tok', 404, {
      'error': 'claim_token_invalid',
    });
    await _pumpLink(tester, api);
    expect(find.text('This link isn\'t valid'), findsOneWidget);
  });

  apiTest('no kept token: the link is not valid', (tester, api) async {
    await _pumpLink(tester, api);
    expect(
      find.byKey(const Key('claim-refused-claim_token_invalid')),
      findsOneWidget,
    );
    expect(api.requests, isEmpty);
  });

  apiTest('already_claimed and closed-state refusals', (tester, api) async {
    await PendingEventClaim.save(_tok);
    api.on('GET /event-claims/preview/$_tok', claimPreviewJson());
    api.fail('POST /me/event-registrations/claim', 409, {
      'error': 'already_claimed',
    });
    await _pumpLink(tester, api);
    await tapVisible(tester, find.byKey(const Key('claim-confirm')));
    expect(
      find.text(
        'This place was already claimed by another account. Contact support.',
      ),
      findsOneWidget,
    );
  });

  apiTest(
    'signed out: preview shows, the button leads to sign-in, token kept',
    (tester, api) async {
      await PendingEventClaim.save(_tok);
      api.on('GET /event-claims/preview/$_tok', claimPreviewJson());
      final host = await _pumpLink(tester, api);
      await host.auth.signOut();
      await tester.pumpAndSettle();
      expect(find.text('Sign in to claim your place'), findsOneWidget);
      await tapVisible(tester, find.byKey(const Key('claim-confirm')));
      expect(find.text('ROUTE-LANGUAGE'), findsOneWidget);
      expect(api.where('POST', '/me/event-registrations/claim'), isEmpty);
    },
  );

  apiTest('"Not me" clears the token and leaves', (tester, api) async {
    await PendingEventClaim.save(_tok);
    api.on('GET /event-claims/preview/$_tok', claimPreviewJson());
    await _pumpLink(tester, api);
    await tapVisible(tester, find.byKey(const Key('claim-not-me')));
    expect(await PendingEventClaim.peek(), isNull);
    expect(find.text('ROUTE-ACTIVITY'), findsOneWidget);
  });

  apiTest('in-app mode claims by id from the claimable row', (
    tester,
    api,
  ) async {
    api.on('GET /me/event-registrations/claimable', {
      'items': [claimableJson()],
    });
    api.on('POST /me/event-registrations/reg_9/claim', {
      'registration': registrationJson(id: 'reg_9', relation: 'claimed'),
    });
    await pumpPage(
      tester,
      api,
      EventClaimPage.inApp(registrationId: 'reg_9', options: optsS3()),
      user: member,
      size: const Size(375, 1200),
      extraRoutes: s3Routes,
      keepRequests: true,
    );
    expect(find.byKey(const Key('claim-card')), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('claim-confirm')));
    expect(api.only('POST', '/me/event-registrations/reg_9/claim').body, {});
    expect(find.text('ROUTE-REG-reg_9'), findsOneWidget);
    expect(EventsAnalytics.debugSink!.single.props['via'], 'in_app');
  });

  apiTest(
    'in-app mode with registration:false redirects; link mode keeps the token',
    (tester, api) async {
      final host = await pumpPage(
        tester,
        api,
        EventClaimPage.inApp(
          registrationId: 'reg_9',
          options: optsS3(registration: false),
        ),
        user: member,
        extraRoutes: s3Routes,
        keepRequests: true,
      );
      expect(find.text('ROUTE-ACTIVITY'), findsOneWidget);
      expect(
        host.snack(host.tr('events.register.unavailable')),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await PendingEventClaim.save(_tok);
      api.fail('GET /event-claims/preview/$_tok', 404, {
        'error': 'feature_disabled',
      });
      await pumpPage(
        tester,
        api,
        EventClaimPage.link(options: optsS3(registration: false)),
        user: member,
        extraRoutes: s3Routes,
      );
      expect(
        find.byKey(const Key('claim-refused-feature_disabled')),
        findsOneWidget,
      );
      expect(await PendingEventClaim.peek(), _tok);
    },
  );

  // ── Events S4 (spec §5.9): the claim landing is live ────────────────────

  group('S4: paid places', () {
    apiTest('a confirmed place says it is paid and confirmed', (
      tester,
      api,
    ) async {
      await PendingEventClaim.save(_tok);
      api.on(
        'GET /event-claims/preview/$_tok',
        claimPreviewJson(status: 'confirmed'),
      );
      final host = await _pumpLink(tester, api);
      expect(find.byKey(const Key('claim-paid')), findsOneWidget);
      expect(find.text(host.tr('events.claim.paid')), findsOneWidget);
      expect(
        find.text(
          'This place is paid and confirmed. Claim it to get your ticket.',
        ),
        findsOneWidget,
      );
    });

    apiTest('a reserved place keeps the S3 text (no paid line)', (
      tester,
      api,
    ) async {
      await PendingEventClaim.save(_tok);
      api.on('GET /event-claims/preview/$_tok', claimPreviewJson());
      await _pumpLink(tester, api);
      expect(find.byKey(const Key('claim-paid')), findsNothing);
    });

    apiTest('claiming a paid place lands on its ticket', (tester, api) async {
      await PendingEventClaim.save(_tok);
      api.on(
        'GET /event-claims/preview/$_tok',
        claimPreviewJson(status: 'confirmed'),
      );
      api.on('POST /me/event-registrations/claim', {
        'registration': registrationJson(
          id: 'reg_9',
          status: 'confirmed',
          orderStatus: 'confirmed',
          relation: 'claimed',
          ticket: {'state': 'active', 'displayCode': 'T-3F9A2B'},
        ),
      });
      final host = await _pumpLink(tester, api);
      await tapVisible(tester, find.byKey(const Key('claim-confirm')));
      expect(host.snack(host.tr('events.claim.done')), findsOneWidget);
      expect(find.text('ROUTE-TICKET-reg_9'), findsOneWidget);
      expect(await PendingEventClaim.peek(), isNull);
    });

    apiTest('a confirmed place whose answer names no ticket is still tried', (
      tester,
      api,
    ) async {
      await PendingEventClaim.save(_tok);
      api.on(
        'GET /event-claims/preview/$_tok',
        claimPreviewJson(status: 'confirmed'),
      );
      api.on('POST /me/event-registrations/claim', {
        'registration': registrationJson(
          id: 'reg_9',
          status: 'confirmed',
          orderStatus: 'confirmed',
          relation: 'claimed',
        ),
      });
      await _pumpLink(tester, api);
      await tapVisible(tester, find.byKey(const Key('claim-confirm')));
      expect(find.text('ROUTE-TICKET-reg_9'), findsOneWidget);
    });

    apiTest('a revoked ticket lands on the registration instead', (
      tester,
      api,
    ) async {
      await PendingEventClaim.save(_tok);
      api.on(
        'GET /event-claims/preview/$_tok',
        claimPreviewJson(status: 'confirmed'),
      );
      api.on('POST /me/event-registrations/claim', {
        'registration': registrationJson(
          id: 'reg_9',
          status: 'confirmed',
          orderStatus: 'confirmed',
          relation: 'claimed',
          ticket: {'state': 'revoked'},
        ),
      });
      await _pumpLink(tester, api);
      await tapVisible(tester, find.byKey(const Key('claim-confirm')));
      expect(find.text('ROUTE-REG-reg_9'), findsOneWidget);
    });

    apiTest('an expired link says who to ask for a new one', (
      tester,
      api,
    ) async {
      await PendingEventClaim.save(_tok);
      api.fail('GET /event-claims/preview/$_tok', 410, {
        'error': 'claim_token_expired',
      });
      await _pumpLink(tester, api);
      expect(
        find.text(
          'Ask the person who registered you to send the invitation again.',
        ),
        findsOneWidget,
      );
      expect(await PendingEventClaim.peek(), isNull);
    });

    apiTest('an expired link at claim time names the purchaser', (
      tester,
      api,
    ) async {
      await PendingEventClaim.save(_tok);
      api.on(
        'GET /event-claims/preview/$_tok',
        claimPreviewJson(status: 'confirmed'),
      );
      api.fail('POST /me/event-registrations/claim', 410, {
        'error': 'claim_token_expired',
      });
      await _pumpLink(tester, api);
      await tapVisible(tester, find.byKey(const Key('claim-confirm')));
      expect(
        find.text('Ask N**** to send the invitation again.'),
        findsOneWidget,
      );
    });

    apiTest('a cancelled or refunded place is no longer active', (
      tester,
      api,
    ) async {
      await PendingEventClaim.save(_tok);
      api.on(
        'GET /event-claims/preview/$_tok',
        claimPreviewJson(status: 'confirmed'),
      );
      api.fail('POST /me/event-registrations/claim', 409, {
        'error': 'registration_closed_state',
      });
      await _pumpLink(tester, api);
      await tapVisible(tester, find.byKey(const Key('claim-confirm')));
      expect(
        find.byKey(const Key('claim-refused-registration_closed_state')),
        findsOneWidget,
      );
      expect(
        find.text('This registration is no longer active'),
        findsOneWidget,
      );
    });
  });
}
