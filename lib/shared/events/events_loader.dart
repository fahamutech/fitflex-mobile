import 'dart:async';

/// Debounced, latest-wins fetching for the event list, modelled on
/// `DiscoveryLoader` (which is typed for `/discover/*` and gated on its own
/// flag, so it is not reused directly). A slow answer to an older request
/// never replaces a newer one; a failure reaches [onError] only when it is
/// the newest request.
class EventsLoader<Q, R> {
  EventsLoader({
    required this.fetch,
    required this.onResult,
    required this.onError,
    this.onLoading,
    this.debounce = const Duration(milliseconds: 350),
  });

  final Future<R> Function(Q query) fetch;
  final void Function(Q query, R result) onResult;
  final void Function(Q query, Object error) onError;
  final void Function(bool loading)? onLoading;
  final Duration debounce;

  Timer? _timer;
  int _latest = 0;
  bool _disposed = false;

  /// Ask for [query]. `immediate` skips the debounce (a chip tap, not typing).
  void request(Q query, {bool immediate = false}) {
    if (_disposed) return;
    _timer?.cancel();
    final id = ++_latest;
    onLoading?.call(true);
    Future<void> run() async {
      try {
        final result = await fetch(query);
        if (_disposed || id != _latest) return;
        onLoading?.call(false);
        onResult(query, result);
      } catch (e) {
        if (_disposed || id != _latest) return;
        onLoading?.call(false);
        onError(query, e);
      }
    }

    if (immediate || debounce == Duration.zero) {
      run();
    } else {
      _timer = Timer(debounce, run);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
