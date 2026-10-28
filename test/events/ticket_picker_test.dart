// Events S3 (spec §5.14 ticket_picker_test): min/max jumps, sold-out rows
// disabled, the estimate line, the per-order cap hint.
import 'package:fitflexmobile/screens/member/events/register/ticket_picker.dart';
import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/events/event_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/recording_api.dart';
import 'fixtures.dart';
import 's3_support.dart';

Finder _add(String ticket) => find.descendant(
  of: find.byKey(Key('ticket-qty-$ticket')),
  matching: find.byKey(const Key('ff-stepper-add')),
);
Finder _remove(String ticket) => find.descendant(
  of: find.byKey(Key('ticket-qty-$ticket')),
  matching: find.byKey(const Key('ff-stepper-remove')),
);
String _value(WidgetTester tester, String ticket) => tester
    .widget<Text>(
      find.descendant(
        of: find.byKey(Key('ticket-qty-$ticket')),
        matching: find.byKey(const Key('ff-stepper-value')),
      ),
    )
    .data!;

Future<void> _pump(
  WidgetTester tester,
  RecordingApi api, {
  int max = 10,
  Map<String, int> initial = const {},
  Map<String, int>? out,
}) async {
  final d = EventDetail.fromJson(detail('evt_1'));
  var lines = Map<String, int>.from(initial);
  await pumpPage(
    tester,
    api,
    StatefulBuilder(
      builder: (context, setState) => SingleChildScrollView(
        child: TicketPicker(
          detail: d,
          lines: lines,
          maxParticipants: max,
          onChanged: (v) => setState(() {
            lines = v;
            out?.clear();
            out?.addAll(v);
          }),
        ),
      ),
    ),
    user: member,
    size: const Size(375, 1400),
  );
}

void main() {
  apiTest('a first tap lands on the ticket\'s minimum; below it goes to 0', (
    tester,
    api,
  ) async {
    final out = <String, int>{};
    await _pump(tester, api, out: out);
    expect(_value(tester, 'tt_std'), '0');
    await tapVisible(tester, _add('tt_std'));
    expect(_value(tester, 'tt_std'), '1');
    expect(out, {'tt_std': 1});
    await tapVisible(tester, _add('tt_std'));
    expect(_value(tester, 'tt_std'), '2');
    await tapVisible(tester, _remove('tt_std'));
    await tapVisible(tester, _remove('tt_std'));
    expect(_value(tester, 'tt_std'), '0');
    expect(out, isEmpty);
  });

  apiTest('sold-out rows keep a disabled stepper and their pill', (
    tester,
    api,
  ) async {
    await _pump(tester, api);
    expect(isEnabled(tester, _add('tt_early')), isFalse);
    expect(isEnabled(tester, _remove('tt_early')), isFalse);
    expect(
      find.descendant(
        of: find.byKey(const Key('ticket-row-tt_early')),
        matching: find.byType(FFBadge),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('ticket-minage-cat_21')), findsOneWidget);
    expect(find.text('Age 18+'), findsOneWidget);
    expect(find.text('7 left'), findsOneWidget);
  });

  apiTest('the estimate line sums unit prices and is a live region', (
    tester,
    api,
  ) async {
    await _pump(tester, api, initial: {'tt_std': 2, 'tt_free': 1});
    expect(
      find.text('3 participant(s) · TSh 50,000 (estimate)'),
      findsOneWidget,
    );
    final sem = tester.getSemantics(find.byKey(const Key('ticket-estimate')));
    expect(sem.flagsCollection.isLiveRegion, isTrue);
  });

  apiTest('reaching maxParticipantsPerOrder disables plus and shows the hint', (
    tester,
    api,
  ) async {
    await _pump(tester, api, max: 2, initial: {'tt_std': 2});
    expect(isEnabled(tester, _add('tt_std')), isFalse);
    expect(isEnabled(tester, _add('tt_free')), isFalse);
    expect(isEnabled(tester, _remove('tt_std')), isTrue);
    expect(find.byKey(const Key('ticket-max-hint')), findsOneWidget);
    expect(find.textContaining('Up to 2 people per order'), findsOneWidget);
  });

  apiTest('the stepper announces its label and value', (tester, api) async {
    await _pump(tester, api, initial: {'tt_std': 1});
    final sem = tester.getSemantics(find.byKey(const Key('ticket-qty-tt_std')));
    expect(sem.label, 'Quantity for Standard');
    expect(sem.value, '1');
    expect(sem.increasedValue, '2');
    expect(sem.decreasedValue, '0');
  });
}
