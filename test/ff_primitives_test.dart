import 'package:fitflexmobile/shared/components/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ff_harness.dart';

void main() {
  group('FFButton', () {
    for (final dark in [false, true]) {
      for (final v in FFButtonVariant.values) {
        testWidgets('${v.name} renders and taps (dark=$dark)', (t) async {
          var taps = 0;
          await pumpFF(
            t,
            FFButton(label: 'Save', variant: v, onPressed: () => taps++),
            dark: dark,
          );
          await t.tap(find.text('Save'));
          expect(taps, 1);
        });
      }
    }

    testWidgets('loading ignores taps and keeps width', (t) async {
      var taps = 0;
      Widget b(bool loading) => FFButton(
        label: 'Save changes',
        loading: loading,
        onPressed: () => taps++,
      );
      await pumpFF(t, b(false));
      final w = t.getSize(find.byType(FilledButton)).width;
      await pumpFF(t, b(true));
      expect(t.getSize(find.byType(FilledButton)).width, w);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(taps, 0);
    });

    testWidgets('null onPressed disables', (t) async {
      await pumpFF(t, const FFButton(label: 'Save', onPressed: null));
      expect(t.widget<FilledButton>(find.byType(FilledButton)).enabled, false);
    });

    testWidgets('min tap size per size', (t) async {
      for (final (s, h) in [
        (FFButtonSize.sm, 40.0),
        (FFButtonSize.md, 48.0),
        (FFButtonSize.lg, 52.0),
      ]) {
        await pumpFF(t, FFButton(label: 'Go', size: s, onPressed: () {}));
        final size = t.getSize(find.byType(FilledButton));
        expect(size.height, greaterThanOrEqualTo(h));
        // Hit area (the padded tap target) is at least 48dp.
        final hit = t.getSize(
          find.byWidgetPredicate(
            (w) => w.runtimeType.toString() == '_InputPadding',
          ),
        );
        expect(hit.height, greaterThanOrEqualTo(48));
      }
    });

    testWidgets('long Swahili label does not overflow', (t) async {
      await pumpFF(
        t,
        FFButton(
          label: 'Thibitisha na uendelee na malipo ya uanachama wako',
          fullWidth: true,
          icon: Icons.check,
          onPressed: () {},
        ),
        width: 200,
        textScale: 1.3,
      );
      expect(t.takeException(), isNull);
    });
  });

  group('FFSnack', () {
    Widget trigger(void Function(BuildContext) fn) => Builder(
      builder: (c) =>
          TextButton(onPressed: () => fn(c), child: const Text('go')),
    );

    testWidgets('success and error show message; new replaces old', (t) async {
      await pumpFF(
        t,
        Column(
          children: [
            trigger((c) => FFSnack.success(c, 'Saved')),
            Builder(
              builder: (c) => TextButton(
                onPressed: () => FFSnack.error(c, 'Failed'),
                child: const Text('err'),
              ),
            ),
          ],
        ),
      );
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('Saved'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      await t.tap(find.text('err'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 800));
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Saved'), findsNothing);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('action fires and dark theme works', (t) async {
      var undone = false;
      await pumpFF(
        t,
        trigger(
          (c) => FFSnack.warning(
            c,
            'Careful',
            actionLabel: 'Undo',
            onAction: () => undone = true,
          ),
        ),
        dark: true,
      );
      await t.tap(find.text('go'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await t.tap(find.text('Undo'));
      expect(undone, true);
    });
  });

  group('showFFConfirmDialog', () {
    Future<bool?> run(
      WidgetTester t,
      String tap, {
      bool destructive = false,
    }) async {
      bool? result;
      await pumpFF(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () async => result = await showFFConfirmDialog(
              c,
              title: 'Delete?',
              message: 'Gone for good',
              destructive: destructive,
            ),
            child: const Text('open'),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Gone for good'), findsOneWidget);
      await t.tap(find.text(tap));
      await t.pumpAndSettle();
      return result;
    }

    testWidgets('confirm -> true', (t) async {
      expect(await run(t, 'Confirm', destructive: true), true);
    });
    testWidgets('cancel -> false', (t) async {
      expect(await run(t, 'Cancel'), false);
    });
  });

  group('FFSheet', () {
    testWidgets('shows title, close has tooltip and closes', (t) async {
      await pumpFF(
        t,
        Builder(
          builder: (c) => TextButton(
            onPressed: () => showFFSheet<void>(
              c,
              title: 'Filters',
              child: const Text('body'),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      expect(find.text('Filters'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      await t.tap(find.byTooltip('Close'));
      await t.pumpAndSettle();
      expect(find.text('Filters'), findsNothing);
    });
  });

  group('FFSkeleton', () {
    testWidgets('renders with animations', (t) async {
      await pumpFF(t, const FFSkeletonList(count: 2));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.byType(FFSkeletonCard), findsNWidgets(2));
      expect(t.takeException(), isNull);
    });

    testWidgets('disableAnimations: no running animation', (t) async {
      await pumpFF(
        t,
        const Column(children: [FFSkeleton(width: 100), FFSkeletonLine()]),
        disableAnimations: true,
      );
      await t.pumpAndSettle(); // would time out if it kept pulsing
      expect(t.takeException(), isNull);
    });

    testWidgets('dark theme', (t) async {
      await pumpFF(t, const FFSkeletonCard(), dark: true);
      expect(t.takeException(), isNull);
    });
  });
}
