// Message templates: one template's preview in English and Swahili on each
// channel (with "use", "copy", "edit" and "archive"), and the editor for a
// gym's own templates. FitFlex's templates are read-only — owners copy them.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app_scope.dart';
import '../../../shared/api_client.dart';
import '../../../shared/api_error_message.dart';
import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'data/communication_models.dart';
import 'data/communication_repository.dart';
import 'widgets/campaign_preview.dart';
import 'widgets/template_selector.dart';

class TemplateDetailPage extends StatefulWidget {
  const TemplateDetailPage({
    super.key,
    required this.templateId,
    this.gymId,
    this.repository,
  });

  final String templateId;
  final String? gymId;
  final CommunicationRepository? repository;

  @override
  State<TemplateDetailPage> createState() => _TemplateDetailPageState();
}

class _TemplateDetailPageState extends State<TemplateDetailPage> {
  late CommunicationRepository _repo;
  CommTemplate? _template;
  TemplatePreview? _preview;
  Object? _error;
  String? _lang;
  bool _busy = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repo =
        widget.repository ?? CommunicationRepository(AppScope.of(context).api);
    _lang = FFLocaleScope.of(context).locale.languageCode;
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _repo.template(widget.templateId),
        _repo.previewTemplate(widget.templateId, gymId: widget.gymId),
      ]);
      if (!mounted) return;
      setState(() {
        _template = results[0] as CommTemplate;
        _preview = results[1] as TemplatePreview;
        if (!_preview!.byLocale.containsKey(_lang)) {
          _lang = _preview!.byLocale.keys.first;
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  String _gymQuery([Map<String, String> extra = const {}]) {
    final q = {'gymId': ?widget.gymId, ...extra};
    return q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';
  }

  Future<void> _copy() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final copy = await _repo.duplicateTemplate(
        widget.templateId,
        gymId: widget.gymId,
        name: templateName(context, _template!),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('comms.tpl.copied'))),
      );
      context.pushReplacement(
        '/owner/communications/templates/${copy.id}/edit${_gymQuery()}',
      );
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(FFLocaleScope.of(context), e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('comms.tpl.archiveTitle')),
        content: Text(ctx.tr('comms.tpl.archiveBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('comms.keep')),
          ),
          FilledButton(
            key: const Key('dialog-confirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('comms.yes')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.archiveTemplate(widget.templateId);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('comms.tpl.archived'))),
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(FFLocaleScope.of(context), e)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _template;
    final p = _preview;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t == null ? context.tr('comms.tpl.title') : templateName(context, t),
        ),
      ),
      body: t == null || p == null
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('comms.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                    action: FilledButton(
                      onPressed: _load,
                      child: Text(context.tr('comms.retry')),
                    ),
                  ))
          : _body(context, t, p),
    );
  }

  Widget _body(BuildContext context, CommTemplate t, TemplatePreview p) {
    final theme = Theme.of(context);
    final shown = p.byLocale[_lang]!;
    return ListView(
      padding: const EdgeInsets.all(FFTokens.spacingLg),
      children: [
        Wrap(
          spacing: FFTokens.spacingXs,
          children: [
            FFBadge(
              label: context.tr(
                t.system ? 'comms.tplSource.fitflex' : 'comms.tplSource.gym',
              ),
              tone: t.system ? FFBadgeTone.gray : FFBadgeTone.brand,
            ),
            FFBadge(label: context.tr('comms.group.${t.group}')),
            if (t.purpose != null)
              FFBadge(label: context.tr('comms.purpose.${t.purpose!.name}')),
          ],
        ),
        const SizedBox(height: FFTokens.spacingMd),
        if (p.byLocale.length > 1)
          FFSegmented(
            key: const Key('tpl-lang'),
            value: _lang!,
            options: [
              for (final l in p.byLocale.keys) (l, context.tr('comms.lang.$l')),
            ],
            onChanged: (l) => setState(() => _lang = l),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        Text(
          context.tr('comms.preview.asSeenBy').replaceFirst('{name}', 'Amina'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingSm),
        CampaignPreviewView(
          message: shown.inApp,
          channels: const {CommChannel.push, CommChannel.inApp},
          gymName: p.senderName,
        ),
        if (shown.pushTruncated)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              context.tr('comms.tpl.pushCut'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        FFAlert(
          key: const Key('tpl-whatsapp'),
          tone: FFAlertTone.info,
          message: context.tr(
            p.whatsappReady[_lang] == true
                ? 'comms.tpl.whatsappReady'
                : 'comms.tpl.whatsappNotYet',
          ),
        ),
        if (p.needsValues.isNotEmpty) ...[
          const SizedBox(height: FFTokens.spacingSm),
          Text(
            context
                .tr('comms.tpl.needsValues')
                .replaceFirst(
                  '{names}',
                  p.needsValues
                      .map((v) => context.tr('comms.var.$v'))
                      .join(', '),
                ),
            style: theme.textTheme.bodySmall,
          ),
        ],
        const SizedBox(height: FFTokens.spacingLg),
        FilledButton.icon(
          key: const Key('tpl-use'),
          onPressed: _busy
              ? null
              : () => context.push(
                  '/owner/communications/new${_gymQuery({'templateId': t.id})}',
                ),
          icon: const Icon(Icons.send_outlined),
          label: Text(context.tr('comms.tpl.use')),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        if (t.system)
          OutlinedButton(
            key: const Key('tpl-copy'),
            onPressed: _busy ? null : _copy,
            child: Text(context.tr('comms.tpl.copy')),
          )
        else ...[
          OutlinedButton(
            key: const Key('tpl-edit'),
            onPressed: _busy
                ? null
                : () async {
                    await context.push(
                      '/owner/communications/templates/${t.id}/edit${_gymQuery()}',
                    );
                    if (mounted) await _load();
                  },
            child: Text(context.tr('comms.tpl.edit')),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          TextButton(
            key: const Key('tpl-archive'),
            onPressed: _busy ? null : _archive,
            child: Text(context.tr('comms.tpl.archive')),
          ),
        ],
      ],
    );
  }
}

/// Create or edit one of the gym's own templates.
class TemplateEditorPage extends StatefulWidget {
  const TemplateEditorPage({
    super.key,
    this.templateId,
    this.gymId,
    this.repository,
  });

  /// Null for a new template.
  final String? templateId;
  final String? gymId;
  final CommunicationRepository? repository;

  @override
  State<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends State<TemplateEditorPage> {
  late CommunicationRepository _repo;
  bool _ready = false;
  bool _saving = false;
  Object? _error;
  String _lang = 'en';
  String _group = 'general';
  CampaignPurpose _purpose = CampaignPurpose.announcement;
  DeepLink _link = DeepLink.message;
  final _name = TextEditingController();
  final _title = {for (final l in kMessageLocales) l: TextEditingController()};
  final _body = {for (final l in kMessageLocales) l: TextEditingController()};
  final _cta = {for (final l in kMessageLocales) l: TextEditingController()};
  bool _targetTitle = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repo =
        widget.repository ?? CommunicationRepository(AppScope.of(context).api);
    _lang = FFLocaleScope.of(context).locale.languageCode;
    _load();
  }

  Future<void> _load() async {
    if (widget.templateId == null) {
      setState(() => _ready = true);
      return;
    }
    try {
      final t = await _repo.template(widget.templateId!);
      if (!mounted) return;
      setState(() {
        _name.text = t.name;
        _group = t.group;
        _purpose = t.purpose ?? CampaignPurpose.general;
        _link = t.deepLink;
        for (final e in t.bodies.entries) {
          _title[e.key]?.text = e.value.title;
          _body[e.key]?.text = e.value.body;
          _cta[e.key]?.text = e.value.ctaLabel ?? '';
        }
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      ..._title.values,
      ..._body.values,
      ..._cta.values,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> get _payload => {
    'gymId': ?widget.gymId,
    'name': _name.text.trim(),
    'group': _group,
    'purpose': _purpose.name,
    'deepLink': _link.name,
    'bodies': {
      for (final l in kMessageLocales)
        if (_title[l]!.text.trim().isNotEmpty ||
            _body[l]!.text.trim().isNotEmpty)
          l: MessageText(
            title: _title[l]!.text,
            body: _body[l]!.text,
            ctaLabel: _cta[l]!.text,
          ).toJson(),
    },
  };

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      _name.text.trim().length <= 60 &&
      kMessageLocales.any(
        (l) =>
            _title[l]!.text.trim().isNotEmpty &&
            _body[l]!.text.trim().isNotEmpty,
      ) &&
      kMessageLocales.every((l) {
        final t = _title[l]!.text.trim();
        final b = _body[l]!.text.trim();
        return (t.isEmpty && b.isEmpty) ||
            (t.isNotEmpty &&
                b.isNotEmpty &&
                t.length <= 65 &&
                b.length <= 1000);
      });

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final body = _payload;
      if (widget.templateId == null) {
        await _repo.createTemplate(body);
      } else {
        body.remove('gymId');
        await _repo.updateTemplate(widget.templateId!, body);
      }
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.tr('comms.tpl.saved'))),
      );
      context.pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(apiErrorMessage(FFLocaleScope.of(context), e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _insert(String variable) {
    final t = (_targetTitle ? _title : _body)[_lang]!;
    final token = '{{$variable}}';
    final sel = t.selection;
    final start = sel.isValid ? sel.start : t.text.length;
    final end = sel.isValid ? sel.end : t.text.length;
    t.value = TextEditingValue(
      text: t.text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(
            widget.templateId == null ? 'comms.tpl.new' : 'comms.tpl.edit',
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingMd),
          child: FilledButton(
            key: const Key('tpl-save'),
            onPressed: _ready && _valid && !_saving ? _save : null,
            child: Text(context.tr('comms.tpl.save')),
          ),
        ),
      ),
      body: !_ready
          ? (_error == null
                ? const Center(child: FFSpinner())
                : FFEmptyState(
                    title: context.tr('comms.loadFailed'),
                    body: errorMessage(FFLocaleScope.of(context), _error!),
                  ))
          : ListView(
              padding: const EdgeInsets.all(FFTokens.spacingLg),
              children: [
                FFTextField(
                  key: const Key('tpl-name'),
                  controller: _name,
                  label: context.tr('comms.tpl.name'),
                  onChanged: (_) => setState(() {}),
                  errorText: _name.text.trim().length > 60
                      ? context
                            .tr('comms.msg.tooLong')
                            .replaceFirst('{n}', '60')
                      : null,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFDropdownField<String>(
                  key: const Key('tpl-group'),
                  label: context.tr('comms.tpl.group'),
                  value: _group,
                  items: [
                    for (final g in kTemplateGroups)
                      DropdownMenuItem(
                        value: g,
                        child: Text(context.tr('comms.group.$g')),
                      ),
                  ],
                  onChanged: (g) => setState(() => _group = g ?? 'general'),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFDropdownField<CampaignPurpose>(
                  key: const Key('tpl-purpose'),
                  label: context.tr('comms.tpl.purpose'),
                  value: _purpose,
                  items: [
                    for (final p in CampaignPurpose.values)
                      DropdownMenuItem(
                        value: p,
                        child: Text(context.tr('comms.purpose.${p.name}')),
                      ),
                  ],
                  onChanged: (p) =>
                      setState(() => _purpose = p ?? CampaignPurpose.general),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFDropdownField<DeepLink>(
                  key: const Key('tpl-link'),
                  label: context.tr('comms.msg.opens'),
                  value: _link,
                  items: [
                    for (final d in DeepLink.values)
                      DropdownMenuItem(
                        value: d,
                        child: Text(context.tr('comms.link.${d.name}')),
                      ),
                  ],
                  onChanged: (d) =>
                      setState(() => _link = d ?? DeepLink.message),
                ),
                const SizedBox(height: FFTokens.spacingLg),
                FFSegmented(
                  key: const Key('tpl-edit-lang'),
                  value: _lang,
                  options: [
                    for (final l in kMessageLocales)
                      (l, context.tr('comms.lang.$l')),
                  ],
                  onChanged: (l) => setState(() => _lang = l),
                ),
                const SizedBox(height: FFTokens.spacingXs),
                Text(
                  context.tr('comms.tpl.bothLangs'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Focus(
                  onFocusChange: (f) => f ? _targetTitle = true : null,
                  child: FFTextField(
                    key: Key('tpl-title-$_lang'),
                    controller: _title[_lang],
                    label: context.tr('comms.msg.title'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Focus(
                  onFocusChange: (f) => f ? _targetTitle = false : null,
                  child: FFTextField(
                    key: Key('tpl-body-$_lang'),
                    controller: _body[_lang],
                    label: context.tr('comms.msg.body'),
                    maxLines: 6,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: FFTokens.spacingSm),
                Wrap(
                  spacing: FFTokens.spacingXs,
                  runSpacing: FFTokens.spacingXs,
                  children: [
                    for (final v in kMessageVariables)
                      FFPill(
                        key: Key('tpl-var-$v'),
                        label: context.tr('comms.var.$v'),
                        onTap: () => _insert(v),
                      ),
                  ],
                ),
                const SizedBox(height: FFTokens.spacingSm),
                FFTextField(
                  key: Key('tpl-cta-$_lang'),
                  controller: _cta[_lang],
                  label: context.tr('comms.msg.buttonLabel'),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
    );
  }
}
