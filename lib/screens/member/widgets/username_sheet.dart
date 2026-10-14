import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import '../../../shared/tone_theme.dart';

/// Opens the username editor. Resolves to true when the username was set or
/// removed, so the caller can reload the member.
Future<bool?> showUsernameSheet(
  BuildContext context, {
  String? current,
  DateTime? changeableAt,
}) {
  return showFFSheet<bool>(
    context,
    title: context.tr('username.title'),
    child: UsernameSheet(current: current, changeableAt: changeableAt),
  );
}

/// The translated line for a server reason code, or null for one we don't know.
String? usernameReasonText(BuildContext context, String? code) {
  return switch (code) {
    'invalid_username' => context.tr('username.invalid'),
    'username_reserved' => context.tr('username.reserved'),
    'username_taken' => context.tr('username.taken'),
    'username_released_recently' => context.tr('username.releasedRecently'),
    'username_not_allowed' => context.tr('username.notAllowed'),
    _ => null,
  };
}

class UsernameSheet extends StatefulWidget {
  const UsernameSheet({super.key, this.current, this.changeableAt});

  final String? current;
  final DateTime? changeableAt;

  @override
  State<UsernameSheet> createState() => _UsernameSheetState();
}

enum _Check { idle, checking, available, unavailable }

class _UsernameSheetState extends State<UsernameSheet> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.current ?? '',
  );
  Timer? _debounce;
  _Check _check = _Check.idle;
  String? _reason;
  String? _error;
  bool _saving = false;
  int _seq = 0;

  bool get _locked =>
      widget.changeableAt != null &&
      widget.changeableAt!.isAfter(DateTime.now());

  String get _typed => _ctrl.text.trim().replaceFirst(RegExp(r'^@'), '');

  bool get _unchanged =>
      _typed.toLowerCase() == (widget.current ?? '').toLowerCase();

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    setState(() {
      _error = null;
      _reason = null;
      _check = _typed.length >= 3 && !_unchanged
          ? _Check.checking
          : _Check.idle;
    });
    if (_check != _Check.checking) return;
    _debounce = Timer(const Duration(milliseconds: 400), _runCheck);
  }

  Future<void> _runCheck() async {
    final handle = _typed;
    final seq = ++_seq;
    try {
      final res = await AppScope.of(context).api.usernameAvailable(handle);
      if (!mounted || seq != _seq) return;
      setState(() {
        _check = res['available'] == true
            ? _Check.available
            : _Check.unavailable;
        _reason = res['reason']?.toString();
      });
    } catch (_) {
      // The save itself explains any problem; just stop showing "checking".
      if (mounted && seq == _seq) setState(() => _check = _Check.idle);
    }
  }

  String _dateOf(DateTime d) {
    final lang = Localizations.localeOf(context).languageCode;
    return DateFormat('d MMM y', lang).format(d);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.setUsername(_typed);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      var text = usernameReasonText(context, e.code);
      if (e.code == 'username_cooldown') {
        final next = DateTime.tryParse(
          (e.body is Map ? (e.body as Map)['nextChangeAt'] : null)
                  ?.toString() ??
              '',
        )?.toLocal();
        text = context
            .tr('username.cooldown')
            .replaceAll('{date}', next == null ? '' : _dateOf(next));
      }
      setState(() {
        _saving = false;
        _error = text ?? apiErrorMessage(FFLocaleScope.of(context), e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessage(FFLocaleScope.of(context), e);
      });
    }
  }

  Future<void> _clear() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AppScope.of(context).api.clearUsername();
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      var text = usernameReasonText(context, e.code);
      if (e.code == 'username_cooldown') {
        final next = DateTime.tryParse(
          (e.body is Map ? (e.body as Map)['nextChangeAt'] : null)
                  ?.toString() ??
              '',
        )?.toLocal();
        text = context
            .tr('username.cooldown')
            .replaceAll('{date}', next == null ? '' : _dateOf(next));
      }
      setState(() {
        _saving = false;
        _error = text ?? apiErrorMessage(FFLocaleScope.of(context), e);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = errorMessage(FFLocaleScope.of(context), e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final good = FFToneTheme.of(context).success.fg;
    final line = _error != null
        ? (_error!, theme.colorScheme.error)
        : switch (_check) {
            _Check.checking => (context.tr('username.checking'), null),
            _Check.available => (context.tr('username.available'), good),
            _Check.unavailable => (
              usernameReasonText(context, _reason) ??
                  context.tr('username.invalid'),
              theme.colorScheme.error,
            ),
            _Check.idle => (null, null),
          };
    final canSave =
        !_locked &&
        !_saving &&
        _check == _Check.available &&
        _typed.isNotEmpty &&
        !_unchanged;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('username.visibility'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: FFTokens.spacingMd),
        FFTextField(
          key: const Key('username-field'),
          controller: _ctrl,
          label: context.tr('username.hint'),
          helperText: context.tr('username.rules'),
          enabled: !_locked && !_saving,
          maxLength: 20,
          autofocus: true,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 16, right: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              widthFactor: 1,
              child: Text('@'),
            ),
          ),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9._@]')),
          ],
          onChanged: _onChanged,
        ),
        if (line.$1 != null)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              line.$1!,
              key: const Key('username-status'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: line.$2 ?? theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (_locked)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              context
                  .tr('username.cooldown')
                  .replaceAll('{date}', _dateOf(widget.changeableAt!)),
              key: const Key('username-cooldown'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: FFTokens.spacingLg),
        FFButton(
          key: const Key('username-save'),
          fullWidth: true,
          label: context.tr('username.save'),
          loading: _saving,
          onPressed: canSave ? _save : null,
        ),
        if ((widget.current ?? '').isNotEmpty && !_locked) ...[
          const SizedBox(height: FFTokens.spacingXs),
          FFButton(
            key: const Key('username-clear'),
            fullWidth: true,
            variant: FFButtonVariant.ghost,
            label: context.tr('username.clear'),
            onPressed: _saving ? null : _clear,
          ),
        ],
      ],
    );
  }
}
