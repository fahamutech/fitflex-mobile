import 'dart:async';

import 'promotion.dart';

/// Whether discovery lists come from the server's ranked `/discover/*` (with
/// Featured sections and promotion labels) rather than being filtered on the
/// phone. On by default; `--dart-define=SERVER_DISCOVERY=false` turns it off.
const bool kServerDiscovery = bool.fromEnvironment(
  'SERVER_DISCOVERY',
  defaultValue: true,
);

/// Fetches a ranked discovery list as the customer types and filters.
///
/// Requests are debounced and only the newest answer is used: a slow answer to
/// an older query never replaces a newer one. When a request fails, [onResult]
/// is called with null so the screen falls back to the plain list it already
/// has; discovery is an improvement over that list, never a requirement.
class DiscoveryLoader<T> {
  DiscoveryLoader({
    required this.fetch,
    required this.onResult,
    this.onLoading,
    this.debounce = const Duration(milliseconds: 350),
  });

  final Future<DiscoverResult<T>> Function(DiscoverQuery query) fetch;
  final void Function(DiscoverResult<T>? result) onResult;
  final void Function(bool loading)? onLoading;
  final Duration debounce;

  Timer? _timer;
  int _latest = 0;
  bool _disposed = false;

  /// Ask for [query]. `immediate` skips the debounce (a chip tap, not typing).
  void request(DiscoverQuery query, {bool immediate = false}) {
    if (!kServerDiscovery || _disposed) return;
    _timer?.cancel();
    final id = ++_latest;
    onLoading?.call(true);
    Future<void> run() async {
      try {
        final result = await fetch(query);
        if (_disposed || id != _latest) return;
        onLoading?.call(false);
        onResult(result);
      } catch (_) {
        if (_disposed || id != _latest) return;
        onLoading?.call(false);
        onResult(null);
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
