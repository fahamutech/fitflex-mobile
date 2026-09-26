import 'package:flutter/material.dart';

import '../../../../shared/components/components.dart';
import '../../../../shared/design_tokens.dart';
import '../../../../shared/i18n.dart';
import '../communication_controller.dart';
import '../data/communication_models.dart';

/// Title, body (with member variables), button, and offer details.
class MessageComposer extends StatefulWidget {
  const MessageComposer({super.key, required this.controller});

  final CampaignComposerController controller;

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  late final _title = TextEditingController(text: _c.content.title);
  late final _body = TextEditingController(text: _c.content.body);
  late final _cta = TextEditingController(text: _c.content.ctaLabel ?? '');
  late final _offer = TextEditingController(text: _c.content.offerName ?? '');
  late final _discount = TextEditingController(text: _c.content.discount ?? '');
  late final _amount = TextEditingController(
    text: _c.content.amountTzs?.toString() ?? '',
  );

  // Variable chips insert into whichever of title/body was used last.
  late TextEditingController _target = _body;

  CampaignComposerController get _c => widget.controller;

  @override
  void dispose() {
    for (final t in [_title, _body, _cta, _offer, _discount, _amount]) {
      t.dispose();
    }
    super.dispose();
  }

  void _push() {
    final amount = int.tryParse(_amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    _c.setContent(
      _c.content.copyWith(
        title: _title.text,
        body: _body.text,
        ctaLabel: () => _cta.text,
        offerName: () => _offer.text,
        discount: () => _discount.text,
        amountTzs: () => amount,
      ),
    );
  }

  void _insert(String variable) {
    final t = _target;
    final token = '{{$variable}}';
    final sel = t.selection;
    final start = sel.isValid ? sel.start : t.text.length;
    final end = sel.isValid ? sel.end : t.text.length;
    t.value = TextEditingValue(
      text: t.text.replaceRange(start, end, token),
      selection: TextSelection.collapsed(offset: start + token.length),
    );
    _push();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = _c.content;
    final used = content.variables;
    final showOffer =
        _c.purpose == CampaignPurpose.promotion ||
        used.any(CampaignComposerController.senderVariables.contains);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Focus(
          onFocusChange: (f) => f ? _target = _title : null,
          child: FFTextField(
            key: const Key('msg-title'),
            controller: _title,
            label: context.tr('comms.msg.title'),
            hint: context.tr('comms.msg.titleHint'),
            onChanged: (_) => _push(),
            errorText: content.title.length > 65
                ? context.tr('comms.msg.tooLong').replaceFirst('{n}', '65')
                : null,
          ),
        ),
        _Counter(content.title.length, 65),
        Focus(
          onFocusChange: (f) => f ? _target = _body : null,
          child: FFTextField(
            key: const Key('msg-body'),
            controller: _body,
            label: context.tr('comms.msg.body'),
            hint: context.tr('comms.msg.bodyHint'),
            maxLines: 6,
            onChanged: (_) => _push(),
            errorText: content.body.length > 1000
                ? context.tr('comms.msg.tooLong').replaceFirst('{n}', '1000')
                : null,
          ),
        ),
        _Counter(content.body.length, 1000),
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
        if (showOffer) ...[
          const SizedBox(height: FFTokens.spacingLg),
          FFFieldLabel(context.tr('comms.msg.offer')),
          FFTextField(
            key: const Key('msg-offer'),
            controller: _offer,
            label: context.tr('comms.var.offer_name'),
            onChanged: (_) => _push(),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          FFTextField(
            key: const Key('msg-discount'),
            controller: _discount,
            label: context.tr('comms.var.discount'),
            hint: context.tr('comms.msg.discountHint'),
            onChanged: (_) => _push(),
          ),
          const SizedBox(height: FFTokens.spacingSm),
          FFTextField(
            key: const Key('msg-amount'),
            controller: _amount,
            label: context.tr('comms.msg.amountTzs'),
            keyboardType: TextInputType.number,
            onChanged: (_) => _push(),
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
        const SizedBox(height: FFTokens.spacingLg),
        FFFieldLabel(context.tr('comms.msg.button')),
        FFTextField(
          key: const Key('msg-cta'),
          controller: _cta,
          label: context.tr('comms.msg.buttonLabel'),
          hint: context.tr('comms.msg.buttonHint'),
          onChanged: (_) => _push(),
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
