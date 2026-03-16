import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Pulsing dot + label showing online/offline state.
class HealthIndicator extends StatelessWidget {
  final bool isOnline;
  final DateTime? lastSeen;
  final double size;
  final bool showLabel;

  const HealthIndicator({
    super.key,
    required this.isOnline,
    this.lastSeen,
    this.size = 10,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.onlineColor(isOnline);
    final label = isOnline ? 'Online' : 'Offline';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color, size: size, pulse: isOnline),
        if (showLabel) ...[
          const SizedBox(width: 6),
          Text(
            label,
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

class _Dot extends StatefulWidget {
  final Color color;
  final double size;
  final bool pulse;
  const _Dot({required this.color, required this.size, required this.pulse});

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _anim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Dot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1.0;
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
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
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
