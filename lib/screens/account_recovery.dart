import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_scope.dart';
import '../shared/api_client.dart';
import '../shared/design_tokens.dart';
import '../shared/i18n.dart';
import 'pin_flows.dart';

// Identity V2 · account recovery (member path): someone who lost every
// verified number and email, and forgot the PIN, asks FitFlex to move the
// account to a new number or email. They prove the new one with a code,
// answer a few questions, and wait; FitFlex staff decide. Nobody at FitFlex
// ever sets or sees a PIN: once it is done the person sets their own with
// Forgot PIN, using the code sent to the new number or email.

const _tokenKey = 'recovery_request_token';

/// The request token this phone kept (null when there is none). It is a
/// secret that lets the holder look at and cancel the request: never logged.
Future<String?> savedRecoveryToken() async {
  try {
    final token = (await SharedPreferences.getInstance()).getString(_tokenKey);
    return token == null || token.isEmpty ? null : token;
  } catch (_) {
    return null;
  }
}

Future<void> _saveToken(String token) async {
  try {
    await (await SharedPreferences.getInstance()).setString(_tokenKey, token);
  } catch (_) {}
}

Future<void> clearRecoveryToken() async {
  try {
    await (await SharedPreferences.getInstance()).remove(_tokenKey);
  } catch (_) {}
}

/// Message for a recovery failure the person can act on.
String recoveryErrorMessage(BuildContext context, Object error) {
  final code = error is ApiException ? error.code : null;
  final body = error is ApiException && error.body is Map
      ? error.body as Map
      : const {};
  if (code == 'recovery_blocked') {
    final seconds = (body['retryAfterSeconds'] as num?)?.toInt() ?? 604800;
    return context
        .tr('rec.errBlocked')
        .replaceAll('{n}', '${(seconds / 86400).ceil().clamp(1, 365)}');
  }
  final key = switch (code) {
    'account_not_found' => 'rec.errNotFound',
    'identifier_in_use' => 'rec.errInUse',
    'identifier_unchanged' => 'rec.errSame',
    'recovery_already_open' => 'rec.errOpen',
    'staff_recovery_not_available' => 'rec.errStaff',
    'partner_recovery_not_available' ||
    'recovery_not_available' => 'rec.errSupport',
    'old_and_new_identifier_required' => 'rec.fill',
    'name_required' => 'rec.nameRequired',
    'evidence_required' => 'rec.errEvidence',
    'request_token_invalid' => 'rec.gone',
    _ => null,
  };
  return key != null ? context.tr(key) : pinErrorMessage(context, error);
}

String _locale(BuildContext context) =>
    FFLocaleScope.of(context).locale.languageCode;

String _when(Object? iso) {
  final at = DateTime.tryParse(iso?.toString() ?? '')?.toLocal();
  if (at == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${at.year}-${two(at.month)}-${two(at.day)} ${two(at.hour)}:${two(at.minute)}';
}

Widget _scaffold(
  BuildContext context, {
  required String title,
  required List<Widget> children,
}) => Scaffold(
  appBar: AppBar(title: Text(title)),
  body: SafeArea(
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          children: children,
        ),
      ),
    ),
  ),
);

