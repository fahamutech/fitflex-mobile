import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../communication_controller.dart';
import '../data/communication_models.dart';

/// Title, body (with member variables) and button, in the main language and
/// optionally the other app language, plus offer details. Can start from a
/// template.
class MessageComposer extends StatefulWidget {
  const MessageComposer({
    super.key,
    required this.controller,
    this.onPickTemplate,
  });

  final CampaignComposerController controller;

  /// Opens the template picker; null hides "Start from a template".
  final VoidCallback? onPickTemplate;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  CampaignComposerController get _c => widget.controller;

  late String _lang = _c.content.locale;

  // One set of fields per language.
  late final _title = {
    for (final l in kMessageLocales)
      l: TextEditingController(text: _textIn(l).title),
  };
  late final _body = {
    for (final l in kMessageLocales)
      l: TextEditingController(text: _textIn(l).body),
  };
  late final _cta = {
    for (final l in kMessageLocales)
      l: TextEditingController(text: _textIn(l).ctaLabel ?? ''),
  };
  late final _offer = TextEditingController(text: _c.content.offerName ?? '');
  late final _discount = TextEditingController(text: _c.content.discount ?? '');
  late final _amount = TextEditingController(
    text: _c.content.amountTzs?.toString() ?? '',
  );

  // Variable chips insert into the title or body used last.
  bool _targetTitle = false;

  MessageText _textIn(String lang) => lang == _c.content.locale
      ? _c.content.main
      : (_c.content.translations[lang] ?? const MessageText());

  @override
  void dispose() {
    for (final t in [
      ..._title.values,
      ..._body.values,
      ..._cta.values,
      _offer,
      _discount,
      _amount,
    ]) {
      t.dispose();
    }
    super.dispose();
  }

  void _pushText(String lang) {
    _c.setText(
      lang,
      MessageText(
        title: _title[lang]!.text,
        body: _body[lang]!.text,
        ctaLabel: _cta[lang]!.text,
      ),
    );
  }

