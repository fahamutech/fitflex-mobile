import 'package:flutter/material.dart';
import '../design_tokens.dart';

class PinInputRow extends StatelessWidget {
  const PinInputRow({super.key, required this.pin, this.obscure = true});

  final String pin;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 60,
        constraints: const BoxConstraints(minWidth: 160),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 2,
            ),
          ),
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pin.length, (index) {
            return Container(
              margin: const EdgeInsets.symmetric(
                horizontal: FFTokens.spacingSm,
              ),
              child: obscure
                  ? Container(
                      width: FFTokens.iconSm,
                      height: FFTokens.iconSm,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.onSurface,
                        shape: BoxShape.circle,
                      ),
                    )
                  : Text(
                      pin[index],
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                    ),
            );
          }),
        ),
      ),
    );
  }
}
