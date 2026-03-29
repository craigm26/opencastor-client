/// M3 Robot Card — used in fleet list.
///
/// Features:
/// - Hero animation for robot avatar (tag: `robot-avatar-<rrn>`)
/// - Animated pulse dot when online
/// - ESTOP button visible when online (Protocol 66 — non-negotiable)
/// - Semantics labels for accessibility
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/robot.dart';
import '../core/theme/app_theme.dart';
import 'status_indicator.dart';

class SharedRobotCard extends StatelessWidget {
  final Robot robot;
  final VoidCallback onTap;
  final Future<void> Function()? onEstop;
  final VoidCallback? onControl;

  const SharedRobotCard({
    super.key,
    required this.robot,
    required this.onTap,
    this.onEstop,
    this.onControl,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final isOnline = robot.isOnline;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: cs.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Robot avatar with Hero animation ─────────────────
                  Hero(
                    tag: 'robot-avatar-${robot.rrn}',
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: cs.primaryContainer,
                      child: Icon(
                        Icons.precision_manufacturing_outlined,
                        size: 22,
                        color: cs.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // ── Robot name + status ───────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          robot.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        StatusIndicator(isOnline: isOnline),
                      ],
                    ),
                  ),

                  // ── ESTOP button (Protocol 66 — always accessible) ────
                  if (isOnline && onEstop != null)
                    Semantics(
                      label: 'Emergency stop ${robot.name}',
                      button: true,
                      child: Tooltip(
                        message: 'Emergency Stop',
                        child: IconButton(
                          icon: const Icon(Icons.stop_circle_outlined),
                          color: AppTheme.estop,
                          iconSize: 28,
                          onPressed: () async {
                            HapticFeedback.heavyImpact();
                            await onEstop!();
                          },
                        ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // ── Version pill + RRN ────────────────────────────────────
              Row(
                children: [
                  if (robot.version.isNotEmpty) ...[
                    _Pill(
                      text: 'v${robot.version}',
                      color: cs.secondaryContainer,
                      textColor: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 6),
                  ],
                  _Pill(
                    text: robot.rrn,
                    color: cs.surfaceContainerHighest,
                    textColor: cs.onSurface,
                    mono: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  final Color textColor;
  final bool mono;

  const _Pill({
    required this.text,
    required this.color,
    required this.textColor,
    this.mono = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: textColor,
          fontWeight: FontWeight.w600,
          fontFamily: mono ? 'JetBrainsMono' : null,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
