import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// Minus / value / plus for a count (event tickets, kit counts). Each
/// button is a 44 dp target; assistive tech hears one adjustable control
/// ("Quantity for Early bird, 2") with increase / decrease actions, and the
/// buttons carry their own tooltips ("Add one" / "Remove one").
///
/// Stepping is left to the caller through [onChanged] with the next value:
/// [increment] / [decrement] compute it (a ticket's minimum per order makes
/// 0 → min and min − 1 → 0), so the widget stays a plain control.
class FFQuantityStepper extends StatelessWidget {
  const FFQuantityStepper({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    required this.addLabel,
    required this.removeLabel,
    this.min = 0,
    this.max = 99,
    this.step = 1,
    this.enabled = true,
    this.canIncrement,
  });

  final int value;

  /// Called with the next value; null disables both buttons.
  final ValueChanged<int>? onChanged;

  /// What the control is for ("Quantity for Early bird").
  final String label;
  final String addLabel;
  final String removeLabel;

  /// The lowest non-zero value (a ticket's `minPerOrder`): stepping up from
  /// 0 lands here and stepping down from here lands on 0.
  final int min;
  final int max;
  final int step;
  final bool enabled;

  /// Extra gate on the plus button (an order-wide cap); null means [max]
  /// alone decides.
  final bool? canIncrement;

  int get _next => value == 0 ? (min > 0 ? min : step) : value + step;
  int get _previous => value <= min ? 0 : value - step;

  bool get _canAdd =>
      enabled && onChanged != null && value < max && (canIncrement ?? true);
  bool get _canRemove => enabled && onChanged != null && value > 0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: label,
      value: '$value',
      increasedValue: _canAdd ? '$_next' : null,
      decreasedValue: _canRemove ? '$_previous' : null,
      onIncrease: _canAdd ? () => onChanged!(_next) : null,
      onDecrease: _canRemove ? () => onChanged!(_previous) : null,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(FFTokens.radiusFull),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              buttonKey: const Key('ff-stepper-remove'),
              icon: Icons.remove,
              tooltip: removeLabel,
              onPressed: _canRemove ? () => onChanged!(_previous) : null,
            ),
            ExcludeSemantics(
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 28),
                child: Text(
                  '$value',
                  key: const Key('ff-stepper-value'),
                  textAlign: TextAlign.center,
                  style: tt.titleMedium?.copyWith(
                    color: enabled ? null : cs.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            _StepButton(
              buttonKey: const Key('ff-stepper-add'),
              icon: Icons.add,
              tooltip: addLabel,
              onPressed: _canAdd ? () => onChanged!(_next) : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: IconButton(
      key: buttonKey,
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.standard,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    ),
  );
}
