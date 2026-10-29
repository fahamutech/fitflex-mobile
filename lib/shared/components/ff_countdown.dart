import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../design_tokens.dart';
import '../i18n.dart';

/// What a countdown to [endsAt] shows at [now] (both UTC instants).
enum FFCountdownPhase {
  /// More than 24 hours left: "Ends in N days" text.
  days,

  /// 24 hours or less: HH:MM:SS chips.
  chips,

  /// Reached zero: "Sale ended".
  ended,
}

/// Time left from [now] to [endsAt], never negative.
Duration ffCountdownLeft(DateTime endsAt, DateTime now) {
  final d = endsAt.toUtc().difference(now.toUtc());
  return d.isNegative ? Duration.zero : d;
}

FFCountdownPhase ffCountdownPhase(Duration left) => left == Duration.zero
    ? FFCountdownPhase.ended
    : left > const Duration(hours: 24)
    ? FFCountdownPhase.days
    : FFCountdownPhase.chips;

/// The screen-reader label at minute precision (spec P1 §11.2): "Sale ends
/// in 2 hours 14 minutes", "in 1 hour", "in 24 hours", "in 1 minute",
/// under a minute "Sale ends in less than a minute". No "0 minutes", and
/// singular forms for 1. Changes at most once a minute.
String ffCountdownA11yLabel(BuildContext context, Duration left) {
  if (left == Duration.zero) return context.tr('shop.home.saleEnded');
  if (left > const Duration(hours: 24)) {
    return ffCountdownDaysText(context, left);
  }
  final h = left.inHours;
  final m = left.inMinutes % 60;
  String t(String key) =>
      context.tr(key).replaceAll('{h}', '$h').replaceAll('{m}', '$m');
  if (h == 0) {
    return switch (m) {
      0 => t('shop.a11y.countdownUnderMinute'),
      1 => t('shop.a11y.countdownOneMinute'),
      _ => t('shop.a11y.countdownMinutes'),
    };
  }
  if (m == 0) {
    return t(
      h == 1 ? 'shop.a11y.countdownOneHour' : 'shop.a11y.countdownHoursOnly',
    );
  }
  if (h == 1) {
    return t(
      m == 1
          ? 'shop.a11y.countdownOneHourOneMinute'
          : 'shop.a11y.countdownOneHourMinutes',
    );
  }
  return t(
    m == 1 ? 'shop.a11y.countdownHoursOneMinute' : 'shop.a11y.countdown',
  );
}

/// "Ends in 2 days" / "Ends in 1 day" (whole days, rounded down).
String ffCountdownDaysText(BuildContext context, Duration left) {
  final days = left.inDays;
  return days <= 1
      ? context.tr('shop.home.endsInOneDay')
      : context.tr('shop.home.endsInDays').replaceAll('{n}', '$days');
}

/// The flash-sale countdown (spec P1 §3 #3, §11.2; Phase 2 §8.1): Fuel
/// HH:MM:SS chips in mono digits while 24 hours or less remain, "Ends in
/// N days" above that, and "Sale ended" at zero.
///
/// Driven by the server's clock, not the device's: [serverOffset] is
/// `serverNow − device time when the answer arrived`, so a phone set an
/// hour wrong still counts down to the right moment (AC-21).
///
/// Accessibility: the chips are excluded; the container carries one label
/// at minute precision (it changes at most once a minute) and is not a live
/// region. Reaching zero while on screen makes one polite announcement,
/// "Sale ended", and calls [onEnded] once.
class FFCountdown extends StatefulWidget {
  const FFCountdown({
    super.key,
    required this.endsAt,
    this.serverOffset = Duration.zero,
    this.now,
    this.onEnded,
    this.chipsLabel,
  });

  final DateTime endsAt;

  /// Words before the chips ("Ends in"); not read out (the label says it).
  final String? chipsLabel;

  /// Server time minus device time.
  final Duration serverOffset;

  /// The device clock (tests); [DateTime.now] otherwise.
  final DateTime Function()? now;

