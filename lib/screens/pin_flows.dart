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
    'setup_token_invalid' ||
    'start_token_invalid' ||
    'onboarding_token_invalid' => 'pin.errStartAgain',
    'display_name_required' => 'start.errName',
    'invitation_not_open' || 'invitation_not_found' => 'invite.errNotOpen',
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

/// Finish a flow that returned a session: store it and open the app. A
/// person who has no profile yet gets the onboarding step instead.
Future<void> _enter(BuildContext context, Map<String, dynamic> session) async {
  if (session['onboarding'] == true) {
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => OnboardingScreen(step: session)),
    );
    return;
  }
  final auth = AppScope.of(context).auth;
  final router = GoRouter.of(context);
  await auth.completeFitFlexSession(session);
  router.go(routeForSignedInUser(auth));
}

/// What a PIN sign-in answered when it was not a session: the start of an
/// invitation, or the step for a person with no profile yet. Returns true
/// when it opened a screen for it.
Future<bool> openSignInStep(
  BuildContext context,
  Map<String, dynamic> res,
) async {
  if (res['startPin'] == true) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => InviteStartScreen(
          startToken: res['startToken'].toString(),
          invitation: res['invitation'] is Map
              ? Map<String, dynamic>.from(res['invitation'] as Map)
              : const {},
        ),
      ),
    );
    return true;
  }
  if (res['onboarding'] == true) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => OnboardingScreen(step: res)),
    );
    return true;
  }
  return false;
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
          onTap: () => changePinAndReport(context),
        );
      },
    );
  }
}

/// Open the change-PIN dialog and say how it went.
Future<void> changePinAndReport(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final changed = context.tr('pin.changed');
  final notSet = context.tr('pin.errNotSet');
  final result = await showChangePinDialog(context);
  if (result == null) return;
  messenger.showSnackBar(SnackBar(content: Text(result ? changed : notSet)));
}

/// Change PIN as an app-bar button, for screens with no profile list (the
/// vendor screen). Hidden while the backend does not keep PINs.
class ChangePinButton extends StatelessWidget {
  const ChangePinButton({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!auth.pinLoginEnabled) return const SizedBox.shrink();
        return IconButton(
          key: const Key('change-pin-button'),
          tooltip: context.tr('member.changePin'),
          icon: const Icon(Icons.lock_outline),
          onPressed: () => changePinAndReport(context),
        );
      },
    );
  }
}

// ── Invited, and new to FitFlex ─────────────────────────────────────────────

String _startRole(BuildContext context, Object? role) => switch (role) {
  'trainer' => context.tr('role.trainer'),
  'member' => context.tr('role.member'),
  _ => context.tr('start.roleStaff'),
};

/// After signing in with the start PIN from an invitation: the person gives
/// their name and chooses their own PIN. Only then does their account exist.
class InviteStartScreen extends StatefulWidget {
  const InviteStartScreen({
    super.key,
    required this.startToken,
    this.invitation = const {},
  });

  final String startToken;
  final Map<String, dynamic> invitation;

  @override
  State<InviteStartScreen> createState() => _InviteStartScreenState();
}

class _InviteStartScreenState extends State<InviteStartScreen> {
  final _name = TextEditingController();
  bool _nameDone = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _nameEntered() {
    if (_name.text.trim().length < 2) {
      setState(() => _error = context.tr('start.errName'));
      return;
    }
    setState(() {
      _nameDone = true;
      _error = null;
    });
  }

