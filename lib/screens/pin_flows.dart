import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../router.dart';
import '../shared/api_client.dart';
import '../shared/api_error_message.dart';
import '../shared/auth_state.dart';
import '../shared/components/components.dart';
import '../shared/design_tokens.dart';
import '../shared/i18n.dart';

// Identity V2 · I7d: registering, signing in and recovering a PIN that
// FitFlex keeps. A mobile number or email is proved once with a code; after
// that, sign-in is the number or email and a four-digit PIN.

/// `{phone: …}` or `{email: …}` for what the person typed.
Map<String, String> contactOf(String raw) {
  final value = raw.trim();
  return value.contains('@') ? {'email': value} : {'phone': value};
}

/// Message for a PIN or code failure the person can act on.
String pinErrorMessage(BuildContext context, Object error) {
  if (error is AdminMobileSignInException) {
    return context.tr('auth.adminPortalOnly');
  }
  final code = error is ApiException ? error.code : null;
  final body = error is ApiException && error.body is Map
      ? error.body as Map
      : const {};
  if (code == 'too_many_attempts') {
    final seconds = (body['retryAfterSeconds'] as num?)?.toInt() ?? 900;
    return context
        .tr('pin.errTooMany')
        .replaceAll('{n}', '${(seconds / 60).ceil()}');
  }
  if (code == 'code_incorrect') {
    return context
        .tr('verify.errIncorrect')
        .replaceAll('{n}', '${body['attemptsLeft'] ?? ''}');
  }
  final key = switch (code) {
    'invalid_credentials' => 'pin.errInvalid',
    'pin_reset_required' => 'pin.errResetRequired',
    'already_registered' => 'pin.errAlreadyRegistered',
    'current_pin_incorrect' => 'pin.errCurrentWrong',
    'pin_unchanged' => 'pin.errUnchanged',
    'pin_must_be_4_digits' || 'pin_required' => 'auth.pinExactlyFour',
    'pin_not_set' => 'pin.errNotSet',
    'code_attempts_exceeded' => 'verify.errAttempts',
    'code_not_found_or_expired' => 'verify.errExpired',
    'code_rate_limited' => 'verify.errTooMany',
    'code_resend_too_soon' => 'verify.errWait',
    'one_phone_or_email_required' => 'verify.errInvalid',
    'registration_token_invalid' ||
    'reset_token_invalid' ||
    'setup_token_invalid' => 'pin.errStartAgain',
    'sms_not_configured' ||
    'email_not_configured' ||
    'code_not_sent' ||
    'registration_busy' ||
    'pin_not_configured' => 'verify.errNotSent',
    _ => null,
  };
  return key != null
      ? context.tr(key)
      : errorMessage(FFLocaleScope.of(context), error);
}

String _locale(BuildContext context) =>
    FFLocaleScope.of(context).locale.languageCode;

/// Finish a flow that returned a session: store it and open the app.
Future<void> _enter(BuildContext context, Map<String, dynamic> session) async {
  final auth = AppScope.of(context).auth;
  final router = GoRouter.of(context);
  await auth.completeFitFlexSession(session);
  router.go(routeForSignedInUser(auth));
}

// ── Shared steps ────────────────────────────────────────────────────────────

/// Enter the 6-digit code that was sent to [sentTo].
class CodeStep extends StatefulWidget {
  const CodeStep({
    super.key,
    required this.sentTo,
    required this.onSubmit,
    this.onResend,
    this.resendAfterSeconds = 60,
    this.error,
    this.busy = false,
  });

  final String sentTo;
  final ValueChanged<String> onSubmit;
  final Future<int?> Function()? onResend;
  final int resendAfterSeconds;
  final String? error;
  final bool busy;

  @override
  State<CodeStep> createState() => _CodeStepState();
}

class _CodeStepState extends State<CodeStep> {
  final _code = TextEditingController();
  Timer? _ticker;
  int _resendIn = 0;

  @override
  void initState() {
    super.initState();
    _wait(widget.resendAfterSeconds);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _wait(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('pin.codeSentTo').replaceAll('{to}', widget.sentTo),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        TextField(
          key: const Key('pin-flow-code'),
          controller: _code,
          enabled: !widget.busy,
          autofocus: true,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 6,
          decoration: InputDecoration(labelText: context.tr('verify.code')),
          onSubmitted: widget.onSubmit,
        ),
        if (widget.error != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            widget.error!,
            key: const Key('pin-flow-error'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('pin-flow-code-continue'),
          onPressed: widget.busy ? null : () => widget.onSubmit(_code.text),
          child: Text(context.tr('verify.confirm')),
        ),
        if (widget.onResend != null)
          TextButton(
            key: const Key('pin-flow-resend'),
            onPressed: widget.busy || _resendIn > 0
                ? null
                : () async {
                    final wait = await widget.onResend!();
                    if (mounted && wait != null) _wait(wait);
                  },
            child: Text(
              _resendIn > 0
                  ? context
                        .tr('verify.resendIn')
                        .replaceAll('{n}', '$_resendIn')
                  : context.tr('verify.resend'),
            ),
          ),
      ],
    );
  }
}

