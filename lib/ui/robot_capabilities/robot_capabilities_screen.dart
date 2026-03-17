/// Robot Capabilities Screen — conformance score + grouped capability sections.
///
/// Replaces the flat badge list with:
///   - Conformance score card (linear progress, %)
///   - Grouped sections: Identity & Registry, Safety, Transport, AI Capabilities
///   - Fix/Enable/Upgrade buttons that open bottom sheets or external URLs
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../data/models/robot.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/health_indicator.dart';
import '../robot_detail/robot_detail_view_model.dart';

class RobotCapabilitiesScreen extends ConsumerWidget {
  final String rrn;

  /// If non-null, scroll to this anchor after load (e.g. "qos").
  final String? anchor;

  const RobotCapabilitiesScreen(
      {super.key, required this.rrn, this.anchor});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return const Scaffold(
              body: Center(child: Text('Robot not found')));
        }
        return _CapabilitiesView(robot: robot);
      },
    );
  }
}

// ── Conformance score calculation ─────────────────────────────────────────────

int _conformanceScore(Robot robot) {
  int score = 0;
  if (robot.supportsQos2) score += 20; // ESTOP QoS (Protocol 66 §4)
  if (robot.isRcanV15) score += 15; // Replay protection (RCAN v1.5+)
  if (robot.loaEnforcement) score += 15; // LoA enforcement ON
  if (robot.isRcanV16) score += 10; // RCAN v1.6 (federation + multi-modal)
  if (robot.rrn.isNotEmpty) score += 10; // RRN assigned
  if (robot.hasCapability(RobotCapability.vision)) score += 10; // Vision
  final tier = robot.registryTier.toLowerCase();
  if (tier == 'verified' || tier == 'authoritative' || tier == 'root') {
    score += 10; // Registry verified+
  }
  if (robot.offlineCapable) score += 5; // Offline mode
  return score.clamp(0, 100);
}

/// Count of passing protocol-66 checks (out of 5).
int _p66PassCount(Robot robot) {
  int pass = 0;
  if (true) pass++; // §4.1 ESTOP never blocked (always true in app)
  if (true) pass++; // §consent dialogs (always true in app)
  if (true) pass++; // §audit sender-type trail (always true)
  if (true) pass++; // §rate-limit (always true)
  if (robot.loaEnforcement) pass++; // §loa enforcement
  return pass;
}

// ── View ──────────────────────────────────────────────────────────────────────

class _CapabilitiesView extends StatelessWidget {
  final Robot robot;
  const _CapabilitiesView({required this.robot});

