import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../design_tokens.dart';

/// Standard text input — relies on the app's [InputDecorationTheme] so all
/// fields share the same border radius, fill, and focus colors from the
/// design system. Use this instead of bare [TextFormField] in feature pages.
class FFTextField extends StatelessWidget {
  const FFTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.errorText,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.enabled = true,
    this.maxLines = 1,
    this.minLines,
    this.onChanged,
    this.prefixIcon,
    this.suffixIcon,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofillHints,
    this.maxLength,
    this.inputFormatters,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.readOnly = false,
    this.onTap,
    this.helperText,
    this.suffixText,
    this.autovalidateMode,
    this.focusNode,
    this.helperMaxLines = 3,
    this.errorMaxLines = 3,
    this.scrollPadding = const EdgeInsets.all(20),
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? errorText;
  final FormFieldValidator<String>? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final bool enabled;
  final int maxLines;

  /// Minimum visible lines for a growing multi-line field (use with a larger
  /// [maxLines]). Null keeps the field at its natural height.
  final int? minLines;
  final ValueChanged<String>? onChanged;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final Iterable<String>? autofillHints;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final bool readOnly;
  final VoidCallback? onTap;
  final String? helperText;
  final String? suffixText;
  final AutovalidateMode? autovalidateMode;

  /// Lets a screen move focus back to this field (e.g. after a conflict).
  final FocusNode? focusNode;

  /// Helper and error text wrap (up to this many lines) instead of being cut
  /// off with "…" — longer in Swahili.
  final int helperMaxLines;
  final int errorMaxLines;

  /// Space kept around the field when it scrolls into view above the
  /// keyboard; a larger bottom keeps the button under it in view too.
  final EdgeInsets scrollPadding;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      initialValue: initialValue,
      validator: validator,
      keyboardType: keyboardType,
      obscureText: obscureText,
      enabled: enabled,
      maxLines: maxLines,
      minLines: minLines,
      onChanged: onChanged,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autofillHints: autofillHints,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      autofocus: autofocus,
      textCapitalization: textCapitalization,
      readOnly: readOnly,
      onTap: onTap,
      autovalidateMode: autovalidateMode,
      scrollPadding: scrollPadding,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        helperText: helperText,
        helperMaxLines: helperMaxLines,
        errorMaxLines: errorMaxLines,
        suffixText: suffixText,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }
}

/// Standard dropdown input sharing the same themed decoration as [FFTextField].
class FFDropdownField<T> extends StatelessWidget {
  const FFDropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.width,
    this.isExpanded = false,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? label;
  final double? width;

  /// Makes the selected item fill the field so long labels can ellipsize
  /// instead of overflowing.
  final bool isExpanded;

  @override
  Widget build(BuildContext context) {
    final field = DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      isExpanded: isExpanded,
      decoration: InputDecoration(labelText: label),
    );
    if (width != null) return SizedBox(width: width, child: field);
    return field;
  }
}

/// Form section label — replaces ad-hoc bold `Text` labels above inputs.
class FFFieldLabel extends StatelessWidget {
  const FFFieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FFTokens.spacingSm),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}
