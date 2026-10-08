import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'promotion.dart';

/// Kill switch for promotion analytics. On by default;
/// `--dart-define=PROMOTION_ANALYTICS=false` turns every event off.
const bool kPromotionAnalytics = bool.fromEnvironment(
  'PROMOTION_ANALYTICS',
  defaultValue: true,
);

/// A random id for this app launch (at least 8 characters, as the server needs).
final String _launchSessionId = _makeSessionId();

String _makeSessionId() {
  Random rnd;
  try {
    rnd = Random.secure();
  } catch (_) {
    rnd = Random();
  }
  final b = StringBuffer();
  for (var i = 0; i < 16; i++) {
    b.write(rnd.nextInt(16).toRadixString(16));
  }
  return b.toString();
}

/// Where the tracker sends a batch. [ApiClient.postEvents] in the app.
typedef PromotionEventSender =
    Future<void> Function(List<Map<String, dynamic>> events);

class _Touch {
  _Touch(this.promotionId, this.placement, this.at);
  final String promotionId;
  final String? placement;
  final DateTime at;
}

/// Records promotion analytics (impressions, clicks, detail views, saves and
/// booking / subscription taps) and sends them to `POST /events` in batches.
///
/// It is a no-op until [install] is called, never throws into a screen, never
/// waits on the network from the UI, and only ever records events for cards
/// that carry a promotion tag: organic cards produce nothing.
class PromotionEvents with WidgetsBindingObserver {
  PromotionEvents._({
    required bool enabled,
    PromotionEventSender? sender,
    DateTime Function()? now,
    this.flushInterval = const Duration(seconds: 15),
    this.flushAt = 20,
    this.queueCap = 200,
    this.backoffBase = const Duration(seconds: 2),
    this.rateLimitPause = const Duration(seconds: 60),
    this.touchTtl = const Duration(minutes: 30),
  }) : _enabled = enabled && sender != null,
       _sender = sender,
       _now = now ?? DateTime.now;

  static PromotionEvents _instance = PromotionEvents._(enabled: false);

  /// The tracker the screens use. A no-op until [install].
  static PromotionEvents get instance => _instance;

  /// Start tracking. Call once from `main`. Replaces any earlier instance.
  static void install(
    ApiClient api, {
    bool enabled = kPromotionAnalytics,
    PromotionEventSender? sender,
    DateTime Function()? now,
    Duration flushInterval = const Duration(seconds: 15),
    int flushAt = 20,
    int queueCap = 200,
    Duration backoffBase = const Duration(seconds: 2),
    Duration rateLimitPause = const Duration(seconds: 60),
    Duration touchTtl = const Duration(minutes: 30),
  }) {
    _instance.dispose();
    _instance = PromotionEvents._(
      enabled: enabled,
      sender: sender ?? (events) async => api.postEvents(events),
      now: now,
      flushInterval: flushInterval,
      flushAt: flushAt,
      queueCap: queueCap,
      backoffBase: backoffBase,
      rateLimitPause: rateLimitPause,
      touchTtl: touchTtl,
    );
    _instance._attach();
  }

  /// Back to the no-op tracker (tests, sign-out is not needed).
  static void reset() {
    _instance.dispose();
    _instance = PromotionEvents._(enabled: false);
  }

  final Duration flushInterval;
  final int flushAt;
  static const int maxBatch = 50;
  final int queueCap;
  final Duration backoffBase;
  final Duration rateLimitPause;
  final Duration touchTtl;

  final bool _enabled;
  final PromotionEventSender? _sender;
  final DateTime Function() _now;

  final List<Map<String, dynamic>> _queue = [];
  final Map<String, DateTime> _seenImpressions = {};
  final Map<String, DateTime> _seenDetails = {};
  final Map<String, _Touch> _touches = {};
  Timer? _timer;
  bool _flushing = false;
  bool _attached = false;
  DateTime? _pausedUntil;

  static const _impressionWindow = Duration(hours: 1);
  static const _detailWindow = Duration(minutes: 10);

  bool get enabled => _enabled;
  String get currentSessionId => _launchSessionId;

  /// Events waiting to be sent (for tests).
  int get pending => _queue.length;

