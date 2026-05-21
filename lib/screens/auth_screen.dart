import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/auth_state.dart';
import '../shared/components/components.dart';
import '../shared/design_tokens.dart';
import '../shared/firebase_auth_service.dart';
import '../shared/i18n.dart';
import 'email_auth_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    this.authService,
    this.enableFirebaseRecovery = true,
  });

  final FirebaseAuthService? authService;
  final bool enableFirebaseRecovery;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  FirebaseAuthService? _firebaseAuth;
  final _emailCtrl = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _recovering = false;

  FirebaseAuthService get _authService =>
      _firebaseAuth ??= widget.authService ?? FirebaseAuthService();

  @override
  void initState() {
    super.initState();
    if (widget.enableFirebaseRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverWebUser());
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _recoverWebUser() async {
    if (!kIsWeb || !mounted || AppScope.of(context).auth.isSignedIn) return;
    final user = _authService.currentUser;
    if (user == null) return;
    setState(() => _recovering = true);
    try {
      await _finishFirebaseUser(user);
    } catch (_) {
      // Keep the normal login screen available if recovery cannot complete.
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    if (_busy || _recovering) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final credential = await _authService.signInWithGoogle();
      final user = credential?.user ?? _authService.currentUser;
      await _finishFirebaseUser(user);
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _firebaseError(e));
    } on ApiException catch (e) {
      await _handleSessionApiError(e);
    } on AdminMobileSignInException {
      if (mounted) setState(() => _error = context.tr('auth.adminPortalOnly'));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _finishFirebaseUser(User? firebaseUser) async {
    final idToken = await _authService.idTokenFor(firebaseUser);
    if (idToken == null) throw StateError('Missing Firebase ID token');
    if (!mounted) return;
    final auth = AppScope.of(context).auth;
    await auth.completeFirebaseSession(
      idToken: idToken,
      requestedRole: auth.role,
      firebaseAuth: _authService,
    );
    if (!mounted) return;
    context.go(routeForSignedInUser(auth));
  }

  Future<void> _handleSessionApiError(ApiException e) async {
    final body = e.body is Map ? e.body as Map : const {};
    final code = body['error']?.toString();
    if (code == 'email_already_used_for_different_role') {
      final auth = AppScope.of(context).auth;
      final message = context.tr('auth.roleConflict');
      await _authService.signOut();
      await auth.signOut();
      if (mounted) setState(() => _error = message);
      return;
    }
    if (mounted) setState(() => _error = 'API ${e.status}');
  }

  String _firebaseError(FirebaseAuthException e) {
    switch (e.code) {
      case 'popup-closed-by-user':
      case 'cancelled-popup-request':
        return context.tr('auth.cancelled');
      case 'network-request-failed':
        return context.tr('auth.networkError');
      default:
        return e.message ?? e.code;
    }
  }

  void _continueWithEmail({EmailAuthMode mode = EmailAuthMode.signIn}) {
    final email = Uri.encodeComponent(_emailCtrl.text.trim());
    final path =
        '${AppRoutes.emailAuth}?email=$email'
        '&mode=${mode == EmailAuthMode.signUp ? 'signup' : 'signin'}';
    context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final loading = _busy || _recovering;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.role),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: FFTokens.surface,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: FFTokens.shadowSm,
                        border: Border.all(color: FFTokens.border),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Image.asset('assets/brand/fitflex-logo.png'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    context.tr('auth.loginTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: FFTokens.fgPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    context.tr('auth.loginSubtitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: FFTokens.fgQuaternary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: InputDecoration(
                      hintText: context.tr('auth.emailPlaceholder'),
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _continueWithEmail(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: loading ? null : _continueWithEmail,
                    child: loading
                        ? const FFSpinner(size: 18, color: Colors.white)
                        : Text(context.tr('auth.continueWithEmail')),
                  ),
                  const SizedBox(height: 24),
                  _DividerLabel(label: context.tr('auth.or')),
                  const SizedBox(height: 24),
                  OutlinedButton.icon(
                    onPressed: loading ? null : _signInWithGoogle,
                    icon: const _GoogleMark(),
                    label: Text(context.tr('auth.continueWithGoogle')),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    FFAlert(message: _error!, tone: FFAlertTone.error),
                  ],
                  const SizedBox(height: 28),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        context.tr('auth.noAccount'),
                        style: const TextStyle(color: FFTokens.fgQuaternary),
                      ),
                      TextButton(
                        onPressed: loading
                            ? null
                            : () => _continueWithEmail(
                                mode: EmailAuthMode.signUp,
                              ),
                        child: Text(context.tr('auth.signUp')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
  int _pollInterval = 5;
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
      final scope = AppScope.of(context);
      final meRes = await scope.api.me();
      if (!mounted) return;
      final user = Map<String, dynamic>.from(meRes['user'] as Map);
      final status = user['approvalStatus']?.toString();
      if (status != 'pending_approval') {
        await scope.auth.signIn(scope.auth.token!, user);
        if (!mounted) return;
        _polling = false;
        context.go(routeForSignedInUser(scope.auth));
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
    final auth = AppScope.of(context).auth;
    await auth.signOut();
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

class GoogleWebCallbackScreen extends StatefulWidget {
  const GoogleWebCallbackScreen({super.key});

  @override
  State<GoogleWebCallbackScreen> createState() =>
      _GoogleWebCallbackScreenState();
}

class _GoogleWebCallbackScreenState extends State<GoogleWebCallbackScreen> {
  final _firebaseAuth = FirebaseAuthService();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
  }

  Future<void> _complete() async {
    if (!kIsWeb) {
      context.go(AppRoutes.auth);
      return;
    }
    try {
      final credential = await _firebaseAuth.completeWebRedirect();
      final user = credential?.user ?? _firebaseAuth.currentUser;
      final idToken = await _firebaseAuth.idTokenFor(user);
      if (idToken == null) throw StateError('Missing Firebase ID token');
      if (!mounted) return;
      final auth = AppScope.of(context).auth;
      await auth.completeFirebaseSession(
        idToken: idToken,
        requestedRole: auth.role,
        firebaseAuth: _firebaseAuth,
      );
      if (!mounted) return;
      context.go(routeForSignedInUser(auth));
    } on ApiException catch (e) {
      final body = e.body is Map ? e.body as Map : const {};
      final code = body['error']?.toString();
      if (code == 'email_already_used_for_different_role') {
        final auth = AppScope.of(context).auth;
        final message = context.tr('auth.roleConflict');
        await _firebaseAuth.signOut();
        await auth.signOut();
        if (mounted) setState(() => _error = message);
        return;
      }
      if (mounted) setState(() => _error = 'API ${e.status}');
    } on AdminMobileSignInException {
      if (mounted) setState(() => _error = context.tr('auth.adminPortalOnly'));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: _error == null
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const FFSpinner(size: 32),
                        const SizedBox(height: 16),
                        Text(context.tr('auth.finishingSignIn')),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FFAlert(message: _error!, tone: FFAlertTone.error),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: () => context.go(AppRoutes.auth),
                          child: Text(context.tr('auth.backToSignIn')),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DividerLabel extends StatelessWidget {
  const _DividerLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider()),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: const TextStyle(
              color: FFTokens.fgQuaternary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'G',
      style: TextStyle(
        color: Color(0xFF4285F4),
        fontWeight: FontWeight.w800,
        fontSize: 18,
      ),
    );
  }
}
