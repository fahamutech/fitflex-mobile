import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/tone_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ff_harness.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'FFSnack error and info use the ${dark ? 'dark' : 'light'} tones',
      (tester) async {
        await pumpFF(
          tester,
          Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => FFSnack.error(context, 'Failed'),
                  child: const Text('err'),
                ),
                TextButton(
                  onPressed: () => FFSnack.info(context, 'FYI'),
                  child: const Text('info'),
                ),
              ],
            ),
          ),
          dark: dark,
        );
        await tester.pumpAndSettle();
        final tones = dark ? FFToneTheme.dark : FFToneTheme.light;

        await tester.tap(find.text('err'));
        await tester.pumpAndSettle();
        var bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.backgroundColor, tones.danger.bg);

        await tester.tap(find.text('info'));
        await tester.pumpAndSettle();
        bar = tester.widget<SnackBar>(find.byType(SnackBar));
        expect(bar.backgroundColor, tones.info.bg);
      },
    );
  }
}
