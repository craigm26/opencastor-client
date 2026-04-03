/// Physical Control Screen — directional D-pad movement control with ESTOP.
///
/// Protocol 66 §consent: confirmation dialog required before ANY movement.
/// ESTOP is always visible and never blocked.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/confirmation_dialog.dart';
import '../../ui/core/widgets/health_indicator.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;
import '../shared/error_view.dart';
import '../shared/empty_view.dart';
import '../shared/loading_view.dart';
import '../robot_detail/robot_detail_view_model.dart';
import '../../core/constants.dart';

// ── Speed levels ──────────────────────────────────────────────────────────────

enum _Speed { slow, medium, fast }

extension _SpeedLabel on _Speed {
  String get label {
    switch (this) {
      case _Speed.slow:
        return 'Slow';
      case _Speed.medium:
        return 'Medium';
      case _Speed.fast:
        return 'Fast';
    }
  }

  double get sliderValue {
    switch (this) {
      case _Speed.slow:
        return 0;
      case _Speed.medium:
        return 1;
      case _Speed.fast:
        return 2;
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PhysicalControlScreen extends ConsumerStatefulWidget {
  final String rrn;
  const PhysicalControlScreen({super.key, required this.rrn});

  @override
  ConsumerState<PhysicalControlScreen> createState() =>
      _PhysicalControlScreenState();
}

class _PhysicalControlScreenState
    extends ConsumerState<PhysicalControlScreen> {
  _Speed _speed = _Speed.medium;
  bool _busy = false;
  String? _lastAction;

  Future<void> _sendMove(Robot robot, String instruction) async {
    if (_busy) return;

    // Protocol 66 §consent — mandatory confirmation before movement
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Send Movement Command',
      body: '"$instruction"\n\n'
          'Speed: ${_speed.label}\n\n'
          'This will physically move ${robot.name}. '
          'Ensure the workspace is clear.',
      confirmLabel: 'Move',
      isDangerous: false,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _lastAction = instruction;
    });

    try {
      await ref.read(robotRepositoryProvider).sendCommand(
            rrn: robot.rrn,
            instruction: '$instruction at ${_speed.label.toLowerCase()} speed',
            scope: CommandScope.control,
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEstop(Robot robot) async {
    final confirmed = await showEstopDialog(context, robot.name);
    if (!confirmed || !mounted) return;
    try {
      await ref.read(robotRepositoryProvider).sendEstop(robot.rrn);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ESTOP sent — robot halted'),
            backgroundColor: AppTheme.estop,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ESTOP failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final robotAsync = ref.watch(robotDetailProvider(widget.rrn));
    return robotAsync.when(
      loading: () =>
          const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(body: ErrorView(error: e.toString())),
      data: (robot) {
        if (robot == null) {
          return const Scaffold(body: EmptyView(title: 'Robot not found'));
        }
        return _buildUI(context, robot);
      },
    );
  }

  Widget _buildUI(BuildContext context, Robot robot) {
    final cs = Theme.of(context).colorScheme;
    final isOnline = robot.isOnline;

    return Scaffold(
      appBar: AppBar(
        title: Text('Control — ${robot.name}'),
        actions: [
          HealthIndicator(isOnline: isOnline, size: 8),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Consent Docs',
            onPressed: () =>
                launchUrl(Uri.parse(AppConstants.docsConsent)),
          ),
          // Always-visible ESTOP in app bar
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: isOnline ? () => _sendEstop(robot) : null,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: const Text('ESTOP'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.estop,
                minimumSize: const Size(0, 36),
              ),
            ),
          ),
        ],
      ),
      body: !isOnline
          ? _OfflineView(robotName: robot.name)
          : Column(
              children: [
                // ── Safety banner ──────────────────────────────────────────
                _SafetyBanner(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        // ── Speed slider ───────────────────────────────────
                        _SpeedControl(
                          speed: _speed,
                          onChanged: (v) =>
                              setState(() => _speed = v),
                        ),
                        const SizedBox(height: 32),

                        // ── D-Pad ──────────────────────────────────────────
                        _DPad(
                          busy: _busy,
                          onDirection: (dir) => _sendMove(robot, dir),
                        ),
                        const SizedBox(height: 24),

                        // ── Last action ────────────────────────────────────
                        if (_lastAction != null)
                          Text(
                            'Last: $_lastAction',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant),
                          ),

                        const Spacer(),

                        // ── Prominent ESTOP button ─────────────────────────
                        SizedBox(
                          width: double.infinity,
                          height: 56,
                          child: FilledButton.icon(
                            onPressed: () => _sendEstop(robot),
                            icon: const Icon(
                                Icons.stop_circle_outlined,
                                size: 24),
                            label: const Text(
                              'EMERGENCY STOP',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.estop,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Protocol 66 §4.1 — ESTOP never blocked',
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// ── D-Pad ──────────────────────────────────────────────────────────────────────

class _DPad extends StatelessWidget {
  final bool busy;
  final void Function(String direction) onDirection;

  const _DPad({required this.busy, required this.onDirection});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _DPadButton(
          icon: Icons.arrow_upward_rounded,
          label: 'Forward',
          onTap: busy ? null : () => onDirection('move_forward'),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _DPadButton(
              icon: Icons.arrow_back_rounded,
              label: 'Left',
              onTap: busy ? null : () => onDirection('move_left'),
            ),
            const SizedBox(width: 56), // center gap
            _DPadButton(
              icon: Icons.arrow_forward_rounded,
              label: 'Right',
              onTap: busy ? null : () => onDirection('move_right'),
            ),
          ],
        ),
        _DPadButton(
          icon: Icons.arrow_downward_rounded,
          label: 'Backward',
          onTap: busy ? null : () => onDirection('move_backward'),
        ),
      ],
    );
  }
}

class _DPadButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _DPadButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(4),
      child: Tooltip(
        message: label,
        child: Material(
          color: onTap != null ? cs.primaryContainer : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(
                icon,
                size: 32,
                color: onTap != null
                    ? cs.onPrimaryContainer
                    : cs.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Speed control ─────────────────────────────────────────────────────────────

class _SpeedControl extends StatelessWidget {
  final _Speed speed;
  final void Function(_Speed) onChanged;

  const _SpeedControl({required this.speed, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speed_outlined, size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('Speed: ${speed.label}',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ],
        ),
        Slider(
          value: speed.sliderValue,
          min: 0,
          max: 2,
          divisions: 2,
          label: speed.label,
          onChanged: (v) {
            final s = _Speed.values.firstWhere(
                (e) => e.sliderValue == v,
                orElse: () => _Speed.medium);
            onChanged(s);
          },
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: _Speed.values
              .map((s) => Text(s.label,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant)))
              .toList(),
        ),
      ],
    );
  }
}

// ── Safety banner ──────────────────────────────────────────────────────────────

class _SafetyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.warning.withValues(alpha: 0.12),
      child: const Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppTheme.warning, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Physical movement commands. Ensure workspace is clear. '
              'Confirmation required per Protocol 66.',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.warning),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Offline view ──────────────────────────────────────────────────────────────

class _OfflineView extends StatelessWidget {
  final String robotName;
  const _OfflineView({required this.robotName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 64, color: AppTheme.offline),
            const SizedBox(height: 16),
            Text('$robotName is offline',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text(
              'Start  castor bridge  on the robot to enable physical control.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
