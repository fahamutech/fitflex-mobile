import 'package:flutter/material.dart';
import '../design_tokens.dart';

class CustomKeypad extends StatelessWidget {
  const CustomKeypad({
    super.key,
    required this.onDigit,
    required this.onDelete,
    required this.onOk,
    required this.okEnabled,
    this.isLoading = false,
  });

  final ValueChanged<int> onDigit;
  final VoidCallback onDelete;
  final VoidCallback onOk;
  final bool okEnabled;
  final bool isLoading;

  Widget _buildKey(
    BuildContext context,
    Widget child,
    VoidCallback? onTap, {
    Color? bgColor,
  }) {
    final borderCol = bgColor != null
        ? Colors.transparent
        : Theme.of(context).colorScheme.outline;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingSm),
        child: Material(
          color: bgColor ?? Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FFTokens.radiusLg),
            side: BorderSide(color: borderCol),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: isLoading ? null : onTap,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }

  Widget _buildDigitKey(BuildContext context, int digit) {
    return _buildKey(
      context,
      Text(
        digit.toString(),
        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      () => onDigit(digit),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDigitKey(context, 1),
              _buildDigitKey(context, 2),
              _buildDigitKey(context, 3),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDigitKey(context, 4),
              _buildDigitKey(context, 5),
              _buildDigitKey(context, 6),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildDigitKey(context, 7),
              _buildDigitKey(context, 8),
              _buildDigitKey(context, 9),
            ],
          ),
        ),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildKey(
                context,
                Icon(
                  Icons.backspace_outlined,
                  color: Theme.of(context).colorScheme.onSurface,
                  size: FFTokens.iconLg,
                ),
                onDelete,
              ),
              _buildDigitKey(context, 0),
              _buildKey(
                context,
                isLoading
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      )
                    : Text(
                        'OK',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: okEnabled
                                  ? Theme.of(context).colorScheme.onPrimary
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.38),
                            ),
                      ),
                okEnabled ? onOk : null,
                bgColor: okEnabled
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
