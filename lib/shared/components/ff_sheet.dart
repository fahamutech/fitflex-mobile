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
    this.showHandle = true,
    this.focusTitle = false,
    this.trapFocus = false,
  });

  /// Keyboard focus starts on the title (a focusable header with a ring),
  /// so Tab then walks the sheet top to bottom.
  final bool focusTitle;

  /// Tab and Shift+Tab stay inside the sheet (they wrap around), also on
  /// Flutter web where a route would otherwise let focus leave the page.
  final bool trapFocus;

  final String title;
  final Widget child;
  final bool showClose;

  /// The drag handle (off when shown as a centred dialog).
  final bool showHandle;

  @override
  Widget build(BuildContext context) {
    // The route is announced by its title, not a generic "Bottom sheet".
    final sheet = Semantics(
      namesRoute: true,
      explicitChildNodes: true,
      label: title,
      child: _sheet(context),
    );
    return trapFocus ? _FocusTrap(child: sheet) : sheet;
  }

  Widget _sheet(BuildContext context) {
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
              if (showHandle)
                Center(
                  child: ExcludeSemantics(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline,
                        borderRadius: BorderRadius.circular(
                          FFTokens.radiusFull,
                        ),
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
                      child: focusTitle
                          ? _FocusableTitle(
                              title: title,
                              style: theme.textTheme.titleMedium,
                            )
                          : Semantics(
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
                        key: const Key('ff-sheet-close'),
                        // 48x48 on every platform (web/desktop default to 40).
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          visualDensity: VisualDensity.standard,
                        ),
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

/// The sheet's title as the first keyboard stop: focused when the sheet
/// opens, read as a header, with a 2px focus-ring outline while focused.
class _FocusableTitle extends StatefulWidget {
  const _FocusableTitle({required this.title, this.style});
  final String title;
  final TextStyle? style;

  @override
  State<_FocusableTitle> createState() => _FocusableTitleState();
}

class _FocusableTitleState extends State<_FocusableTitle> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Focus(
      key: const Key('ff-sheet-title'),
      autofocus: true,
      onFocusChange: (f) => setState(() => _focused = f),
      child: Semantics(
        header: true,
        focused: _focused,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FFTokens.radiusSm),
            border: Border.all(
              color: _focused
                  ? (dark ? ffFocusRingDark : ffFocusRingLight)
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Text(
              widget.title,
              style: widget.style,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps keyboard traversal inside its child: past the last control focus
/// wraps to the first (and back).
class _FocusTrap extends StatefulWidget {
  const _FocusTrap({required this.child});
  final Widget child;

  @override
  State<_FocusTrap> createState() => _FocusTrapState();
}

class _FocusTrapState extends State<_FocusTrap> {
  final _scope = FocusScopeNode(
    debugLabel: 'ff-sheet-trap',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FocusScope(node: _scope, child: widget.child);
}

/// Opens [child] in an [FFSheet]. Resolves with whatever the sheet pops.
///
/// [wideDialogWidth] (opt-in): from 1024 px wide the sheet opens as a
/// centred dialog at most that wide instead (spec shop-home-phase2 §12).
/// The backdrop is announced as "Close" in the app's language, not the
/// framework's untranslated "Scrim".
Future<T?> showFFSheet<T>(
  BuildContext context, {
  required String title,
  required Widget child,
  bool showClose = true,
  bool isDismissible = true,
  double? wideDialogWidth,
  bool focusTitle = false,
  bool trapFocus = false,
}) {
  final barrier = context.tr('common.close');
  if (wideDialogWidth != null && MediaQuery.sizeOf(context).width >= 1024) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      barrierLabel: barrier,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(FFTokens.spacingLg),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: wideDialogWidth),
          child: FFSheet(
            title: title,
            showClose: showClose,
            showHandle: false,
            focusTitle: focusTitle,
            trapFocus: trapFocus,
            child: child,
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: isDismissible,
    barrierLabel: barrier,
    builder: (_) => FFSheet(
      title: title,
      showClose: showClose,
      focusTitle: focusTitle,
      trapFocus: trapFocus,
      child: child,
    ),
  );
}
