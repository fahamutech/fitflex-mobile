import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../components/components.dart';
import '../design_tokens.dart';
import '../i18n.dart';

/// The terms a role agrees to (GET /me/terms): the FitFlex Terms for members,
/// the partner agreement for gym owners, trainers and vendors.
class TermsInfo {
  const TermsInfo({
    required this.required,
    required this.accepted,
    this.version = '',
    this.title = '',
    this.reference = '',
    this.sections = const [],
  });

  /// False for roles with nothing to accept (staff).
  final bool required;
  final bool accepted;
  final String version;
  final String title;
  final String reference;
  final List<({String heading, String text})> sections;

  bool get mustAccept => required && !accepted;

  factory TermsInfo.fromJson(Map<String, dynamic> j) => TermsInfo(
    required: j['required'] != false,
    accepted: j['accepted'] == true,
    version: j['version']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    reference: j['reference']?.toString() ?? '',
    sections: [
      for (final s in (j['sections'] as List? ?? const []).whereType<Map>())
        (
          heading: s['heading']?.toString() ?? '',
          text: s['text']?.toString() ?? '',
        ),
    ],
  );
}

String _lang(BuildContext context) =>
    FFLocaleScope.of(context).locale.languageCode;

/// The full text of [terms], numbered by section.
class TermsText extends StatelessWidget {
  const TermsText({super.key, required this.terms});

  final TermsInfo terms;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, s) in terms.sections.indexed) ...[
          Text(
            '${i + 1}. ${s.heading}',
            style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(s.text, style: tt.bodyMedium?.copyWith(height: 1.4)),
          const SizedBox(height: 14),
        ],
        if (terms.reference.isNotEmpty)
          Text('${terms.reference} · ${terms.version}', style: tt.bodySmall),
      ],
    );
  }
}

/// Full-screen terms to read. With [askToAgree] it has an "I agree" tick and
/// an Agree button, and pops `true` when the user agrees.
class TermsPage extends StatefulWidget {
  const TermsPage({super.key, required this.terms, this.askToAgree = false});

  final TermsInfo terms;
  final bool askToAgree;

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> {
  bool _agreed = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.terms.title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                key: const Key('terms-text'),
                padding: const EdgeInsets.all(FFTokens.spacingLg),
                child: TermsText(terms: widget.terms),
              ),
            ),
            if (widget.askToAgree)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFTokens.spacingMd,
                  0,
                  FFTokens.spacingMd,
                  FFTokens.spacingMd,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CheckboxListTile(
                      key: const Key('terms-page-check'),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _agreed,
                      onChanged: (v) => setState(() => _agreed = v ?? false),
                      title: Text(context.tr('terms.agreeRead')),
                    ),
                    FilledButton(
                      key: const Key('terms-page-agree'),
                      onPressed: _agreed
                          ? () => Navigator.of(context).pop(true)
                          : null,
                      child: Text(context.tr('terms.agreeContinue')),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Ask the user to agree to the terms of a role before they take it on.
///
/// With [role] (a role being added) the terms are only shown: nothing can be
/// recorded until the role exists, so the caller records it afterwards with
/// [recordTermsAccepted]. Without [role] the signed-in role's terms are shown
/// and the acceptance is recorded here.
///
/// Returns the accepted version, '' when there was nothing to accept, or
/// null when the user did not agree (or the terms could not be loaded).
///
/// [quiet] is for a check made on the user's behalf (not something they
/// tapped): if the terms cannot be loaded, nothing is shown.
Future<String?> askToAgreeTerms(
  BuildContext context, {
  String? role,
  bool quiet = false,
}) async {
  final api = AppScope.of(context).api;
  final messenger = ScaffoldMessenger.of(context);
  final failed = context.tr('terms.loadFailed');
  final TermsInfo terms;
  try {
    terms = TermsInfo.fromJson(
      await api.myTerms(lang: _lang(context), role: role),
    );
  } catch (_) {
    if (!quiet) messenger.showSnackBar(SnackBar(content: Text(failed)));
    return null;
  }
  if (!terms.mustAccept) return '';
  if (!context.mounted) return null;
  final agreed = await Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TermsPage(terms: terms, askToAgree: true),
    ),
  );
  if (agreed != true) return null;
  if (role == null && !await recordTermsAccepted(api, terms.version)) {
    messenger.showSnackBar(SnackBar(content: Text(failed)));
    return null;
  }
  return terms.version;
}

/// Record acceptance for the signed-in role. True when it is on record.
Future<bool> recordTermsAccepted(dynamic api, String version) async {
  if (version.isEmpty) return true;
  try {
    await api.acceptTerms(version);
    return true;
  } catch (_) {
    return false;
  }
}

/// "I agree to the …" for an onboarding form: loads the signed-in role's
/// terms, links to the full text and holds the tick.
///
/// The form checks [TermsAgreementFieldState.agreed] before submitting and
/// calls [TermsAgreementFieldState.record] to put the acceptance on record.
class TermsAgreementField extends StatefulWidget {
  const TermsAgreementField({super.key, this.onChanged});

  final VoidCallback? onChanged;

  @override
  State<TermsAgreementField> createState() => TermsAgreementFieldState();
}

class TermsAgreementFieldState extends State<TermsAgreementField> {
  TermsInfo? _terms;
  bool _failed = false;
  bool _ticked = false;
  bool _started = false;

  /// True when the user may continue: ticked, already accepted earlier, or
  /// nothing to accept for this role.
  bool get agreed {
    final t = _terms;
    if (t == null) return false;
    return !t.mustAccept || _ticked;
  }

  /// Put the acceptance on record (no-op when already there). False when it
  /// could not be saved.
  Future<bool> record() async {
    final t = _terms;
    if (t == null) return false;
    if (!t.mustAccept) return true;
    if (!_ticked) return false;
    final ok = await recordTermsAccepted(AppScope.of(context).api, t.version);
    if (ok && mounted) {
      setState(
        () => _terms = TermsInfo(
          required: true,
          accepted: true,
          version: t.version,
          title: t.title,
          reference: t.reference,
          sections: t.sections,
        ),
      );
    }
    return ok;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    setState(() => _failed = false);
    try {
      final json = await AppScope.of(context).api.myTerms(lang: _lang(context));
      if (!mounted) return;
      setState(() => _terms = TermsInfo.fromJson(json));
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _read() {
    final t = _terms;
    if (t == null) return;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => TermsPage(terms: t),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = _terms;
    if (_failed) {
      return Row(
        key: const Key('terms-field-failed'),
        children: [
          Expanded(
            child: Text(
              context.tr('terms.loadFailed'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: _load, child: Text(context.tr('terms.retry'))),
        ],
      );
    }
    if (t == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: FFSpinner(size: 20)),
      );
    }
    if (!t.required) return const SizedBox.shrink();
    final readLink = TextButton(
      key: const Key('terms-read'),
      onPressed: _read,
      child: Text(context.tr('terms.read')),
    );
    if (t.accepted) {
      return Row(
        key: const Key('terms-field-accepted'),
        children: [
          const Icon(Icons.check_circle, color: FFTokens.success600, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              context.tr('terms.accepted').replaceAll('{title}', t.title),
            ),
          ),
          readLink,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: CheckboxListTile(
            key: const Key('terms-check'),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _ticked,
            onChanged: (v) {
              setState(() => _ticked = v ?? false);
              widget.onChanged?.call();
            },
            title: Text(
              context.tr('terms.agreeTo').replaceAll('{title}', t.title),
            ),
          ),
        ),
        readLink,
      ],
    );
  }
}
