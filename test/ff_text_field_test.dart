import 'package:fitflexmobile/shared/components/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ff_harness.dart';

void main() {
  testWidgets('FFTextField minLines is passed through', (tester) async {
    await pumpFF(
      tester,
      const FFTextField(label: 'Notes', minLines: 2, maxLines: 5),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, 2);
    expect(field.maxLines, 5);
  });

  testWidgets('FFTextField minLines defaults to null', (tester) async {
    await pumpFF(tester, const FFTextField(label: 'Name'));
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.minLines, isNull);
    expect(field.maxLines, 1);
  });

  testWidgets('FFTextField passes the extra TextField options through', (
    tester,
  ) async {
    var tapped = 0;
    await pumpFF(
      tester,
      FFTextField(
        label: 'Code',
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofocus: true,
        textCapitalization: TextCapitalization.characters,
        readOnly: true,
        onTap: () => tapped++,
        helperText: 'Six digits',
        suffixText: 'TZS',
      ),
    );
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.maxLength, 6);
    expect(field.inputFormatters, isNotEmpty);
    expect(field.autofocus, isTrue);
    expect(field.textCapitalization, TextCapitalization.characters);
    expect(field.readOnly, isTrue);
    expect(field.decoration?.helperText, 'Six digits');
    expect(field.decoration?.suffixText, 'TZS');
    await tester.tap(find.byType(TextField));
    expect(tapped, 1);
  });

  testWidgets('FFTextField digits-only formatter filters typed text', (
    tester,
  ) async {
    final c = TextEditingController();
    await pumpFF(
      tester,
      FFTextField(
        controller: c,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      ),
    );
    await tester.enterText(find.byType(TextField), 'a1b2');
    expect(c.text, '12');
  });

  testWidgets('FFDropdownField isExpanded is passed through', (tester) async {
    await pumpFF(
      tester,
      FFDropdownField<String>(
        value: 'a',
        isExpanded: true,
        items: const [DropdownMenuItem(value: 'a', child: Text('A'))],
        onChanged: (_) {},
      ),
      width: 300,
    );
    final dd = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dd.isExpanded, isTrue);
  });

  testWidgets('FFDropdownField isExpanded defaults to false', (tester) async {
    await pumpFF(
      tester,
      FFDropdownField<String>(
        value: 'a',
        items: const [DropdownMenuItem(value: 'a', child: Text('A'))],
        onChanged: (_) {},
      ),
      width: 300,
    );
    final dd = tester.widget<DropdownButton<String>>(
      find.byType(DropdownButton<String>),
    );
    expect(dd.isExpanded, isFalse);
  });
}
