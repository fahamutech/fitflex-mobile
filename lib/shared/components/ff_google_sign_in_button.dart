import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'ff_spinner.dart';

/// Shared "Continue with Google" button used across auth screens.
class FFGoogleSignInButton extends StatelessWidget {
  const FFGoogleSignInButton({
    super.key,
    required this.label,
    required this.onTap,
    required this.loading,
  });

  final String label;
  final VoidCallback? onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        side: BorderSide(color: Theme.of(context).colorScheme.outline),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
        // At least 60 tall; a long label (large text, Swahili) wraps inside
        // the button instead of running past its edge.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FFTokens.spacingSm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: loading
                  ? [const FFSpinner(size: 20)]
                  : [
                      const _GoogleMark(),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
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

class _GoogleMark extends StatelessWidget {
  const _GoogleMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'G',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }
}
