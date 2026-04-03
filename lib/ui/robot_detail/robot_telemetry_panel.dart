/// RobotTelemetryPanel — collapsible real-time vitals strip.
///
/// Displays CPU temp, disk usage, free memory, and uptime sourced from:
///   1. WebSocket stream (wsTelemetryProvider) — ~200 ms updates when on LAN
///   2. Firestore telemetry (robot.telemetry) — 30 s updates as fallback
///
/// CPU temp is color-coded:
///   normal  → onSurface
///   >70 °C  → orange (warning)
///   >80 °C  → AppTheme.danger (critical)
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/robot.dart';
import '../../data/services/ws_telemetry_service.dart';
import '../core/theme/app_theme.dart';

class RobotTelemetryPanel extends ConsumerStatefulWidget {
  final Robot robot;
  const RobotTelemetryPanel({super.key, required this.robot});

  @override
  ConsumerState<RobotTelemetryPanel> createState() =>
      _RobotTelemetryPanelState();
}

class _RobotTelemetryPanelState extends ConsumerState<RobotTelemetryPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final wsAsync = ref.watch(wsTelemetryProvider(widget.robot.rrn));

    // Prefer live WS data; fall back to Firestore telemetry snapshot.
    final Map<String, dynamic> data =
        wsAsync.valueOrNull ?? widget.robot.telemetry;

    // Fields may live at root level or nested under 'system'.
    final sys = data['system'] as Map<String, dynamic>?;
    final cpuTemp = _toDouble(data['cpu_temp_c'] ?? sys?['cpu_temp_c']);
    final diskPct = _toDouble(data['disk_used_pct'] ?? sys?['disk_used_pct']);
    final memFree = _toDouble(data['mem_free_mb'] ?? sys?['mem_free_mb']);
    final uptimeRaw = data['uptime'] ?? sys?['uptime'];
    final uptime = _formatUptime(uptimeRaw);

    // Hide panel entirely when no telemetry fields are present.
    if (cpuTemp == null && diskPct == null && memFree == null && uptime == null) {
      return const SizedBox.shrink();
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: Container(
        color: cs.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Always-visible header row ──────────────────────────────
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      Icons.monitor_heart_outlined,
                      size: 14,
                      color: cs.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Telemetry',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                    const Spacer(),
                    // CPU temp preview when collapsed
                    if (cpuTemp != null && !_expanded) ...[
                      Text(
                        _formatTemp(cpuTemp),
                        style:
                            Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: _cpuTempColor(cpuTemp),
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded metrics row ───────────────────────────────────
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    if (cpuTemp != null)
                      _TelemetryChip(
                        label: 'CPU',
                        value: _formatTemp(cpuTemp),
                        color: _cpuTempColor(cpuTemp),
                      ),
                    if (diskPct != null)
                      _TelemetryChip(
                        label: 'Disk',
                        value: '${diskPct.toStringAsFixed(0)}%',
                      ),
                    if (memFree != null)
                      _TelemetryChip(
                        label: 'Mem free',
                        value: '${memFree.toStringAsFixed(0)} MB',
                      ),
                    if (uptime != null)
                      _TelemetryChip(label: 'Uptime', value: uptime),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Color _cpuTempColor(double temp) {
    if (temp > 80) return AppTheme.danger;
    if (temp > 70) return Colors.orange;
    return Theme.of(context).colorScheme.onSurface;
  }

  String _formatTemp(double temp) => '${temp.toStringAsFixed(1)}\u00B0C';

  /// Converts an uptime value to a human-readable string.
  ///
  /// Accepts seconds as [int]/[double], or a pre-formatted [String].
  static String? _formatUptime(dynamic v) {
    if (v == null) return null;
    if (v is String && v.isNotEmpty) return v;
    final secs = _toDouble(v);
    if (secs == null) return null;
    final d = Duration(seconds: secs.toInt());
    if (d.inDays > 0) return '${d.inDays}d ${d.inHours.remainder(24)}h';
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    return '${d.inMinutes}m';
  }

  static double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}

// ── Metric chip ───────────────────────────────────────────────────────────────

class _TelemetryChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _TelemetryChip({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color ?? cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
    );
  }
}
