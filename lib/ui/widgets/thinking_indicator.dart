/// Animated three-dot "robot is thinking" indicator.
///
/// Shows robot avatar icon + name + bouncing dots (non-compact).
/// Compact mode shows just the three dots inline (for use inside ChatBubble).
library;

import 'package:flutter/material.dart';

class ThinkingIndicator extends StatefulWidget {
  /// Display name of the robot (shown in non-compact mode).
  final String robotName;

  /// Accent color for the left border, dots, and icon. Defaults to primary.
  final Color? color;

  /// When true: just the three bouncing dots, no bubble, no name.
  final bool compact;

  const ThinkingIndicator({
    super.key,
    required this.robotName,
    this.color,
    this.compact = false,
  });

  @override
  State<ThinkingIndicator> createState() => _ThinkingIndicatorState();
}

class _ThinkingIndicatorState extends State<ThinkingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<Animation<double>> _scales;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Each dot animates over a 40% window of the total cycle, staggered by
    // 20% (≈ 240 ms at 1.2 s) so they bounce sequentially.
    _scales = List.generate(3, (i) {
      final start = i * 0.2;
      final end = (i * 0.2 + 0.4).clamp(0.0, 1.0);
      return TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 1.5)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween(begin: 1.5, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOut)),
          weight: 50,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _ctrl,
          curve: Interval(start, end, curve: Curves.linear),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Widget _dots(Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        return AnimatedBuilder(
          animation: _scales[i],
          builder: (_, __) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Transform.scale(
              scale: _scales[i].value,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = widget.color ?? cs.primary;

    if (widget.compact) {
      return _dots(effectiveColor);
    }

    // Full bubble layout — left-aligned, left border in robot color.
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(right: 48),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          border: Border(
            left: BorderSide(color: effectiveColor, width: 12),
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy_outlined, size: 16, color: effectiveColor),
            if (widget.robotName.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                widget.robotName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 10),
            ] else
              const SizedBox(width: 6),
            _dots(effectiveColor),
          ],
        ),
      ),
    );
  }
}
