// Vendor tools · S1: one row per product variant in the product form —
// name, stock, cost price and reorder level.
//
// Stock moves only through "Adjust stock" once a product exists, so on an
// edit no stock is ever sent: the server keeps the stored counts and merges
// variants by name. A new variant on a product whose variants keep stock
// starts at 0.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../shared/components/components.dart';
import '../../../shared/design_tokens.dart';
import '../../../shared/i18n.dart';
import 'stock_options.dart';

/// One variant row being edited.
class VariantDraft {
  VariantDraft({
    this.original,
    this.storedStock,
    String name = '',
    int? cost,
    int? reorder,
  }) : name = TextEditingController(text: name),
       stock = TextEditingController(),
       cost = TextEditingController(text: cost?.toString() ?? ''),
       reorder = TextEditingController(text: reorder?.toString() ?? '');

  /// From a stored variant (`{name, stock, costTzs, reorderLevel}`).
  factory VariantDraft.stored(Map variant) {
    final name = variant['name']?.toString() ?? '';
    return VariantDraft(
      original: name,
      storedStock: (variant['stock'] as num?)?.toInt(),
      name: name,
      cost: (variant['costTzs'] as num?)?.toInt(),
      reorder: (variant['reorderLevel'] as num?)?.toInt(),
    );
  }

  /// The stored name; null for a variant added in this form.
  final String? original;

  /// The stored count, when this variant keeps its own stock.
  int? storedStock;

  final TextEditingController name;
  final TextEditingController stock;
  final TextEditingController cost;
  final TextEditingController reorder;

  /// Set when the vendor tried to remove it while it still has stock.
  bool removeBlocked = false;

  /// The outcome of the last "Adjust stock" on this variant, shown in the
  /// row (a snackbar would be hidden behind the product form).
  ({String message, bool error})? notice;

  bool get isNew => original == null;
  bool get holdsStock => (storedStock ?? 0) > 0;
  String get trimmedName => name.text.trim();

  void dispose() {
    name.dispose();
    stock.dispose();
    cost.dispose();
    reorder.dispose();
  }
}

int? _intOrNull(String text) => int.tryParse(text.trim());

/// The `variants` to send. A new product sends each variant's starting
/// stock; an edit never sends stock. Empty cost / reorder level send null.
/// Cost is sent only by someone allowed to see it ([withCost]).
List<Map<String, dynamic>> variantsPayload(
  List<VariantDraft> rows, {
  required bool creating,
  required bool withCost,
}) => [
  for (final row in rows)
    {
      'name': row.trimmedName,
      if (creating) 'stock': _intOrNull(row.stock.text) ?? 0,
      if (withCost) 'costTzs': _intOrNull(row.cost.text),
      'reorderLevel': _intOrNull(row.reorder.text),
    },
];

/// Problems with the rows, by row index, as i18n keys: an empty or repeated
/// name (case-insensitive), or an existing variant with stock renamed (the
/// server treats that as removing it).
Map<int, String> validateVariants(List<VariantDraft> rows) {
  final errors = <int, String>{};
  final seen = <String, int>{};
  for (var i = 0; i < rows.length; i++) {
    final name = rows[i].trimmedName;
    if (name.isEmpty) {
      errors[i] = 'vendor.variant.nameRequired';
      continue;
    }
    final key = name.toLowerCase();
    if (seen.containsKey(key)) {
      errors[i] = 'vendor.variant.duplicateName';
      errors.putIfAbsent(seen[key]!, () => 'vendor.variant.duplicateName');
    } else {
      seen[key] = i;
    }
    final row = rows[i];
    if (!row.isNew && row.holdsStock && name != row.original) {
      errors[i] = 'vendor.variant.removeHasStock';
    }
  }
  return errors;
}

/// The variants section of the product form.
class VariantRowsEditor extends StatelessWidget {
  const VariantRowsEditor({
    super.key,
    required this.rows,
    required this.creating,
    required this.onChanged,
    this.errors = const {},
    this.onAdjust,
    this.enabled = true,
    this.showCost = false,
  });

  final List<VariantDraft> rows;

  /// Cost price is shown only to the vendor and their admin staff.
  final bool showCost;

  /// A new product: starting stock is typed in. Otherwise stock is read-only.
  final bool creating;

  /// Called after a row was added, removed or typed in.
  final VoidCallback onChanged;

  /// Row index → i18n key of its problem.
  final Map<int, String> errors;

  /// Opens "Adjust stock" for a stored variant.
  final void Function(String name)? onAdjust;
  final bool enabled;

