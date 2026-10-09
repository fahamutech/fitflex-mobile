import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/api_error_message.dart';
import '../shared/auth_state.dart';
import '../shared/components/components.dart';
import '../shared/design_tokens.dart';
import '../shared/firebase_auth_service.dart';
import '../shared/i18n.dart';
import 'pin_flows.dart';

/// Independent account-creation entry point, reached only from the
/// sign-in screen's "Create account" link. Kept separate from
/// [AuthScreen] so the sign-in / sign-up flows don't confuse users.
class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key, this.authService});

  final FirebaseAuthService? authService;

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen>
    with SingleTickerProviderStateMixin {
  FirebaseAuthService? _firebaseAuth;
  final _emailCtrl = TextEditingController();
  bool _busy = false;
  bool _isValidInput = false;
  String? _inputError;

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
  }

  void _validateInput() {
    final text = _emailCtrl.text.trim();
    final isEmail = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(text);
    final isPhone = RegExp(r'^\+?[0-9]{7,15}$').hasMatch(text);

    final isValid = isEmail || isPhone;
    if (_isValidInput != isValid || (isValid && _inputError != null)) {
      setState(() {
        _isValidInput = isValid;
        if (isValid) _inputError = null;
      });
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailCtrl.dispose();
    super.dispose();
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
    if (requiresEmailVerification(e.body)) {
      final auth = AppScope.of(context).auth;
      context.go(AppRoutes.verifyEmailFor(auth.role));
      return;
    }
    _showErrorDialog(apiErrorMessage(FFLocaleScope.of(context), e));
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
    if (_busy) return;
    setState(() => _busy = true);
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
      if (mounted) _showErrorDialog(errorMessage(FFLocaleScope.of(context), e));
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

  void _attemptContinue() {
    if (!_isValidInput) {
      setState(() => _inputError = context.tr('auth.invalidEmailOrPhone'));
      return;
    }
    setState(() => _inputError = null);
    // When FitFlex keeps the PIN: prove the number or email with a code, then
    // choose the PIN. Otherwise the Firebase email + PIN path, as before.
    final auth = AppScope.of(context).auth;
    final contact = _emailCtrl.text.trim();
    if (auth.pinLoginEnabled &&
        !contact.contains('@') &&
        !auth.smsCodesAvailable) {
      setState(() => _inputError = context.tr('auth.phoneSignUpUnavailable'));
      return;
    }
    if (usesFitFlexCodes(auth, contact)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RegisterFlowScreen(contact: contact),
        ),
      );
      return;
    }
    final email = Uri.encodeComponent(_emailCtrl.text.trim());
    context.push('${AppRoutes.emailAuth}?email=$email&mode=signup');
  }

  @override
  Widget build(BuildContext context) {
    final loading = _busy;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: context.tr('a11y.back'),
          icon: const Icon(Icons.arrow_back),
          onPressed: loading
              ? null
              : () => context.canPop()
                    ? context.pop()
                    : context.go(AppRoutes.auth),
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
                      Text(
                        context.tr('auth.signUp'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 36),
                      FFGoogleSignInButton(
                        label: context
                            .tr('auth.continueWithGoogle')
                            .toUpperCase(),
                        onTap: loading ? null : _signInWithGoogle,
                        loading: _busy,
                      ),
                      const SizedBox(height: 28),
                      FFDividerLabel(label: context.tr('auth.or')),
                      const SizedBox(height: 28),
                      FFTextField(
                        controller: _emailCtrl,
                        enabled: !loading,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        hint: context.tr('auth.emailOrPhone'),
                        errorText: _inputError,
                        prefixIcon: const Icon(Icons.mail_outline_rounded),
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: loading
                            ? null
                            : (_) => _attemptContinue(),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: loading ? null : _attemptContinue,
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