  Future<void> _begin(String pin) async {
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      final step = await api.inviteBegin(
        startToken: widget.startToken,
        displayName: _name.text.trim(),
        pin: pin,
      );
      if (mounted) await _enter(context, step);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = pinErrorMessage(context, e);
        if (e is ApiException && e.code == 'display_name_required') {
          _nameDone = false;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final role = _startRole(context, widget.invitation['role']);
    return _flowScaffold(
      context,
      title: context.tr('start.title'),
      child: _nameDone
          ? ChoosePinStep(onChosen: _begin, busy: _busy, error: _error)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('start.body').replaceAll('{role}', role),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: FFTokens.spacingMd),
                TextField(
                  key: const Key('start-name'),
                  controller: _name,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.tr('start.name'),
                  ),
                  onSubmitted: (_) => _nameEntered(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: FFTokens.spacingSm),
                  Text(
                    _error!,
                    key: const Key('pin-flow-error'),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: FFTokens.spacingMd),
                FilledButton(
                  key: const Key('start-name-continue'),
                  onPressed: _nameEntered,
                  child: Text(context.tr('start.continue')),
                ),
              ],
            ),
    );
  }
}

// ── A person with no profile yet ────────────────────────────────────────────

/// Accept or decline the invitations waiting for a person who has no profile
/// yet; with none left, choose how to use FitFlex, as when registering.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.step});

  /// `{onboardingToken, invitations}` as the backend answered it.
  final Map<String, dynamic> step;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  late Map<String, dynamic> _step = widget.step;
  bool _busy = false;
  String? _error;

  String get _token => _step['onboardingToken'].toString();
  List<Map<String, dynamic>> get _invitations =>
      (_step['invitations'] as List? ?? const [])
          .whereType<Map>()
          .map((i) => Map<String, dynamic>.from(i))
          .toList();

  Future<void> _run(Future<Map<String, dynamic>> Function() call) async {
    setState(() => _busy = true);
    try {
      final res = await call();
      if (!mounted) return;
      if (res['onboarding'] == true) {
        // Declined: stay here with what is left.
        setState(() {
          _step = res;
          _error = null;
        });
      } else {
        await _enter(context, res);
      }
    } catch (e) {
      if (mounted) setState(() => _error = pinErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _invitation(Map<String, dynamic> inv) {
    final api = AppScope.of(context).api;
    final id = inv['id'].toString();
    final org = inv['orgName']?.toString() ?? context.tr('invite.aGym');
    return FFCard(
      key: Key('onboarding-invitation-$id'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(org, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            context
                .tr('invite.asRole')
                .replaceAll('{role}', _startRole(context, inv['role'])),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: Key('onboarding-decline-$id'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => api.onboardingAnswer(_token, id, accept: false),
                        ),
                  child: Text(context.tr('invite.decline')),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  key: Key('onboarding-accept-$id'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => api.onboardingAnswer(_token, id, accept: true),
                        ),
                  child: Text(context.tr('invite.accept')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roleChoice(String role, String titleKey, String bodyKey) {
    final api = AppScope.of(context).api;
    return FFCard(
      child: ListTile(
        key: Key('onboarding-role-$role'),
        enabled: !_busy,
        title: Text(context.tr(titleKey)),
        subtitle: Text(context.tr(bodyKey)),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _run(() => api.onboardingRole(_token, role)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final invitations = _invitations;
    return _flowScaffold(
      context,
      title: context.tr(
        invitations.isEmpty ? 'role.welcomeTitle' : 'invite.inboxTitle',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null) ...[
            Text(
              _error!,
              key: const Key('pin-flow-error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: FFTokens.spacingSm),
          ],
          if (invitations.isNotEmpty) ...[
            Text(context.tr('start.invitedBody'), textAlign: TextAlign.center),
            const SizedBox(height: FFTokens.spacingMd),
            for (final inv in invitations) ...[
              _invitation(inv),
              const SizedBox(height: FFTokens.spacingSm),
            ],
          ] else ...[
            Text(
              context.tr('role.welcomeSubtitle'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FFTokens.spacingMd),
            _roleChoice('member', 'role.member', 'role.memberBody'),
            _roleChoice('trainer', 'role.trainer', 'role.trainerBody'),
            _roleChoice('gym_owner', 'role.owner', 'role.ownerBody'),
            _roleChoice('vendor', 'role.vendor', 'role.vendorBody'),
          ],
        ],
      ),
    );
  }
}