  void _remove(VariantDraft row) {
    if (!row.isNew && row.holdsStock) {
      row.removeBlocked = true;
    } else {
      rows.remove(row);
      row.dispose();
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracked = rows.any((r) => !r.isNew && r.storedStock != null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  context.tr('vendor.variants'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
            ),
            FFButton(
              key: const Key('variant-add'),
              label: context.tr('vendor.variant.add'),
              icon: Icons.add,
              variant: FFButtonVariant.ghost,
              visualDensity: VisualDensity.standard,
              onPressed: enabled
                  ? () {
                      rows.add(VariantDraft());
                      onChanged();
                    }
                  : null,
            ),
          ],
        ),
        if (!creating && tracked && rows.any((r) => r.isNew))
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: FFAlert(
              key: const Key('variant-new-zero'),
              message: context.tr('vendor.variant.newStartsAtZero'),
              tone: FFAlertTone.info,
            ),
          ),
        for (var i = 0; i < rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
            child: _row(context, i, rows[i]),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, int index, VariantDraft row) {
    final label = row.trimmedName;
    // Typing in a row means the vendor keeps it: drop the remove warning.
    void edited() {
      row.removeBlocked = false;
      onChanged();
    }

    // Short visible labels (a long variant name would cut them off); the
    // row's fields are grouped under the variant name for screen readers.
    String fieldLabel(String key) => context.tr(key);
    final digits = [FilteringTextInputFormatter.digitsOnly];
    final error = errors[index];
    final nameError =
        error == 'vendor.variant.nameRequired' ||
            error == 'vendor.variant.duplicateName'
        ? context.tr(error!)
        : null;

    Widget stockCell() {
      if (creating) {
        return FFTextField(
          key: Key('variant-stock-$index'),
          controller: row.stock,
          enabled: enabled,
          keyboardType: TextInputType.number,
          inputFormatters: digits,
          label: fieldLabel('vendor.stock.initial'),
          onChanged: (_) => edited(),
        );
      }
      if (row.isNew || row.storedStock == null) return const SizedBox.shrink();
      // The count, then "Adjust stock" on its own line: side by side the
      // label was squeezed to a few pixels and broke per character.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            label:
                '${label.isEmpty ? '' : '$label: '}${context.tr('vendor.stock.current')}: ${row.storedStock}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('vendor.stock.current'),
                  key: Key('variant-stock-label-$index'),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                Text(
                  formatStock(row.storedStock!),
                  key: Key('variant-stock-value-$index'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
          if (onAdjust != null)
            FFButton(
              key: Key('variant-adjust-$index'),
              label: context.tr('vendor.stock.adjust'),
              semanticLabel: fillIn(context.tr('vendor.stock.adjustFor'), {
                'name': row.original,
              }),
              icon: Icons.tune,
              variant: FFButtonVariant.ghost,
              // A full 48dp target on web and desktop too.
              visualDensity: VisualDensity.standard,
              onPressed: enabled ? () => onAdjust!(row.original!) : null,
            ),
        ],
      );
    }

    final Widget? cost = !showCost
        ? null
        : FFTextField(
            key: Key('variant-cost-$index'),
            controller: row.cost,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            label: fieldLabel('vendor.costPrice'),
            onChanged: (_) => edited(),
          );
    final reorder = FFTextField(
      key: Key('variant-reorder-$index'),
      controller: row.reorder,
      enabled: enabled,
      keyboardType: TextInputType.number,
      inputFormatters: digits,
      label: fieldLabel('vendor.stock.reorderLevel'),
      onChanged: (_) => edited(),
    );
    final hasStockCell = creating || (!row.isNew && row.storedStock != null);

    return FFCard(
      key: Key('variant-row-$index'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FFTextField(
                  key: Key('variant-name-$index'),
                  controller: row.name,
                  enabled: enabled,
                  label: context.tr('vendor.variant.name'),
                  errorText: nameError,
                  onChanged: (_) => edited(),
                ),
              ),
              IconButton(
                key: Key('variant-remove-$index'),
                tooltip: fillIn(context.tr('vendor.variant.remove'), {
                  'name': label,
                }),
                icon: const Icon(Icons.delete_outline),
                // 48dp even where the platform density is compact (web).
                style: IconButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                onPressed: enabled ? () => _remove(row) : null,
              ),
            ],
          ),
          const SizedBox(height: FFTokens.spacingSm),
          Semantics(
            container: true,
            label: label,
            child: LayoutBuilder(
              builder: (context, box) {
                final cells = <Widget>[
                  if (hasStockCell) stockCell(),
                  ?cost,
                  reorder,
                ];
                final scaled = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
                Widget line(List<Widget> items) => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(width: FFTokens.spacingMd),
                      Expanded(child: items[i]),
                    ],
                  ],
                );
                // Swahili labels are longer: give each field more room before
                // putting fields side by side.
                final sw =
                    FFLocaleScope.of(context).locale.languageCode == 'sw';
                final minField = sw ? 200.0 : 140.0;
                bool fits(int n) =>
                    !scaled &&
                    box.maxWidth >= n * minField + (n - 1) * FFTokens.spacingMd;
                Widget stack(List<Widget> items) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const SizedBox(height: FFTokens.spacingSm),
                      items[i],
                    ],
                  ],
                );
                // The stored count with its "Adjust stock" button needs a
                // whole line below ~600 wide (beside Cost the button was
                // cut to "Adjust st…"); Cost and Reorder share the next.
                final countCell = hasStockCell && !creating;
                if (countCell && (box.maxWidth < 600 || !fits(cells.length))) {
                  final rest = cells.sublist(1);
                  return stack([
                    cells.first,
                    if (fits(rest.length)) line(rest) else stack(rest),
                  ]);
                }
                if (fits(cells.length)) return line(cells);
                if (cells.length == 3 && fits(2)) {
                  return stack([line(cells.sublist(0, 2)), cells[2]]);
                }
                return stack(cells);
              },
            ),
          ),
          if (row.notice case final notice?)
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: Semantics(
                liveRegion: true,
                child: FFAlert(
                  key: Key('variant-stock-notice-$index'),
                  message: notice.message,
                  tone: notice.error ? FFAlertTone.error : FFAlertTone.success,
                ),
              ),
            ),
          if (row.removeBlocked || error == 'vendor.variant.removeHasStock')
            Padding(
              padding: const EdgeInsets.only(top: FFTokens.spacingSm),
              child: FFAlert(
                key: Key('variant-has-stock-$index'),
                message: context.tr('vendor.variant.removeHasStock'),
                tone: FFAlertTone.warning,
              ),
            ),
        ],
      ),
    );
  }
}
