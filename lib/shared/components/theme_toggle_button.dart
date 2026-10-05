import 'package:flutter/material.dart';

import '../theme_notifier.dart';
import '../i18n.dart';

/// A reusable icon button that toggles between light and dark theme.
/// Place this in any AppBar's `actions` list.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return IconButton(
      icon: Icon(
        theme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
      ),
      tooltip: FFLocaleScope.of(
        context,
      ).t(theme.isDark ? 'theme.switchLight' : 'theme.switchDark'),
      onPressed: theme.toggle,
    );
  }
}
