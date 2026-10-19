import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../router.dart';
import '../shared/i18n.dart';
import '../shared/design_tokens.dart';
import '../shared/components/components.dart';

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
                          context.tr('lang.title'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        Text(
                          context.tr('lang.slogan'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        SizedBox(height: FFTokens.spacingXl * 1.5),
                        // Each language is named in its own language.
                        FFChoiceTile(
                          key: const Key('langEnglish'),
                          title: context.tr('lang.name.en'),
                          selected: _selected == 'en',
                          onSelected: () => _select('en'),
                        ),
                        const SizedBox(height: FFTokens.spacingMd),
                        FFChoiceTile(
                          key: const Key('langKiswahili'),
                          title: context.tr('lang.name.sw'),
                          selected: _selected == 'sw',
                          onSelected: () => _select('sw'),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(FFTokens.spacingLg),
                  child: SizedBox(
                    width: double.infinity,
                    child: FFButton(
                      label: context.tr('lang.continue'),
                      onPressed: _selected != null ? _continue : null,
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
