import 'dart:async';

import 'package:flutter/material.dart';

/// "27 min left" counting down to [until]. Re-renders each minute, and each
/// second under a minute; announces changes politely (a live region at
/// minute granularity so screen readers are not chattered at). [onDone]
/// fires once when the time is reached.
class FFCountdownText extends StatefulWidget {
  const FFCountdownText({
    super.key,
    required this.until,
    required this.minutesLabel,
    required this.secondsLabel,
    this.style,
    this.urgentStyle,
    this.urgentBelow = const Duration(minutes: 5),
    this.onDone,
    this.now,
  });

  final DateTime until;

  /// Copy with `{n}` for whole minutes, e.g. "{n} min left".
  final String minutesLabel;

  /// Copy with `{n}` for seconds under a minute, e.g. "{n} s left".
  final String secondsLabel;
  final TextStyle? style;

  /// Used once less than [urgentBelow] remains (Fuel text per the spec).
  final TextStyle? urgentStyle;
  final Duration urgentBelow;
  final VoidCallback? onDone;

  /// Injectable clock for tests; the widget still ticks with real timers.
  final DateTime Function()? now;

  @override
  State<FFCountdownText> createState() => _FFCountdownTextState();
}

class _FFCountdownTextState extends State<FFCountdownText> {
  Timer? _timer;
  bool _doneFired = false;

  DateTime get _now => (widget.now ?? DateTime.now)();
  Duration get _left {
    final d = widget.until.difference(_now);
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(FFCountdownText old) {
    super.didUpdateWidget(old);
    if (old.until != widget.until) {
      _doneFired = false;
      _schedule();
    }
  }

  void _schedule() {
    _timer?.cancel();
    final left = _left;
    if (left == Duration.zero) {
      _fireDone();
      return;
    }
    // Next tick: on the next whole second under a minute, else the next
    // whole minute boundary of the remaining time.
    final next = left <= const Duration(minutes: 1)
        ? Duration(milliseconds: (left.inMilliseconds % 1000) + 1)
        : Duration(
            milliseconds:
                (left.inMilliseconds %
                    const Duration(minutes: 1).inMilliseconds) +
                1,
          );
    _timer = Timer(next, () {
      if (!mounted) return;
      setState(() {});
      _schedule();
    });
  }

  void _fireDone() {
    if (_doneFired) return;
    _doneFired = true;
    final cb = widget.onDone;
    if (cb != null) WidgetsBinding.instance.addPostFrameCallback((_) => cb());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = _left;
    final text = left <= const Duration(minutes: 1)
        ? widget.secondsLabel.replaceFirst('{n}', '${left.inSeconds}')
        : widget.minutesLabel.replaceFirst('{n}', '${left.inMinutes}');
    final urgent = left < widget.urgentBelow;
    return Semantics(
      liveRegion: true,
      child: Text(
        text,
        key: const Key('ff-countdown'),
        style: urgent ? (widget.urgentStyle ?? widget.style) : widget.style,
      ),
    );
  }
}
