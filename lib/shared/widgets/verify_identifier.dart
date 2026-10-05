import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../api_client.dart';
import '../api_error_message.dart';
import '../components/ff_action_tile.dart';
import '../design_tokens.dart';
import '../i18n.dart';

// Identity V2 · I6a: a person proves a mobile number or email is theirs with
// a code FitFlex sends (SMS to a number, email to an email). It is asked for
// once; after that the number or email is simply theirs.

/// Message for a verification failure the person can act on.
String verifyErrorMessage(BuildContext context, Object error) {
  final code = error is ApiException ? error.code : null;
  if (code == 'code_incorrect' && error is ApiException) {
    final left = error.body is Map ? (error.body as Map)['attemptsLeft'] : null;
    return context.tr('verify.errIncorrect').replaceAll('{n}', '${left ?? ''}');
  }
  if (code == 'too_many_attempts' && error is ApiException) {
    final seconds = error.body is Map
        ? ((error.body as Map)['retryAfterSeconds'] as num?)?.toInt()
        : null;
    return context
        .tr('pin.errTooMany')
        .replaceAll('{n}', '${((seconds ?? 900) / 60).ceil()}');
  }
  final key = switch (code) {
    'pin_incorrect' => 'pin.errCurrentWrong',
    'pin_reset_required' => 'pin.errResetRequired',
    'pin_not_set' => 'pin.errNotSet',
    'identifier_unchanged' => 'change.errSame',
    'nothing_to_change' => 'verify.errInvalid',
    'identifier_in_use' => 'verify.errInUse',
    'code_attempts_exceeded' => 'verify.errAttempts',
    'code_not_found_or_expired' => 'verify.errExpired',
    'code_rate_limited' => 'verify.errTooMany',
    'code_resend_too_soon' => 'verify.errWait',
    'one_phone_or_email_required' => 'verify.errInvalid',
    'sms_not_configured' ||
    'email_not_configured' ||
    'code_not_sent' => 'verify.errNotSent',
    _ => null,
  };
  return key != null
      ? context.tr(key)
      : errorMessage(FFLocaleScope.of(context), error);
}

/// Profile entry to the person's verified mobile numbers and emails. Hidden
/// while the backend has identifier verification off.
class ContactDetailsTile extends StatelessWidget {
  const ContactDetailsTile({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) {
        if (!auth.identifiersEnabled) return const SizedBox.shrink();
        final pending = auth.unverifiedIdentifiers.length;
        final tile = FFActionTile(
          key: const Key('contact-details-tile'),
          icon: Icons.verified_user_outlined,
          title: context.tr('verify.tileTitle'),
          subtitle: pending > 0
              ? context.tr('verify.tilePending').replaceAll('{n}', '$pending')
              : null,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ContactDetailsScreen()),
          ),
        );
        final missing = auth.secondContactReminder;
        if (missing == null) return tile;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SecondContactCard(missing: missing),
            tile,
          ],
        );
      },
    );
  }
}

/// A gentle reminder to verify a second way in (an email beside a number, or
/// a number beside an email), so losing one never locks the person out.
/// Dismissed for the rest of the session with "Not now".
class SecondContactCard extends StatelessWidget {
  const SecondContactCard({super.key, required this.missing});