  void _pushValues() {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    _c.setContent(
      _c.content.copyWith(
        offerName: () => _offer.text,
        discount: () => _discount.text,
        amountTzs: () => amount,
      ),
    );
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
    _pushText(_lang);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = _c.content;
    final isMain = _lang == content.locale;
    final text = _textIn(_lang);
    final used = content.variables;
    final showOffer =
        _c.purpose == CampaignPurpose.promotion ||
        used.any(CampaignComposerController.senderVariables.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.onPickTemplate != null)
          _c.templateId == null
              ? FFActionTile(
                  key: const Key('msg-pick-template'),
                  icon: Icons.library_books_outlined,
                  title: context.tr('comms.tpl.start'),
                  subtitle: context.tr('comms.tpl.startBody'),
                  onTap: widget.onPickTemplate!,
                )
              : FFCard(
                  child: Row(
                    children: [
                      Icon(
                        Icons.library_books_outlined,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: FFTokens.spacingSm),
                      Expanded(
                        child: Text(
                          context.tr('comms.tpl.using'),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      TextButton(
                        key: const Key('msg-change-template'),
                        onPressed: widget.onPickTemplate,
                        child: Text(context.tr('comms.tpl.change')),
                      ),
                      TextButton(
                        key: const Key('msg-clear-template'),
                        onPressed: _c.clearTemplate,
                        child: Text(context.tr('comms.tpl.blank')),
                      ),
                    ],
                  ),
                ),
        const SizedBox(height: FFTokens.spacingMd),
        FFSegmented(
          key: const Key('msg-lang'),
          value: _lang,
          options: [
            for (final l in kMessageLocales)
              (
                l,
                l == content.locale
                    ? '${context.tr('comms.lang.$l')} · ${context.tr('comms.lang.main')}'
                    : context.tr('comms.lang.$l'),
              ),
          ],
          onChanged: (l) => setState(() => _lang = l),
        ),
        const SizedBox(height: FFTokens.spacingXs),
        if (!isMain)
          Row(
            children: [
              Expanded(
                child: Text(
                  context
                      .tr('comms.lang.optional')
                      .replaceFirst('{lang}', context.tr('comms.lang.$_lang')),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              if (!text.isEmpty)
                TextButton(
                  key: const Key('msg-remove-translation'),
                  onPressed: () {
                    _title[_lang]!.clear();
                    _body[_lang]!.clear();
                    _cta[_lang]!.clear();
                    _c.removeTranslation(_lang);
                  },
                  child: Text(context.tr('comms.lang.remove')),
                ),
            ],
          ),
        const SizedBox(height: FFTokens.spacingSm),
        Focus(
          onFocusChange: (f) => f ? _targetTitle = true : null,
          child: FFTextField(
            key: Key('msg-title-$_lang'),
            controller: _title[_lang],
            label: context.tr('comms.msg.title'),
            hint: context.tr('comms.msg.titleHint'),
            onChanged: (_) => _pushText(_lang),
            errorText: text.title.length > 65
                ? context.tr('comms.msg.tooLong').replaceFirst('{n}', '65')
                : null,
          ),
        ),
        _Counter(text.title.length, 65),
        Focus(
          onFocusChange: (f) => f ? _targetTitle = false : null,
          child: FFTextField(
            key: Key('msg-body-$_lang'),
            controller: _body[_lang],
            label: context.tr('comms.msg.body'),
            hint: context.tr('comms.msg.bodyHint'),
            maxLines: 6,
            onChanged: (_) => _pushText(_lang),
            errorText: text.body.length > 1000
                ? context.tr('comms.msg.tooLong').replaceFirst('{n}', '1000')
                : null,
          ),
        ),
        _Counter(text.body.length, 1000),
        if (!isMain &&
            !text.isEmpty &&
            (text.title.trim().isEmpty || text.body.trim().isEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFAlert(
              tone: FFAlertTone.warning,
              message: context.tr('comms.lang.incomplete'),
            ),
          ),
        Text(
          context.tr('comms.msg.personalise'),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        Wrap(
          spacing: FFTokens.spacingXs,
          runSpacing: FFTokens.spacingXs,
          children: [
            for (final v in kMessageVariables)
              FFPill(
                key: Key('var-$v'),
                label: context.tr('comms.var.$v'),
                onTap: () => _insert(v),
              ),
          ],
        ),
        if (_c.unknownVariables.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingSm),
            child: FFAlert(
              tone: FFAlertTone.error,
              message: context
                  .tr('comms.msg.unknownVariable')
                  .replaceFirst('{name}', _c.unknownVariables.first),
            ),
          ),
        const SizedBox(height: FFTokens.spacingMd),
        FFTextField(
          key: Key('msg-cta-$_lang'),
          controller: _cta[_lang],
          label: context.tr('comms.msg.buttonLabel'),
          hint: context.tr('comms.msg.buttonHint'),
          onChanged: (_) => _pushText(_lang),
        ),
        const SizedBox(height: FFTokens.spacingSm),
        FFDropdownField<DeepLink>(
          key: const Key('msg-link'),
          label: context.tr('comms.msg.opens'),
          value: content.deepLink,
          items: [
            for (final d in DeepLink.values)
              DropdownMenuItem(
                value: d,
                child: Text(context.tr('comms.link.${d.name}')),
              ),
          ],
          onChanged: (d) => _c.setContent(
            _c.content.copyWith(deepLink: d ?? DeepLink.message),
          ),
        ),
        if (showOffer) ...[
          const SizedBox(height: FFTokens.spacingLg),
          FFFieldLabel(context.tr('comms.msg.offer')),
          Text(
            context.tr('comms.msg.offerBothLangs'),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: FFTokens.spacingXs),
          FFTextField(
            key: const Key('msg-offer'),
            controller: _offer,
            label: context.tr('comms.var.offer_name'),
            onChanged: (_) => _pushValues(),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          FFTextField(
            key: const Key('msg-discount'),
            controller: _discount,
            label: context.tr('comms.var.discount'),
            hint: context.tr('comms.msg.discountHint'),
            onChanged: (_) => _pushValues(),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          FFTextField(
            key: const Key('msg-amount'),
            controller: _amount,
            label: context.tr('comms.msg.amountTzs'),
            keyboardType: TextInputType.number,
            onChanged: (_) => _pushValues(),
          ),
          if (_c.missingSenderValues.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: FFAlert(
                tone: FFAlertTone.warning,
                message: context
                    .tr('comms.msg.fillIn')
                    .replaceFirst(
                      '{names}',
                      _c.missingSenderValues
                          .map((v) => context.tr('comms.var.$v'))
                          .join(', '),
                    ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter(this.length, this.max);
  final int length;
  final int max;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(
      top: FFTokens.spacing2xs,
      bottom: FFTokens.spacingSm,
    ),
    child: Align(
      alignment: Alignment.centerRight,
      child: Text(
        '$length/$max',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: length > max ? Theme.of(context).colorScheme.error : null,
        ),
      ),
    ),
  );
}
