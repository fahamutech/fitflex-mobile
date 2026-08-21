import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router.dart';
import '../shared/components/theme_toggle_button.dart';
import '../shared/i18n.dart';
import '../shared/design_tokens.dart';

class LanguageScreen extends StatefulWidget {
  const LanguageScreen({super.key});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen>
    with SingleTickerProviderStateMixin {
  String? _selected;
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: FFTokens.motionSlow,
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeOut));

    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _select(String code) {
    setState(() => _selected = code);
  }

  Future<void> _continue() async {
    if (_selected == null) return;
    FFLocaleScope.of(context).set(Locale(_selected!));
    final router = GoRouter.of(context);
    if (!mounted) return;
    router.go(AppRoutes.auth);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: const [ThemeToggleButton()],
      ),
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FFTokens.spacingLg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(height: FFTokens.spacingXl * 3),
                        Text(
                          'Choose language',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        Text(
                          'Chagua lugha unayoipenda',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        SizedBox(height: FFTokens.spacingXl * 1.5),
                        _LanguageTile(
                          key: const Key('langEnglish'),
                          title: 'English',
                          subtitle: 'International Standard',
                          selected: _selected == 'en',
                          onTap: () => _select('en'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        _LanguageTile(
                          key: const Key('langKiswahili'),
                          title: 'Swahili',
                          subtitle: 'Lugha ya Kiswahili',
                          selected: _selected == 'sw',
                          onTap: () => _select('sw'),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _selected != null ? _continue : null,
                      child: const Text('Continue'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: FFTokens.motionMedium,
        curve: FFTokens.motionCurve,
        padding: const EdgeInsets.symmetric(
          horizontal: FFTokens.spacingLg,
          vertical: FFTokens.spacingMd,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(FFTokens.radiusXl),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: FFTokens.spacingXs),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            _RadioDot(selected: selected),
          ],
        ),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final muted = Theme.of(context).colorScheme.outline;
    return Container(
      width: FFTokens.spacingLg,
      height: FFTokens.spacingLg,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? primary : null,
        border: Border.all(color: selected ? primary : muted, width: 2),
      ),
      child: selected
          ? Center(
              child: CircleAvatar(
                radius: 5,
                backgroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            )
          : null,
    );
  }
}