  /// 'email' or 'phone': the kind to add.
  final String missing;

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    final phone = missing == 'phone';
    return Card(
      key: const Key('second-contact-card'),
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.tr(phone ? 'second.phone' : 'second.email')),
            const SizedBox(height: FFTokens.spacingSm),
            Wrap(
              spacing: FFTokens.spacingSm,
              children: [
                FilledButton.tonal(
                  key: const Key('second-contact-add'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => VerifyIdentifierScreen(type: missing),
                    ),
                  ),
                  child: Text(
                    context.tr(phone ? 'verify.addPhone' : 'second.addEmail'),
                  ),
                ),
                TextButton(
                  key: const Key('second-contact-dismiss'),
                  onPressed: auth.dismissSecondContactReminder,
                  child: Text(context.tr('second.dismiss')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// What the person has verified, what is waiting, and a way to add a number.
class ContactDetailsScreen extends StatelessWidget {
  const ContactDetailsScreen({super.key});

  Future<void> _verify(BuildContext context, String type, [String? value]) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VerifyIdentifierScreen(type: type, initialValue: value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = AppScope.of(context).auth;
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('verify.tileTitle'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: auth,
          builder: (context, _) {
            final verified = auth.verifiedIdentifiers;
            final waiting = auth.unverifiedIdentifiers;
            final hasPhone = verified.any((i) => i['type'] == 'phone');
            return ListView(
              padding: const EdgeInsets.all(FFTokens.spacingMd),
              children: [
                Text(context.tr('verify.intro')),
                const SizedBox(height: FFTokens.spacingMd),
                for (final item in verified)
                  ListTile(
                    key: Key('verified-${item['value']}'),
                    leading: Icon(
                      item['type'] == 'phone'
                          ? Icons.phone_iphone
                          : Icons.mail_outline,
                    ),
                    title: Text(item['value']?.toString() ?? ''),
                    subtitle: Text(context.tr('verify.verified')),
                    // Replacing one needs the PIN, so it follows the PIN options.
                    trailing: auth.pinResetEnabled
                        ? TextButton(
                            key: Key('change-${item['value']}'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => ChangeIdentifierScreen(
                                  type: item['type'].toString(),
                                  current: item['value']?.toString() ?? '',
                                ),
                              ),
                            ),
                            child: Text(context.tr('change.action')),
                          )
                        : const Icon(Icons.check_circle_outline),
                  ),
                for (final item in waiting)
                  ListTile(
                    key: Key('unverified-${item['value']}'),
                    leading: Icon(
                      item['type'] == 'phone'
                          ? Icons.phone_iphone
                          : Icons.mail_outline,
                    ),
                    title: Text(item['value']?.toString() ?? ''),
                    subtitle: Text(context.tr('verify.notVerified')),
                    trailing: TextButton(
                      key: Key('verify-${item['value']}'),
                      onPressed: () => _verify(
                        context,
                        item['type'].toString(),
                        item['value']?.toString(),
                      ),
                      child: Text(context.tr('verify.verify')),
                    ),
                  ),
                if (!hasPhone) ...[
                  const SizedBox(height: FFTokens.spacingMd),
                  OutlinedButton.icon(
                    key: const Key('add-phone'),
                    icon: const Icon(Icons.add),
                    label: Text(context.tr('verify.addPhone')),
                    onPressed: () => _verify(context, 'phone'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Send a code to one mobile number or email, then confirm it. Pops `true`
/// once it is verified.
class VerifyIdentifierScreen extends StatefulWidget {
  const VerifyIdentifierScreen({
    super.key,
    required this.type,
    this.initialValue,
  });

  /// 'phone' or 'email'.
  final String type;
  final String? initialValue;

  @override
  State<VerifyIdentifierScreen> createState() => _VerifyIdentifierScreenState();
}

class _VerifyIdentifierScreenState extends State<VerifyIdentifierScreen> {
  late final _value = TextEditingController(text: widget.initialValue ?? '');
  final _code = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _notice;
  Timer? _ticker;
  int _resendIn = 0;

  bool get _isPhone => widget.type == 'phone';

  @override
  void dispose() {
    _ticker?.cancel();
    _value.dispose();
    _code.dispose();
    super.dispose();
  }

  void _startResendWait(int seconds) {
    _ticker?.cancel();
    setState(() => _resendIn = seconds);
    if (seconds <= 0) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendIn -= 1);
      if (_resendIn <= 0) timer.cancel();
    });
  }

  Future<void> _done() async {
    final auth = AppScope.of(context).auth;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final message = context.tr('verify.done');
    await auth.refreshIdentifiers();
    // A newly verified number or email can bring invitations with it.
    await auth.refreshInvitations();
    messenger.showSnackBar(SnackBar(content: Text(message)));
    navigator.pop(true);
  }

  Future<void> _send() async {
    final value = _value.text.trim();
    if (value.isEmpty) {
      setState(() => _notice = context.tr('verify.errInvalid'));
      return;
    }
    final api = AppScope.of(context).api;
    final locale = FFLocaleScope.of(context).locale.languageCode;
    setState(() => _busy = true);
    try {
      final res = await api.requestIdentifierCode(
        phone: _isPhone ? value : null,
        email: _isPhone ? null : value,
        locale: locale,
      );
      if (!mounted) return;
      if (res['alreadyVerified'] == true) return _done();
      setState(() {
        _sent = true;
        _notice = context.tr(_isPhone ? 'verify.sentSms' : 'verify.sentEmail');
      });
      _startResendWait((res['resendAfterSeconds'] as num?)?.toInt() ?? 60);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _notice = verifyErrorMessage(context, e));
      final wait = e.body is Map ? (e.body as Map)['retryAfterSeconds'] : null;
      if (wait is num) {
        // A code was sent a moment ago: let them type it in.
        setState(() => _sent = true);
        _startResendWait(wait.toInt());
      }
    } catch (e) {
      if (mounted) setState(() => _notice = verifyErrorMessage(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    final api = AppScope.of(context).api;
    final value = _value.text.trim();
    setState(() => _busy = true);
    try {
      await api.confirmIdentifierCode(
        phone: _isPhone ? value : null,
        email: _isPhone ? null : value,
        code: code,
      );
      if (mounted) await _done();
    } catch (e) {
      if (mounted) {
        setState(() {
          _notice = verifyErrorMessage(context, e);
          _code.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(_isPhone ? 'verify.phoneTitle' : 'verify.emailTitle'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          children: [
            Text(
              context.tr(_isPhone ? 'verify.phoneBody' : 'verify.emailBody'),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            TextField(
              key: const Key('verify-value'),
              controller: _value,
              enabled: !_sent && !_busy,
              keyboardType: _isPhone
                  ? TextInputType.phone
                  : TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: context.tr(
                  _isPhone ? 'verify.phoneLabel' : 'verify.emailLabel',
                ),
                hintText: _isPhone ? '0712 345 678' : null,
              ),
            ),
            if (_sent) ...[
              const SizedBox(height: FFTokens.spacingMd),
              TextField(
                key: const Key('verify-code'),
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: context.tr('verify.code'),
                ),
                onSubmitted: (_) => _confirm(),
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(_notice!, key: const Key('verify-notice')),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            if (!_sent)
              FilledButton(
                key: const Key('verify-send'),
                onPressed: _busy ? null : _send,
                child: Text(context.tr('verify.send')),
              )
            else ...[
              FilledButton(
                key: const Key('verify-confirm'),
                onPressed: _busy ? null : _confirm,
                child: Text(context.tr('verify.confirm')),
              ),
              const SizedBox(height: FFTokens.spacingSm),
              TextButton(
                key: const Key('verify-resend'),
                onPressed: _busy || _resendIn > 0 ? null : _send,
                child: Text(
                  _resendIn > 0
                      ? context
                            .tr('verify.resendIn')
                            .replaceAll('{n}', '$_resendIn')
                      : context.tr('verify.resend'),
                ),
              ),
              TextButton(
                key: const Key('verify-change'),
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _sent = false;
                        _notice = null;
                        _code.clear();
                      }),
                child: Text(
                  context.tr(
                    _isPhone ? 'verify.changePhone' : 'verify.changeEmail',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Replace the mobile number or email the person signs in with: the new
/// value and their PIN, then the code sent to the new value. Pops `true`
/// once it is changed.
class ChangeIdentifierScreen extends StatefulWidget {
  const ChangeIdentifierScreen({
    super.key,
    required this.type,
    required this.current,
  });

  /// 'phone' or 'email'.
  final String type;
  final String current;

  @override
  State<ChangeIdentifierScreen> createState() => _ChangeIdentifierScreenState();
}

class _ChangeIdentifierScreenState extends State<ChangeIdentifierScreen> {
  final _value = TextEditingController();
  final _pin = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  bool _sent = false;
  String? _notice;

  bool get _isPhone => widget.type == 'phone';

  @override
  void dispose() {
    _value.dispose();
    _pin.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _value.text.trim();
    if (value.isEmpty || _pin.text.isEmpty) {
      setState(() => _notice = context.tr('change.errFill'));
      return;
    }
    final api = AppScope.of(context).api;
    final locale = FFLocaleScope.of(context).locale.languageCode;
    setState(() => _busy = true);
    try {
      await api.requestIdentifierChange(
        phone: _isPhone ? value : null,
        email: _isPhone ? null : value,
        pin: _pin.text,
        locale: locale,
      );
      if (!mounted) return;
      setState(() {
        _sent = true;
        _notice = context.tr(_isPhone ? 'verify.sentSms' : 'verify.sentEmail');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _notice = verifyErrorMessage(context, e);
        // A code sent a moment ago is still good: let them type it in.
        if (e is ApiException && e.code == 'code_resend_too_soon') _sent = true;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    final scope = AppScope.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final done = context.tr('change.done');
    final locale = FFLocaleScope.of(context).locale.languageCode;
    final value = _value.text.trim();
    setState(() => _busy = true);
    try {
      await scope.api.confirmIdentifierChange(
        phone: _isPhone ? value : null,
        email: _isPhone ? null : value,
        code: code,
        locale: locale,
      );
      await scope.auth.refreshIdentifiers();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      navigator.pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _notice = verifyErrorMessage(context, e);
          _code.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(_isPhone ? 'change.phoneTitle' : 'change.emailTitle'),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          children: [
            Text(
              context.tr('change.body').replaceAll('{current}', widget.current),
            ),
            const SizedBox(height: FFTokens.spacingMd),
            TextField(
              key: const Key('change-value'),
              controller: _value,
              enabled: !_sent && !_busy,
              keyboardType: _isPhone
                  ? TextInputType.phone
                  : TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: context.tr(
                  _isPhone ? 'change.newPhone' : 'change.newEmail',
                ),
                hintText: _isPhone ? '0712 345 678' : null,
              ),
            ),
            const SizedBox(height: FFTokens.spacingSm),
            TextField(
              key: const Key('change-pin'),
              controller: _pin,
              enabled: !_sent && !_busy,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              maxLength: 8,
              decoration: InputDecoration(
                labelText: context.tr('change.pin'),
                counterText: '',
              ),
            ),
            if (_sent) ...[
              const SizedBox(height: FFTokens.spacingSm),
              TextField(
                key: const Key('change-code'),
                controller: _code,
                enabled: !_busy,
                autofocus: true,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLength: 6,
                decoration: InputDecoration(
                  labelText: context.tr('verify.code'),
                ),
                onSubmitted: (_) => _confirm(),
              ),
            ],
            if (_notice != null) ...[
              const SizedBox(height: FFTokens.spacingSm),
              Text(_notice!, key: const Key('change-notice')),
            ],
            const SizedBox(height: FFTokens.spacingMd),
            if (!_sent)
              FilledButton(
                key: const Key('change-send'),
                onPressed: _busy ? null : _send,
                child: Text(context.tr('verify.send')),
              )
            else
              FilledButton(
                key: const Key('change-confirm'),
                onPressed: _busy ? null : _confirm,
                child: Text(context.tr('verify.confirm')),
              ),
          ],
        ),
      ),
    );
  }
}
