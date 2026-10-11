import 'package:fitflexmobile/shared/components/components.dart';
import 'package:flutter/material.dart';
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
}
