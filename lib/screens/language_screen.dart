import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../router.dart';
import '../shared/i18n.dart';
import '../shared/design_tokens.dart';

class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  Future<void> _select(BuildContext context, String code) async {
    FFLocaleScope.of(context).set(Locale(code));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', code);
    if (!context.mounted) return;
    context.go(AppRoutes.role);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(FFTokens.spacingLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 48),
              Image.asset(
                'assets/brand/fitflex-logo.png',
                width: 88,
                height: 88,
                alignment: Alignment.centerLeft,
              ),
              const SizedBox(height: 20),
              const Text(
                'FitFlex Af',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  color: FFTokens.brand700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.tr('lang.choose'),
                style: const TextStyle(color: FFTokens.fgQuaternary),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => _select(context, 'en'),
                child: const Text('English'),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _select(context, 'sw'),
                child: const Text('Kiswahili'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
