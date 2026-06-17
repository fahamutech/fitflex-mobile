import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseAuthService {
  FirebaseAuthService({FirebaseAuth? auth})
    : _auth = auth ?? FirebaseAuth.instance;

  static const _defaultServerClientId = String.fromEnvironment(
    'GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
    defaultValue:
        '318978253903-u6du2v8thfbdbmortdh49k1g06uv91v7.apps.googleusercontent.com',
  );

  final FirebaseAuth _auth;
  Future<void>? _googleInit;

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<UserCredential> createAccountWithEmail({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<void> updateEmailPassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No signed-in Firebase user is available.',
      );
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  }

  Future<UserCredential?> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({'prompt': 'select_account'});

    if (kIsWeb) {
      return _auth.signInWithPopup(provider);
    }

    await _ensureGoogleSignInInitialized();
    final googleUser = await GoogleSignIn.instance.authenticate();
    final googleIdToken = googleUser.authentication.idToken;
    if (googleIdToken == null) {
      throw FirebaseAuthException(
        code: 'missing-google-id-token',
        message: 'Google did not return an ID token.',
      );
    }
    final credential = GoogleAuthProvider.credential(idToken: googleIdToken);
    return _auth.signInWithCredential(credential);
  }

  Future<void> _ensureGoogleSignInInitialized() {
    return _googleInit ??= GoogleSignIn.instance.initialize(
      serverClientId: _defaultServerClientId,
    );
  }

  Future<UserCredential?> completeWebRedirect() async {
    if (!kIsWeb) return null;
    return _auth.getRedirectResult();
  }

  Future<String?> idTokenFor(User? user) {
    if (user == null) return Future.value();
    return user.getIdToken();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!kIsWeb) {
      try {
        await _ensureGoogleSignInInitialized();
        await GoogleSignIn.instance.signOut();
      } catch (_) {
        // Firebase sign-out is authoritative for app state.
      }
    }
  }
}
