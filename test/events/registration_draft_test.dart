// Events S3 (spec §5.14 registration_draft_test): save / restore / expiry /
// clear, the resume dialog, nothing sent before the quote.
import 'dart:convert';

import 'package:fitflexmobile/screens/member/events/register/member_event_register_page.dart';
import 'package:fitflexmobile/screens/member/events/register/self_profile.dart';
import 'package:fitflexmobile/shared/events/events_cache.dart';
import 'package:fitflexmobile/shared/events/events_checkout.dart';
import 'package:fitflexmobile/shared/events/registration_draft.dart';
import 'package:fitflexmobile/shared/events_flag.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

const _self = RegistrationSelfProfile(
  firstName: 'Asha',
  lastName: 'Mollel',
  phone: '+255712345678',
  dateOfBirth: '1990-05-09',
);

RegistrationDraft _draft({DateTime? savedAt, int step = 1}) =>
    RegistrationDraft(
      eventId: 'evt_1',
      savedAt: savedAt ?? DateTime.utc(2027, 3, 9, 12),
      step: step,
      lines: const {'tt_std': 2},
      mode: 'selfOthers',
      team: const TeamChoice.create(name: 'Coco Runners', teamType: 'club'),
      participants: [
        EventParticipantInput(
          ticketTypeId: 'tt_std',
          categoryId: 'cat_21',
          isSelf: true,
          firstName: 'Asha',
          lastName: 'Mollel',
          phone: '+255712345678',
          dateOfBirth: '1990-05-09',
          emergencyName: 'Mama',
          emergencyPhone: '0712000000',
          consented: true,
        ),
        EventParticipantInput(
          ticketTypeId: 'tt_std',
          categoryId: 'cat_21',
          firstName: 'Juma',
          lastName: 'Kessy',
          phone: '0799999999',
          dateOfBirth: '2000-01-01',
          consented: true,
        ),
      ],
    );

void main() {
  setUp(() {
    debugEventsDiscoveryOverride = true;
    EventsCache.reset();
    RegistrationDraftStore.clock = () => DateTime.utc(2027, 3, 10, 12);
  });
  tearDown(() {
    debugEventsDiscoveryOverride = null;
    RegistrationDraftStore.clock = DateTime.now;
  });

  group('store', () {
    test('round-trips every field including the emergency contact', () async {
      SharedPreferences.setMockInitialValues({});
      await RegistrationDraftStore.save(_draft(step: 3));
      final back = await RegistrationDraftStore.load('evt_1');
      expect(back, isNotNull);
      expect(back!.step, 3);
      expect(back.lines, {'tt_std': 2});
      expect(back.mode, 'selfOthers');
      expect(back.team?.name, 'Coco Runners');
      expect(back.team?.teamType, 'club');
      expect(back.participants, hasLength(2));
      expect(back.participants.first.isSelf, isTrue);
      expect(back.participants.first.emergencyName, 'Mama');
      expect(back.participants.last.firstName, 'Juma');
      expect(back.participants.last.consented, isTrue);
    });

    test('a draft older than 7 days is dropped', () async {
      SharedPreferences.setMockInitialValues({});
      await RegistrationDraftStore.save(
        _draft(savedAt: DateTime.utc(2027, 3, 2, 11)),
      );
      expect(await RegistrationDraftStore.load('evt_1'), isNull);
      final p = await SharedPreferences.getInstance();
      expect(p.getString(RegistrationDraftStore.keyFor('evt_1')), isNull);
    });

    test('clear forgets it; unreadable JSON is ignored', () async {
      SharedPreferences.setMockInitialValues({
        RegistrationDraftStore.keyFor('evt_1'): 'not json',
      });
      expect(await RegistrationDraftStore.load('evt_1'), isNull);
      await RegistrationDraftStore.save(_draft());
      await RegistrationDraftStore.clear('evt_1');
      expect(await RegistrationDraftStore.load('evt_1'), isNull);
    });
  });

  apiTest('a kept draft is offered; Continue restores it; nothing is sent', (
    tester,
    api,
  ) async {
    SharedPreferences.setMockInitialValues({
      RegistrationDraftStore.keyFor('evt_1'): jsonEncode(_draft().toJson()),
    });
    api.on('GET /events/evt_1', detail('evt_1', registration: true));
    final host = await pumpPage(
      tester,
      api,
      MemberEventRegisterPage(
        eventId: 'evt_1',
        options: optsS3(),
        selfProfile: _self,
        now: DateTime.utc(2027, 3, 10, 12),
        draftDebounce: Duration.zero,
      ),
      user: member,
      size: const Size(375, 1200),
      extraRoutes: s3Routes,
      keepRequests: true,
    );
    expect(find.text(host.tr('events.draft.resume.title')), findsOneWidget);
    expect(
      find.text('You started registering for Dar Half Marathon on 9 Mar 2027.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('draft-continue')));
    await tester.pumpAndSettle();
    // Lines restored: the stepper for Standard reads 2.
    expect(
      find.descendant(
        of: find.byKey(const Key('ticket-qty-tt_std')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(api.where('POST', '/me/event-orders/quote'), isEmpty);
    expect(api.where('POST', '/me/event-orders'), isEmpty);
  });

  apiTest('Start over clears the draft', (tester, api) async {
    SharedPreferences.setMockInitialValues({
      RegistrationDraftStore.keyFor('evt_1'): jsonEncode(_draft().toJson()),
    });
    api.on('GET /events/evt_1', detail('evt_1', registration: true));
    await pumpPage(
      tester,
      api,
      MemberEventRegisterPage(
        eventId: 'evt_1',
        options: optsS3(),
        selfProfile: _self,
        now: DateTime.utc(2027, 3, 10, 12),
        draftDebounce: Duration.zero,
      ),
      user: member,
      size: const Size(375, 1200),
      extraRoutes: s3Routes,
    );
    await tester.tap(find.byKey(const Key('draft-discard')));
    await tester.pumpAndSettle();
    expect(await RegistrationDraftStore.load('evt_1'), isNull);
    expect(
      find.descendant(
        of: find.byKey(const Key('ticket-qty-tt_std')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
  });

  apiTest('changes are saved on this device and leaving says so', (
    tester,
    api,
  ) async {
    api.on('GET /events/evt_1', detail('evt_1', registration: true));
    final host = await pumpPage(
      tester,
      api,
      MemberEventRegisterPage(
        eventId: 'evt_1',
        options: optsS3(),
        selfProfile: _self,
        now: DateTime.utc(2027, 3, 10, 12),
        draftDebounce: Duration.zero,
      ),
      user: member,
      size: const Size(375, 1200),
      extraRoutes: s3Routes,
    );
    await tapVisible(
      tester,
      find.descendant(
        of: find.byKey(const Key('ticket-qty-tt_std')),
        matching: find.byKey(const Key('ff-stepper-add')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 10));
    final kept = await RegistrationDraftStore.load('evt_1');
    expect(kept?.lines, {'tt_std': 1});
    // Leaving from step 1 pops with the "saved" snack.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(host.snack(host.tr('events.draft.saved')), findsOneWidget);
    expect(find.text('ROUTE-EVENT-evt_1'), findsOneWidget);
  });
}
