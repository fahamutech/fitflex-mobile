import 'package:flutter/material.dart';

import '../../../../shared/api_error_message.dart';
import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../data/communication_models.dart';
import '../data/communication_repository.dart';

/// A template's name: FitFlex templates are named in the app's language,
/// gym templates by what the owner called them.
String templateName(BuildContext context, CommTemplate t) {
  if (!t.system) return t.name;
  final key = 'comms.tpl.${t.key}';
  final name = context.tr(key);
  return name == key ? t.key : name;
}

/// The template's text in the app's language, for lists and previews.
MessageText templateText(BuildContext context, CommTemplate t) =>
    t.textIn(FFLocaleScope.of(context).locale.languageCode);

/// One template in a list.
class TemplateTile extends StatelessWidget {
  const TemplateTile({super.key, required this.template, required this.onTap});

  final CommTemplate template;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final t = template;
    final text = templateText(context, t);
    return FFCard(
      margin: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: InkWell(
        key: Key('template-${t.key}'),
        borderRadius: BorderRadius.circular(FFTokens.radiusXl),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    templateName(context, t),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                FFBadge(
                  label: context.tr(
                    t.system
                        ? 'comms.tplSource.fitflex'
                        : 'comms.tplSource.gym',
                  ),
                  tone: t.system ? FFBadgeTone.gray : FFBadgeTone.brand,
                ),
              ],
            ),
            const SizedBox(height: FFTokens.spacing2xs),
            Text(
              text.body,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet to pick a template, filtered by group. Templates for the
/// message's purpose come first.
Future<CommTemplate?> pickTemplate(
  BuildContext context, {
  required CommunicationRepository repository,
  String? gymId,
  CampaignPurpose? purpose,
}) => showModalBottomSheet<CommTemplate>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => FractionallySizedBox(
    heightFactor: 0.85,
    child: _TemplatePicker(
      repository: repository,
      gymId: gymId,
      purpose: purpose,
    ),
  ),
);

class _TemplatePicker extends StatefulWidget {
  const _TemplatePicker({required this.repository, this.gymId, this.purpose});

  final CommunicationRepository repository;
  final String? gymId;
  final CampaignPurpose? purpose;

  @override
  State<_TemplatePicker> createState() => _TemplatePickerState();
}

class _TemplatePickerState extends State<_TemplatePicker> {
  List<CommTemplate>? _templates;
  Object? _error;
  String? _group;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.repository.templates(gymId: widget.gymId);
      if (!mounted) return;
      // The message's purpose first; the server's order otherwise.
      final p = widget.purpose;
      setState(
        () => _templates = [
          ...all.where((t) => p != null && t.purpose == p),
          ...all.where((t) => p == null || t.purpose != p),
        ],
      );
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final all = _templates;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('comms.tpl.pick'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: FFTokens.spacingSm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final g in [null, ...kTemplateGroups])
                  Padding(
                    padding: const EdgeInsets.only(right: FFTokens.spacingXs),
                    child: FFPill(
                      key: Key('tpl-group-${g ?? 'all'}'),
                      label: context.tr(
                        g == null ? 'comms.filter.all' : 'comms.group.$g',
                      ),
                      filled: _group == g,
                      onTap: () => setState(() => _group = g),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Expanded(
            child: all == null
                ? (_error == null
                      ? const Center(child: FFSpinner())
                      : FFEmptyState(
                          title: context.tr('comms.loadFailed'),
                          body: errorMessage(
                            FFLocaleScope.of(context),
                            _error!,
                          ),
                        ))
                : ListView(
                    children: [
                      for (final t in all.where(
                        (t) => _group == null || t.group == _group,
                      ))
                        TemplateTile(
                          template: t,
                          onTap: () => Navigator.pop(context, t),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
