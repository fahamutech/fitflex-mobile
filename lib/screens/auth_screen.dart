import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router.dart';
import '../shared/components/components.dart';
import '../shared/i18n.dart';
import '../shared/design_tokens.dart';
import '../shared/api_client.dart';
import '../app_scope.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String? _error;
  bool _busy = false;

  Future<void> _signInWithGoogle() async {
    final scope = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final provider = GoogleAuthProvider()
        ..setCustomParameters({'prompt': 'select_account'});

      // signInWithProvider is not supported on web — use signInWithPopup there
      final UserCredential credential;
      if (kIsWeb) {
        credential = await FirebaseAuth.instance.signInWithPopup(provider);
      } else {
        credential = await FirebaseAuth.instance.signInWithProvider(provider);
      }
      final firebaseUser = credential.user;
      final idToken = await firebaseUser?.getIdToken();
      if (idToken == null) throw StateError('Missing Firebase ID token');

      final res = await scope.api.firebaseSession(idToken, scope.auth.role);
      await scope.auth.signInWithFitFlexSession(
        res['token'] as String,
        Map<String, dynamic>.from(res['user'] as Map),
      );
      // GoRouter redirect will handle navigation based on auth state
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } on ApiException catch (e) {
      final body = e.body is Map ? e.body as Map : const {};
      final code = body['error']?.toString();
      if (mounted) {
        setState(
          () => _error = code == 'email_already_used_for_different_role'
              ? context.tr('auth.roleConflict')
              : 'API ${e.status}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = AppScope.of(context).auth.role;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('auth.google.heading'),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: FFTokens.fgPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${context.tr('auth.google.body')} ${role.toUpperCase()}',
                style: const TextStyle(color: FFTokens.fgQuaternary),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _signInWithGoogle,
                icon: _busy
                    ? const FFSpinner(size: 18, color: Colors.white)
                    : const Icon(Icons.login),
                label: Text(
                  _busy
                      ? context.tr('auth.signingIn')
                      : context.tr('auth.google'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                FFAlert(message: _error!, tone: FFAlertTone.error),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class PendingApprovalScreen extends StatelessWidget {
  const PendingApprovalScreen({super.key});

  Future<void> _backToRoles(BuildContext context) async {
    await AppScope.of(context).auth.signOut();
    if (!context.mounted) return;
    context.go(AppRoutes.role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('app.title'))),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.pending_actions,
                size: 72,
                color: FFTokens.brand500,
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('auth.pendingTitle'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: FFTokens.fgPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('auth.pendingBody'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: FFTokens.fgQuaternary,
                  height: 1.4,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => _backToRoles(context),
                child: Text(context.tr('auth.backToRoles')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
