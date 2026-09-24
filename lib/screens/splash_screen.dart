import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../app_scope.dart';
import '../router.dart';
import '../shared/design_tokens.dart';

/// First screen shown on app launch.
///
/// Displays only the FitFlex logo on a background that matches the
/// currently saved theme (light/dark), then "pans out" (zooms + fades)
/// once ready, before handing off to the language screen or the
/// signed-in user's home route.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _entranceScale;
  late final Animation<double> _entranceFade;
  late final Animation<double> _panOutScale;
  late final Animation<double> _exitFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _entranceScale = Tween<double>(begin: 0.82, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.35, curve: Curves.easeOutCubic),
      ),
    );
    _entranceFade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    _panOutScale = Tween<double>(begin: 1.0, end: 2.4).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.6, 1.0, curve: Curves.easeInCubic),
      ),
    );
    _exitFade = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.7, 1.0, curve: Curves.easeIn),
      ),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _goNext();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goNext() {
    if (!mounted) return;
    final auth = AppScope.of(context).auth;
    final destination = auth.isSignedIn
        ? routeForSignedInUser(auth)
        : AppRoutes.language;
    GoRouter.of(context).go(destination);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final scale = _entranceScale.value * _panOutScale.value;
            final opacity = _entranceFade.value * _exitFade.value;
            return Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: Image.asset(
            // Transparent mark: the full logo PNG has an opaque navy square.
            'assets/brand/fitflex-icon.png',
            width: FFTokens.spacingXl * 6,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
