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
      final user = Map<String, dynamic>.from(res['user'] as Map);
      if (user['userType']?.toString() == 'admin') {
        await FirebaseAuth.instance.signOut();
        await scope.auth.signOut();
        if (!mounted) return;
        setState(() => _error = context.tr('auth.adminPortalOnly'));
        return;
      }

      await scope.auth.signInWithFitFlexSession(res['token'] as String, user);
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
      appBar: AppBar(
        title: Text(context.tr('app.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.role),
        ),
      ),
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

class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key});

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _checking = false;
  int _pollInterval = 5; // seconds, increases with backoff
  bool _polling = true;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _polling = false;
    super.dispose();
  }

  Future<void> _startPolling() async {
    while (_polling && mounted) {
      await Future.delayed(Duration(seconds: _pollInterval));
      if (!_polling || !mounted) break;
      await _checkApproval(silent: true);
      // Exponential backoff: 5s → 10s → 20s → 40s → max 60s
      if (mounted && _polling) {
        setState(() {
          _pollInterval = (_pollInterval * 2).clamp(5, 60);
        });
      }
    }
  }

  Future<void> _checkApproval({bool silent = false}) async {
    if (_checking) return;
    setState(() => _checking = true);
    try {
      final api = AppScope.of(context).api;
      final meRes = await api.me();
      if (!mounted) return;
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      final status = user['approvalStatus']?.toString();
      if (status != 'pending_approval') {
        // Approved! Re-hydrate auth and navigate
        await AppScope.of(
          context,
        ).auth.signIn(AppScope.of(context).auth.token!, user);
        if (!mounted) return;
        _polling = false;
        context.go(AppRoutes.home);
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('auth.stillPending'))),
        );
      }
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.tr('auth.checkFailed'))));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _backToRoles() async {
    _polling = false;
    await AppScope.of(context).auth.signOut();
    if (!mounted) return;
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
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _checking ? null : () => _checkApproval(),
                icon: _checking
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh),
                label: Text(context.tr('auth.checkApproval')),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: _backToRoles,
                child: Text(context.tr('auth.backToRoles')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
