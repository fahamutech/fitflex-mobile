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
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(FFTokens.spacingSm),
        child: Material(
          color: bgColor ?? FFTokens.darkSurface,
          borderRadius: BorderRadius.circular(FFTokens.radiusLg),
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
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w600,
          color: FFTokens.darkFgPrimary,
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
                const Icon(
                  Icons.backspace_outlined,
                  color: FFTokens.darkFgPrimary,
                ),
                onDelete,
              ),
              _buildDigitKey(context, 0),
              _buildKey(
                context,
                isLoading
                    ? const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: FFTokens.bgPrimary,
                      )
                    : const Text(
                        'OK',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: FFTokens.bgPrimary,
                        ),
                      ),
                okEnabled ? onOk : null,
                bgColor: okEnabled
                    ? FFTokens.brandVibrant
                    : FFTokens.darkBorder,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
