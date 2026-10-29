import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../design_tokens.dart';
import '../i18n.dart';

/// The nine named focus points (spec §42.2), in reading order, with their
/// label keys.
const List<(Alignment, String)> kFocalPositions = [
  (Alignment.topLeft, 'partnerMedia.sheet.pos.topLeft'),
  (Alignment.topCenter, 'partnerMedia.sheet.pos.top'),
  (Alignment.topRight, 'partnerMedia.sheet.pos.topRight'),
  (Alignment.centerLeft, 'partnerMedia.sheet.pos.left'),
  (Alignment.center, 'partnerMedia.sheet.pos.centre'),
  (Alignment.centerRight, 'partnerMedia.sheet.pos.right'),
  (Alignment.bottomLeft, 'partnerMedia.sheet.pos.bottomLeft'),
  (Alignment.bottomCenter, 'partnerMedia.sheet.pos.bottom'),
  (Alignment.bottomRight, 'partnerMedia.sheet.pos.bottomRight'),
];

const List<IconData> _posIcons = [
  Icons.north_west,
  Icons.north,
  Icons.north_east,
  Icons.west,
  Icons.center_focus_strong_outlined,
  Icons.east,
  Icons.south_west,
  Icons.south,
  Icons.south_east,
];

/// The label key of the named position nearest [a].
String focalPositionKey(Alignment a) {
  var best = kFocalPositions[4];
  var dist = double.infinity;
  for (final p in kFocalPositions) {
    final d = (p.$1.x - a.x) * (p.$1.x - a.x) + (p.$1.y - a.y) * (p.$1.y - a.y);
    if (d < dist) {
      dist = d;
      best = p;
    }
  }
  return best.$2;
}

/// Picks the point of a photo that must stay in view (spec §42.2): the
/// whole photo, fit to the width (at most 640), with a crosshair that a tap
/// or a drag moves; and, for keyboards and screen readers, a 3 x 3 grid of
/// 48 x 48 buttons (Top left … Bottom right). [value] is an [Alignment]
/// (-1..1 each), as `BoxFit.cover` uses it.
class FFFocalPointPicker extends StatelessWidget {
  const FFFocalPointPicker({
    super.key,
    required this.image,
    required this.aspect,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final ImageProvider image;

  /// Width / height of the photo.
  final double aspect;
  final Alignment value;
  final ValueChanged<Alignment> onChanged;
  final bool enabled;

  void _announce(BuildContext context, Alignment a) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      context
          .tr('partnerMedia.sheet.focalNow')
          .replaceAll('{position}', context.tr(focalPositionKey(a))),
      Directionality.of(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = aspect.isFinite && aspect > 0 ? aspect : 1.5;
    final position = context.tr(focalPositionKey(value));
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth.clamp(0.0, 640.0);
            final h = w / a;
            Alignment at(Offset p) => Alignment(
              ((p.dx / w) * 2 - 1).clamp(-1.0, 1.0),
              ((p.dy / h) * 2 - 1).clamp(-1.0, 1.0),
            );
            return Semantics(
              key: const Key('ff-focal-image'),
              label: context
                  .tr('partnerMedia.a11y.focalImage')
                  .replaceAll('{position}', position),
              image: true,
              excludeSemantics: true,
              child: GestureDetector(
                onTapUp: enabled ? (d) => onChanged(at(d.localPosition)) : null,
                onPanUpdate: enabled
                    ? (d) => onChanged(at(d.localPosition))
                    : null,
                onPanEnd: enabled ? (_) => _announce(context, value) : null,
                child: SizedBox(
                  width: w,
                  height: h,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(
                            FFTokens.radiusSm,
                          ),
                          child: Image(
                            image: image,
                            fit: BoxFit.fill,
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) => const ColoredBox(
                              color: FFTokens.heroPlaceholder,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: (value.x + 1) / 2 * w - 14,
                        top: (value.y + 1) / 2 * h - 14,
                        child: const _Crosshair(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          context.tr('partnerMedia.sheet.focalHint'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        SizedBox(
          width: 3 * 48 + 2 * FFTokens.spacingXs,
          child: Wrap(
            spacing: FFTokens.spacingXs,
            runSpacing: FFTokens.spacingXs,
            children: [
              for (var i = 0; i < kFocalPositions.length; i++)
                Builder(
                  builder: (context) {
                    final (pos, key) = kFocalPositions[i];
                    final selected = focalPositionKey(value) == key;
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: context.tr(key),
                      excludeSemantics: true,
                      child: SizedBox(
                        key: Key('ff-focal-pos-$i'),
                        width: 48,
                        height: 48,
                        child: IconButton(
                          style: IconButton.styleFrom(
                            backgroundColor: selected
                                ? scheme.primaryContainer
                                : null,
                            side: BorderSide(color: scheme.outlineVariant),
                          ),
                          onPressed: enabled
                              ? () {
                                  onChanged(pos);
                                  _announce(context, pos);
                                }
                              : null,
                          icon: Icon(selected ? Icons.check : _posIcons[i]),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(color: Color(0xFF020617), spreadRadius: 2)],
      ),
      alignment: Alignment.center,
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    ),
  );
}
