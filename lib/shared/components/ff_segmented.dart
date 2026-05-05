import 'package:flutter/material.dart';
import '../design_tokens.dart';

/// Tab-style toggle group — matches portal's Segmented component.
class FFSegmented extends StatelessWidget {
  const FFSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String value;
  final List<(String id, String label)> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: FFTokens.bgTertiary,
        borderRadius: BorderRadius.circular(FFTokens.radiusLg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: options.map((opt) {
          final selected = opt.$1 == value;
          return Flexible(
            child: GestureDetector(
              onTap: () => onChanged(opt.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: selected ? FFTokens.bgPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(FFTokens.radiusMd),
                  boxShadow: selected ? FFTokens.shadowXs : null,
                ),
                child: Text(
                  opt.$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: selected ? FFTokens.fgPrimary : FFTokens.fgTertiary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
