/// Reusable online/offline status dot + optional label.
library;

import 'package:flutter/material.dart';
import '../core/theme/app_theme.dart';

/// Animated pulse dot + label chip indicating robot online/offline status.
class StatusIndicator extends StatelessWidget {
  final bool isOnline;
  final bool showLabel;
  final double dotSize;

  const StatusIndicator({
    super.key,
    required this.isOnline,
    this.showLabel = true,
    this.dotSize = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    final color = isOnline ? AppTheme.online : AppTheme.offline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PulseDot(color: color, size: dotSize, pulse: isOnline),
        if (showLabel) ...[
          const SizedBox(width: 5),
          Text(
            isOnline ? 'Online' : 'Offline',
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulse;

  const _PulseDot({
    required this.color,
    required this.size,
    required this.pulse,
  });

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _opacity = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl
        ..stop()
        ..value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _opacity,
      builder: (_, __) => Opacity(
        opacity: _opacity.value,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}
