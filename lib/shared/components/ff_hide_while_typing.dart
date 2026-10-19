import 'package:flutter/material.dart';

/// Below this height a focused text field leaves too little room for both a
/// bottom bar and the button under the field (360x400 with the keyboard up).
const double ffShortScreenHeight = 520;

/// True while a text field has keyboard focus.
bool ffTextFieldHasFocus() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null || !ctx.mounted) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

/// True while the on-screen keyboard is (very likely) up: the system reports
/// it as a bottom inset, or, on a mobile browser that shrinks the page
/// instead, a text field has focus on a short screen.
bool ffKeyboardLikelyOpen(BuildContext context) {
  final mq = MediaQuery.of(context);
  if (mq.viewInsets.bottom > 0) return true;
  return mq.size.height < ffShortScreenHeight && ffTextFieldHasFocus();
}

/// Hides [child] (a bottom navigation bar) while the keyboard is up, so the
/// page above it gets the room back and its submit button is not covered.
class FFHideWhileTyping extends StatefulWidget {
  const FFHideWhileTyping({super.key, required this.child});

  final Widget child;

  @override
  State<FFHideWhileTyping> createState() => _FFHideWhileTypingState();
}

class _FFHideWhileTypingState extends State<FFHideWhileTyping> {
  bool? _focused;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    super.dispose();
  }

  void _onFocus() {
    final focused = ffTextFieldHasFocus();
    if (focused == _focused || !mounted) return;
    setState(() => _focused = focused);
  }

  @override
  Widget build(BuildContext context) {
    if (ffKeyboardLikelyOpen(context)) {
      return const SizedBox.shrink(key: Key('bottom-nav-hidden'));
    }
    return widget.child;
  }
}
