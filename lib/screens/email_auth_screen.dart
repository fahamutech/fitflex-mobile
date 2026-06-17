import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
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
import '../shared/pin_credentials.dart';

enum EmailAuthMode { signIn, signUp }

class EmailAuthScreen extends StatefulWidget {
  const EmailAuthScreen({
    super.key,
    this.initialEmail = '',
    this.initialMode = EmailAuthMode.signIn,
    this.authService,
  });

  final String initialEmail;
  final EmailAuthMode initialMode;
  final FirebaseAuthService? authService;

  @override
  State<EmailAuthScreen> createState() => _EmailAuthScreenState();
}

class _EmailAuthScreenState extends State<EmailAuthScreen> {
  final _formKey = GlobalKey<FormState>();
  FirebaseAuthService? _firebaseAuth;
  late EmailAuthMode _mode;
  late final TextEditingController _emailCtrl;
  final _pinCtrl = TextEditingController();
  final _confirmPinCtrl = TextEditingController();
  bool _obscurePin = true;
  bool _obscureConfirmPin = true;
  bool _acceptedTerms = false;
  bool _busy = false;
  String? _error;

  FirebaseAuthService get _authService =>
      _firebaseAuth ??= widget.authService ?? FirebaseAuthService();

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pinCtrl.dispose();
    _confirmPinCtrl.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == EmailAuthMode.signUp;

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    if (_isSignUp && !_acceptedTerms) {
      setState(() => _error = context.tr('auth.acceptTermsRequired'));
      return;
    }

    setState(() => _busy = true);
    try {
      final email = _emailCtrl.text.trim();
      final pin = _pinCtrl.text;
      final password = firebasePasswordForPin(pin);
      final credential = _isSignUp
          ? await _authService.createAccountWithEmail(
              email: email,
              password: password,
            )
          : await _authService.signInWithEmail(
              email: email,
              password: password,
            );
      final idToken = await _authService.idTokenFor(credential.user);
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
      case 'email-already-in-use':
        return context.tr('auth.emailAlreadyInUse');
      case 'invalid-email':
        return context.tr('onboarding.invalidEmail');
      case 'invalid-credential':
      case 'user-not-found':
      case 'wrong-password':
        return context.tr('auth.invalidCredentials');
      case 'weak-password':
        return context.tr('auth.weakPassword');
      case 'network-request-failed':
        return context.tr('auth.networkError');
      default:
        return e.message ?? e.code;
    }
  }

  String? _emailValidator(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return context.tr('onboarding.required');
    final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
    return ok ? null : context.tr('onboarding.invalidEmail');
  }

  String? _pinValidator(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return context.tr('onboarding.required');
    if (!RegExp(r'^\d+$').hasMatch(text)) {
      return context.tr('auth.pinDigitsOnly');
    }
    if (text.length < 4 || text.length > 8) return context.tr('auth.pinLength');
    return null;
  }

  String? _confirmPinValidator(String? value) {
    if (!_isSignUp) return null;
    if (value != _pinCtrl.text) return context.tr('auth.pinMismatch');
    return null;
  }

  void _switchMode(EmailAuthMode mode) {
    setState(() {
      _mode = mode;
      _error = null;
    });
  }

  void _showTermsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('auth.termsTitle')),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              ctx.tr('auth.termsContent'),
              style: const TextStyle(fontSize: 13, height: 1.6),
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _acceptedTerms = true);
            },
            child: Text(ctx.tr('auth.acceptAndClose')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(ctx.tr('member.cancel')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('app.title')),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go(AppRoutes.auth),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(FFTokens.spacingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
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
                      _isSignUp
                          ? context.tr('auth.createTitle')
                          : context.tr('auth.emailTitle'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: FFTokens.fgPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _isSignUp
                          ? context.tr('auth.createSubtitle')
                          : context.tr('auth.emailSubtitle'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        color: FFTokens.fgQuaternary,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const Key('emailField'),
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      validator: _emailValidator,
                      decoration: InputDecoration(
                        labelText: context.tr('member.email'),
                        hintText: context.tr('auth.emailPlaceholder'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const Key('pinField'),
                      controller: _pinCtrl,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      autofillHints: const [AutofillHints.password],
                      validator: _pinValidator,
                      decoration: InputDecoration(
                        labelText: context.tr('auth.pin'),
                        counterText: '',
                        suffixIcon: IconButton(
                          key: const Key('pinVisibilityToggle'),
                          icon: Icon(
                            _obscurePin
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _obscurePin = !_obscurePin),
                        ),
                      ),
                    ),
                    if (_isSignUp) ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        key: const Key('confirmPinField'),
                        controller: _confirmPinCtrl,
                        obscureText: _obscureConfirmPin,
                        keyboardType: TextInputType.number,
                        maxLength: 8,
                        autofillHints: const [AutofillHints.newPassword],
                        validator: _confirmPinValidator,
                        decoration: InputDecoration(
                          labelText: context.tr('auth.confirmPin'),
                          counterText: '',
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirmPin
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _obscureConfirmPin = !_obscureConfirmPin,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Checkbox(
                            key: const Key('termsCheckbox'),
                            value: _acceptedTerms,
                            onChanged: (v) =>
                                setState(() => _acceptedTerms = v ?? false),
                          ),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 14,
                                  color: FFTokens.fgSecondary,
                                ),
                                children: [
                                  TextSpan(
                                    text: context.tr('auth.acceptTermsPrefix'),
                                  ),
                                  TextSpan(
                                    text: context.tr('auth.termsLink'),
                                    style: const TextStyle(
                                      color: FFTokens.brand600,
                                      decoration: TextDecoration.underline,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => _showTermsDialog(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      FFAlert(message: _error!, tone: FFAlertTone.error),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const FFSpinner(size: 18, color: Colors.white)
                          : Text(
                              _isSignUp
                                  ? context.tr('auth.createAccount')
                                  : context.tr('auth.signInWithEmail'),
                            ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _isSignUp
                              ? context.tr('auth.haveAccount')
                              : context.tr('auth.noAccount'),
                          style: const TextStyle(color: FFTokens.fgQuaternary),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _switchMode(
                                  _isSignUp
                                      ? EmailAuthMode.signIn
                                      : EmailAuthMode.signUp,
                                ),
                          child: Text(
                            _isSignUp
                                ? context.tr('auth.signIn')
                                : context.tr('auth.signUp'),
                          ),
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
    );
  }
}
