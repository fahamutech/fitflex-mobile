// The photo-hero scrim rule (docs/design/photo-hero-screens.md §5, owner
// decision 2026-10-20 "lighter"), checked on a pumped FFPhotoHero.

import 'package:fitflexmobile/shared/components/components.dart';
import 'package:fitflexmobile/shared/design_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between two opaque colours.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

/// The hero scrim at [alpha] composited over a pure-white photo pixel.
Color scrimOverWhite(double alpha) =>
    Color.alphaBlend(FFTokens.heroScrim.withValues(alpha: alpha), Colors.white);

Rect _rectOf(Element e) {
  final box = e.renderObject! as RenderBox;
  return box.localToGlobal(Offset.zero) & box.size;
}

List<ScrimStop> scrimStopsOf(WidgetTester tester, Finder f) {
  final painter = tester.widget<CustomPaint>(f).painter! as FFScrimPainter;
  return painter.stopsFor(tester.getSize(f));
}

/// The scrim's alpha at global [y] in the painted box [f] (vertical).
double scrimAlphaAtY(WidgetTester tester, Finder f, double y) {
  final r = tester.getRect(f);
  return scrimAlphaAt(scrimStopsOf(tester, f), (y - r.top) / r.height);
}

/// Every text line, chip, button and leading widget of the (single) hero
/// sits in its text zone, at least 24px below the zone's top edge (where
/// the ramp starts), and the scrim under each of them is at least
/// [FFTokens.heroScrimText] from its top row to its bottom row. The fade
/// zone above holds no text and ends at the lead-in value.
void expectHeroScrimRule(WidgetTester tester, {Finder? hero}) {
  final scope = hero ?? find.byType(FFPhotoHero);
  final zone = find.descendant(
    of: scope,
    matching: find.byKey(const Key('ff-hero-text-zone')),
  );
  final fade = find.descendant(
    of: scope,
    matching: find.byKey(const Key('ff-hero-fade-zone')),
  );
  expect(zone, findsOneWidget);
  final zoneRect = tester.getRect(zone);
  final rampStart = zoneRect.top;

  final items = <Element>[
    ...find.descendant(of: scope, matching: find.byType(RichText)).evaluate(),
    ...find.descendant(of: scope, matching: find.byType(FFButton)).evaluate(),
    ...find
        .descendant(of: scope, matching: find.byKey(const Key('ff-hero-chip')))
        .evaluate(),
    ...find
        .descendant(
          of: scope,
          matching: find.byKey(const Key('ff-hero-leading')),
        )
        .evaluate(),
  ];
  expect(items, isNotEmpty);
  for (final e in items) {
    final r = _rectOf(e);
    if (r.isEmpty) continue;
    final what = e.widget.toStringShort();
    // Inside the zone, and at least 24px below the ramp start.
    expect(
      find.descendant(of: zone, matching: find.byWidget(e.widget)),
      findsWidgets,
      reason: what,
    );
    expect(r.top - rampStart, greaterThanOrEqualTo(24 - 0.01), reason: what);
    expect(r.bottom, lessThanOrEqualTo(zoneRect.bottom + 0.01), reason: what);
    for (final y in [r.top, r.center.dy, r.bottom]) {
      expect(
        scrimAlphaAtY(tester, zone, y),
        greaterThanOrEqualTo(FFTokens.heroScrimText - 1e-9),
        reason: '$what at y=$y',
      );
    }
  }
  // The zone stays at the text value or darker down to its bottom edge.
  expect(
    scrimAlphaAtY(tester, zone, zoneRect.bottom),
    greaterThanOrEqualTo(FFTokens.heroScrimText - 1e-9),
  );

  // Photo only above: no text, clear at first, the lead-in at the bottom.
  expect(
    find.descendant(of: fade, matching: find.byType(RichText)),
    findsNothing,
  );
  final fadeRect = tester.getRect(fade);
  final fadeStops = scrimStopsOf(tester, fade);
  expect(fadeStops.last.$2, closeTo(FFTokens.heroScrimLeadIn, 1e-9));
  if (fadeRect.height > FFTokens.heroScrimLeadInLength) {
    expect(fadeStops.first.$2, 0);
    expect(
      scrimAlphaAtY(
        tester,
        fade,
        fadeRect.bottom - FFTokens.heroScrimLeadInLength,
      ),
      closeTo(0, 1e-6),
    );
  }
}
