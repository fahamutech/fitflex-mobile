import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'firebase_auth_service.dart';
import 'push_service.dart';

/// Global session state. In a larger app this would be DI'd via Riverpod/Provider.
class AuthState extends ChangeNotifier {
  AuthState(this.api, {this.push}) {
    api.onUnauthorized = () => signOut();
  }

  final ApiClient api;

  /// Optional: registers the device for push while a session exists.
  final PushService? push;
  String? _token;
  Map<String, dynamic>? _user;
  String _role = 'member';

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  String get role => _role;
  bool get isSignedIn => _token != null;
  bool get isPendingApproval =>
      _user?['approvalStatus']?.toString() == 'pending_approval';

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    final u = prefs.getString('user');
    _user = u == null ? null : jsonDecode(u) as Map<String, dynamic>;
    _role = prefs.getString('role') ?? 'member';
    api.setToken(_token);

    // If we have a token, refresh user from backend to get latest status
    if (_token != null) {
      try {
        final meRes = await api.me();
        final freshUser = Map<String, dynamic>.from(meRes['user'] as Map);
        _user = freshUser;
        await prefs.setString('user', jsonEncode(freshUser));
        unawaited(push?.register());
      } on ApiException catch (e) {
        // Token invalid or user deleted — clear session
        if (e.status == 401 || e.status == 404) {
          _token = null;
          _user = null;
          api.setToken(null);
          await prefs.remove('token');
          await prefs.remove('user');
        }
        // For other errors (network etc.), keep cached data
      } catch (_) {
        // Network failure — keep cached data, router will use what we have
      }
    }

    // Sync role with the authoritative userType from user object
    final userType = _user?['userType']?.toString();
    if (userType != null && userType != _role) {
      _role = userType;
      await prefs.setString('role', userType);
    }

    notifyListeners();
  }

  Future<void> setRole(String role) async {
    _role = role;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', role);
    notifyListeners();
  }

  Future<void> signIn(String token, Map<String, dynamic> user) async {
    _token = token;
    _user = user;
    // The backend owns role assignment. Persist the role returned with every
    // session so a later app launch (or a logout followed by login) cannot
    // reuse a stale role selected during an earlier registration attempt.
    final sessionRole = user['userType']?.toString();
    if (sessionRole != null && sessionRole.isNotEmpty) {
      _role = sessionRole;
    }
    api.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('user', jsonEncode(user));
    if (sessionRole != null && sessionRole.isNotEmpty) {
      await prefs.setString('role', sessionRole);
    }
    notifyListeners();
    unawaited(push?.register());
  }

  Future<void> signInWithFitFlexSession(
    String token,
    Map<String, dynamic> user,
  ) async {
    await signIn(token, user);
  }

  Future<Map<String, dynamic>> completeFirebaseSession({
    required String idToken,
    String? requestedRole,
    FirebaseAuthService? firebaseAuth,
  }) async {
    Map<String, dynamic> res;
    try {
      res = await api.firebaseSession(idToken, requestedRole);
    } on ApiException catch (error) {
      final fallbackRole = requestedRole == null
          ? preferredAutomaticRole(error.body)
          : null;
      if (fallbackRole == null) rethrow;
      res = await api.firebaseSession(idToken, fallbackRole);
    }
    final user = Map<String, dynamic>.from(res['user'] as Map);
    if (user['userType']?.toString() == 'admin') {
      await firebaseAuth?.signOut();
      await signOut();
      throw const AdminMobileSignInException();
    }
    await signInWithFitFlexSession(res['token'] as String, user);
    return user;
  }

  Future<void> signOut() async {
    // While the session token is still set, so the backend accepts the call.
    await push?.unregister();
    _token = null;
    _user = null;
    api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    notifyListeners();
  }
}

String? preferredAutomaticRole(Object? errorBody) {
  if (errorBody is! Map ||
      errorBody['error']?.toString() != 'profile_role_required') {
    return null;
  }
  final availableRoles = errorBody['availableRoles'];
  if (availableRoles is! Iterable) return null;
  final operationalRoles = availableRoles
      .map((role) => role.toString())
      .where((role) => role.isNotEmpty && role != 'member')
      .toSet();
  return operationalRoles.length == 1 ? operationalRoles.single : null;
}

class AdminMobileSignInException implements Exception {
  const AdminMobileSignInException();
}
