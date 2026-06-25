import 'package:firebase_auth/firebase_auth.dart';
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
  FirebaseAuthService? _firebaseAuth;
  bool _busy = false;
  String _pin = '';
  final int _minPinLength = 4;
  final int _maxPinLength = 6;
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

  Future<void> _submit() async {
    if (_pin.length < _minPinLength) return;
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
        requestedRole: auth.role,
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
      _showErrorDialog(e.toString());
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
      _showErrorDialog(message);
      return;
    }
    _showErrorDialog('API ${e.status}');
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
                        onPressed: _busy
                            ? null
                            : () {
                                // Forgot password logic here
                              },
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
