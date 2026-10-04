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
import '../shared/pin_credentials.dart';
import 'pin_flows.dart';

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
  FirebaseAuthService? _firebaseAuth;
  bool _busy = false;
  String _pin = '';
  final int _minPinLength = 4;
  // A new PIN is exactly four digits. Signing in still accepts the longer
  // PINs that could be set before that rule, up to the old limit of eight.
  int get _maxPinLength => widget.initialMode == EmailAuthMode.signUp ? 4 : 8;
  bool _obscurePin = true;

  FirebaseAuthService get _authService =>
      _firebaseAuth ??= widget.authService ?? FirebaseAuthService();

  void _onDigit(int digit) {
    if (_pin.length < _maxPinLength) {
      setState(() => _pin += digit.toString());
    }
  }

  void _onDelete() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
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
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _pin = '');
            },
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AppScope.of(context).auth.loadSignInOptions();
    });
  }

  /// Sign in with the PIN FitFlex keeps. An existing user whose PIN is still
  /// with Firebase is taken through moving it across.
  Future<void> _submitWithFitFlexPin() async {
    final scope = AppScope.of(context);
    final locale = FFLocaleScope.of(context).locale.languageCode;
    setState(() => _busy = true);
    try {
      final res = await scope.api.pinLogin(
        contactOf(widget.initialEmail),
        _pin,
        locale: locale,
      );
      if (!mounted) return;
      // Invited with a start PIN, or no profile yet: those have their own steps.
      if (res['startPin'] == true || res['onboarding'] == true) {
        setState(() => _pin = '');
        await openSignInStep(context, res);
        return;
      }
      if (res['setupRequired'] == true) {
        final pin = _pin;
        setState(() => _pin = '');
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PinSetupScreen(
              setupToken: res['setupToken'].toString(),
              contact:
                  res['identifierValue']?.toString() ?? widget.initialEmail,
              needsCode: res['verificationRequired'] == true,
              needsNewPin: res['pinChangeRequired'] == true,
              currentPin: pin,
              resendAfterSeconds:
                  (res['resendAfterSeconds'] as num?)?.toInt() ?? 60,
            ),
          ),
        );
        return;
      }
      await scope.auth.completeFitFlexSession(res);
      if (!mounted) return;
      context.go(routeForSignedInUser(scope.auth));
    } catch (e) {
      if (!mounted) return;
      _showErrorDialog(pinErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _forgotPin() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ForgotPinScreen(contact: widget.initialEmail),
      ),
    );
  }

  Future<void> _submit() async {
    if (_pin.length < _minPinLength) return;
    // When FitFlex keeps the PIN, sign-in goes to FitFlex, not Firebase.
    if (widget.initialMode == EmailAuthMode.signIn &&
        AppScope.of(context).auth.pinLoginEnabled) {
      return _submitWithFitFlexPin();
    }
    setState(() => _busy = true);

    try {
      final email = widget.initialEmail;
      final password = firebasePasswordForPin(_pin);

      final credential = widget.initialMode == EmailAuthMode.signUp
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
        // A role is only supplied while creating an account. During sign-in
        // FitFlex must resolve the existing role stored on the backend.
        requestedRole: widget.initialMode == EmailAuthMode.signUp
            ? auth.role
            : null,
        firebaseAuth: _authService,
      );

      if (!mounted) return;
      context.go(routeForSignedInUser(auth));
    } on FirebaseAuthException catch (e) {
      _showErrorDialog(_firebaseError(e));
    } on ApiException catch (e) {
      await _handleSessionApiError(e);
    } on AdminMobileSignInException {
      _showErrorDialog(context.tr('auth.adminPortalOnly'));
    } catch (e) {
      _showErrorDialog(errorMessage(FFLocaleScope.of(context), e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleSessionApiError(ApiException e) async {
    if (requiresEmailVerification(e.body)) {
      // Keep the Firebase session: the verify step retries with it.
      final auth = AppScope.of(context).auth;
      final role = widget.initialMode == EmailAuthMode.signUp
          ? auth.role
          : null;
      context.go(AppRoutes.verifyEmailFor(role));
      return;
    }
    _showErrorDialog(apiErrorMessage(FFLocaleScope.of(context), e));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy
              ? null
              : () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppRoutes.auth);
                  }
                },
        ),
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FFTokens.spacingLg,
            vertical: FFTokens.spacingMd,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: FFTokens.spacingLg),
                  Text(
                    widget.initialMode == EmailAuthMode.signUp
                        ? context.tr('auth.createPin')
                        : context.tr('auth.verificationPin'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: FFTokens.spacingSm),
                  Text(
                    widget.initialEmail,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: FFTokens.spacingXl * 1.5),
                  Stack(
                    alignment: Alignment.centerRight,
                    children: [
                      PinInputRow(pin: _pin, obscure: _obscurePin),
                      IconButton(
                        icon: Icon(
                          _obscurePin ? Icons.visibility : Icons.visibility_off,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                        onPressed: () {
                          setState(() => _obscurePin = !_obscurePin);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: FFTokens.spacingXl * 1.5),
                  Expanded(
                    child: CustomKeypad(
                      onDigit: _onDigit,
                      onDelete: _onDelete,
                      onOk: _submit,
                      okEnabled: _pin.length >= _minPinLength,
                      isLoading: _busy,
                    ),
                  ),
                  const SizedBox(height: FFTokens.spacingLg),
                  if (widget.initialMode == EmailAuthMode.signIn)
                    Center(
                      child: TextButton(
                        key: const Key('forgot-pin'),
                        onPressed:
                            _busy || !AppScope.of(context).auth.pinResetEnabled
                            ? null
                            : _forgotPin,
                        child: Text(
                          context.tr('auth.forgotPin'),
                          style: TextStyle(
                            color: Theme.of(context).textTheme.bodySmall?.color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: FFTokens.spacingMd),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
