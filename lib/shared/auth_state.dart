import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';

/// Global session state. In a larger app this would be DI'd via Riverpod/Provider.
class AuthState extends ChangeNotifier {
  AuthState(this.api) {
    api.onUnauthorized = () => signOut();
  }

  final ApiClient api;
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
    api.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('user', jsonEncode(user));
    notifyListeners();
  }

  Future<void> signInWithFitFlexSession(
    String token,
    Map<String, dynamic> user,
  ) async {
    await signIn(token, user);
  }

  Future<void> signOut() async {
    _token = null;
    _user = null;
    api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    notifyListeners();
  }
}
