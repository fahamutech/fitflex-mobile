import 'package:flutter/material.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/formatters.dart';
import '../../../shared/i18n.dart';

/// Picks a time of day for a banner or flash sale (Tanzania time).
///
/// English: the platform's Material time picker. Swahili (QA S4 #12): the
/// Material picker can only say "AM"/"PM", so a list of times every 15
/// minutes in the Swahili 12-hour style with the part of the day ("6:00
/// jioni", glossary 2026-10-04) is shown instead, opened at [initial].
Future<TimeOfDay?> pickMerchTime(
  BuildContext context, {
  required TimeOfDay initial,
  String? helpText,
}) {
  final lang = FFLocaleScope.of(context).locale.languageCode;
  if (lang != 'sw') {
    return showTimePicker(
      context: context,
      initialTime: initial,
      helpText: helpText,
    );
  }
  return showDialog<TimeOfDay>(
    context: context,
    builder: (_) => _SwahiliTimeDialog(initial: initial, title: helpText),
  );
}

class _SwahiliTimeDialog extends StatefulWidget {
  const _SwahiliTimeDialog({required this.initial, this.title});
  final TimeOfDay initial;
  final String? title;

  @override
  State<_SwahiliTimeDialog> createState() => _SwahiliTimeDialogState();
}

class _SwahiliTimeDialogState extends State<_SwahiliTimeDialog> {
  static const _step = 15;
  static const _rowHeight = 48.0;
  late final List<TimeOfDay> _slots = [
    for (var m = 0; m < 24 * 60; m += _step)
      TimeOfDay(hour: m ~/ 60, minute: m % 60),
  ];
  late final int _initialIndex =
      (widget.initial.hour * 60 + widget.initial.minute) ~/ _step;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: ((_initialIndex - 2) * _rowHeight).clamp(
      0,
      double.infinity,
    ),
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _label(TimeOfDay t) =>
      formatTimeOfDay(DateTime(2000, 1, 1, t.hour, t.minute), locale: 'sw');

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.6;
    return AlertDialog(
      key: const Key('merch-sw-time-picker'),
      title: widget.title == null ? null : Text(widget.title!),
      contentPadding: const EdgeInsets.symmetric(vertical: FFTokens.spacingSm),
      content: SizedBox(
        width: 320,
        height: height,
        child: ListView.builder(
          controller: _scroll,
          itemCount: _slots.length,
          itemExtent: _rowHeight,
          itemBuilder: (context, i) {
            final t = _slots[i];
            final selected = i == _initialIndex;
            return ListTile(
              key: Key('merch-sw-time-${t.hour}-${t.minute}'),
              selected: selected,
              title: Text(_label(t)),
              trailing: selected ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(t),
            );
          },
        ),
      ),
      actions: [
        FFButton(
          label: context.tr('common.cancel'),
          variant: FFButtonVariant.ghost,
          visualDensity: VisualDensity.standard,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
