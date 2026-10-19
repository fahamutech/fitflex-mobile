// Owner bug 2026-10-19: green lines down the left and right whenever a gym
// with several photos is viewed. Cause: the full-screen viewer's previous /
// next IconButton.filled sat in a top:0/bottom:0 Positioned with no Center,
// so each stretched into a full-height primary-filled bar. These tests keep
// the photo frame free of primary-coloured bars, borders or neighbour slivers
// in light and dark themes, for multi-photo and single-photo galleries.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:fitflexmobile/shared/i18n.dart';
import 'package:fitflexmobile/shared/widgets/photo_gallery.dart';

// A valid 1x1 PNG so FFRemoteImage uses MemoryImage (no network in tests).
const _png =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

const _galleryKey = Key('gallery-under-test');

Widget _wrap(ThemeData theme, List<String> images) => FFLocaleScope(
  notifier: FFLocale(),
  child: MaterialApp(
    theme: theme,
    home: Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [PhotoGallery(key: _galleryKey, images: images)],
      ),
    ),
  ),
);

bool _isPrimary(Color? c, Color primary) =>
    c != null && c.a > 0.5 && c.withValues(alpha: 1) == primary;

/// No primary-coloured border on any box in [scope], and no opaque
/// primary-filled box/material in [scope] that is taller than a button.
void _expectNoPrimaryBars(WidgetTester tester, Finder scope, Color primary) {
  for (final element
      in find
          .descendant(of: scope, matching: find.byType(DecoratedBox))
          .evaluate()) {
    final decoration = (element.widget as DecoratedBox).decoration;
    if (decoration is! BoxDecoration) continue;
    final border = decoration.border;
    if (border is Border) {
      for (final side in [border.left, border.right, border.top]) {
        expect(
          side.style != BorderStyle.none && _isPrimary(side.color, primary),
          isFalse,
          reason: 'no primary-coloured border around the photo',
        );
      }
    }
    if (_isPrimary(decoration.color, primary)) {
      expect(
        tester.getSize(find.byWidget(element.widget)).height,
        lessThanOrEqualTo(64),
        reason: 'no tall primary-filled box beside the photo',
      );
    }
  }
  for (final element
      in find
          .descendant(of: scope, matching: find.byType(Material))
          .evaluate()) {
    final material = element.widget as Material;
    if (!_isPrimary(material.color, primary)) continue;
    expect(
      tester.getSize(find.byWidget(material)).height,
      lessThanOrEqualTo(64),
      reason: 'primary-filled controls must stay button-sized, not bars',
    );
  }
}

void _expectInlinePageFillsFrame(WidgetTester tester) {
  final pageView = tester.widget<PageView>(
    find.descendant(
      of: find.byKey(_galleryKey),
      matching: find.byType(PageView),
    ),
  );
  expect(pageView.controller?.viewportFraction ?? 1.0, 1.0);

  final frame = tester.getRect(find.byKey(_galleryKey));
  final page = tester.getRect(find.byKey(const Key('gym-photo-0')));
  expect(page.left, frame.left);
  expect(page.right, frame.right);
  expect(page.top, frame.top);
  // The neighbouring photo is not peeking in at either edge.
  final next = find.byKey(const Key('gym-photo-1'));
  if (next.evaluate().isNotEmpty) {
    expect(tester.getRect(next).left, greaterThanOrEqualTo(frame.right));
  }
}

void main() {
  for (final entry in {
    'light': buildTheme(),
    'dark': buildDarkTheme(),
  }.entries) {
    final theme = entry.value;
    final primary = theme.colorScheme.primary;

    testWidgets('${entry.key}: 3 photos fill the frame with no green edges', (
      tester,
    ) async {
      await tester.pumpWidget(_wrap(theme, const [_png, _png, _png]));
      await tester.pump();

      _expectInlinePageFillsFrame(tester);
      _expectNoPrimaryBars(tester, find.byKey(_galleryKey), primary);
      // The position counter stays.
      expect(find.text('1/3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('gym-photo-0')));
      await tester.pumpAndSettle();
      final viewer = find.byKey(const Key('gym-photo-fullscreen'));
      expect(viewer, findsOneWidget);

      final screen = tester.getRect(viewer);
      for (final key in ['gym-photo-previous', 'gym-photo-next']) {
        final rect = tester.getRect(find.byKey(Key(key)));
        expect(rect.height, lessThanOrEqualTo(64), reason: '$key is a bar');
        expect(rect.width, lessThanOrEqualTo(64));
        expect(
          (rect.center.dy - screen.center.dy).abs(),
          lessThan(1),
          reason: '$key stays vertically centred',
        );
      }
      _expectNoPrimaryBars(tester, viewer, primary);
      expect(find.text('1/3'), findsWidgets);

      // Paging still works and the buttons stay button-sized.
      await tester.tap(find.byKey(const Key('gym-photo-next')));
      await tester.pumpAndSettle();
      expect(find.text('2/3'), findsWidgets);
      _expectNoPrimaryBars(tester, viewer, primary);
    });

    testWidgets('${entry.key}: a single photo is unaffected', (tester) async {
      await tester.pumpWidget(_wrap(theme, const [_png]));
      await tester.pump();

      _expectInlinePageFillsFrame(tester);
      _expectNoPrimaryBars(tester, find.byKey(_galleryKey), primary);
      expect(find.text('1/1'), findsNothing);

      await tester.tap(find.byKey(const Key('gym-photo-0')));
      await tester.pumpAndSettle();
      final viewer = find.byKey(const Key('gym-photo-fullscreen'));
      expect(viewer, findsOneWidget);
      expect(find.byKey(const Key('gym-photo-previous')), findsNothing);
      expect(find.byKey(const Key('gym-photo-next')), findsNothing);
      _expectNoPrimaryBars(tester, viewer, primary);
    });
  }
}