Widget _errorText(BuildContext context, String? message) => message == null
    ? const SizedBox.shrink()
    : Padding(
        padding: const EdgeInsets.only(top: FFTokens.spacingSm),
        child: Text(
          message,
          key: const Key('recovery-error'),
          textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      );

// ── 1-2. Details, then the code and the name ────────────────────────────────

class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _name = TextEditingController();
  bool _busy = false;
  String? _error;
  String? _sentTo;
  int _resendAfter = 60;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<int?> _send() async {
    if (_old.text.trim().isEmpty || _new.text.trim().isEmpty) {
      setState(() => _error = context.tr('rec.fill'));
      return null;
    }
    // While FitFlex cannot send email codes, the code goes to a number.
    if (_new.text.contains('@') &&
        !AppScope.of(context).auth.emailCodesAvailable) {
      setState(() => _error = context.tr('rec.newMustBePhone'));
      return null;
    }
    final api = AppScope.of(context).api;
    final locale = _locale(context);
    setState(() => _busy = true);
    try {
      final res = await api.recoveryStart(
        contactOf(_old.text),
        contactOf(_new.text),
        locale,
      );
      if (!mounted) return null;
      final wait = (res['resendAfterSeconds'] as num?)?.toInt() ?? 60;
      setState(() {
        _sentTo = res['identifierValue']?.toString() ?? _new.text.trim();
        _resendAfter = wait;
        _error = null;
      });
      return wait;
    } catch (e) {
      if (mounted) setState(() => _error = recoveryErrorMessage(context, e));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm(String code) async {
    if (_name.text.trim().length < 2) {
      setState(() => _error = context.tr('rec.nameRequired'));
      return;
    }
    if (code.trim().isEmpty) return;
    final api = AppScope.of(context).api;
    final locale = _locale(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final res = await api.recoveryConfirm(
        contactOf(_old.text),
        contactOf(_new.text),
        code.trim(),
        _name.text.trim(),
        locale,
      );
      final token = res['requestToken']?.toString();
      if (token == null || token.isEmpty) return;
      await _saveToken(token);
      if (!mounted) return;
      await navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => RecoveryQuestionsScreen(requestToken: token),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _error = recoveryErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> children;
    if (_sentTo != null) {
      children = [
        TextField(
          key: const Key('recovery-name'),
          controller: _name,
          enabled: !_busy,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(labelText: context.tr('rec.name')),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        CodeStep(
          sentTo: _sentTo!,
          onSubmit: _confirm,
          onResend: _send,
          resendAfterSeconds: _resendAfter,
          error: _error,
          busy: _busy,
        ),
      ];
    } else {
      children = [
        Text(context.tr('rec.intro'), textAlign: TextAlign.center),
        const SizedBox(height: FFTokens.spacingMd),
        TextField(
          key: const Key('recovery-old'),
          controller: _old,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: context.tr('rec.old')),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        TextField(
          key: const Key('recovery-new'),
          controller: _new,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: context.tr('rec.new')),
        ),
        _errorText(context, _error),
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('recovery-request'),
          onPressed: _busy ? null : _send,
          child: Text(context.tr('rec.request')),
        ),
      ];
    }
    return _scaffold(
      context,
      title: context.tr('rec.title'),
      children: children,
    );
  }
}

// ── 3. The questions ────────────────────────────────────────────────────────

const _questionKeys = ['homeGym', 'plan', 'lastCheckin', 'paymentRef', 'other'];

/// Short answers only the owner is likely to know. At least one is needed.
/// Can be opened again while the request is open, to add more.
class RecoveryQuestionsScreen extends StatefulWidget {
  const RecoveryQuestionsScreen({
    super.key,
    required this.requestToken,
    this.toStatusOnSend = true,
  });

  final String requestToken;

  /// True right after the request (replace with the status screen); false when
  /// opened from the status screen, which just gets `true` back.
  final bool toStatusOnSend;

  @override
  State<RecoveryQuestionsScreen> createState() =>
      _RecoveryQuestionsScreenState();
}

class _RecoveryQuestionsScreenState extends State<RecoveryQuestionsScreen> {
  final _fields = {for (final k in _questionKeys) k: TextEditingController()};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    final answers = {
      for (final e in _fields.entries)
        if (e.value.text.trim().isNotEmpty) e.key: e.value.text.trim(),
    };
    if (answers.isEmpty) {
      setState(() => _error = context.tr('rec.errEvidence'));
      return;
    }
    final api = AppScope.of(context).api;
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      await api.recoveryEvidence(widget.requestToken, answers);
      if (!mounted) return;
      _leave(navigator, true);
    } catch (e) {
      if (mounted) setState(() => _error = recoveryErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave(NavigatorState navigator, bool sent) {
    if (widget.toStatusOnSend) {
      navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              RecoveryStatusScreen(requestToken: widget.requestToken),
        ),
      );
    } else {
      navigator.pop(sent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels = {
      'homeGym': 'rec.homeGym',
      'plan': 'rec.plan',
      'lastCheckin': 'rec.lastCheckin',
      'paymentRef': 'rec.paymentRef',
      'other': 'rec.other',
    };
    return _scaffold(
      context,
      title: context.tr('rec.questionsTitle'),
      children: [
        Text(context.tr('rec.questionsIntro'), textAlign: TextAlign.center),
        for (final key in _questionKeys) ...[
          const SizedBox(height: FFTokens.spacingSm),
          TextField(
            key: Key('recovery-answer-$key'),
            controller: _fields[key],
            enabled: !_busy,
            maxLength: 300,
            decoration: InputDecoration(labelText: context.tr(labels[key]!)),
          ),
        ],
        _errorText(context, _error),
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('recovery-send-answers'),
          onPressed: _busy ? null : _send,
          child: Text(context.tr('rec.send')),
        ),
        TextButton(
          key: const Key('recovery-answer-later'),
          onPressed: _busy ? null : () => _leave(Navigator.of(context), false),
          child: Text(context.tr('rec.later')),
        ),
      ],
    );
  }
}

// ── 4. Where the request stands ─────────────────────────────────────────────

/// Open (waiting, what is answered), refused (a general reason, when to try
/// again), cancelled, or completed (then the person sets their own PIN).
class RecoveryStatusScreen extends StatefulWidget {
  const RecoveryStatusScreen({super.key, required this.requestToken});

  final String requestToken;

  @override
  State<RecoveryStatusScreen> createState() => _RecoveryStatusScreenState();
}

class _RecoveryStatusScreenState extends State<RecoveryStatusScreen> {
  Map<String, dynamic>? _status;
  bool _loading = true;
  bool _gone = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // After initState: the API comes from an inherited widget.
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final api = AppScope.of(context).api;
    setState(() => _loading = true);
    try {
      final res = await api.recoveryStatus(widget.requestToken);
      if (!mounted) return;
      setState(() {
        _status = res;
        _gone = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.code == 'request_token_invalid') {
        await clearRecoveryToken();
        if (mounted) setState(() => _gone = true);
      } else {
        setState(() => _error = recoveryErrorMessage(context, e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(context.tr('rec.cancelAsk')),
        actions: [
          TextButton(
            key: const Key('recovery-cancel-no'),
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('rec.cancelNo')),
          ),
          TextButton(
            key: const Key('recovery-cancel-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('rec.cancelYes')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      await api.recoveryCancel(widget.requestToken);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = recoveryErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAnswers() async {
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecoveryQuestionsScreen(
          requestToken: widget.requestToken,
          toStatusOnSend: false,
        ),
      ),
    );
    if (sent == true && mounted) await _load();
  }

  /// The person has seen how it ended: forget the token and leave.
  Future<void> _acknowledge({String? setPinFor}) async {
    await clearRecoveryToken();
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (setPinFor == null) {
      navigator.pop();
    } else {
      await navigator.pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => ForgotPinScreen(contact: setPinFor),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final state = status?['status']?.toString();
    final List<Widget> body;
    if (_loading && status == null) {
      body = [const Center(child: CircularProgressIndicator())];
    } else if (_gone) {
      body = [
        Text(
          context.tr('rec.gone'),
          key: const Key('recovery-gone'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.tr('rec.done')),
        ),
      ];
    } else if (status == null) {
      body = [
        _errorText(context, _error),
        TextButton(onPressed: _load, child: Text(context.tr('verify.resend'))),
      ];
    } else if (state == 'open') {
      final answered = ((status['answered'] as List?) ?? const [])
          .map((k) => context.tr('rec.${_labelKey(k.toString())}'))
          .toList();
      body = [
        Text(
          context
              .tr('rec.open')
              .replaceAll('{when}', _when(status['waitUntil'])),
          key: const Key('recovery-open'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          answered.isEmpty
              ? context.tr('rec.noneAnswered')
              : context
                    .tr('rec.answered')
                    .replaceAll('{list}', answered.join(', ')),
          textAlign: TextAlign.center,
        ),
        _errorText(context, _error),
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('recovery-add-answers'),
          onPressed: _busy ? null : _addAnswers,
          child: Text(context.tr('rec.addAnswers')),
        ),
        TextButton(
          key: const Key('recovery-cancel'),
          onPressed: _busy ? null : _cancel,
          child: Text(context.tr('rec.cancel')),
        ),
      ];
    } else if (state == 'refused') {
      final reason = status['reason']?.toString();
      final reasonKey = 'rec.reason.$reason';
      final text = context.tr(reasonKey);
      body = [
        Text(
          context.tr('rec.refused'),
          key: const Key('recovery-refused'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        Text(
          text == reasonKey ? context.tr('rec.reason.other') : text,
          textAlign: TextAlign.center,
        ),
        if (status['retryAfter'] != null) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context
                .tr('rec.retryAfter')
                .replaceAll('{when}', _when(status['retryAfter'])),
            textAlign: TextAlign.center,
          ),
        ],
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('recovery-ack'),
          onPressed: _acknowledge,
          child: Text(context.tr('rec.done')),
        ),
      ];
    } else if (state == 'completed') {
      final to = status['identifierValue']?.toString() ?? '';
      body = [
        Text(
          context.tr('rec.completed').replaceAll('{to}', to),
          key: const Key('recovery-completed'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('recovery-set-pin'),
          onPressed: () => _acknowledge(setPinFor: to),
          child: Text(context.tr('rec.setPin')),
        ),
      ];
    } else {
      body = [
        Text(
          context.tr('rec.cancelled'),
          key: const Key('recovery-cancelled'),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FilledButton(
          key: const Key('recovery-ack'),
          onPressed: _acknowledge,
          child: Text(context.tr('rec.done')),
        ),
      ];
    }
    return _scaffold(
      context,
      title: context.tr('rec.statusTitle'),
      children: body,
    );
  }
}

String _labelKey(String answer) => switch (answer) {
  'homeGym' || 'plan' || 'lastCheckin' || 'paymentRef' || 'other' => answer,
  _ => 'other',
};

// ── 5. A device that is still signed in ─────────────────────────────────────

/// Wraps the whole app. While a recovery request is open on the signed-in
/// account it shows a banner at the top, with a way to cancel it. Checked at
/// sign-in and when the app comes back to the front; a failure (the feature
/// is off, no network) shows nothing.
class RecoveryBannerHost extends StatefulWidget {
  const RecoveryBannerHost({super.key, required this.child});

  final Widget child;

  @override
  State<RecoveryBannerHost> createState() => _RecoveryBannerHostState();
}

class _RecoveryBannerHostState extends State<RecoveryBannerHost>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _open;
  String? _checkedFor;
  bool _busy = false;
  ChangeNotifier? _auth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = AppScope.of(context).auth;
    if (!identical(_auth, auth)) {
      _auth?.removeListener(_onAuth);
      _auth = auth..addListener(_onAuth);
    }
    _onAuth();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth?.removeListener(_onAuth);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_check());
  }

  /// Signed in or out, or a different session: look again (or clear).
  void _onAuth() {
    final token = AppScope.of(context).auth.token;
    if (token == _checkedFor) return;
    _checkedFor = token;
    if (token == null) {
      if (_open != null) setState(() => _open = null);
    } else {
      unawaited(_check());
    }
  }

  Future<void> _check() async {
    final scope = AppScope.of(context);
    if (scope.auth.token == null) return;
    try {
      final res = await scope.api.myRecovery();
      if (!mounted) return;
      setState(() => _open = res['open'] == true ? res : null);
    } catch (_) {
      // Off, offline or signed out: no banner.
      if (mounted && _open != null) setState(() => _open = null);
    }
  }

  Future<void> _cancel() async {
    final api = AppScope.of(context).api;
    setState(() => _busy = true);
    try {
      await api.cancelMyRecovery();
      if (mounted) setState(() => _open = null);
    } catch (_) {
      await _check();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = _open;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        if (open != null)
          Material(
            key: const Key('recovery-banner'),
            color: scheme.errorContainer,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(FFTokens.spacingMd),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context
                            .tr('rec.bannerText')
                            .replaceAll(
                              '{to}',
                              open['newIdentifier']?.toString() ?? '',
                            ),
                        style: TextStyle(color: scheme.onErrorContainer),
                      ),
                    ),
                    const SizedBox(width: FFTokens.spacingSm),
                    FilledButton(
                      key: const Key('recovery-banner-cancel'),
                      onPressed: _busy ? null : _cancel,
                      child: Text(context.tr('rec.bannerCancel')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          // The banner already covers the status bar.
          child: MediaQuery.removePadding(
            context: context,
            removeTop: open != null,
            child: widget.child,
          ),
        ),
      ],
    );
  }
}
