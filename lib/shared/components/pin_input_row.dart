import 'package:flutter/material.dart';
import '../design_tokens.dart';

class PinInputRow extends StatelessWidget {
  const PinInputRow({
    super.key,
    required this.pin,
    this.obscure = true,
  });

  final String pin;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        height: 60,
        constraints: const BoxConstraints(minWidth: 160),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: FFTokens.brandVibrant,
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
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: obscure
                  ? Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: FFTokens.darkFgPrimary,
                        shape: BoxShape.circle,
                      ),
                    )
                  : Text(
                      pin[index],
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        color: FFTokens.darkFgPrimary,
                      ),
                    ),
            );
          }),
        ),
      ),
    );
  }
}
