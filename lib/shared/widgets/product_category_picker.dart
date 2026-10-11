// Pickers for the fixed product category list: several for a vendor's
// business, one for a product. The list is served by the backend; the
// compiled-in copy is shown straight away and is used when the call fails.

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../design_tokens.dart';
import '../i18n.dart';
import '../product_categories.dart';

/// Keeps a category list in step with what the backend serves.
mixin _CategoryList<T extends StatefulWidget> on State<T> {
  List<ProductCategory> categories = ProductCategories.current;

  @override
  void initState() {
    super.initState();
    final api = context.getInheritedWidgetOfExactType<AppScope>()?.api;
    ProductCategories.load(api).then((list) {
      if (mounted && !identical(list, categories)) {
        setState(() => categories = list);
      }
    });
  }

  String get lang => FFLocaleScope.of(context).locale.languageCode;
}

/// A vendor's product categories: tick one or more.
class ProductCategoryMultiSelect extends StatefulWidget {
  const ProductCategoryMultiSelect({
    super.key,
    required this.selected,
    required this.onChanged,
    this.keyPrefix = 'product-category',
    this.required = false,
    this.showError = false,
  });

  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final String keyPrefix;
  final bool required;

  /// Shows "required" under the list (set after a failed save).
  final bool showError;

  @override
  State<ProductCategoryMultiSelect> createState() =>
      _ProductCategoryMultiSelectState();
}

class _ProductCategoryMultiSelectState extends State<ProductCategoryMultiSelect>
    with _CategoryList {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: Key('${widget.keyPrefix}-list'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('vendor.productCategories') +
              (widget.required ? ' *' : ''),
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: FFTokens.spacingXs),
        for (final c in categories)
          CheckboxListTile(
            key: Key('${widget.keyPrefix}-${c.key}'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: widget.selected.contains(c.key),
            title: Text(c.label(lang)),
            onChanged: (on) {
              final next = [...widget.selected];
              if (on == true) {
                if (!next.contains(c.key)) next.add(c.key);
              } else {
                next.remove(c.key);
              }
              widget.onChanged(next);
            },
          ),
        if (widget.showError && widget.selected.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: FFTokens.spacingXs),
            child: Text(
              context.tr('vendor.categoriesRequired'),
              key: Key('${widget.keyPrefix}-error'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// A product's category: pick one. An older free-text category stays shown
/// as the current value ("Gear (old)") and is not sent unless replaced.
class ProductCategoryDropdown extends StatefulWidget {
  const ProductCategoryDropdown({
    super.key,
    required this.current,
    required this.onChanged,
    this.fieldKey = const Key('vendor-product-category'),
  });

  /// The product's stored category (a key, older free text, or empty).
  final String? current;

  /// Called with the chosen key, or null while the old value is kept.
  final ValueChanged<String?> onChanged;
  final Key fieldKey;

  @override
  State<ProductCategoryDropdown> createState() =>
      _ProductCategoryDropdownState();
}

class _ProductCategoryDropdownState extends State<ProductCategoryDropdown>
    with _CategoryList {
  static const _legacy = '__legacy__';
  late String? _value;

  String get _stored => (widget.current ?? '').trim();

  @override
  void initState() {
    super.initState();
    if (_stored.isEmpty) {
      _value = null;
    } else if (categories.any((c) => c.key == _stored)) {
      _value = _stored;
    } else {
      // Settled in build once the server list is known; free text until then.
      _value = _legacy;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isKnown = categories.any((c) => c.key == _stored);
    // A key the server list only just revealed.
    if (_value == _legacy && isKnown) _value = _stored;
    final hasLegacy = _stored.isNotEmpty && !isKnown;
    return DropdownButtonFormField<String>(
      key: widget.fieldKey,
      initialValue: _value,
      isExpanded: true,
      decoration: InputDecoration(labelText: context.tr('vendor.category')),
      items: [
        if (hasLegacy)
          DropdownMenuItem(
            value: _legacy,
            child: Text(
              '$_stored (${context.tr('vendor.categoryOld')})',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        for (final c in categories)
          DropdownMenuItem(
            value: c.key,
            child: Text(c.label(lang), overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        setState(() => _value = v);
        widget.onChanged(v == _legacy ? null : v);
      },
    );
  }
}
