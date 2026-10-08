import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'promotion.dart';

class ApiException implements Exception {
  final int status;
  final dynamic body;
  ApiException(this.status, this.body);

  /// The backend's machine-readable reason, e.g. 'visits_exhausted'.
  String? get code {
    final b = body;
    if (b is Map) return (b['error'] ?? b['failure'])?.toString();
    return null;
  }

  // Readable fallback for places that still interpolate the exception;
  // screens should use errorMessage() for translated copy.
  @override
  String toString() {
    final c = code;
    if (c == null || c.isEmpty) return 'Request failed ($status)';
    final words = c.replaceAll(RegExp(r'[_-]+'), ' ').trim();
    return words.isEmpty
        ? 'Request failed ($status)'
        : '${words[0].toUpperCase()}${words.substring(1)}';
  }
}

/// Production backend. Used whenever API_BASE is not provided.
const kLiveApiBase = 'https://fitflex-faas.bfast.smartstock.co.tz';

/// Sent on every request; see [ApiClient._request].
const kIdentityV2Client = 'identity-v2';

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

    // 3. Live server. Builds that set nothing always reach production; local
    //    development opts into its own backend with API_BASE in .env.
    return kLiveApiBase;
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
      // Identity V2 (decision C3b): this build understands persons and
      // personas. The backend ignores it unless its V2 flags are on.
      'x-fitflex-client': kIdentityV2Client,
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
        case 'PATCH':
          res = await http
              .patch(uri, headers: headers, body: encoded)
              .timeout(const Duration(seconds: 12));
          break;
        case 'DELETE':
          res = await http
              .delete(uri, headers: headers, body: encoded)
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
    // A 401 always means this bearer session can no longer be used.  Do not
    // rely on a particular backend error shape: gateways and proxies often
    // return their own 401 payloads.
    if (res.statusCode == 401 && onUnauthorized != null) {
      onUnauthorized!();
    }
    throw ApiException(res.statusCode, decoded);
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
    String? requestedRole,
  ) async {
    return await _request(
      'POST',
      '/auth/firebase/session',
      body: {'idToken': idToken, 'requestedRole': ?requestedRole},
    );
  }

  /// Identity V2: the signed-in Person and their personas (User rows).
  /// Answers 404 while the backend's V2 flags are off.
  Future<Map<String, dynamic>> myPersonas() async {
    return await _request('GET', '/me/personas');
  }

  /// Identity V2: add a persona (member, trainer, gym_operator, vendor) to
  /// the signed-in Person. No new account is created.
  Future<Map<String, dynamic>> addPersona(String userType) async {
    return await _request('POST', '/me/personas', body: {'userType': userType});
  }

  // ── Identity V2 · invitations (404 while the backend flag is off) ─────────

  // ── Identity V2 · I7: a PIN kept by FitFlex ───────────────────────────────

  /// True when the backend answers at [path] (anything but "not found" or
  /// "not set up"). An empty request is refused before it does anything.
  Future<bool> _routeAvailable(String path) async {
    try {
      await _request('POST', path, body: const <String, dynamic>{});
      return true;
    } on ApiException catch (e) {
      return e.status != 404 && e.code != 'pin_not_configured';
    } catch (_) {
      return false;
    }
  }

  /// Which sign-in options the server offers (public). Throws on 404 from an
  /// older server; callers fall back to the route probes.
  Future<Map<String, dynamic>> signInOptions() async {
    return await _request('GET', '/auth/options');
  }

  /// Sign-in and registration with a number or email and a PIN are on.
  Future<bool> pinLoginAvailable() => _routeAvailable('/auth/pin/login');

  /// Forgot PIN is on.
  Future<bool> pinResetAvailable() => _routeAvailable('/auth/pin/reset/start');

  /// Sign in with one mobile number or email (`{phone: …}` or `{email: …}`)
  /// and the PIN. Returns a session, or `setupRequired` for an existing user
  /// whose PIN is still held by Firebase.
  Future<Map<String, dynamic>> pinLogin(
    Map<String, String> contact,
    String pin, {
    String? locale,
  }) async {
    return await _request(
      'POST',
      '/auth/pin/login',
      body: {...contact, 'pin': pin, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> pinSetup({
    required String setupToken,
    String? code,
    required String pin,
  }) async {
    return await _request(
      'POST',
      '/auth/pin/setup',
      body: {'setupToken': setupToken, 'code': ?code, 'pin': pin},
    );
  }

  Future<Map<String, dynamic>> registerStart(
    Map<String, String> contact,
    String? locale,
  ) async {
    return await _request(
      'POST',
      '/auth/register/start',
      body: {...contact, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> registerConfirm(
    Map<String, String> contact,
    String code,
  ) async {
    return await _request(
      'POST',
      '/auth/register/confirm',
      body: {...contact, 'code': code},
    );
  }

  Future<Map<String, dynamic>> registerComplete({
    required String registrationToken,
    required String role,
    required String pin,
  }) async {
    return await _request(
      'POST',
      '/auth/register/complete',
      body: {'registrationToken': registrationToken, 'role': role, 'pin': pin},
    );
  }

  Future<Map<String, dynamic>> pinResetStart(
    Map<String, String> contact,
    String? locale,
  ) async {
    return await _request(
      'POST',
      '/auth/pin/reset/start',
      body: {...contact, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> pinResetConfirm(
    Map<String, String> contact,
    String code,
  ) async {
    return await _request(
      'POST',
      '/auth/pin/reset/confirm',
      body: {...contact, 'code': code},
    );
  }

  Future<Map<String, dynamic>> pinResetComplete(
    String resetToken,
    String pin,
  ) async {
    return await _request(
      'POST',
      '/auth/pin/reset/complete',
      body: {'resetToken': resetToken, 'pin': pin},
    );
  }

  /// After signing in with an invitation's start PIN: the person's name and
  /// their own PIN. Answers the onboarding step (their invitations).
  Future<Map<String, dynamic>> inviteBegin({
    required String startToken,
    required String displayName,
    required String pin,
  }) async {
    return await _request(
      'POST',
      '/auth/invite/begin',
      body: {'startToken': startToken, 'displayName': displayName, 'pin': pin},
    );
  }

  /// A person with no profile yet accepts ([accept]) or declines an invitation.
  Future<Map<String, dynamic>> onboardingAnswer(
    String onboardingToken,
    String invitationId, {
    required bool accept,
  }) async {
    return await _request(
      'POST',
      '/auth/onboarding/${accept ? 'accept' : 'decline'}',
      body: {'onboardingToken': onboardingToken, 'invitationId': invitationId},
    );
  }

  /// A person with no profile yet chooses how to use FitFlex.
  Future<Map<String, dynamic>> onboardingRole(
    String onboardingToken,
    String role,
  ) async {
    return await _request(
      'POST',
      '/auth/onboarding/role',
      body: {'onboardingToken': onboardingToken, 'role': role},
    );
  }

  /// Change the PIN. The response is a new session: earlier ones are over.
  Future<Map<String, dynamic>> changePin(
    String currentPin,
    String newPin,
  ) async {
    return await _request(
      'POST',
      '/me/pin',
      body: {'currentPin': currentPin, 'newPin': newPin},
    );
  }

  /// Identity V2 · I6a: this Person's verified mobile numbers and emails
  /// (`identifiers`) and profile values not verified yet (`unverified`).
  Future<Map<String, dynamic>> myIdentifiers() async {
    return await _request('GET', '/me/identifiers');
  }

  /// Send a FitFlex code to one mobile number (SMS) or email.
  Future<Map<String, dynamic>> requestIdentifierCode({
    String? phone,
    String? email,
    String? locale,
  }) async {
    return await _request(
      'POST',
      '/me/identifiers/verify/request',
      body: {'phone': ?phone, 'email': ?email, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> confirmIdentifierCode({
    String? phone,
    String? email,
    required String code,
  }) async {
    return await _request(
      'POST',
      '/me/identifiers/verify/confirm',
      body: {'phone': ?phone, 'email': ?email, 'code': code},
    );
  }

  /// Replace the mobile number or email the person signs in with: their PIN
  /// and the new value. A code goes to the new value.
  Future<Map<String, dynamic>> requestIdentifierChange({
    String? phone,
    String? email,
    required String pin,
    String? locale,
  }) async {
    return await _request(
      'POST',
      '/me/identifiers/change/request',
      body: {'phone': ?phone, 'email': ?email, 'pin': pin, 'locale': ?locale},
    );
  }

  Future<Map<String, dynamic>> confirmIdentifierChange({
    String? phone,
    String? email,
    required String code,
    String? locale,
  }) async {
    return await _request(
      'POST',
      '/me/identifiers/change/confirm',
      body: {'phone': ?phone, 'email': ?email, 'code': code, 'locale': ?locale},
    );
  }

  // ── Identity V2 · account recovery (member path) ───────────────────────────

  /// Step 1: [oldContact] is what the person signed in with before, [newContact]
  /// the number or email that gets a code. Each is `{phone: …}` or `{email: …}`.
  Future<Map<String, dynamic>> recoveryStart(
    Map<String, String> oldContact,
    Map<String, String> newContact,
    String? locale,
  ) async {
    return await _request(
      'POST',
      '/auth/recovery/start',
      body: {'old': oldContact, 'new': newContact, 'locale': ?locale},
    );
  }

  /// Step 2: the code and the name on the account. Returns `requestToken`.
  Future<Map<String, dynamic>> recoveryConfirm(
    Map<String, String> oldContact,
    Map<String, String> newContact,
    String code,
    String name,
    String? locale,
  ) async {
    return await _request(
      'POST',
      '/auth/recovery/confirm',
      body: {
        'old': oldContact,
        'new': newContact,
        'code': code,
        'name': name,
        'locale': ?locale,
      },
    );
  }

  Future<Map<String, dynamic>> recoveryEvidence(
    String requestToken,
    Map<String, String> answers,
  ) async {
    return await _request(
      'POST',
      '/auth/recovery/evidence',
      body: {'requestToken': requestToken, 'answers': answers},
    );
  }

  Future<Map<String, dynamic>> recoveryStatus(String requestToken) async {
    return await _request(
      'POST',
      '/auth/recovery/status',
      body: {'requestToken': requestToken},
    );
  }

  Future<Map<String, dynamic>> recoveryCancel(String requestToken) async {
    return await _request(
      'POST',
      '/auth/recovery/cancel',
      body: {'requestToken': requestToken},
    );
  }

  /// Is a recovery request open on the signed-in account?
  Future<Map<String, dynamic>> myRecovery() async {
    return await _request('GET', '/me/recovery');
  }

  /// The signed-in owner cancels an open recovery request.
  Future<Map<String, dynamic>> cancelMyRecovery() async {
    return await _request('POST', '/me/recovery/cancel', body: const {});
  }

  /// Open invitations addressed to the signed-in Person.
  Future<Map<String, dynamic>> myInvitations() async {
    return await _request('GET', '/me/invitations');
  }

  /// Open an invitation from its link. Fails with `identifier_not_verified`
  /// unless this Person has verified the phone or email it was sent to.
  Future<Map<String, dynamic>> openInvitation(String token) async {
    return await _request(
      'POST',
      '/me/invitations/open',
      body: {'token': token},
    );
  }

  Future<Map<String, dynamic>> acceptInvitation(String id) async {
    return await _request('POST', '/me/invitations/$id/accept');
  }

  Future<Map<String, dynamic>> declineInvitation(String id) async {
    return await _request('POST', '/me/invitations/$id/decline');
  }

  /// Does this exact phone or email belong to a FitFlex person? Answers only
  /// `{found, maskedName}`.
  // [orgType] is 'gym' (the default) or 'vendor'; [gymId] is then the vendor's id.
  Future<Map<String, dynamic>> gymLookupPerson(
    String gymId, {
    String? phone,
    String? email,
    String orgType = 'gym',
  }) async {
    return await _request(
      'POST',
      '/orgs/$orgType/$gymId/people/lookup',
      body: {'phone': ?phone, 'email': ?email},
    );
  }

  /// Invite a person to a gym as member, staff or trainer. No account or
  /// credentials are created; returns the link token once.
  Future<Map<String, dynamic>> gymCreateInvitation(
    String gymId,
    Map<String, dynamic> body, {
    String orgType = 'gym',
  }) async {
    return await _request(
      'POST',
      '/orgs/$orgType/$gymId/invitations',
      body: body,
    );
  }

  Future<Map<String, dynamic>> gymInvitations(
    String gymId, {
    bool needsResolution = false,
    String orgType = 'gym',
  }) async {
    return await _request(
      'GET',
      '/orgs/$orgType/$gymId/invitations${needsResolution ? '?needsResolution=1' : ''}',
    );
  }

  /// [action] is cancel, resend, reissue or refunded.
  Future<Map<String, dynamic>> gymInvitationAction(
    String gymId,
    String invitationId,
    String action, {
    Map<String, dynamic>? body,
    String orgType = 'gym',
  }) async {
    return await _request(
      'POST',
      '/orgs/$orgType/$gymId/invitations/$invitationId/$action',
      body: body,
    );
  }

  /// Identity V2: a session for another persona of the same Person.
  Future<Map<String, dynamic>> switchPersona(String personaId) async {
    return await _request(
      'POST',
      '/auth/switch-persona',
      body: {'personaId': personaId},
    );
  }

  /// DEV ONLY: mock login bypassing Firebase (blackbox testing). The backend
  /// endpoint is disabled in production. [role] = member | trainer | owner.
  Future<Map<String, dynamic>> devLogin(String role) async {
    return await _request('POST', '/auth/dev/login', body: {'role': role});
  }

  /// DEV ONLY: remove E2E-created test users by email pattern or list.
  Future<Map<String, dynamic>> devCleanup({
    String? emailPattern,
    List<String>? emails,
  }) async {
    return await _request(
      'POST',
      '/auth/dev/cleanup',
      body: {'emailPattern': ?emailPattern, 'emails': ?emails},
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

  /// Ranked discovery with promotion: `/discover/gyms`, `/discover/trainers` or
  /// `/discover/products`. A promotion only ever moves a result that already
  /// matches the search and filters; the answer says which cards are promoted.
  Future<Map<String, dynamic>> discover(String kind, DiscoverQuery query) async {
    final out = await _request('GET', '/discover/$kind${query.toQueryString()}');
    return Map<String, dynamic>.from(out as Map);
  }

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

  /// A7: subscribe to a gym's own Daily/Weekly/Monthly plan.
  Future<Map<String, dynamic>> subscribeDirect({
    required String gymId,
    required String plan,
  }) async => await _request(
    'POST',
    '/me/subscribe',
    body: {'type': 'direct_sub', 'homeGymId': gymId, 'plan': plan},
  );

  Future<Map<String, dynamic>> myQr() async => await _request('GET', '/me/qr');

  /// Member self check-in: scan the static QR posted at the gym entrance.
  Future<Map<String, dynamic>> scanGymQr(String gymQr) async =>
      await _request('POST', '/me/checkins/scan', body: {'gymQr': gymQr})
          as Map<String, dynamic>;

  /// Owner/staff: the printable entrance QR for one of their gyms.
  Future<Map<String, dynamic>> gymEntranceQr(String gymId) async =>
      await _request('GET', '/operator/gyms/$gymId/entrance-qr')
          as Map<String, dynamic>;

  /// Saved gyms (US017).
  Future<List<String>> favoriteGymIds() async {
    final res = await _request('GET', '/me/favorites/gyms');
    return ((res as Map)['favoriteGymIds'] as List? ?? const [])
        .map((e) => e.toString())
        .toList();
  }

  Future<void> setFavoriteGym(String gymId, bool favorite) async =>
      await _request(favorite ? 'PUT' : 'DELETE', '/me/favorites/gyms/$gymId');

  /// Push: register / remove this device's FCM token.
  // ── Activity & Progress Engine ────────────────────────────────────────
  Future<List<dynamic>> myActivities({
    required DateTime from,
    required DateTime to,
  }) async {
    final query = Uri(
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    ).query;
    final res = await _request('GET', '/me/activities?$query');
    return (res as Map)['activities'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> logActivity(Map<String, dynamic> data) async =>
      await _request('POST', '/me/activities', body: data);

  Future<void> deleteActivity(String id) async =>
      await _request('DELETE', '/me/activities/${Uri.encodeComponent(id)}');

  Future<List<dynamic>> myGoals() async {
    final res = await _request('GET', '/me/goals');
    return (res as Map)['goals'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> createGoal(Map<String, dynamic> data) async =>
      await _request('POST', '/me/goals', body: data);

  /// Marks a coaching goal done now, or undoes the latest mark.
  Future<Map<String, dynamic>> goalCheckIn(
    String id, {
    bool undo = false,
  }) async => await _request(
    'POST',
    '/me/goals/${Uri.encodeComponent(id)}/check-in${undo ? '/undo' : ''}',
  );

  /// Trainer: set a goal for a client (see fitflex-functions
  /// POST /trainer/clients/:id/goals).
  Future<Map<String, dynamic>> trainerAssignGoal(
    String relationshipId,
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/trainer/clients/${Uri.encodeComponent(relationshipId)}/goals',
    body: body,
  );

  /// Trainer: retarget, retitle or archive a goal they set.
  Future<Map<String, dynamic>> trainerUpdateGoal(
    String relationshipId,
    String goalId,
    Map<String, dynamic> body,
  ) async => await _request(
    'PATCH',
    '/trainer/clients/${Uri.encodeComponent(relationshipId)}/goals/${Uri.encodeComponent(goalId)}',
    body: body,
  );

  Future<Map<String, dynamic>> updateGoal(
    String id,
    Map<String, dynamic> data,
  ) async => await _request(
    'PATCH',
    '/me/goals/${Uri.encodeComponent(id)}',
    body: data,
  );

  Future<List<dynamic>> workoutTemplates() async {
    final res = await _request('GET', '/workouts/templates');
    return (res as Map)['templates'] as List? ?? const [];
  }

  Future<List<dynamic>> myWorkouts({String? from, String? to}) async {
    final query = Uri(queryParameters: {'from': ?from, 'to': ?to}).query;
    final res = await _request(
      'GET',
      query.isEmpty ? '/me/workouts' : '/me/workouts?$query',
    );
    return (res as Map)['workouts'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> planWorkout(Map<String, dynamic> data) async =>
      await _request('POST', '/me/workouts', body: data);

  Future<Map<String, dynamic>> startWorkout(String id) async =>
      await _request('POST', '/me/workouts/${Uri.encodeComponent(id)}/start');

  Future<Map<String, dynamic>> saveWorkout(
    String id,
    Map<String, dynamic> log,
  ) async => await _request(
    'PATCH',
    '/me/workouts/${Uri.encodeComponent(id)}',
    body: log,
  );

  Future<Map<String, dynamic>> completeWorkout(
    String id,
    Map<String, dynamic> log,
  ) async => await _request(
    'POST',
    '/me/workouts/${Uri.encodeComponent(id)}/complete',
    body: log,
  );

  Future<Map<String, dynamic>> skipWorkout(String id) async =>
      await _request('POST', '/me/workouts/${Uri.encodeComponent(id)}/skip');

  // ── Trainer ↔ member connections ──────────────────────────────────────
  Future<List<dynamic>> myTrainerConnections() async {
    final res = await _request('GET', '/me/trainer-connections');
    return (res as Map)['connections'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> requestTrainerConnection(
    String trainerId,
    Map<String, bool> permissions,
  ) async => await _request(
    'POST',
    '/trainers/${Uri.encodeComponent(trainerId)}/connect',
    body: {'permissions': permissions},
  );

  Future<Map<String, dynamic>> updateTrainerConnection(
    String id,
    Map<String, bool> permissions,
  ) async => await _request(
    'PATCH',
    '/me/trainer-connections/${Uri.encodeComponent(id)}',
    body: {'permissions': permissions},
  );

  Future<Map<String, dynamic>> endTrainerConnection(String id) async =>
      await _request(
        'POST',
        '/me/trainer-connections/${Uri.encodeComponent(id)}/end',
      );

  Future<List<dynamic>> trainerClients() async {
    final res = await _request('GET', '/trainer/clients');
    return (res as Map)['clients'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> trainerDecideClient(
    String id, {
    required bool accept,
  }) async => await _request(
    'POST',
    '/trainer/clients/${Uri.encodeComponent(id)}/${accept ? 'accept' : 'decline'}',
  );

  Future<Map<String, dynamic>> trainerEndClient(String id) async =>
      await _request('POST', '/trainer/clients/${Uri.encodeComponent(id)}/end');

  Future<Map<String, dynamic>> trainerClientOverview(String id) async =>
      await _request('GET', '/trainer/clients/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> trainerAssignWorkout(
    String clientId,
    Map<String, dynamic> data,
  ) async => await _request(
    'POST',
    '/trainer/clients/${Uri.encodeComponent(clientId)}/workouts',
    body: data,
  );

  Future<void> trainerCancelWorkout(String workoutId) async => await _request(
    'DELETE',
    '/trainer/workouts/${Uri.encodeComponent(workoutId)}',
  );

  Future<List<dynamic>> trainerPlans() async {
    final res = await _request('GET', '/trainer/plans');
    return (res as Map)['plans'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> trainerSavePlan(
    String? id,
    Map<String, dynamic> plan,
  ) async => id == null
      ? await _request('POST', '/trainer/plans', body: plan)
      : await _request(
          'PUT',
          '/trainer/plans/${Uri.encodeComponent(id)}',
          body: plan,
        );

  Future<void> trainerDeletePlan(String id) async =>
      await _request('DELETE', '/trainer/plans/${Uri.encodeComponent(id)}');

  // ── Gym ↔ member sharing ──────────────────────────────────────────────
  Future<List<dynamic>> myGymSharing() async {
    final res = await _request('GET', '/me/gym-sharing');
    return (res as Map)['gyms'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> updateGymSharing(
    String gymId,
    Map<String, bool> permissions,
  ) async => await _request(
    'PUT',
    '/me/gym-sharing/${Uri.encodeComponent(gymId)}',
    body: {'permissions': permissions},
  );

  Future<List<dynamic>> ownerMemberActivity(String memberId) async {
    final res = await _request(
      'GET',
      '/owner/members/${Uri.encodeComponent(memberId)}/activity',
    );
    return (res as Map)['gyms'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> ownerEngagement({
    String? gymId,
  }) async => await _request(
    'GET',
    gymId == null
        ? '/owner/engagement'
        : '/owner/engagement?${Uri(queryParameters: {'gymId': gymId}).query}',
  );

  // ── Challenges ────────────────────────────────────────────────────────
  Future<List<dynamic>> myChallenges() async {
    final res = await _request('GET', '/me/challenges');
    return (res as Map)['challenges'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> joinChallenge(
    String id, {
    String? teamId,
    String? gymId,
    bool leaderboardOptIn = false,
  }) async => await _request(
    'POST',
    '/challenges/${Uri.encodeComponent(id)}/join',
    body: {
      'teamId': ?teamId,
      'gymId': ?gymId,
      'leaderboardOptIn': leaderboardOptIn,
    },
  );

  Future<Map<String, dynamic>> setLeaderboardOptIn(
    String id,
    bool optIn,
  ) async => await _request(
    'PUT',
    '/challenges/${Uri.encodeComponent(id)}/leaderboard-opt-in',
    body: {'optIn': optIn},
  );

  Future<Map<String, dynamic>> challengeLeaderboard(String id) async =>
      await _request(
        'GET',
        '/challenges/${Uri.encodeComponent(id)}/leaderboard',
      );

  Future<Map<String, dynamic>> creatorLeaderboard(
    String scope,
    String id, {
    String? gymId,
  }) async => await _request(
    'GET',
    _creatorPath(
      scope,
      '/${Uri.encodeComponent(id)}/leaderboard',
      gymId: gymId,
    ),
  );

  /// Daily step totals (or other readings) from this phone or a health
  /// platform. Upserted by (devicePlatform, externalId); a day only goes up.
  Future<Map<String, dynamic>> syncDeviceActivities(
    List<Map<String, dynamic>> records,
  ) async => Map<String, dynamic>.from(
    await _request('POST', '/me/device-activities', body: {'records': records})
        as Map,
  );

  /// Save a GPS-recorded run; the server works out the numbers.
  Future<Map<String, dynamic>> recordRun(Map<String, dynamic> body) async =>
      Map<String, dynamic>.from(
        await _request('POST', '/me/activities/runs', body: body) as Map,
      );

  /// The private route of one of the member's own runs.
  Future<Map<String, dynamic>> runRoute(String activityId) async =>
      Map<String, dynamic>.from(
        await _request(
              'GET',
              '/me/activities/${Uri.encodeComponent(activityId)}/route',
            )
            as Map,
      );

  // ── Sharing between members ──────────────────────────────────────────
  Future<Map<String, dynamic>> _map(
    String method,
    String path, {
    Object? body,
  }) async => Map<String, dynamic>.from(
    await _request(method, path, body: body) as Map,
  );
  String _e(String v) => Uri.encodeComponent(v);

  Future<Map<String, dynamic>> socialSettings() =>
      _map('GET', '/me/social/settings');
  Future<Map<String, dynamic>> updateSocialSettings(Object? defaultShare) =>
      _map('PUT', '/me/social/settings', body: {'defaultShare': defaultShare});
  Future<Map<String, dynamic>> setPublicProfile(bool on) =>
      _map('PUT', '/me/social/settings', body: {'publicProfile': on});
  Future<Map<String, dynamic>> explore({String? before}) => _map(
    'GET',
    before == null
        ? '/social/explore'
        : '/social/explore?${Uri(queryParameters: {'before': before}).query}',
  );
  Future<Map<String, dynamic>> personProfile(
    String userId, {
    String? before,
  }) => _map(
    'GET',
    '/social/people/${_e(userId)}${before == null ? '' : '?${Uri(queryParameters: {'before': before}).query}'}',
  );
  Future<Map<String, dynamic>> postEngagement(String activityId) =>
      _map('GET', '/social/activities/${_e(activityId)}/engagement');
  Future<Map<String, dynamic>> connections() => _map('GET', '/me/connections');
  Future<Map<String, dynamic>> findPeople({String? q, String? code}) => _map(
    'GET',
    '/social/people?${Uri(queryParameters: {'q': ?q, 'code': ?code}).query}',
  );
  Future<Map<String, dynamic>> follow(String userId) =>
      _map('POST', '/me/follows', body: {'userId': userId});
  Future<Map<String, dynamic>> unfollow(String userId) =>
      _map('DELETE', '/me/follows/${_e(userId)}');
  Future<Map<String, dynamic>> removeFollower(String userId) =>
      _map('DELETE', '/me/followers/${_e(userId)}');
  Future<Map<String, dynamic>> block(String userId) =>
      _map('POST', '/me/blocks', body: {'userId': userId});
  Future<Map<String, dynamic>> unblock(String userId) =>
      _map('DELETE', '/me/blocks/${_e(userId)}');
  Future<Map<String, dynamic>> shareActivity(
    String activityId,
    Object? shareWith,
  ) => _map(
    'PUT',
    '/me/activities/${_e(activityId)}/sharing',
    body: {'shareWith': shareWith},
  );
  Future<Map<String, dynamic>> feed({String? before}) => _map(
    'GET',
    before == null
        ? '/me/feed'
        : '/me/feed?${Uri(queryParameters: {'before': before}).query}',
  );
  Future<Map<String, dynamic>> sharedActivity(String id) =>
      _map('GET', '/social/activities/${_e(id)}');
  Future<Map<String, dynamic>> kudos(String id, bool on) =>
      _map(on ? 'POST' : 'DELETE', '/social/activities/${_e(id)}/kudos');
  Future<Map<String, dynamic>> addComment(String id, String text) => _map(
    'POST',
    '/social/activities/${_e(id)}/comments',
    body: {'text': text},
  );
  Future<Map<String, dynamic>> deleteComment(String commentId) =>
      _map('DELETE', '/social/comments/${_e(commentId)}');
  Future<Map<String, dynamic>> report(
    String targetType,
    String targetId, {
    String? reason,
  }) => _map(
    'POST',
    '/social/reports',
    body: {'targetType': targetType, 'targetId': targetId, 'reason': ?reason},
  );

  Future<Map<String, dynamic>> myGroups() => _map('GET', '/me/groups');
  Future<Map<String, dynamic>> createMyGroup(Map<String, dynamic> body) =>
      _map('POST', '/me/groups', body: body);
  Future<Map<String, dynamic>> discoverGroups({String q = ''}) =>
      _map('GET', '/social/groups?${Uri(queryParameters: {'q': q}).query}');
  Future<Map<String, dynamic>> joinGroup({
    String? groupId,
    String? inviteCode,
  }) => _map(
    'POST',
    '/social/groups/join',
    body: {'groupId': ?groupId, 'inviteCode': ?inviteCode},
  );
  Future<Map<String, dynamic>> leaveGroup(String id) =>
      _map('POST', '/social/groups/${_e(id)}/leave');

  /// Group pages: members use `/social/groups`; trainers and gyms their own
  /// prefix ([scope] `trainer` or `owner`, with [gymId] for gyms).
  String _groupBase(String? scope) =>
      scope == null ? '/social/groups' : '/$scope/groups';
  String _gymQ(String? gymId) =>
      gymId == null ? '' : '?${Uri(queryParameters: {'gymId': gymId}).query}';
  Future<Map<String, dynamic>> groupDetail(
    String id, {
    String? scope,
    String? gymId,
  }) => _map('GET', '${_groupBase(scope)}/${_e(id)}${_gymQ(gymId)}');
  Future<Map<String, dynamic>> updateGroup(
    String id,
    Map<String, dynamic> body, {
    String? scope,
    String? gymId,
  }) => _map(
    'PATCH',
    '${_groupBase(scope)}/${_e(id)}${_gymQ(gymId)}',
    body: body,
  );
  Future<Map<String, dynamic>> archiveGroup(
    String id, {
    String? scope,
    String? gymId,
  }) => _map('POST', '${_groupBase(scope)}/${_e(id)}/archive${_gymQ(gymId)}');
  Future<Map<String, dynamic>> groupMemberAction(
    String id,
    String userId,
    String action, {
    String? scope,
    String? gymId,
  }) => _map(
    'POST',
    '${_groupBase(scope)}/${_e(id)}/members/${_e(userId)}/$action${_gymQ(gymId)}',
  );
  Future<Map<String, dynamic>> ownedGroups(String scope, {String? gymId}) =>
      _map('GET', '/$scope/groups${_gymQ(gymId)}');
  Future<Map<String, dynamic>> createOwnedGroup(
    String scope,
    Map<String, dynamic> body, {
    String? gymId,
  }) => _map('POST', '/$scope/groups${_gymQ(gymId)}', body: body);

  /// Rewards the member earned from challenges, and where each stands.
  Future<List<dynamic>> myRewards() async {
    final res = await _request('GET', '/me/rewards');
    return (res as Map)['rewards'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> leaveChallenge(String id) async =>
      await _request('POST', '/challenges/${Uri.encodeComponent(id)}/leave');

  /// Creator endpoints. [scope] is `trainer` or `owner` (gym owner/staff);
  /// gym calls pass [gymId].
  String _creatorPath(String scope, String rest, {String? gymId}) {
    final q = gymId == null
        ? ''
        : '?${Uri(queryParameters: {'gymId': gymId}).query}';
    return '/$scope/challenges$rest$q';
  }

  Future<List<dynamic>> creatorChallenges(String scope, {String? gymId}) async {
    final res = await _request('GET', _creatorPath(scope, '', gymId: gymId));
    return (res as Map)['challenges'] as List? ?? const [];
  }

  Future<Map<String, dynamic>> createChallenge(
    String scope,
    Map<String, dynamic> body, {
    String? gymId,
  }) async =>
      await _request('POST', _creatorPath(scope, '', gymId: gymId), body: body);

  Future<Map<String, dynamic>> cancelChallenge(
    String scope,
    String id, {
    String? gymId,
  }) => challengeAction(scope, id, 'cancel', gymId: gymId);

  /// Edit a challenge you created. Type and format lock once it starts or
  /// anyone joins; the start date locks once it starts.
  Future<Map<String, dynamic>> updateChallenge(
    String scope,
    String id,
    Map<String, dynamic> body, {
    String? gymId,
  }) async => await _request(
    'PATCH',
    _creatorPath(scope, '/${Uri.encodeComponent(id)}', gymId: gymId),
    body: body,
  );

  /// [action]: cancel, close, archive, publish, pause or resume.
  Future<Map<String, dynamic>> challengeAction(
    String scope,
    String id,
    String action, {
    String? gymId,
  }) async => await _request(
    'POST',
    _creatorPath(scope, '/${Uri.encodeComponent(id)}/$action', gymId: gymId),
  );

  Future<Map<String, dynamic>> challengeParticipants(
    String scope,
    String id, {
    String? gymId,
  }) async => await _request(
    'GET',
    _creatorPath(
      scope,
      '/${Uri.encodeComponent(id)}/participants',
      gymId: gymId,
    ),
  );

  Future<void> registerDeviceToken(String token, {String? platform}) async =>
      await _request(
        'POST',
        '/me/device-tokens',
        body: {'token': token, 'platform': ?platform},
      );

  Future<void> unregisterDeviceToken(String token) async => await _request(
    'POST',
    '/me/device-tokens/remove',
    body: {'token': token},
  );

  /// In-app notification inbox (newest first) plus unread count.
  Future<Map<String, dynamic>> notifications() async =>
      await _request('GET', '/me/notifications') as Map<String, dynamic>;

  Future<void> markNotificationRead(String id) async =>
      await _request('POST', '/me/notifications/$id/read');

  /// The member tapped the message's button — in the inbox or on a push.
  Future<void> clickNotification(String id, {String via = 'inbox'}) async =>
      await _request('POST', '/me/notifications/$id/click', body: {'via': via});

  /// A campaign push with no inbox copy was opened.
  Future<void> pushMessageOpened(String messageId) async =>
      await _request('POST', '/me/communications/messages/$messageId/opened');

  /// The member's B2B wellness benefits today, with used and remaining
  /// allowance (all worked out by the server).
  Future<Map<String, dynamic>> myWellnessBenefits() async =>
      await _request('GET', '/b2b/me/benefits') as Map<String, dynamic>;

  /// Ask to pay the member's share of a sponsored pass for this month.
  Future<Map<String, dynamic>> unlockSponsoredPass(
    String entitlementId,
  ) async =>
      await _request('POST', '/b2b/me/passes/$entitlementId/unlock')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> communicationPreferences() async =>
      await _request('GET', '/me/communication-preferences')
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> updateCommunicationPreferences(
    Map<String, dynamic> changes,
  ) async =>
      await _request('PUT', '/me/communication-preferences', body: changes)
          as Map<String, dynamic>;

  /// Price one or more slots (Pass discount applied) without booking them.
  Future<Map<String, dynamic>> quoteTrainerBooking({
    required String trainerId,
    required String gymId,
    required List<Map<String, String>> slots,
  }) async => await _request(
    'POST',
    '/me/trainer-bookings/quote',
    body: {'trainerId': trainerId, 'gymId': gymId, 'slots': slots},
  );

  /// Book one or more slots. They stay payment_pending until an admin
  /// approves the payment request the backend creates alongside them.
  Future<Map<String, dynamic>> bookTrainer({
    required String trainerId,
    required String gymId,
    required List<Map<String, String>> slots,
  }) async => await _request(
    'POST',
    '/me/trainer-bookings',
    body: {'trainerId': trainerId, 'gymId': gymId, 'slots': slots},
  );

  Future<Map<String, dynamic>> trainerRegister(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/trainer/register', body: data);

  /// C8: trainer updates own professional profile (rate, specialties, bio,
  /// availability, photo).
  Future<Map<String, dynamic>> trainerUpdateProfile(
    Map<String, dynamic> data,
  ) async => await _request('PUT', '/trainer/me', body: data);

  /// C3: sessions for a date (bookings + manual). Defaults to today.
  Future<Map<String, dynamic>> trainerSessions({String? date}) async {
    final path = (date == null || date.isEmpty)
        ? '/trainer/sessions'
        : '/trainer/sessions?${Uri(queryParameters: {'date': date}).query}';
    return await _request('GET', path);
  }

  /// My weekly payout statements, and whether my payout account is ready.
  Future<Map<String, dynamic>> trainerStatements() async =>
      await _request('GET', '/trainer/statements');

  /// One payout statement with the sessions it pays for.
  Future<Map<String, dynamic>> trainerStatement(String id) async =>
      await _request('GET', '/trainer/statements/${Uri.encodeComponent(id)}');

  /// C3: record a manual session (walk-in client).
  Future<Map<String, dynamic>> trainerCreateSession(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/trainer/sessions', body: data);

  /// C2: earnings auto-calculated from bookings + manual sessions.
  Future<Map<String, dynamic>> trainerEarnings({
    String? from,
    String? to,
  }) async {
    final query = <String, String>{
      if (from != null && from.isNotEmpty) 'from': from,
      if (to != null && to.isNotEmpty) 'to': to,
    };
    final path = query.isEmpty
        ? '/trainer/earnings'
        : '/trainer/earnings?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  /// A4: member sends an enquiry or shows interest in a trainer.
  Future<Map<String, dynamic>> engageTrainer(
    String trainerId, {
    required String type,
    String? message,
    String? gymId,
  }) async => await _request(
    'POST',
    '/trainers/$trainerId/engage',
    body: {'type': type, 'message': ?message, 'gymId': ?gymId},
  );

  /// A4: trainer inbox for member enquiries and expressions of interest —
  /// each with its conversation (`messages`), `status` and `unread`.
  Future<List<dynamic>> trainerEngagements() async =>
      await _request('GET', '/trainer/engagements');

  /// Trainer replies to an enquiry or interest; the member is notified.
  Future<Map<String, dynamic>> trainerReplyEngagement(
    String id,
    String message,
  ) async => await _request(
    'POST',
    '/trainer/engagements/${Uri.encodeComponent(id)}/reply',
    body: {'message': message},
  );

  Future<Map<String, dynamic>> trainerReadEngagement(String id) async =>
      await _request(
        'POST',
        '/trainer/engagements/${Uri.encodeComponent(id)}/read',
      );

  Future<Map<String, dynamic>> trainerCloseEngagement(String id) async =>
      await _request(
        'POST',
        '/trainer/engagements/${Uri.encodeComponent(id)}/close',
      );

  /// The member's enquiries and interests, with each conversation.
  Future<List<dynamic>> myTrainerEngagements() async =>
      await _request('GET', '/me/trainer-engagements');

  /// The member follows up; the trainer is notified.
  Future<Map<String, dynamic>> memberReplyEngagement(
    String id,
    String message,
  ) async => await _request(
    'POST',
    '/me/trainer-engagements/${Uri.encodeComponent(id)}/reply',
    body: {'message': message},
  );

  Future<Map<String, dynamic>> memberReadEngagement(String id) async =>
      await _request(
        'POST',
        '/me/trainer-engagements/${Uri.encodeComponent(id)}/read',
      );

  /// C4: trainer buys one of a gym's trainer passes ('daily' | 'weekly' |
  /// 'monthly'). Pending until an admin approves the payment.
  Future<Map<String, dynamic>> trainerBuyPass(
    String gymId, {
    String? period,
  }) async => await _request(
    'POST',
    '/trainer/gyms/$gymId/trainer-pass',
    body: {'period': ?period},
  );

  /// At a gym that sells no trainer pass, the trainer buys its member plan.
  Future<Map<String, dynamic>> trainerBuyMemberPlan(
    String gymId,
    String plan,
  ) async => await _request(
    'POST',
    '/trainer/gyms/$gymId/member-plan',
    body: {'plan': plan},
  );

  /// Active gyms, each with `trainerAccess` { access, options } and the
  /// trainer's `currentPass` there.
  Future<List<dynamic>> trainerGyms() async =>
      await _request('GET', '/trainer/gyms') as List<dynamic>;

  /// The trainer's trainer passes and gym member plans, newest first.
  Future<List<dynamic>> trainerPasses() async =>
      await _request('GET', '/trainer/passes') as List<dynamic>;

  /// Withdraw a pass/plan request that is still awaiting payment.
  Future<Map<String, dynamic>> trainerCancelPass(String subscriptionId) async =>
      await _request('POST', '/trainer/passes/$subscriptionId/cancel');

  /// The trainer's own profile (linked + pending gyms).
  Future<Map<String, dynamic>> trainerMe() async =>
      await _request('GET', '/trainer/me') as Map<String, dynamic>;

  /// A trainer's bookable calendar (public; booked slots show as taken).
  Future<Map<String, dynamic>> trainerSchedule(
    String trainerId, {
    String? from,
    int? days,
    String? gymId,
  }) async => await _request(
    'GET',
    _withQuery('/trainers/${Uri.encodeComponent(trainerId)}/schedule', {
      'from': ?from,
      'days': ?days?.toString(),
      'gymId': ?gymId,
    }),
  );

  /// The trainer's own calendar, with who booked each taken slot.
  Future<Map<String, dynamic>> trainerMySchedule({
    String? from,
    int? days,
  }) async => await _request(
    'GET',
    _withQuery('/trainer/schedule', {'from': ?from, 'days': ?days?.toString()}),
  );

  // Shop (D1)
  Future<List<dynamic>> listShopProducts({
    String? category,
    String? search,
    String? brand,
    String? vendorId,
    num? minPrice,
    num? maxPrice,
    num? minRating,
    num? maxDistanceKm,
    bool? delivery,
    bool? promotions,
    String? sort,
  }) async {
    final query = <String, String>{
      if (category != null && category.isNotEmpty) 'category': category,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (brand != null && brand.trim().isNotEmpty) 'brand': brand.trim(),
      if (vendorId != null && vendorId.isNotEmpty) 'vendorId': vendorId,
      if (minPrice != null) 'minPrice': '$minPrice',
      if (maxPrice != null) 'maxPrice': '$maxPrice',
      if (minRating != null) 'minRating': '$minRating',
      if (maxDistanceKm != null) 'maxDistanceKm': '$maxDistanceKm',
      if (delivery != null) 'delivery': '$delivery',
      if (promotions != null) 'promotions': '$promotions',
      if (sort != null && sort.isNotEmpty) 'sort': sort,
    };
    final path = query.isEmpty
        ? '/shop/products'
        : '/shop/products?${Uri(queryParameters: query).query}';
    return await _request('GET', path);
  }

  Future<Map<String, dynamic>> createShopOrder(
    List<Map<String, dynamic>> items, {
    String? note,
    required String deliveryMethod,
    String? pickupGymId,
    String? deliveryAddress,
    required String paymentMethod,
    String paymentOutcome = 'success',
  }) async => await _request(
    'POST',
    '/me/shop-orders',
    body: {
      'items': items,
      'note': ?note,
      'deliveryMethod': deliveryMethod,
      'pickupGymId': ?pickupGymId,
      'deliveryAddress': ?deliveryAddress,
      'paymentMethod': paymentMethod,
      'paymentOutcome': paymentOutcome,
    },
  );

  Future<Map<String, dynamic>> shopProduct(String id) async =>
      await _request('GET', '/shop/products/$id');

  Future<Map<String, dynamic>> vendorStore(String id) async =>
      await _request('GET', '/shop/vendors/$id');

  Future<Map<String, dynamic>> sendMarketplaceEnquiry(
    String productId,
    String message,
  ) async => await _request(
    'POST',
    '/me/marketplace-enquiries',
    body: {'productId': productId, 'message': message},
  );

  Future<Map<String, dynamic>> reviewMarketplaceProduct(
    String orderId,
    String productId,
    int rating,
    String comment,
  ) async => await _request(
    'POST',
    '/me/shop-orders/$orderId/reviews',
    body: {'productId': productId, 'rating': rating, 'comment': comment},
  );

  Future<Map<String, dynamic>> reorderMarketplaceOrder(String orderId) async =>
      await _request('POST', '/me/shop-orders/$orderId/reorder');

  Future<List<dynamic>> myShopOrders() async =>
      await _request('GET', '/me/shop-orders');

  /// Cancel my order before it is dispatched. A paid order is refunded in full.
  Future<Map<String, dynamic>> cancelMyShopOrder(String orderId) async =>
      await _request('POST', '/me/shop-orders/$orderId/cancel');

  // ── Trainer sessions I booked, cancellations and refunds ─────────────

  /// My trainer bookings; each carries `cancellation` (canCancel, refundable, cancelBy).
  Future<List<dynamic>> myTrainerBookings() async =>
      await _request('GET', '/me/trainer-bookings');

  /// Cancel one session: unpaid any time before it starts, paid up to 24
  /// hours before (refunded in full).
  Future<Map<String, dynamic>> cancelMyTrainerBooking(String bookingId) async =>
      await _request('POST', '/me/trainer-bookings/$bookingId/cancel');

  /// Trainer: cancel a session any time before it starts; the member is refunded.
  Future<Map<String, dynamic>> trainerCancelBooking(String bookingId) async =>
      await _request('POST', '/trainer/bookings/$bookingId/cancel');

  Future<Map<String, dynamic>> myRefunds() async =>
      await _request('GET', '/me/refunds');

  Future<List<dynamic>> myPayments() async =>
      await _request('GET', '/me/payments');

  /// Ask for a pass or plan payment back.
  Future<Map<String, dynamic>> requestRefund({
    required String paymentRequestId,
    required String reasonCode,
    String? note,
  }) async => await _request(
    'POST',
    '/me/refunds',
    body: {
      'paymentRequestId': paymentRequestId,
      'reasonCode': reasonCode,
      'note': ?note,
    },
  );

  Future<List<dynamic>> vendorProducts() async =>
      await _request('GET', '/vendor/products');

  Future<Map<String, dynamic>> vendorSaveProduct(
    Map<String, dynamic> data, {
    String? productId,
  }) async => await _request(
    productId == null ? 'POST' : 'PUT',
    productId == null ? '/vendor/products' : '/vendor/products/$productId',
    body: data,
  );

  Future<List<dynamic>> vendorOrders() async =>
      await _request('GET', '/vendor/orders');

  Future<Map<String, dynamic>> vendorUpdateOrderStatus(
    String orderId,
    String status,
  ) async => await _request(
    'POST',
    '/vendor/orders/$orderId/status',
    body: {'status': status},
  );

  Future<Map<String, dynamic>> vendorProfile() async =>
      await _request('GET', '/vendor/profile');

  Future<Map<String, dynamic>> vendorSaveProfile(
    Map<String, dynamic> data,
  ) async => await _request('PUT', '/vendor/profile', body: data);

  Future<Map<String, dynamic>> vendorDuplicateProduct(String productId) async =>
      await _request('POST', '/vendor/products/$productId/duplicate');

  Future<Map<String, dynamic>> vendorDeleteProduct(String productId) async =>
      await _request('DELETE', '/vendor/products/$productId');

  Future<Map<String, dynamic>> vendorPayments() async =>
      await _request('GET', '/vendor/payments');

  Future<String> vendorStatement() async {
    final response = await http
        .get(
          Uri.parse('$baseUrl/vendor/payments/statement'),
          headers: {if (_token != null) 'authorization': 'Bearer $_token'},
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body;
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<List<dynamic>> vendorEnquiries({
    String? search,
  }) async => await _request(
    'GET',
    search == null || search.trim().isEmpty
        ? '/vendor/enquiries'
        : '/vendor/enquiries?search=${Uri.encodeQueryComponent(search.trim())}',
  );

  Future<Map<String, dynamic>> vendorReplyEnquiry(
    String enquiryId,
    String message,
  ) async => await _request(
    'POST',
    '/vendor/enquiries/$enquiryId/reply',
    body: {'message': message},
  );

  Future<Map<String, dynamic>> vendorResolveEnquiry(String enquiryId) async =>
      await _request('POST', '/vendor/enquiries/$enquiryId/resolve');

  Future<List<dynamic>> vendorStaff() async =>
      await _request('GET', '/vendor/staff');

  Future<Map<String, dynamic>> vendorCreateStaff(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/vendor/staff', body: data);

  Future<Map<String, dynamic>> vendorDisableStaff(String staffId) async =>
      await _request('POST', '/vendor/staff/$staffId/disable');

  Future<Map<String, dynamic>> trainerApplyToGym(String gymId) async =>
      await _request('POST', '/trainer/gyms/$gymId/apply');

  Future<Map<String, dynamic>> trainerCancelGymApplication(
    String gymId,
  ) async => await _request('POST', '/trainer/gyms/$gymId/apply/cancel');

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

  Future<List<dynamic>> ownerTrainers({String? gymId}) async {
    final path = (gymId != null && gymId.isNotEmpty)
        ? '/owner/trainers?${Uri(queryParameters: {'gymId': gymId}).query}'
        : '/owner/trainers';
    return await _request('GET', path);
  }

  Future<List<dynamic>> ownerPendingTrainers() async =>
      await _request('GET', '/owner/trainers/pending');

  Future<Map<String, dynamic>> ownerDecideTrainerJoin(
    String trainerId, {
    required String gymId,
    required String decision,
  }) async => await _request(
    'POST',
    '/owner/trainers/$trainerId/decision',
    body: {'gymId': gymId, 'decision': decision},
  );

  Future<Map<String, dynamic>> ownerEarnings({String? gymId}) async {
    final path = (gymId != null && gymId.isNotEmpty)
        ? '/owner/earnings?${Uri(queryParameters: {'gymId': gymId}).query}'
        : '/owner/earnings';
    return await _request('GET', path);
  }

  Future<List<dynamic>> ownerInvoices() async =>
      await _request('GET', '/owner/invoices');

  /// The gym's monthly FitFlex statements, newest first.
  Future<List<dynamic>> ownerSettlements({String? gymId}) async {
    final path = (gymId != null && gymId.isNotEmpty)
        ? '/owner/settlements?${Uri(queryParameters: {'gymId': gymId}).query}'
        : '/owner/settlements';
    return await _request('GET', path);
  }

  /// One statement with its member lines and applied adjustments.
  Future<Map<String, dynamic>> ownerSettlement(String id) async =>
      await _request('GET', '/owner/settlements/${Uri.encodeComponent(id)}');

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
  Future<Map<String, dynamic>> ownerCreateTrainer(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/trainers', body: data);

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

  // Gym staff roster (RBAC) — owner only
  Future<List<dynamic>> ownerStaff() async =>
      await _request('GET', '/owner/staff');

  Future<Map<String, dynamic>> ownerCreateStaff(
    Map<String, dynamic> data,
  ) async => await _request('POST', '/owner/staff', body: data);

  Future<Map<String, dynamic>> ownerUpdateStaff(
    String id,
    Map<String, dynamic> data,
  ) async => await _request('PUT', '/owner/staff/$id', body: data);

  Future<void> ownerRemoveStaff(String id) async =>
      await _request('POST', '/owner/staff/$id/remove');

  // ── Owner communications (messages to the gym's direct members) ─────────

  static String _withQuery(String path, Map<String, String> query) =>
      query.isEmpty ? path : '$path?${Uri(queryParameters: query).query}';

  Future<Map<String, dynamic>> ownerCommunicationOverview({
    String? gymId,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/overview', {
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
    }),
  );

  Future<Map<String, dynamic>> ownerCampaigns({
    String? gymId,
    String? status,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/campaigns', {
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
      if (status != null && status.isNotEmpty) 'status': status,
    }),
  );

  Future<Map<String, dynamic>> ownerCampaign(String id) async =>
      await _request('GET', '/owner/communications/campaigns/$id');

  /// Who a campaign went to, one row per member (history).
  Future<Map<String, dynamic>> ownerCampaignRecipients(
    String id, {
    Map<String, String> query = const {},
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/campaigns/$id/recipients', query),
  );

  /// A member's communications from the owner's gyms, newest first.
  Future<Map<String, dynamic>> ownerMemberCommunications(
    String memberId, {
    Map<String, String> query = const {},
  }) async => await _request(
    'GET',
    _withQuery('/owner/members/$memberId/communications', query),
  );

  /// Results over the last [days]: totals and each campaign / automation.
  Future<Map<String, dynamic>> ownerCommunicationAnalytics({
    int days = 30,
    String? gymId,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/analytics', {
      'days': '$days',
      'gymId': ?gymId,
    }),
  );

  Future<Map<String, dynamic>> ownerCampaignAnalytics(String id) async =>
      await _request('GET', '/owner/communications/campaigns/$id/analytics');

  Future<Map<String, dynamic>> ownerAutomationAnalytics(
    String id, {
    int days = 30,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/automations/$id/analytics', {
      'days': '$days',
    }),
  );

  /// The gym's lifecycle automations (created switched off on first look).
  Future<Map<String, dynamic>> ownerAutomations({String? gymId}) async =>
      await _request(
        'GET',
        _withQuery('/owner/communications/automations', {'gymId': ?gymId}),
      );

  /// Switch on/off, channels or template. PATCH { status?, channels?, templateId? }
  Future<Map<String, dynamic>> ownerUpdateAutomation(
    String id,
    Map<String, dynamic> body,
  ) async => await _request(
    'PATCH',
    '/owner/communications/automations/$id',
    body: body,
  );

  Future<Map<String, dynamic>> ownerAutomationRuns(String id) async =>
      await _request('GET', '/owner/communications/automations/$id/runs');

  Future<Map<String, dynamic>> ownerAutomationPreview(String id) async =>
      await _request('POST', '/owner/communications/automations/$id/preview');

  /// One message in full: status, times, failure, provider reference.
  Future<Map<String, dynamic>> ownerCommunicationMessage(String id) async =>
      await _request('GET', '/owner/communications/messages/$id');

  /// Audience count and a few names. POST { gymId?, preset?, filter?, purpose? }
  Future<Map<String, dynamic>> ownerAudiencePreview(
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/owner/communications/audience/preview',
    body: body,
  );

  /// Reach per channel, a real member's message and warnings, unsaved.
  Future<Map<String, dynamic>> ownerPreviewCampaignDraft(
    Map<String, dynamic> body,
  ) async => await _request(
    'POST',
    '/owner/communications/campaigns/preview',
    body: body,
  );

  Future<Map<String, dynamic>> ownerCreateCampaign(
    Map<String, dynamic> body,
  ) async =>
      await _request('POST', '/owner/communications/campaigns', body: body);

  Future<Map<String, dynamic>> ownerUpdateCampaign(
    String id,
    Map<String, dynamic> body,
  ) async => await _request(
    'PATCH',
    '/owner/communications/campaigns/$id',
    body: body,
  );

  Future<void> ownerDeleteCampaign(String id) async =>
      await _request('DELETE', '/owner/communications/campaigns/$id');

  Future<Map<String, dynamic>> ownerScheduleCampaign(
    String id,
    String scheduledAtIso, {
    bool confirmLargeSend = false,
  }) async => await _request(
    'POST',
    '/owner/communications/campaigns/$id/schedule',
    body: {
      'scheduledAt': scheduledAtIso,
      if (confirmLargeSend) 'confirmLargeSend': true,
    },
  );

  Future<Map<String, dynamic>> ownerUnscheduleCampaign(String id) async =>
      await _request('POST', '/owner/communications/campaigns/$id/unschedule');

  Future<Map<String, dynamic>> ownerCancelCampaign(String id) async =>
      await _request('POST', '/owner/communications/campaigns/$id/cancel');

  /// Copies any campaign into a new draft (same audience, message and
  /// channels); the audience is worked out again when the copy is sent.
  Future<Map<String, dynamic>> ownerDuplicateCampaign(String id) async =>
      await _request('POST', '/owner/communications/campaigns/$id/duplicate');

  /// Send now. Repeating the same [sendRequestId] never sends twice.
  Future<Map<String, dynamic>> ownerSendCampaign(
    String id, {
    required String sendRequestId,
    bool confirmLargeSend = false,
  }) async => await _request(
    'POST',
    '/owner/communications/campaigns/$id/send',
    body: {
      'sendRequestId': sendRequestId,
      if (confirmLargeSend) 'confirmLargeSend': true,
    },
  );

  // ── Owner message templates ─────────────────────────────────────────────

  Future<Map<String, dynamic>> ownerTemplates({
    String? gymId,
    String? group,
  }) async => await _request(
    'GET',
    _withQuery('/owner/communications/templates', {
      if (gymId != null && gymId.isNotEmpty) 'gymId': gymId,
      if (group != null && group.isNotEmpty) 'group': group,
    }),
  );

  Future<Map<String, dynamic>> ownerTemplate(String id) async =>
      await _request('GET', '/owner/communications/templates/$id');

  /// How a template looks on each channel in each language.
  Future<Map<String, dynamic>> ownerTemplatePreview(
    String id, {
    String? gymId,
    Map<String, dynamic>? values,
  }) async => await _request(
    'POST',
    '/owner/communications/templates/$id/preview',
    body: {'gymId': ?gymId, 'values': ?values},
  );

  Future<Map<String, dynamic>> ownerCreateTemplate(
    Map<String, dynamic> body,
  ) async =>
      await _request('POST', '/owner/communications/templates', body: body);

  Future<Map<String, dynamic>> ownerUpdateTemplate(
    String id,
    Map<String, dynamic> body,
  ) async => await _request(
    'PATCH',
    '/owner/communications/templates/$id',
    body: body,
  );

  /// Copies a template (e.g. a FitFlex one) into the gym's own to adapt it.
  Future<Map<String, dynamic>> ownerDuplicateTemplate(
    String id, {
    String? gymId,
    String? name,
  }) async => await _request(
    'POST',
    '/owner/communications/templates/$id/duplicate',
    body: {'gymId': ?gymId, 'name': ?name},
  );

  Future<void> ownerArchiveTemplate(String id) async =>
      await _request('POST', '/owner/communications/templates/$id/archive');

  // ── Partner verification (KYC / KYB) ─────────────────────────────────────

  Future<Map<String, dynamic>> myKyc() async =>
      await _request('GET', '/me/kyc');

  Future<Map<String, dynamic>> updateMyKycBusiness(
    Map<String, dynamic> body,
  ) async => await _request('PUT', '/me/kyc/business', body: body);

  Future<Map<String, dynamic>> updateMyKycPerson(
    String role,
    Map<String, dynamic> body,
  ) async => await _request(
    'PUT',
    '/me/kyc/people/${Uri.encodeComponent(role)}',
    body: body,
  );

  Future<Map<String, dynamic>> updateMyKycDocument(
    String requirementKey,
    Map<String, dynamic> body,
  ) async => await _request(
    'PUT',
    '/me/kyc/documents/${Uri.encodeComponent(requirementKey)}',
    body: body,
  );

  /// Uploads a document's file (PDF, JPEG, PNG or WebP, up to 10 MB).
  Future<Map<String, dynamic>> uploadMyKycDocumentFile(
    String requirementKey, {
    required List<int> bytes,
    required String filename,
    String? docType,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/me/kyc/documents/${Uri.encodeComponent(requirementKey)}/file',
    );
    final request = http.MultipartRequest('POST', uri)
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    if (_token != null) request.headers['authorization'] = 'Bearer $_token';
    if (docType != null) request.fields['docType'] = docType;
    debugPrint('[REST] --> POST $uri (multipart, ${bytes.length} bytes)');
    // Documents can be a few MB on a slow connection: allow longer than JSON calls.
    final streamed = await request.send().timeout(const Duration(seconds: 90));
    final res = await http.Response.fromStream(streamed);
    _logResponse('POST', uri, res);
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return (decoded as Map).cast<String, dynamic>();
    }
    if (res.statusCode == 401 && onUnauthorized != null) onUnauthorized!();
    throw ApiException(res.statusCode, decoded);
  }

  Future<Map<String, dynamic>> addMyKycSettlementAccount(
    Map<String, dynamic> body,
  ) async => await _request('POST', '/me/kyc/settlement-accounts', body: body);

  Future<void> removeMyKycSettlementAccount(String id) async => await _request(
    'DELETE',
    '/me/kyc/settlement-accounts/${Uri.encodeComponent(id)}',
  );

  Future<Map<String, dynamic>> submitMyKyc() async =>
      await _request('POST', '/me/kyc/submit');

  Future<Map<String, dynamic>> withdrawMyKyc() async =>
      await _request('POST', '/me/kyc/withdraw');

  /// The partner terms and verification consent to accept, in [lang] (en or sw).
  Future<Map<String, dynamic>> myKycAgreements(String lang) async =>
      await _request('GET', '/me/kyc/agreements?lang=$lang');

  Future<Map<String, dynamic>> acceptMyKycAgreement(
    String agreementType,
    String version,
  ) async => await _request(
    'POST',
    '/me/kyc/agreements',
    body: {'agreementType': agreementType, 'version': version},
  );

  // ── Gym and trainer reviews ──────────────────────────────────────────
  Future<ReviewSummary> reviewSummary(ReviewSubject subject, String id) async =>
      ReviewSummary.fromJson(
        await _map('GET', '/${subject.path}/${_e(id)}/rating'),
      );

  Future<List<Review>> reviews(ReviewSubject subject, String id) async =>
      Review.listFrom(
        await _request('GET', '/${subject.path}/${_e(id)}/reviews?limit=50'),
      );

  /// Whether the member may review [id], plus their existing review if any.
  Future<MyReviewState> myReviewState(ReviewSubject subject, String id) async {
    final base = '/me/${subject.path}/${_e(id)}';
    final can = await _map('GET', '$base/can-review');
    Map<String, dynamic>? mine;
    if (can['hasExistingReview'] == true) {
      mine = await _map('GET', '$base/review');
    }
    return MyReviewState(
      eligible: can['eligible'] == true,
      reason: can['reason']?.toString(),
      rating: (mine?['rating'] as num?)?.toInt(),
      text: mine?['text'] as String?,
    );
  }

  /// Creates or replaces the member's review. Returns the new average and count.
  Future<({num average, int count})> submitReview(
    ReviewSubject subject,
    String id, {
    required int rating,
    String? text,
  }) async {
    final res = await _map(
      'POST',
      '/me/${subject.path}/${_e(id)}/review',
      body: {
        'rating': rating,
        'text': (text ?? '').trim().isEmpty ? null : text!.trim(),
      },
    );
    return _ratingFrom(res, subject);
  }

  Future<({num average, int count})> deleteMyReview(
    ReviewSubject subject,
    String id,
  ) async => _ratingFrom(
    await _map('DELETE', '/me/${subject.path}/${_e(id)}/review'),
    subject,
  );

  ({num average, int count}) _ratingFrom(
    Map<String, dynamic> res,
    ReviewSubject subject,
  ) {
    final r = res[subject == ReviewSubject.gym ? 'gymRating' : 'trainerRating'];
    final m = r is Map ? r : const {};
    return (
      average: (m['averageRating'] as num?) ?? 0,
      count: (m['reviewCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// Trainer: the summary and reviews on their own profile.
  Future<({ReviewSummary summary, List<Review> reviews})>
  myTrainerReviews() async {
    final res = await _map('GET', '/trainer/reviews');
    return (
      summary: ReviewSummary.fromJson(
        Map<String, dynamic>.from(res['summary'] as Map? ?? const {}),
      ),
      reviews: Review.listFrom(res['reviews']),
    );
  }
}
