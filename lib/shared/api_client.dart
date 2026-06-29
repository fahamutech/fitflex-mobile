import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final dynamic body;
  ApiException(this.status, this.body);
  @override
  String toString() => 'ApiException($status, $body)';
}

class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _resolveBaseUrl();

  static String _resolveBaseUrl() {
    // 1. Compile-time --dart-define wins (CI/CD, prod builds).
    const compileTime = String.fromEnvironment('API_BASE', defaultValue: '');
    if (compileTime.isNotEmpty) return compileTime;

    // 2. Runtime .env (loaded by main()).
    String? fromEnv;
    try {
      final v = dotenv.maybeGet('API_BASE');
      if (v != null && v.isNotEmpty) fromEnv = v;
    } catch (_) {
      // dotenv not initialised — ignore.
    }
    if (fromEnv != null) return fromEnv;

    // 3. Platform-aware fallback so dev runs work out of the box.
    if (kIsWeb) return 'http://localhost:3000';
    if (Platform.isAndroid) return 'http://localhost:3000';
    return 'http://localhost:3000';
  }

  final String baseUrl;
  String? _token;
  void Function()? onUnauthorized;

  void setToken(String? token) => _token = token;

  Future<dynamic> _request(String method, String path, {Object? body}) =>
      _doRequest(method, path, body: body, attempt: 0);

  Future<dynamic> _doRequest(
    String method,
    String path, {
    Object? body,
    required int attempt,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'content-type': 'application/json',
      if (_token != null) 'authorization': 'Bearer $_token',
    };
    late http.Response res;
    final encoded = body == null ? null : jsonEncode(body);
    _logRequest(method, uri, headers, encoded);
    try {
      switch (method) {
        case 'GET':
          res = await http
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 12));
          break;
        case 'POST':
          res = await http
              .post(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        case 'PUT':
          res = await http
              .put(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        default:
          throw ArgumentError('Unsupported method $method');
      }
    } catch (e) {
      _logError(method, uri, e);
      if (attempt < 2 && _isRetryableError(e)) {
        final delayMs = attempt == 0 ? 400 : 1200;
        debugPrint(
          '[REST] retrying $method $uri (attempt ${attempt + 1}) after ${delayMs}ms',
        );
        await Future.delayed(Duration(milliseconds: delayMs));
        return _doRequest(method, path, body: body, attempt: attempt + 1);
      }
      rethrow;
    }
    _logResponse(method, uri, res);
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    if (_shouldClearSession(res.statusCode, decoded) &&
        onUnauthorized != null) {
      onUnauthorized!();
    }
    throw ApiException(res.statusCode, decoded);
  }

  static bool _shouldClearSession(int statusCode, dynamic decoded) {
    if (statusCode != 401 || decoded is! Map) return false;
    final error = decoded['error']?.toString();
    return error == 'unauthenticated' ||
        error == 'invalid_token' ||
        error == 'token_expired';
  }

  static bool _isRetryableError(Object e) {
    if (e is http.ClientException) {
      final msg = e.message.toLowerCase();
      return msg.contains('connection abort') ||
          msg.contains('connection reset') ||
          msg.contains('broken pipe') ||
          msg.contains('errno = 103') ||
          msg.contains('errno = 104') ||
          msg.contains('errno = 7') ||
          msg.contains('failed host lookup') ||
          msg.contains('no address associated');
    }
    return false;
  }

  void _logRequest(
    String method,
    Uri uri,
    Map<String, String> headers,
    String? body,
  ) {
    final safeHeaders = Map<String, String>.from(headers);
    if (safeHeaders.containsKey('authorization')) {
      safeHeaders['authorization'] = 'Bearer <redacted>';
    }
    debugPrint('[REST] --> $method $uri');
    debugPrint('[REST] headers: $safeHeaders');
    if (body != null) debugPrint('[REST] request: ${_safeBody(body)}');
  }

  void _logResponse(String method, Uri uri, http.Response res) {
    debugPrint('[REST] <-- ${res.statusCode} $method $uri');
    debugPrint('[REST] response: ${_safeBody(res.body)}');
  }

  void _logError(String method, Uri uri, Object error) {
    debugPrint('[REST] !! $method $uri');
    debugPrint('[REST] error: $error');
  }

  String _safeBody(String body) {
    var text = body;
    text = text.replaceAll(
      RegExp(r'"idToken"\s*:\s*"[^"]+"'),
      '"idToken":"<redacted>"',
    );
    text = text.replaceAll(
      RegExp(r'"token"\s*:\s*"[^"]+"'),
      '"token":"<redacted>"',
    );
    return text.length > 4000
        ? '${text.substring(0, 4000)}...<truncated>'
        : text;
  }

  Future<Map<String, dynamic>> requestOtp(String phone, String userType) async {
    return await _request(
      'POST',
      '/auth/otp/request',
      body: {'phone': phone, 'userType': userType},
    );
  }

  Future<Map<String, dynamic>> verifyOtp(String phone, String code) async {
    return await _request(
      'POST',
      '/auth/otp/verify',
      body: {'phone': phone, 'code': code},
    );
  }

  Future<Map<String, dynamic>> firebaseSession(
    String idToken,
    String requestedRole,
  ) async {
    return await _request(
      'POST',
      '/auth/firebase/session',
      body: {'idToken': idToken, 'requestedRole': requestedRole},
    );
  }

  /// DEV ONLY: mock login bypassing Firebase (blackbox testing). The backend
  /// endpoint is disabled in production. [role] = member | trainer | owner.
  Future<Map<String, dynamic>> devLogin(String role) async {
    return await _request('POST', '/auth/dev/login', body: {'role': role});
  }

  Future<Map<String, dynamic>> me() async => await _request('GET', '/me');

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profile,
  ) async => await _request('POST', '/me/profile', body: profile);

  Future<List<dynamic>> listPasses() async => await _request('GET', '/passes');

  Future<List<dynamic>> listSubscriptionTiers() async =>
      await _request('GET', '/subscription-tiers');

  Future<List<dynamic>> listGyms() async => await _request('GET', '/gyms');

  Future<List<dynamic>> getSpecialties() async =>
      await _request('GET', '/settings/specialties');

  Future<List<dynamic>> listTrainers() async =>
      await _request('GET', '/trainers');

  Future<List<dynamic>> myCheckins() async =>
      await _request('GET', '/me/checkins');

  Future<Map<String, dynamic>> requestPass(String tier) async => await _request(
    'POST',
    '/me/subscribe',
    body: {'tier': tier, 'type': 'platform_pass'},
  );

  Future<Map<String, dynamic>> subscribe(String tier) async =>
      await requestPass(tier);

  Future<Map<String, dynamic>> myQr() async => await _request('GET', '/me/qr');

  Future<Map<String, dynamic>> bookTrainer({
    required String trainerId,
    required String gymId,
    required String date,
    required String slot,
  }) async => await _request(
    'POST',
    '/me/trainer-bookings',
    body: {'trainerId': trainerId, 'gymId': gymId, 'date': date, 'slot': slot},
  );

  Future<Map<String, dynamic>> trainerRegister(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/trainer/register', body: data);

  Future<Map<String, dynamic>> gymOwnerRegister(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/gym-owner/register', body: data);

  // Owner APIs
  Future<List<dynamic>> ownerGyms() async =>
      await _request('GET', '/owner/gyms');

  Future<Map<String, dynamic>> ownerUpdateGym(
    String gymId,
    Map<String, dynamic> data,
  ) async => await _request('PUT', '/owner/gyms/$gymId', body: data);

  Future<List<dynamic>> ownerTrainers() async =>
      await _request('GET', '/owner/trainers');

  Future<Map<String, dynamic>> ownerAddTrainer(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/trainers', body: data);

  Future<Map<String, dynamic>> ownerEarnings() async =>
      await _request('GET', '/owner/earnings');

  Future<List<dynamic>> ownerGymCheckins(String gymId) async =>
      await _request('GET', '/owner/gyms/$gymId/checkins');

  Future<Map<String, dynamic>> operatorDashboard({
    String? gymId,
    String? periodStart,
    String? periodEnd,
    String? memberType,
  }) async {
    final query = <String, String>{
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
      if (periodStart != null && periodStart.isNotEmpty)
        'periodStart': periodStart,
      if (periodEnd != null && periodEnd.isNotEmpty) 'periodEnd': periodEnd,
      if (memberType != null && memberType.isNotEmpty) 'memberType': memberType,
    };
    final path = query.isEmpty
        ? '/operator/dashboard'
        : '/operator/dashboard?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> operatorVerifyQr(
    String qrToken, {
    String? gymId,
  }) async {
    final body = <String, dynamic>{'qrToken': qrToken};
    if (gymId != null) body['gymId'] = gymId;
    return await _request('POST', '/operator/verify-qr', body: body);
  }

  Future<Map<String, dynamic>> operatorCheckIn(
    String qrToken, {
    String? gymId,
  }) async {
    final body = <String, dynamic>{'qrToken': qrToken};
    if (gymId != null) body['gymId'] = gymId;
    return await _request('POST', '/operator/checkins', body: body);
  }

  // Owner gym CRUD
  Future<Map<String, dynamic>> ownerCreateGym(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/gyms', body: data);

  Future<void> ownerDeleteGym(String gymId) async =>
      await _request('POST', '/owner/gyms/$gymId/delete');

  // Owner trainer management
  Future<Map<String, dynamic>> ownerUpdateTrainer(
    String trainerId,
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/trainers/$trainerId', body: data);

  Future<void> ownerRemoveTrainer(String trainerId) async =>
      await _request('POST', '/owner/trainers/$trainerId/remove');

  Future<Map<String, dynamic>> ownerCreateMember(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/members', body: data);

  Future<Map<String, dynamic>> ownerUpdateMember(
    String memberId,
    Map<String, dynamic> data,
  ) async => await _request('PATCH', '/owner/members/$memberId', body: data);

  // Owner member management
  Future<Map<String, dynamic>> ownerMembers({
    String? gymId,
    String? memberType,
    String? status,
    String? search,
  }) async {
    final query = <String, String>{
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
      if (memberType != null && memberType.isNotEmpty && memberType != 'all')
        'memberType': memberType,
      if (status != null && status.isNotEmpty && status != 'all')
        'status': status,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final path = query.isEmpty
        ? '/owner/members'
        : '/owner/members?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> ownerMemberDetail(String memberId) async =>
      await _request('GET', '/owner/members/$memberId');

  Future<Map<String, dynamic>> ownerMemberCheckInSummary(
    String memberId, {
    String? period,
    String? from,
    String? to,
  }) async {
    final query = <String, String>{
      if (period != null && period.isNotEmpty) 'period': period,
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    };
    final path = query.isEmpty
        ? '/owner/members/$memberId/checkin-summary'
        : '/owner/members/$memberId/checkin-summary?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> ownerMemberCheckins(
    String memberId, {
    int? cursor,
    int? limit,
    String? from,
    String? to,
    String? search,
  }) async {
    final query = <String, String>{
      if (cursor != null) 'cursor': '$cursor',
      if (limit != null) 'limit': '$limit',
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final path = query.isEmpty
        ? '/owner/members/$memberId/checkins'
        : '/owner/members/$memberId/checkins?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> ownerMemberPayments(
    String memberId, {
    int? cursor,
    int? limit,
    String? from,
    String? to,
    String? search,
  }) async {
    final query = <String, String>{
      if (cursor != null) 'cursor': '$cursor',
      if (limit != null) 'limit': '$limit',
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final path = query.isEmpty
        ? '/owner/members/$memberId/payments'
        : '/owner/members/$memberId/payments?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> ownerCheckInMember(
    String memberId, {
    String? gymId,
  }) async => await _request(
    'POST',
    '/owner/members/$memberId/checkin',
    body: {'gymId': ?gymId},
  );

  Future<Map<String, dynamic>> ownerRenewMember(
    String memberId,
    Map<String, dynamic> data,
  ) async =>
      await _request('POST', '/owner/members/$memberId/renew', body: data);

  Future<Map<String, dynamic>> ownerSuspendMember(
    String memberId, {
    required bool suspend,
  }) async => await _request(
    'POST',
    '/owner/members/$memberId/suspend',
    body: {'suspend': suspend},
  );

  // Subscription tiers
  Future<List<dynamic>> subscriptionTiers() async =>
      await _request('GET', '/subscription-tiers');
}
