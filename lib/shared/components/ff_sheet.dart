import 'package:flutter/material.dart';
import '../design_tokens.dart';
import '../i18n.dart';

/// Bottom-sheet scaffold: drag handle, title row with a close button,
/// keyboard-aware padding and scrollable content. Usually opened through
/// [showFFSheet].
class FFSheet extends StatelessWidget {
  const FFSheet({
    super.key,
    required this.title,
    required this.child,
    this.showClose = true,
  });

  final String title;
  final Widget child;
  final bool showClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: FFTokens.spacingSm),
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outline,
                      borderRadius: BorderRadius.circular(FFTokens.radiusFull),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: FFTokens.spacingMd,
                  right: FFTokens.spacingSm,
                  top: FFTokens.spacingSm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (showClose)
                      IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: context.tr('common.close'),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    FFTokens.spacingMd,
                    FFTokens.spacingSm,
                    FFTokens.spacingMd,
                    FFTokens.spacingMd,
                  ),
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [child] in an [FFSheet]. Resolves with whatever the sheet pops.
Future<T?> showFFSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  bool showClose = true,
  bool isDismissible = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    builder: (_) => FFSheet(title: title, showClose: showClose, child: child),
  );
}
