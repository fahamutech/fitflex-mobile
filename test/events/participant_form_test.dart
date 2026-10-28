// Events S3 (spec §5.14 participant_form_test): fields from `fields`, the
// self card's read-only verified contact and missing-verified warning,
// per-card consent, the DOB picker, local validation (listed twice, age vs
// minAge on event day) and server problems on the card.
import 'package:fitflexmobile/screens/member/events/register/participant_form.dart';
import 'package:fitflexmobile/shared/events/event_detail.dart';
import 'package:fitflexmobile/shared/events/event_order.dart';
import 'package:fitflexmobile/shared/events/events_checkout.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

final _cat21 = EventDetail.fromJson(detail('evt_1')).categories.first;
final _start = DateTime.utc(2027, 3, 14, 3, 30);

EventParticipantInput _other({
  String first = 'Juma',
  String last = 'Kessy',
  String phone = '0712345678',
  String dob = '2000-01-01',
  bool consented = true,
}) => EventParticipantInput(
  ticketTypeId: 'tt_std',
  categoryId: 'cat_21',
  firstName: first,
  lastName: last,
  phone: phone,
  dateOfBirth: dob,
  consented: consented,
);

Future<PageHost> _pump(
  WidgetTester tester,
  RecordingApi api,
  EventParticipantInput p, {
  ParticipantFields fields = const ParticipantFields(
    dateOfBirth: FieldPolicy.required,
    kitSize: FieldPolicy.optional,
  ),
  Map<String, FieldProblem> problems = const {},
  bool selfVerified = true,
  bool expanded = true,
  String consentText = '',
  VoidCallback? onCopy,
}) => pumpPage(
  tester,
  api,
  StatefulBuilder(
    builder: (context, setState) => SingleChildScrollView(
      child: ParticipantForm(
        index: 0,
        total: 3,
        participant: p,
        fields: fields,
        category: _cat21,
        ticketName: 'Standard',
        problems: problems,
        expanded: expanded,
        consentText: consentText,
        selfHasVerifiedContact: selfVerified,
        onEditProfile: () {},
        onCopyEmergency: onCopy,
        onToggle: () {},
        onChanged: () => setState(() {}),
      ),
    ),
  ),
  user: member,
  size: const Size(375, 1600),
);