/// Choose a four-digit PIN and type it a second time to confirm it.
class ChoosePinStep extends StatefulWidget {
  const ChoosePinStep({
    super.key,
    required this.onChosen,
    this.busy = false,
    this.error,
  });

  final ValueChanged<String> onChosen;
  final bool busy;
  final String? error;

  @override
  State<ChoosePinStep> createState() => _ChoosePinStepState();
}

class _ChoosePinStepState extends State<ChoosePinStep> {
  String _pin = '';
  String? _first;
  String? _mismatch;

  void _digit(int d) {
    if (_pin.length < 4) setState(() => _pin += '$d');
  }

  void _delete() {
    if (_pin.isNotEmpty) {
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    }
  }

  void _ok() {
    if (_pin.length != 4) return;
    if (_first == null) {
      setState(() {
        _first = _pin;
        _pin = '';
        _mismatch = null;
      });
      return;
    }
    if (_pin != _first) {
      setState(() {
        _first = null;
        _pin = '';
        _mismatch = context.tr('auth.pinMismatch');
      });
      return;
    }
    widget.onChosen(_pin);
  }

  @override
  Widget build(BuildContext context) {
    final error = _mismatch ?? widget.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr(_first == null ? 'pin.chooseTitle' : 'pin.confirmTitle'),
          key: const Key('pin-flow-pin-title'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 4),
        Text(context.tr('pin.chooseBody'), textAlign: TextAlign.center),
        const SizedBox(height: FFTokens.spacingLg),
        PinInputRow(pin: _pin, obscure: true),
        if (error != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            error,
            key: const Key('pin-flow-error'),
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: FFTokens.spacingLg),
        SizedBox(
          height: 300,
          child: CustomKeypad(
            onDigit: _digit,
            onDelete: _delete,
            onOk: _ok,
            okEnabled: _pin.length == 4,
            isLoading: widget.busy,
          ),
        ),
      ],
    );
  }
}

Widget _flowScaffold(
  BuildContext context, {
  required String title,
  required Widget child,
}) => Scaffold(
  appBar: AppBar(title: Text(title)),
  body: SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: [child],
        ),
      ),
    ),
  ),
);

// ── Register ────────────────────────────────────────────────────────────────

/// Register with a mobile number or email: a code, then a PIN (typed twice).
class RegisterFlowScreen extends StatefulWidget {
  const RegisterFlowScreen({super.key, required this.contact});

  final String contact;

  @override
  State<RegisterFlowScreen> createState() => _RegisterFlowScreenState();
}

