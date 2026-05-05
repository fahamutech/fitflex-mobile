import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  final int status;
  final dynamic body;
  ApiException(this.status, this.body);
  @override
  String toString() => 'ApiException($status, $body)';
}

class ApiClient {
  ApiClient({String? baseUrl})
    : baseUrl =
          baseUrl ??
          const String.fromEnvironment(
            'API_BASE',
            defaultValue: 'http://localhost:3000',
          );

  final String baseUrl;
  String? _token;
  void Function()? onUnauthorized;

  void setToken(String? token) => _token = token;

  Future<dynamic> _request(String method, String path, {Object? body}) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{
      'content-type': 'application/json',
      if (_token != null) 'authorization': 'Bearer $_token',
    };
    late http.Response res;
    final encoded = body == null ? null : jsonEncode(body);
    switch (method) {
      case 'GET':
        res = await http.get(uri, headers: headers);
        break;
      case 'POST':
        res = await http.post(uri, headers: headers, body: encoded);
        break;
      case 'PUT':
        res = await http.put(uri, headers: headers, body: encoded);
        break;
      default:
        throw ArgumentError('Unsupported method $method');
    }
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    if (res.statusCode == 401 && onUnauthorized != null) {
      onUnauthorized!();
    }
    throw ApiException(res.statusCode, decoded);
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

  Future<Map<String, dynamic>> me() async => await _request('GET', '/me');

  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> profile,
  ) async => await _request('POST', '/me/profile', body: profile);

  Future<List<dynamic>> listPasses() async => await _request('GET', '/passes');

  Future<List<dynamic>> listSubscriptionTiers() async =>
      await _request('GET', '/subscription-tiers');

  Future<List<dynamic>> listGyms() async => await _request('GET', '/gyms');

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

  Future<Map<String, dynamic>> operatorDashboard() async =>
      await _request('GET', '/operator/dashboard');

  Future<Map<String, dynamic>> operatorVerifyQr(String qrToken) async =>
      await _request('POST', '/operator/verify-qr', body: {'qrToken': qrToken});

  Future<Map<String, dynamic>> operatorCheckIn(String qrToken) async =>
      await _request('POST', '/operator/checkins', body: {'qrToken': qrToken});
}
