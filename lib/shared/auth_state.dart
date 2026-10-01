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
  // Identity V2: the Person's personas (User rows). Empty while the backend's
  // V2 flags are off, which keeps the app on single-persona behaviour.
  List<Map<String, dynamic>> _personas = const [];
  List<String> _addablePersonaTypes = const [];
  bool _personaChoiceRequired = false;
  // Identity V2 invitations. `_invitesEnabled` follows the backend flag:
  // while it is off the app keeps the legacy "create" forms.
  bool _invitesEnabled = false;
  List<Map<String, dynamic>> _invitations = const [];

  String? get token => _token;
  Map<String, dynamic>? get user => _user;
  String get role => _role;
  bool get isSignedIn => _token != null;
  bool get isPendingApproval =>
      _user?['approvalStatus']?.toString() == 'pending_approval';

  /// All live personas of the signed-in Person (empty before Identity V2).
  List<Map<String, dynamic>> get personas => _personas;

  /// Personas this session can switch to: not the current one, not
  /// portal-only, not suspended or rejected.
  List<Map<String, dynamic>> get switchablePersonas => _personas
      .where(
        (p) =>
            p['id'] != _user?['id'] &&
            p['portalOnly'] != true &&
            p['accountStatus'] != 'suspended' &&
            p['approvalStatus'] != 'rejected',
      )
      .toList(growable: false);

  /// Roles this Person could still add (empty unless the backend offers it).
  List<String> get addablePersonaTypes => _addablePersonaTypes;

  /// True when organisations invite people instead of creating accounts.
  bool get invitesEnabled => _invitesEnabled;

  /// Open invitations addressed to this Person.
  List<Map<String, dynamic>> get invitations => _invitations;

  /// Set when the backend couldn't pick a persona (several, none used last).
  bool get personaChoiceRequired => _personaChoiceRequired;

  Future<void> hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token');
    final u = prefs.getString('user');
    _user = u == null ? null : jsonDecode(u) as Map<String, dynamic>;
    _role = prefs.getString('role') ?? 'member';
    _personas = _decodePersonas(prefs.getString('personas'));
    api.setToken(_token);

    // If we have a token, refresh user from backend to get latest status
    if (_token != null) {
      try {
        final meRes = await api.me();
        final freshUser = Map<String, dynamic>.from(meRes['user'] as Map);
        _user = freshUser;
        await prefs.setString('user', jsonEncode(freshUser));
        unawaited(push?.register());
        await refreshPersonas();
        await refreshInvitations();
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
    await _applyPersonaPayload(res);
    unawaited(refreshInvitations());
    return user;
  }

  /// Identity V2: move this session onto another persona of the same Person.
  Future<void> switchPersona(String personaId) async {
    final res = await api.switchPersona(personaId);
    final user = Map<String, dynamic>.from(res['user'] as Map);
    // Push belongs to the persona: drop it for the old one, the new session
    // registers again in signIn().
    await push?.unregister();
    await signIn(res['token'] as String, user);
    await _applyPersonaPayload(res);
  }

  /// Identity V2: add a role to this Person, then continue as it. The new
  /// persona goes through that role's normal registration and approval.
  Future<void> addPersona(String userType) async {
    final res = await api.addPersona(userType);
    await _applyPersonaPayload(res, keepChoice: true);
    final persona = res['persona'];
    if (persona is Map && persona['id'] != null) {
      await switchPersona(persona['id'].toString());
    }
  }

  /// The user picked the persona they're already in.
  void keepCurrentPersona() {
    if (!_personaChoiceRequired) return;
    _personaChoiceRequired = false;
    notifyListeners();
  }

  /// Re-read this Person's invitations; a 404 means invitations are off.
  Future<void> refreshInvitations() async {
    if (_token == null) return;
    try {
      final res = await api.myInvitations();
      final raw = res['invitations'];
      _invitesEnabled = true;
      _invitations = raw is List
          ? raw
                .whereType<Map>()
                .map((i) => Map<String, dynamic>.from(i))
                .toList()
          : const [];
    } on ApiException catch (e) {
      if (e.status == 404) {
        _invitesEnabled = false;
        _invitations = const [];
      }
    } catch (_) {
      // Offline: keep what we have.
    }
    notifyListeners();
  }

  /// Re-read the personas list; a 404 means Identity V2 is off.
  Future<void> refreshPersonas() async {
    if (_token == null) return;
    try {
      await _applyPersonaPayload(await api.myPersonas(), keepChoice: true);
    } on ApiException catch (e) {
      if (e.status == 404) await _applyPersonaPayload(const {});
    } catch (_) {
      // Offline: keep what we have.
    }
  }

  Future<void> _applyPersonaPayload(
    Map<String, dynamic> res, {
    bool keepChoice = false,
  }) async {
    final raw = res['personas'];
    _personas = raw is List
        ? raw.whereType<Map>().map((p) => Map<String, dynamic>.from(p)).toList()
        : const [];
    final addable = res['addablePersonaTypes'];
    _addablePersonaTypes = addable is List
        ? addable.map((t) => t.toString()).toList(growable: false)
        : const [];
    if (!keepChoice) {
      _personaChoiceRequired =
          res['personaChoiceRequired'] == true && _personas.length > 1;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('personas', jsonEncode(_personas));
    notifyListeners();
  }

  static List<Map<String, dynamic>> _decodePersonas(String? raw) {
    if (raw == null) return const [];
    try {
      final list = jsonDecode(raw);
      return list is List
          ? list
                .whereType<Map>()
                .map((p) => Map<String, dynamic>.from(p))
                .toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> signOut() async {
    // While the session token is still set, so the backend accepts the call.
    await push?.unregister();
    _token = null;
    _user = null;
    _personas = const [];
    _addablePersonaTypes = const [];
    _personaChoiceRequired = false;
    _invitesEnabled = false;
    _invitations = const [];
    api.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user');
    await prefs.remove('personas');
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

/// True when the backend refused a sign-in until Firebase verifies the
/// account's email (an unverified email can't claim an existing profile).
bool requiresEmailVerification(Object? errorBody) =>
    errorBody is Map &&
    errorBody['error']?.toString() == 'email_verification_required';

class AdminMobileSignInException implements Exception {
  const AdminMobileSignInException();
}