  /// Called once, after the frame, when the countdown reaches zero.
  final VoidCallback? onEnded;

  @override
  State<FFCountdown> createState() => _FFCountdownState();
}

class _FFCountdownState extends State<FFCountdown> {
  Timer? _timer;
  bool _endedFired = false;

  /// Whether this countdown was running when it reached zero (only then is
  /// "Sale ended" announced; one that was already over says nothing).
  bool _wasRunning = false;

  DateTime get _serverNow =>
      (widget.now ?? DateTime.now)().toUtc().add(widget.serverOffset);

  Duration get _left => ffCountdownLeft(widget.endsAt, _serverNow);

  @override
  void initState() {
    super.initState();
    _wasRunning = _left > Duration.zero;
    _schedule();
  }

  @override
  void didUpdateWidget(FFCountdown old) {
    super.didUpdateWidget(old);
    if (old.endsAt != widget.endsAt ||
        old.serverOffset != widget.serverOffset) {
      _endedFired = false;
      _wasRunning = _left > Duration.zero;
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final left = _left;
    if (left == Duration.zero) {
      _ended();
      return;
    }
    // Each second on the chips; above 24 hours the text changes at most
    // once a minute, so wake on the next minute boundary of the time left.
    final ms = left.inMilliseconds;
    final next = ffCountdownPhase(left) == FFCountdownPhase.chips
        ? Duration(milliseconds: ms % 1000 == 0 ? 1000 : ms % 1000)
        : Duration(milliseconds: ms % 60000 == 0 ? 60000 : ms % 60000);
    _timer = Timer(next, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  void _ended() {
    if (_endedFired) return;
    _endedFired = true;
    final announce = _wasRunning;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (announce) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          context.tr('shop.home.saleEnded'),
          Directionality.of(context),
        );
      }
      widget.onEnded?.call();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final left = _left;
    final label = ffCountdownA11yLabel(context, left);
    switch (ffCountdownPhase(left)) {
      case FFCountdownPhase.ended:
        return Semantics(
          container: true,
          label: label,
          excludeSemantics: true,
          child: Text(
            label,
            key: const Key('ff-countdown-ended'),
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case FFCountdownPhase.days:
        return Semantics(
          container: true,
          label: label,
          excludeSemantics: true,
          child: Text(
            label,
            key: const Key('ff-countdown-days'),
            style: theme.textTheme.labelLarge?.copyWith(
              // Fuel text on the surface: 5.35:1 light, 7.74:1 dark.
              color: dark ? FFTokens.fuelOnDark : FFTokens.fuel,
              fontWeight: FontWeight.w700,
            ),
          ),
        );
      case FFCountdownPhase.chips:
        final h = left.inHours;
        final m = left.inMinutes % 60;
        final s = left.inSeconds % 60;
        String two(int v) => v.toString().padLeft(2, '0');
        final sep = Text(
          ':',
          style: theme.textTheme.labelLarge?.copyWith(
            color: dark ? FFTokens.fuelOnDark : FFTokens.fuel,
            fontWeight: FontWeight.w700,
          ),
        );
        return Semantics(
          key: const Key('ff-countdown'),
          container: true,
          label: label,
          child: ExcludeSemantics(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.chipsLabel case final words?) ...[
                  Text(
                    words,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                _Chip(two(h), key: const Key('ff-countdown-h')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: sep,
                ),
                _Chip(two(m), key: const Key('ff-countdown-m')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: sep,
                ),
                _Chip(two(s), key: const Key('ff-countdown-s')),
              ],
            ),
          ),
        );
    }
  }
}

/// One HH / MM / SS chip: white on Fuel (5.35:1), JetBrains Mono 13 w600,
/// tabular figures so the digits do not shift.
class _Chip extends StatelessWidget {
  const _Chip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
    decoration: BoxDecoration(
      color: FFTokens.fuel,
      borderRadius: BorderRadius.circular(FFTokens.radiusSm),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontFamily: 'JetBrains Mono',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Colors.white,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    ),
  );
}