void main() {
  group('local validation (§3.11 subset)', () {
    test('age on event day: a birthday on event day counts', () {
      final day = DateTime(2027, 3, 14);
      expect(ageOn(DateTime(2009, 3, 14), day), 18);
      expect(ageOn(DateTime(2009, 3, 15), day), 17);
    });

    test('a complete other participant passes', () {
      final problems = validateParticipantLocally(
        _other(),
        fields: const ParticipantFields(dateOfBirth: FieldPolicy.required),
        minAge: 18,
        eventStartUtc: _start,
        offsetMinutes: 180,
        now: DateTime.utc(2027, 3, 10),
      );
      expect(problems, isEmpty);
    });

    test('required, invalid and under-age fields are named by code', () {
      final problems = validateParticipantLocally(
        _other(first: '', last: 'K3ssy', phone: 'abc', dob: '2015-06-01'),
        fields: const ParticipantFields(dateOfBirth: FieldPolicy.required),
        minAge: 18,
        eventStartUtc: _start,
        offsetMinutes: 180,
        now: DateTime.utc(2027, 3, 10),
      );
      expect(problems['firstName']?.code, 'required');
      expect(problems['lastName']?.code, 'name_invalid');
      expect(problems['phone']?.code, 'phone_invalid');
      expect(problems['dateOfBirth']?.code, 'age_not_eligible');
      expect(problems['dateOfBirth']?.extra?['minAge'], 18);
      expect(problems['dateOfBirth']?.extra?['ageOnEventDay'], 11);
    });

    test('a non-self row needs a contact and consent', () {
      final problems = validateParticipantLocally(
        _other(phone: '', consented: false),
        fields: const ParticipantFields(phone: FieldPolicy.optional),
      );
      expect(problems['phone']?.code, 'contact_required');
      expect(problems['consent']?.code, 'required');
    });

    test('fields the event does not collect are never checked', () {
      final problems = validateParticipantLocally(
        _other(phone: '', dob: 'nonsense'),
        fields: const ParticipantFields(
          phone: FieldPolicy.off,
          email: FieldPolicy.off,
          dateOfBirth: FieldPolicy.off,
        ),
      );
      expect(problems, isEmpty);
    });

    test(
      'listed twice: same phone (two spellings) or email in one category',
      () {
        final a = _other(phone: '0712345678');
        final b = _other(phone: '+255712345678');
        final c = _other(phone: '0799999999');
        expect(listedTwice([a, b, c]), {0, 1});
        final d = _other(phone: '')..email = 'X@Example.com';
        final e = _other(phone: '')..email = 'x@example.com';
        expect(listedTwice([d, e]), {0, 1});
        final f = EventParticipantInput(
          ticketTypeId: 'tt_free',
          categoryId: 'cat_5',
          phone: '0712345678',
        );
        expect(listedTwice([a, f]), isEmpty, reason: 'different categories');
      },
    );

    test('toJson drops fields the policy turns off', () {
      final p = _other()
        ..gender = 'female'
        ..kitSize = 'm';
      final json = p.toJson(
        const ParticipantFields(
          gender: FieldPolicy.off,
          kitSize: FieldPolicy.off,
        ),
      );
      expect(json.containsKey('gender'), isFalse);
      expect(json.containsKey('kitSize'), isFalse);
      expect(json['consentBasis'], 'purchaser_authorised');
      expect(json['phone'], '0712345678');
    });
  });

  apiTest('fields render from the policy: off fields are absent', (
    tester,
    api,
  ) async {
    await _pump(
      tester,
      api,
      _other(),
      fields: const ParticipantFields(
        dateOfBirth: FieldPolicy.required,
        gender: FieldPolicy.required,
        kitSize: FieldPolicy.off,
        emergencyContact: FieldPolicy.off,
      ),
    );
    expect(find.byKey(const Key('participant-first-0')), findsOneWidget);
    expect(find.byKey(const Key('participant-dob-0')), findsOneWidget);
    expect(find.byKey(const Key('participant-gender-0')), findsOneWidget);
    expect(find.byKey(const Key('participant-kit-0')), findsNothing);
    expect(find.byKey(const Key('participant-emname-0')), findsNothing);
    expect(
      find.text('Participant 1 of 3 · 21K Half Marathon · Standard'),
      findsOneWidget,
    );
    expect(
      find.text('Needed to check the age rule for 21K Half Marathon'),
      findsOneWidget,
    );
    expect(find.text('Prefer not to say'), findsOneWidget);
  });

  apiTest('self: contact read-only with the profile hint; no consent row', (
    tester,
    api,
  ) async {
    final p = _other()..isSelf = true;
    await _pump(tester, api, p);
    final phone = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('participant-phone-0')),
        matching: find.byType(TextField),
      ),
    );
    expect(phone.readOnly, isTrue);
    expect(find.text('From your verified profile'), findsWidgets);
    expect(find.byKey(const Key('participant-consent-0')), findsNothing);
    expect(find.byKey(const Key('participant-need-verified')), findsNothing);
  });

  apiTest('self without a verified contact: warning and Edit profile', (
    tester,
    api,
  ) async {
    final p = _other(phone: '')..isSelf = true;
    await _pump(tester, api, p, selfVerified: false);
    expect(find.byKey(const Key('participant-need-verified')), findsOneWidget);
    expect(
      find.text('Add a verified phone number to register yourself'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('participant-edit-profile')), findsOneWidget);
  });

  apiTest('others: the per-card consent row uses the quote copy', (
    tester,
    api,
  ) async {
    final p = _other(consented: false);
    await _pump(tester, api, p, consentText: 'I confirm I have permission.');
    expect(find.text('I confirm I have permission.'), findsOneWidget);
    await tapVisible(tester, find.byKey(const Key('participant-consent-0')));
    expect(p.consented, isTrue);
  });

  apiTest('the DOB picker writes YYYY-MM-DD into the field', (
    tester,
    api,
  ) async {
    final p = _other(dob: '');
    await _pump(tester, api, p);
    await tapVisible(tester, find.byKey(const Key('participant-dob-pick-0')));
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(p.dateOfBirth, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(
      textOf(tester, find.byKey(const Key('participant-dob-0'))),
      p.dateOfBirth,
    );
  });

  apiTest('server problems show on the card header and inline', (
    tester,
    api,
  ) async {
    await _pump(
      tester,
      api,
      _other(),
      problems: const {
        'phone': FieldProblem(field: 'phone', code: 'duplicate_participant'),
        'dateOfBirth': FieldProblem(
          field: 'dateOfBirth',
          code: 'age_not_eligible',
          extra: {'minAge': 18, 'ageOnEventDay': 17},
        ),
      },
    );
    expect(find.byKey(const Key('participant-tofix-0')), findsOneWidget);
    expect(find.text('2 to fix'), findsOneWidget);
    expect(find.text('Already registered in this category'), findsOneWidget);
    expect(find.text('Must be 18+ on event day (will be 17)'), findsOneWidget);
    final sem = tester.getSemantics(
      find.byKey(const Key('participant-header-0')),
    );
    expect(sem.flagsCollection.isButton, isTrue);
    expect('${sem.flagsCollection.isExpanded}', 'Tristate.isTrue');
  });

  apiTest('collapsed: a masked summary line; "Use my emergency contact"', (
    tester,
    api,
  ) async {
    var copied = false;
    await _pump(
      tester,
      api,
      _other(),
      expanded: false,
      onCopy: () => copied = true,
    );
    expect(find.text('Juma Kessy · ••• 678 · ✓'), findsOneWidget);
    expect(find.byKey(const Key('participant-first-0')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, api, _other(), onCopy: () => copied = true);
    await tapVisible(
      tester,
      find.byKey(const Key('participant-copy-emergency-0')),
    );
    expect(copied, isTrue);
  });
}