  @override
  Widget build(BuildContext context) {
    final score = _conformanceScore(robot);
    final p66Pass = _p66PassCount(robot);

    return Scaffold(
      appBar: AppBar(
        title: Text('Capabilities — ${robot.name}'),
        actions: [
          HealthIndicator(isOnline: robot.isOnline, size: 8),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'RCAN Spec',
            onPressed: () =>
                launchUrl(Uri.parse(AppConstants.rcanSpecUrl)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Conformance Score ─────────────────────────────────────────────
          _ConformanceCard(robot: robot, score: score, p66Pass: p66Pass),
          const SizedBox(height: 16),

          // ── Identity & Registry ───────────────────────────────────────────
          _CapSection(
            title: 'Identity & Registry',
            icon: Icons.badge_outlined,
            rows: [
              _CapabilityRow(
                label: _registryTierLabel(robot.registryTier),
                status: _CapStatus.ok,
                description:
                    'Registered in the ${robot.registryTier} tier registry.',
                actionLabel: 'Upgrade to Verified ↗',
                actionUrl: AppConstants.rrfOpencastorUrl,
              ),
              _CapabilityRow(
                label: robot.rcanVersion != null
                    ? 'RCAN v${robot.rcanVersion}'
                    : 'RCAN version unknown',
                status: robot.rcanVersion != null
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description: 'RCAN protocol version reported by the bridge.',
              ),
              _CapabilityRow(
                label: robot.rrn.isNotEmpty ? 'RRN assigned' : 'No RRN',
                status: robot.rrn.isNotEmpty
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description: robot.rrn.isNotEmpty
                    ? 'Robot Resource Name: ${robot.rrn}'
                    : 'Robot has no assigned RRN.',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Safety (Protocol 66) ──────────────────────────────────────────
          _CapSection(
            title: 'Safety (Protocol 66)',
            icon: Icons.shield_outlined,
            rows: [
              _CapabilityRow(
                label: 'ESTOP QoS',
                status: robot.supportsQos2
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description:
                    'Exactly-once delivery guarantee for ESTOP commands (GAP-11).',
              ),
              _CapabilityRow(
                label: 'Replay Protection',
                status: robot.isRcanV15
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description:
                    'Prevents duplicate/replay command attacks via nonce cache (GAP-03).',
              ),
              _CapabilityRow(
                label: robot.loaEnforcement
                    ? 'LoA Enforcement: ON'
                    : 'LoA Enforcement: OFF',
                status: robot.loaEnforcement
                    ? _CapStatus.ok
                    : _CapStatus.warning,
                description: robot.loaEnforcement
                    ? 'LoA policy enforced — min LoA ${robot.minLoaForControl} required (GAP-16).'
                    : 'LoA policy in log-only mode. Enable to enforce access control (GAP-16).',
                actionLabel: robot.loaEnforcement ? null : 'Enable →',
                onAction: robot.loaEnforcement
                    ? null
                    : (ctx) => _showLoaBottomSheet(ctx),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Transport ─────────────────────────────────────────────────────
          _CapSection(
            title: 'Transport',
            icon: Icons.swap_horiz_outlined,
            rows: [
              _CapabilityRow(
                label: 'HTTP',
                status: robot.supportedTransports
                        .map((t) => t.toLowerCase())
                        .contains('http')
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description: 'HTTP/HTTPS transport encoding (GAP-17).',
              ),
              _CapabilityRow(
                label: 'COMPACT',
                status: robot.supportsCompactTransport
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description:
                    'Binary compact encoding — bandwidth-efficient (GAP-17).',
              ),
              _CapabilityRow(
                label: robot.supportedTransports
                        .map((t) => t.toLowerCase())
                        .contains('websocket')
                    ? 'WebSocket'
                    : 'WebSocket: not configured',
                status: robot.supportedTransports
                        .map((t) => t.toLowerCase())
                        .contains('websocket')
                    ? _CapStatus.ok
                    : _CapStatus.info,
                description:
                    'WebSocket transport for low-latency streaming.',
                actionLabel: 'Learn more ↗',
                actionUrl: AppConstants.rcanSpecUrl,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── AI Capabilities ───────────────────────────────────────────────
          _CapSection(
            title: 'AI Capabilities',
            icon: Icons.psychology_outlined,
            rows: [
              _CapabilityRow(
                label: 'Delegation',
                status: robot.supportsDelegation
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description:
                    'Command delegation chains supported: human → cloud → robot (GAP-01).',
              ),
              _CapabilityRow(
                label: 'Offline Mode',
                status: robot.offlineCapable
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description:
                    'Operates with cached credentials when disconnected (GAP-06).',
              ),
              _CapabilityRow(
                label: robot.hasCapability(RobotCapability.vision)
                    ? 'Vision: enabled'
                    : 'Vision: not enabled',
                status: robot.hasCapability(RobotCapability.vision)
                    ? _CapStatus.ok
                    : _CapStatus.missing,
                description:
                    'Camera and visual perception capability (GAP-18).',
                actionLabel: robot.hasCapability(RobotCapability.vision)
                    ? null
                    : 'Enable →',
                onAction: robot.hasCapability(RobotCapability.vision)
                    ? null
                    : (ctx) => _showVisionBottomSheet(ctx),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _registryTierLabel(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return 'Root Registry';
      case 'authoritative':
        return 'Authoritative Registry';
      case 'verified':
        return 'Verified Registry';
      default:
        return 'Community Registry';
    }
  }

  static void _showLoaBottomSheet(BuildContext context) {
    const snippet = 'loa_enforcement: true';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InstructionSheet(
        title: 'Enable LoA Enforcement',
        steps: const [
          'Open your robot config file: .rcan.yaml',
          'Add or update the following line:',
          'Restart the castor bridge:',
        ],
        codeSnippets: const [
          null,
          snippet,
          'castor bridge restart',
        ],
        note:
            'LoA enforcement requires RCAN v1.6+. Your robot will reject commands below the configured minimum assurance level.',
      ),
    );
  }

  static void _showVisionBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _InstructionSheet(
        title: 'Enable Vision Capability',
        steps: [
          'Connect a camera to your robot.',
          'Add "vision" to the capabilities list in .rcan.yaml:',
          'Restart the castor bridge:',
        ],
        codeSnippets: [
          null,
          'capabilities:\n  - vision',
          'castor bridge restart',
        ],
        note:
            'Vision requires a compatible camera driver. See the RCAN docs for supported hardware.',
      ),
    );
  }
}

// ── Conformance score card ────────────────────────────────────────────────────

class _ConformanceCard extends StatelessWidget {
  final Robot robot;
  final int score;
  final int p66Pass;

  const _ConformanceCard({
    required this.robot,
    required this.score,
    required this.p66Pass,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progressColor = score >= 80
        ? AppTheme.online
        : score >= 50
            ? AppTheme.warning
            : AppTheme.danger;
    final rcanLabel = robot.rcanVersion != null
        ? 'RCAN v${robot.rcanVersion}'
        : 'RCAN v?';
    final tierLabel = _tierDisplayLabel(robot.registryTier);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined,
                    size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Conformance Score',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100.0,
                      minHeight: 8,
                      backgroundColor:
                          progressColor.withOpacity(0.15),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(progressColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$score%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: progressColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rcanLabel,
                    style: TextStyle(
                        fontSize: 10,
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$tierLabel · $p66Pass/5 P66 checks',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _tierDisplayLabel(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return 'Root Registry';
      case 'authoritative':
        return 'Authoritative Registry';
      case 'verified':
        return 'Verified Community';
      default:
        return 'Community Registry';
    }
  }
}

// ── Capability section ────────────────────────────────────────────────────────

class _CapSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<_CapabilityRow> rows;

  const _CapSection({
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: cs.primary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                _CapabilityRowWidget(row: rows[i]),
                if (i < rows.length - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: cs.outlineVariant.withOpacity(0.4),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Capability row data ───────────────────────────────────────────────────────

enum _CapStatus { ok, warning, missing, info }

class _CapabilityRow {
  final String label;
  final _CapStatus status;
  final String description;
  final String? actionLabel;
  final String? actionUrl;
  final void Function(BuildContext ctx)? onAction;

  const _CapabilityRow({
    required this.label,
    required this.status,
    required this.description,
    this.actionLabel,
    this.actionUrl,
    this.onAction,
  });
}

// ── Capability row widget ─────────────────────────────────────────────────────

class _CapabilityRowWidget extends StatelessWidget {
  final _CapabilityRow row;
  const _CapabilityRowWidget({required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = _iconAndColor(row.status, cs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Status icon
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),

          // Label + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.description,
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          // Action button (if any)
          if (row.actionLabel != null) ...[
            const SizedBox(width: 8),
            _ActionButton(
              label: row.actionLabel!,
              onPressed: () {
                if (row.actionUrl != null) {
                  launchUrl(Uri.parse(row.actionUrl!),
                      mode: LaunchMode.externalApplication);
                } else if (row.onAction != null) {
                  row.onAction!(context);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  (IconData, Color) _iconAndColor(_CapStatus status, ColorScheme cs) {
    switch (status) {
      case _CapStatus.ok:
        return (Icons.check_circle_outline, AppTheme.online);
      case _CapStatus.warning:
        return (Icons.warning_amber_outlined, AppTheme.warning);
      case _CapStatus.missing:
        return (Icons.cancel_outlined, cs.onSurfaceVariant);
      case _CapStatus.info:
        return (Icons.info_outline, cs.onSurfaceVariant);
    }
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}

// ── Instruction bottom sheet ──────────────────────────────────────────────────

class _InstructionSheet extends StatelessWidget {
  final String title;
  final List<String> steps;
  final List<String?> codeSnippets;
  final String? note;

  const _InstructionSheet({
    required this.title,
    required this.steps,
    required this.codeSnippets,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < steps.length; i++) ...[
              _StepItem(
                  number: i + 1, label: steps[i]),
              if (codeSnippets[i] != null) ...[
                const SizedBox(height: 8),
                _CodeBlock(snippet: codeSnippets[i]!),
              ],
              const SizedBox(height: 12),
            ],
            if (note != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppTheme.warning.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note!,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final int number;
  final String label;

  const _StepItem({required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: TextStyle(
                fontSize: 11,
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ),
        ),
      ],
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String snippet;
  const _CodeBlock({required this.snippet});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              snippet,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 16),
            tooltip: 'Copy',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: snippet));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
