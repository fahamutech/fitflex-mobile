import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/tone_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ff_harness.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

Map<String, FFToneColors> _all(FFToneTheme t) => {
  'neutral': t.neutral,
  'gray': t.gray,
  'brand': t.brand,
  'success': t.success,
  'danger': t.danger,
  'warning': t.warning,
  'info': t.info,
};

void main() {
  for (final entry in {
    'light': FFToneTheme.light,
    'dark': FFToneTheme.dark,
  }.entries) {
    test('${entry.key} tones: text on tint is at least 4.5:1', () {
      for (final tone in _all(entry.value).entries) {
        expect(
          _contrast(tone.value.fg, tone.value.bg),
          greaterThanOrEqualTo(4.5),
          reason: '${entry.key}/${tone.key}',
        );
      }
    });
  }

  testWidgets('FFBadge uses the dark palette in dark mode', (tester) async {
    await pumpFF(
      tester,
      const FFBadge(label: 'Active', tone: FFBadgeTone.success),
      dark: true,
    );
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(FFBadge),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (box.decoration as BoxDecoration).color,
      FFToneTheme.dark.success.bg,
    );
  });

  testWidgets('FFBadge default tone is a pale chip in light mode', (
    tester,
  ) async {
    await pumpFF(tester, const FFBadge(label: 'Draft'));
    final box = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(FFBadge),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(
      (box.decoration as BoxDecoration).color,
      FFToneTheme.light.neutral.bg,
    );
  });

  testWidgets('FFAlert error uses the danger tone in both themes', (
    tester,
  ) async {
    for (final dark in [false, true]) {
      await pumpFF(
        tester,
        const FFAlert(message: 'Oops', tone: FFAlertTone.error),
        dark: dark,
      );
      await tester.pumpAndSettle();
      final box = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(FFAlert),
              matching: find.byType(Container),
            )
            .first,
      );
      final expected = (dark ? FFToneTheme.dark : FFToneTheme.light).danger.bg;
      expect(
        (box.decoration as BoxDecoration).color,
        expected,
        reason: dark ? 'dark' : 'light',
      );
    }
  });

  testWidgets('tone lookup works without the extension installed', (
    tester,
  ) async {
    late FFToneTheme seen;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Builder(
          builder: (c) {
            seen = FFToneTheme.of(c);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(seen.brand.bg, FFToneTheme.dark.brand.bg);
  });
}