  void _attach() {
    if (!_enabled) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    } catch (_) {
      // No binding (plain unit test): the timer alone drives sending.
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_attached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _attached = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      unawaited(flush());
    }
  }

  // ── Recording ───────────────────────────────────────────────────────────

  /// A promoted card was rendered.
  void impression(
    String entityType,
    String entityId,
    PromotionTag? tag, {
    String? placement,
  }) {
    if (!_enabled || !_usable(tag, entityId)) return;
    try {
      final now = _now();
      final key = '${tag!.id}|${placement ?? ''}';
      if (_fresh(_seenImpressions, key, _impressionWindow, now)) return;
      _seenImpressions[key] = now;
      _enqueue('impression', entityType, entityId, tag.id, placement);
    } catch (_) {}
  }

  /// A promoted card was tapped: record the click and remember the touch so
  /// the detail page and the actions that follow can be attributed to it.
  void click(
    String entityType,
    String entityId,
    PromotionTag? tag, {
    String? placement,
  }) {
    if (!_enabled || !_usable(tag, entityId)) return;
    try {
      _touches['$entityType:$entityId'] = _Touch(tag!.id, placement, _now());
      _enqueue('click', entityType, entityId, tag.id, placement);
    } catch (_) {}
  }

  /// Records [type] only when a promoted card for this entity was tapped within
  /// the last 30 minutes. Opening the same page organically records nothing.
  void recordForTouched(String type, String entityType, String entityId) {
    if (!_enabled) return;
    try {
      final key = '$entityType:$entityId';
      final touch = _touches[key];
      if (touch == null) return;
      final now = _now();
      if (now.difference(touch.at) >= touchTtl) {
        _touches.remove(key);
        return;
      }
      if (type == 'detail_view' &&
          _fresh(_seenDetails, touch.promotionId, _detailWindow, now)) {
        return;
      }
      if (type == 'detail_view') _seenDetails[touch.promotionId] = now;
      _enqueue(type, entityType, entityId, touch.promotionId, touch.placement);
    } catch (_) {}
  }

  bool _usable(PromotionTag? tag, String entityId) =>
      tag != null && tag.id.isNotEmpty && entityId.isNotEmpty;

  bool _fresh(
    Map<String, DateTime> seen,
    String key,
    Duration window,
    DateTime now,
  ) {
    if (seen.length > 500) {
      seen.removeWhere((_, t) => now.difference(t) >= window);
    }
    final t = seen[key];
    return t != null && now.difference(t) < window;
  }

  void _enqueue(
    String type,
    String entityType,
    String entityId,
    String promotionId,
    String? placement,
  ) {
    _queue.add({
      'type': type,
      'entityType': entityType,
      'entityId': entityId,
      'promotionId': promotionId,
      'placement': ?placement,
      'sessionId': currentSessionId,
      'at': _now().toUtc().toIso8601String(),
    });
    _trim();
    if (_queue.length >= flushAt) {
      unawaited(flush());
    } else {
      _schedule();
    }
  }

  void _trim() {
    if (_queue.length > queueCap) {
      _queue.removeRange(0, _queue.length - queueCap);
    }
  }

  void _schedule() {
    if (_timer != null || _queue.isEmpty) return;
    var delay = flushInterval;
    final paused = _pausedUntil;
    if (paused != null) {
      final left = paused.difference(_now());
      if (left > delay) delay = left;
    }
    _timer = Timer(delay, () {
      _timer = null;
      unawaited(flush());
    });
  }

  // ── Sending ─────────────────────────────────────────────────────────────

  /// Send what is queued, at most [maxBatch] events per request. Never throws.
  Future<void> flush() async {
    if (!_enabled || _flushing) return;
    _timer?.cancel();
    _timer = null;
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final paused = _pausedUntil;
        if (paused != null && _now().isBefore(paused)) break;
        _pausedUntil = null;
        final n = min(maxBatch, _queue.length);
        final batch = List<Map<String, dynamic>>.of(_queue.sublist(0, n));
        _queue.removeRange(0, n);
        final result = await _sendWithRetry(batch);
        if (result == _Result.rateLimited) {
          _queue.insertAll(0, batch);
          _trim();
          _pausedUntil = _now().add(rateLimitPause);
          break;
        }
      }
    } catch (_) {
      // Analytics must never surface an error.
    } finally {
      _flushing = false;
      _schedule();
    }
  }

  Future<_Result> _sendWithRetry(List<Map<String, dynamic>> batch) async {
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _sender!(batch);
        return _Result.sent;
      } on ApiException catch (e) {
        if (e.status == 429) return _Result.rateLimited;
        if (e.status < 500) return _Result.dropped; // never retry other 4xx
      } catch (_) {
        // Network or timeout: retry.
      }
      if (attempt < 3) {
        await Future<void>.delayed(backoffBase * (1 << (attempt - 1)));
      }
    }
    return _Result.dropped;
  }
}

enum _Result { sent, dropped, rateLimited }

/// Convenience used by cards: a tap on a promoted card.
void trackPromotionClick(
  String entityType,
  String entityId,
  PromotionTag? tag, {
  String? placement,
}) => PromotionEvents.instance.click(
  entityType,
  entityId,
  tag,
  placement: placement,
);

/// Wraps a card and records one `impression` the first time it is built with a
/// promotion tag. This is a "rendered impression": lazily built grid and list
/// children are built when they are about to be shown, which approximates
/// "shown". Scrolling a card out and back in builds it again, so the tracker
/// de-duplicates per promotion and placement per hour. Cards without a tag
/// record nothing. Clicks are recorded by the card's own tap handler through
/// [trackPromotionClick], so the existing navigation is left untouched.
class PromotionTracked extends StatefulWidget {
  const PromotionTracked({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.promotion,
    this.placement,
    required this.child,
  });

  final String entityType;
  final String entityId;
  final PromotionTag? promotion;
  final String? placement;
  final Widget child;

  @override
  State<PromotionTracked> createState() => _PromotionTrackedState();
}

class _PromotionTrackedState extends State<PromotionTracked> {
  @override
  void initState() {
    super.initState();
    PromotionEvents.instance.impression(
      widget.entityType,
      widget.entityId,
      widget.promotion,
      placement: widget.placement,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
