import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Loading spinner — matches portal's Spinner component.
class FFSpinner extends StatelessWidget {
  const FFSpinner({super.key, this.size = 20, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: 2.5,
        color: color ?? FFTokens.fgDisabled,
      ),
    );
  }
}

/// Full-page centered spinner.
class FFLoadingScreen extends StatelessWidget {
  const FFLoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: FFSpinner(size: 32)));
  }
}
