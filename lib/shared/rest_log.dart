import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

/// How much [ApiClient] writes to the console about each request.
///
/// Release builds (including Flutter web, where the browser console is open to
/// anyone) must never print headers, tokens, PINs or request/response bodies:
/// they hold names, phone numbers, emails and order data.
enum RestLogLevel {
  /// Nothing is printed.
  off,

  /// Method, path (no query string) and status only. No bodies, no headers.
  summary,

  /// Everything, with secrets redacted. Debug builds only.
  full,
}

/// Opt-in for a summary log in profile/release builds:
/// `--dart-define=FITFLEX_REST_LOG=true`. It never enables bodies.
const bool kRestLogDefine = bool.fromEnvironment('FITFLEX_REST_LOG');

/// The level for a build. Bodies are logged only when [debugMode] is true.
RestLogLevel restLogLevelFor({required bool debugMode, required bool define}) {
  if (debugMode) return RestLogLevel.full;
  if (define) return RestLogLevel.summary;
  return RestLogLevel.off;
}

final RestLogLevel kRestLogLevel = restLogLevelFor(
  debugMode: kDebugMode,
  define: kRestLogDefine,
);

/// Writes REST log lines at a given [level]. [sink] is replaceable for tests.
class RestLogger {
  RestLogger({RestLogLevel? level, void Function(String line)? sink})
    : level = level ?? kRestLogLevel,
      _sink = sink ?? ((line) => debugPrint(line));

  final RestLogLevel level;
  final void Function(String line) _sink;

  bool get _on => level != RestLogLevel.off;
  bool get _full => level == RestLogLevel.full;

  /// The URI as it may be printed: full in debug, path only otherwise (query
  /// strings can carry phone numbers, emails and search terms).
  String describeUri(Uri uri) =>
      _full ? uri.toString() : '${uri.origin}${uri.path}';

  void request(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    if (!_on) return;
    _sink('[REST] --> $method ${describeUri(uri)}');
    if (!_full) return;
    _sink('[REST] headers: ${redactHeaders(headers)}');
    if (body != null) _sink('[REST] request: ${redactBody(body)}');
  }

  void multipart(String method, Uri uri, int bytes) {
    if (!_on) return;
    _sink('[REST] --> $method ${describeUri(uri)} (multipart, $bytes bytes)');
  }

  void response(String method, Uri uri, int status, String body) {
    if (!_on) return;
    _sink('[REST] <-- $status $method ${describeUri(uri)}');
    if (!_full) return;
    _sink('[REST] response: ${redactBody(body)}');
  }

  void error(String method, Uri uri, Object error) {
    if (!_on) return;
    _sink('[REST] !! $method ${describeUri(uri)}');
    // Exception messages can echo the URL or payload; only debug sees them.
    _sink('[REST] error: ${_full ? error : error.runtimeType}');
  }

  void retry(String method, Uri uri, int attempt, int delayMs) {
    if (!_on) return;
    _sink(
      '[REST] retrying $method ${describeUri(uri)} (attempt $attempt) after ${delayMs}ms',
    );
  }
}

// x-ff-area: the shopper's area (shop near-you) is personal; never printed.
const _secretHeaders = {
  'authorization',
  'cookie',
  'set-cookie',
  'x-api-key',
  'x-ff-area',
};

Map<String, String> redactHeaders(Map<String, String> headers) => {
  for (final e in headers.entries)
    e.key: _secretHeaders.contains(e.key.toLowerCase())
        ? '<redacted>'
        : e.value,
};

/// JSON keys whose string or number values are replaced with `<redacted>`:
/// any key ending in token, pin, password, secret or otp (idToken, setupToken,
/// newPin, ...), plus verification `code`.
final _secretValue = RegExp(
  r'"([A-Za-z_]*(?:token|pin|password|secret|otp)|code)"\s*:\s*("(?:[^"\\]|\\.)*"|-?\d+)',
  caseSensitive: false,
);

/// Redacts secret values from a JSON text and truncates long bodies.
String redactBody(String body) {
  final text = body.replaceAllMapped(
    _secretValue,
    (m) => '"${m.group(1)}":"<redacted>"',
  );
  return text.length > 4000 ? '${text.substring(0, 4000)}...<truncated>' : text;
}