class _RegisterFlowScreenState extends State<RegisterFlowScreen> {
  bool _busy = true;
  String? _error;
  String? _sentTo;
  int _resendAfter = 60;
  String? _token;
  bool _alreadyRegistered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send());
  }

  Future<int?> _send() async {
    final api = AppScope.of(context).api;
    final locale = _locale(context);
    setState(() => _busy = true);
    try {
      final res = await api.registerStart(contactOf(widget.contact), locale);
      if (!mounted) return null;
      final wait = (res['resendAfterSeconds'] as num?)?.toInt() ?? 60;
      setState(() {
        _sentTo = res['identifierValue']?.toString() ?? widget.contact;
        _resendAfter = wait;
        _error = null;
      });
      return wait;
    } catch (e) {
      if (!mounted) return null;
      setState(() {
        _alreadyRegistered =
            e is ApiException && e.code == 'already_registered';
        _error = pinErrorMessage(context, e);
        // A code sent a moment ago is still good.
        if (e is ApiException && e.code == 'code_resend_too_soon') {
          _sentTo ??= widget.contact;
        }
      });
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(String code) async {
    if (code.trim().isEmpty) return;
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      final res = await api.registerConfirm(
        contactOf(widget.contact),
        code.trim(),
      );
      if (!mounted) return;
      setState(() {
        _token = res['registrationToken']?.toString();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = pinErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(String pin) async {
    final scope = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final session = await scope.api.registerComplete(
        registrationToken: _token!,
        role: scope.auth.role,
        pin: pin,
      );
      if (mounted) await _enter(context, session);
    } catch (e) {
      if (mounted) setState(() => _error = pinErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget step;
    if (_token != null) {
      step = ChoosePinStep(onChosen: _complete, busy: _busy, error: _error);
    } else if (_sentTo != null) {
      step = CodeStep(
        sentTo: _sentTo!,
        onSubmit: _confirm,
        onResend: _send,
        resendAfterSeconds: _resendAfter,
        error: _error,
        busy: _busy,
      );
    } else {
      step = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Text(
              _error!,
              key: const Key('pin-flow-error'),
              textAlign: TextAlign.center,
            ),
          if (_alreadyRegistered) ...[
            const SizedBox(height: FFTokens.spacingMd),
            FilledButton(
              key: const Key('pin-flow-go-sign-in'),
              onPressed: () => context.go(AppRoutes.auth),
              child: Text(context.tr('pin.signInInstead')),
            ),
          ] else if (!_busy) ...[
            const SizedBox(height: FFTokens.spacingMd),
            OutlinedButton(
              key: const Key('pin-flow-retry'),
              onPressed: _send,
              child: Text(context.tr('verify.send')),
            ),
          ],
        ],
      );
    }
    return _flowScaffold(
      context,
      title: context.tr('pin.registerTitle'),
      child: step,
    );
  }
}

// ── Forgot PIN ──────────────────────────────────────────────────────────────

/// Forgot PIN: a code to the number or email, then a new PIN (typed twice).
class ForgotPinScreen extends StatefulWidget {
  const ForgotPinScreen({super.key, this.contact = ''});

  final String contact;

  @override
  State<ForgotPinScreen> createState() => _ForgotPinScreenState();
}

class _ForgotPinScreenState extends State<ForgotPinScreen> {
  late final _contact = TextEditingController(text: widget.contact);
  bool _busy = false;
  String? _error;
  String? _sentTo;
  int _resendAfter = 60;
  String? _token;

  @override
  void dispose() {
    _contact.dispose();
    super.dispose();
  }

  Future<int?> _send() async {
    if (_contact.text.trim().isEmpty) {
      setState(() => _error = context.tr('verify.errInvalid'));
      return null;
    }
    final api = AppScope.of(context).api;
    final locale = _locale(context);
    setState(() => _busy = true);
    try {
      final res = await api.pinResetStart(contactOf(_contact.text), locale);
      if (!mounted) return null;
      final wait = (res['resendAfterSeconds'] as num?)?.toInt() ?? 60;
      setState(() {
        _sentTo = res['identifierValue']?.toString() ?? _contact.text.trim();
        _resendAfter = wait;
        _error = null;
      });
      return wait;
    } catch (e) {
      if (mounted) setState(() => _error = pinErrorMessage(context, e));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(String code) async {
    if (code.trim().isEmpty) return;
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      final res = await api.pinResetConfirm(
        contactOf(_contact.text),
        code.trim(),
      );
      if (!mounted) return;
      setState(() {
        _token = res['resetToken']?.toString();
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = pinErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _complete(String pin) async {
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      final session = await api.pinResetComplete(_token!, pin);
      if (mounted) await _enter(context, session);
    } catch (e) {
      if (mounted) setState(() => _error = pinErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget step;
    if (_token != null) {
      step = ChoosePinStep(onChosen: _complete, busy: _busy, error: _error);
    } else if (_sentTo != null) {
      step = CodeStep(
        sentTo: _sentTo!,
        onSubmit: _confirm,
        onResend: _send,
        resendAfterSeconds: _resendAfter,
        error: _error,
        busy: _busy,
      );
    } else {
      step = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('pin.forgotBody'), textAlign: TextAlign.center),
          const SizedBox(height: FFTokens.spacingMd),
          TextField(
            key: const Key('pin-flow-contact'),
            controller: _contact,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: context.tr('auth.emailOrPhone'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: FFTokens.spacingSm),
            Text(_error!, key: const Key('pin-flow-error')),
          ],
          const SizedBox(height: FFTokens.spacingMd),
          FilledButton(
            key: const Key('pin-flow-send'),
            onPressed: _busy ? null : _send,
            child: Text(context.tr('verify.send')),
          ),
        ],
      );
    }
    return _flowScaffold(
      context,
      title: context.tr('pin.forgotTitle'),
      child: step,
    );
  }
}

// ── Existing user: moving the PIN to FitFlex ────────────────────────────────

/// An existing user's first sign-in with a FitFlex-held PIN: prove the email
/// with the code that was sent (when asked), and choose a four-digit PIN if
/// the old one was longer.
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({
    super.key,
    required this.setupToken,
    required this.contact,
    required this.needsCode,
    required this.needsNewPin,
    required this.currentPin,
    this.resendAfterSeconds = 60,
  });

  final String setupToken;
  final String contact;
  final bool needsCode;
  final bool needsNewPin;
  final String currentPin;
  final int resendAfterSeconds;

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  bool _busy = false;
  String? _error;
  String? _code;

  Future<void> _finish({String? code, String? pin}) async {
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      final session = await api.pinSetup(
        setupToken: widget.setupToken,
        code: code ?? _code,
        pin: pin ?? widget.currentPin,
      );
      if (mounted) await _enter(context, session);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = pinErrorMessage(context, e);
        // A wrong code sends them back to the code step.
        if (e is ApiException && (e.code ?? '').startsWith('code_')) {
          _code = null;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _codeEntered(String code) {
    if (code.trim().isEmpty) return;
    if (widget.needsNewPin) {
      setState(() {
        _code = code.trim();
        _error = null;
      });
    } else {
      _finish(code: code.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final askCode = widget.needsCode && _code == null;
    return _flowScaffold(
      context,
      title: context.tr('pin.setupTitle'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('pin.setupBody'), textAlign: TextAlign.center),
          const SizedBox(height: FFTokens.spacingMd),
          if (askCode)
            CodeStep(
              sentTo: widget.contact,
              onSubmit: _codeEntered,
              resendAfterSeconds: widget.resendAfterSeconds,
              error: _error,
              busy: _busy,
            )
          else
            ChoosePinStep(
              onChosen: (pin) => _finish(pin: pin),
              busy: _busy,
              error: _error,
            ),
        ],
      ),
    );
  }
}

// ── Change PIN ──────────────────────────────────────────────────────────────

/// Change the PIN FitFlex keeps. Returns true when it was changed, false when
/// this account has no FitFlex PIN yet (the caller may fall back), null when
/// cancelled.
Future<bool?> showChangePinDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (_) => const _ChangePinDialog(),
  );
}

class _ChangePinDialog extends StatefulWidget {
  const _ChangePinDialog();

  @override
  State<_ChangePinDialog> createState() => _ChangePinDialogState();
}

class _ChangePinDialogState extends State<_ChangePinDialog> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!RegExp(r'^\d{4}$').hasMatch(_next.text)) {
      setState(() => _error = context.tr('auth.pinExactlyFour'));
      return;
    }
    if (_next.text != _again.text) {
      setState(() => _error = context.tr('auth.pinMismatch'));
      return;
    }
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final session = await scope.api.changePin(_current.text, _next.text);
      // Earlier sessions are over; this is the new one for this device.
      await scope.auth.completeFitFlexSession(session);
      navigator.pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == 'pin_not_set') return navigator.pop(false);
      setState(() => _error = pinErrorMessage(context, e));
    } catch (e) {
      if (mounted) setState(() => _error = pinErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(String key, TextEditingController c, String label, int max) =>
      TextField(
        key: Key(key),
        controller: c,
        obscureText: true,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        maxLength: max,
        decoration: InputDecoration(labelText: label, counterText: ''),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.tr('member.changePin')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(
            'change-pin-current',
            _current,
            context.tr('member.currentPin'),
            8,
          ),
          const SizedBox(height: 12),
          _field('change-pin-new', _next, context.tr('member.newPin'), 4),
          const SizedBox(height: 12),
          _field('change-pin-again', _again, context.tr('pin.confirmTitle'), 4),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              key: const Key('change-pin-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(context.tr('invite.cancel')),
        ),
        FilledButton(
          key: const Key('change-pin-save'),
          onPressed: _busy ? null : _save,
          child: Text(context.tr('member.changePin')),
        ),
      ],
    );
  }
}

/// Profile entry to change the PIN, for every role. Hidden while the backend
/// does not keep PINs.
class ChangePinTile extends StatelessWidget {
  const ChangePinTile({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!auth.pinLoginEnabled) return const SizedBox.shrink();
        return FFActionTile(
          key: const Key('change-pin-tile'),
          icon: Icons.lock_outline,
          title: context.tr('member.changePin'),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final changed = context.tr('pin.changed');
            final notSet = context.tr('pin.errNotSet');
            final result = await showChangePinDialog(context);
            if (result == null) return;
            messenger.showSnackBar(
              SnackBar(content: Text(result ? changed : notSet)),
            );
          },
        );
      },
    );
  }
}
