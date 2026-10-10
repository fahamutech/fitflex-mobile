import 'package:flutter/material.dart';

import '../i18n.dart';
import '../theme_notifier.dart';

/// Theme picker for any AppBar's `actions`: dark, light, or auto (dark at
/// night, light in the daytime). The icon shows what is chosen.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  static IconData _icon(ThemePreference p) => switch (p) {
    ThemePreference.dark => Icons.dark_mode_outlined,
    ThemePreference.light => Icons.light_mode_outlined,
    ThemePreference.auto => Icons.brightness_auto_outlined,
  };

  static String _label(BuildContext context, ThemePreference p) =>
      context.tr(switch (p) {
        ThemePreference.dark => 'theme.dark',
        ThemePreference.light => 'theme.light',
        ThemePreference.auto => 'theme.auto',
      });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeScope.of(context);
    return PopupMenuButton<ThemePreference>(
      tooltip:
          '${context.tr('theme.title')}: ${_label(context, theme.preference)}',
      icon: Icon(_icon(theme.preference)),
      initialValue: theme.preference,
      onSelected: theme.setPreference,
      itemBuilder: (context) => [
        for (final p in ThemePreference.values)
          PopupMenuItem<ThemePreference>(
            value: p,
            child: Row(
              children: [
                Icon(_icon(p), size: 20),
                const SizedBox(width: 12),
                Flexible(child: Text(_label(context, p))),
                if (p == theme.preference) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.check, size: 18),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// One-tap language switch (English <-> Swahili) for the page the user is on.
/// Everything re-renders in place; the choice is remembered.
class LanguageToggleButton extends StatelessWidget {
  const LanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context) {
    final locale = FFLocaleScope.of(context);
    final isSw = locale.locale.languageCode == 'sw';
    return Semantics(
      button: true,
      label: context.tr(isSw ? 'lang.switchToEnglish' : 'lang.switchToSwahili'),
      excludeSemantics: true,
      child: Tooltip(
        message: context.tr(
          isSw ? 'lang.switchToEnglish' : 'lang.switchToSwahili',
        ),
        child: InkResponse(
          onTap: () => locale.set(Locale(isSw ? 'en' : 'sw')),
          radius: 24,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            child: Center(
              child: Text(
                isSw ? 'SW' : 'EN',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Language + theme controls, side by side, for an AppBar's `actions`.
class AppPrefsButtons extends StatelessWidget {
  const AppPrefsButtons({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [LanguageToggleButton(), ThemeToggleButton()],
  );
}
