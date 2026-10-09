import 'package:fitflexmobile/shared/components/components.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/ff_harness.dart';

void main() {
  testWidgets('FFEmptyState works with and without icon', (t) async {
    await pumpFF(t, const FFEmptyState(title: 'Nothing', body: 'yet'));
    expect(find.byType(Icon), findsNothing);
    await pumpFF(
      t,
      const FFEmptyState(title: 'Nothing', icon: Icons.fitness_center),
    );
    expect(find.byIcon(Icons.fitness_center), findsOneWidget);
  });

  for (final lang in ['en', 'sw']) {
    testWidgets('FFErrorState defaults and retry ($lang)', (t) async {
      var retries = 0;
      await pumpFF(
        t,
        FFErrorState(onRetry: () => retries++),
        lang: lang,
        dark: true,
        width: 300,
        textScale: 1.3,
      );
      expect(
        find.text(lang == 'en' ? 'Something went wrong' : 'Hitilafu imetokea'),
        findsOneWidget,
      );
      await t.tap(find.text(lang == 'en' ? 'Try again' : 'Jaribu tena'));
      expect(retries, 1);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('FFErrorState hides retry without callback', (t) async {
    await pumpFF(t, const FFErrorState(title: 'Oops', message: 'Bad'));
    expect(find.byType(FFButton), findsNothing);
    expect(find.text('Oops'), findsOneWidget);
  });

  testWidgets('FFSkeletonList as a loading placeholder', (t) async {
    await pumpFF(t, const FFSkeletonList(count: 3, semanticLabel: 'Loading…'));
    expect(find.byType(FFSkeletonCard), findsNWidgets(3));
  });
}
