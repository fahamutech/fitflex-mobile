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

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  FirebaseAuthService? _firebaseAuth;
  final _emailCtrl = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _recovering = false;
  bool _isValidInput = false;

  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  FirebaseAuthService get _authService =>
      _firebaseAuth ??= widget.authService ?? FirebaseAuthService();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: FFTokens.motionSlow,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();

    _emailCtrl.addListener(_validateInput);

    if (widget.enableFirebaseRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recoverWebUser());
    }
  }

  void _validateInput() {
    final text = _emailCtrl.text.trim();
    // Basic email validation or phone number validation (7-15 digits, optional +)
    final isEmail = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(text);
    final isPhone = RegExp(r'^\+?[0-9]{7,15}$').hasMatch(text);

    final isValid = isEmail || isPhone;
    if (_isValidInput != isValid) {
      setState(() => _isValidInput = isValid);
    }
  }

  @override
  void dispose() {
    _animController.dispose();
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

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Authentication Error'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleSessionApiError(ApiException e) async {
    final body = e.body is Map ? e.body as Map : const {};
    final code = body['error']?.toString();
    if (code == 'email_already_used_for_different_role') {
      final auth = AppScope.of(context).auth;
      final message = context.tr('auth.roleConflict');
      await _authService.signOut();
      await auth.signOut();
      _showErrorDialog(message);
      return;
    }
    _showErrorDialog('API ${e.status}');
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

  Future<void> _signInWithGoogle() async {
    if (_busy || _recovering) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final adminPortalOnlyMsg = context.tr('auth.adminPortalOnly');
    try {
      final credential = await _authService.signInWithGoogle();
      final user = credential?.user ?? _authService.currentUser;
      await _finishFirebaseUser(user);
    } on FirebaseAuthException catch (e) {
      _showErrorDialog(_firebaseError(e));
    } on ApiException catch (e) {
      await _handleSessionApiError(e);
    } on AdminMobileSignInException {
      _showErrorDialog(adminPortalOnlyMsg);
    } catch (e) {
      _showErrorDialog(e.toString());
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

  void _continueWithEmail({EmailAuthMode mode = EmailAuthMode.signIn}) {
    final email = Uri.encodeComponent(_emailCtrl.text.trim());
    final path =
        '${AppRoutes.emailAuth}?email=$email'
        '&mode=${mode == EmailAuthMode.signUp ? 'signup' : 'signin'}';
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final loading = _busy || _recovering;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: loading ? null : () => context.go(AppRoutes.role),
        ),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: FFTokens.spacingLg,
                vertical: FFTokens.spacingMd,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 16),
                      // Title
                      Text(
                        context.tr('auth.signIn'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 36),
                      // Google sign-in
                      _GoogleSignInButton(
                        label: context
                            .tr('auth.continueWithGoogle')
                            .toUpperCase(),
                        onTap: loading ? null : _signInWithGoogle,
                        loading: _busy,
                      ),
                      const SizedBox(height: 28),
                      _DividerLabel(label: context.tr('auth.or')),
                      const SizedBox(height: 28),
                      // Email/Phone field
                      FFTextField(
                        controller: _emailCtrl,
                        enabled: !loading,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        hint: context.tr('auth.emailOrPhone'),
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: _isValidInput && !loading
                            ? (_) => _continueWithEmail()
                            : null,
                      ),
                      const SizedBox(height: 24),
                      // CONTINUE button
                      FilledButton(
                        onPressed: loading || !_isValidInput
                            ? null
                            : _continueWithEmail,
                        child: loading
                            ? FFSpinner(
                                size: 18,
                                color: Theme.of(context).colorScheme.onPrimary,
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    context.tr('lang.continue').toUpperCase(),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                        ),
                                  ),
                                  const SizedBox(width: FFTokens.spacingSm),
                                  const Icon(
                                    Icons.chevron_right,
                                    size: FFTokens.iconMd,
                                  ),
                                ],
                              ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        FFAlert(message: _error!, tone: FFAlertTone.error),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            context.tr('auth.noAccount'),
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).textTheme.bodySmall?.color,
                                ),
                          ),
                          TextButton(
                            onPressed: loading
                                ? null
                                : () => _continueWithEmail(
                                    mode: EmailAuthMode.signUp,
                                  ),
                            child: Text(context.tr('auth.createAccount')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
      appBar: AppBar(
        title: Text(context.tr('app.title')),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                Icons.pending_actions,
                size: 72,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('auth.pendingTitle'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: FFTokens.spacingSm),
              Text(
                context.tr('auth.pendingBody'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _checking ? null : () => _checkApproval(),
                icon: _checking
                    ? SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
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

class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({
    required this.label,
    required this.onTap,
    required this.loading,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: loading
                ? [const FFSpinner(size: 20)]
                : [
                    const _GoogleMark(),
                    const SizedBox(width: 14),
                    Text(
                      label,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
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
          padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingSm),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
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
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
