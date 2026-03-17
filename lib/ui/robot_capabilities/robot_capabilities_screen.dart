/// Robot Capabilities Screen — expanded RCAN feature badges and Protocol 66 details.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/robot.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/capability_badge.dart';
import '../../ui/core/widgets/health_indicator.dart';
import '../robot_detail/robot_detail_view_model.dart';
import '../../core/constants.dart';

class RobotCapabilitiesScreen extends ConsumerWidget {
  final String rrn;
  /// If non-null, scroll to this anchor after load (e.g. "qos").
  final String? anchor;

  const RobotCapabilitiesScreen({super.key, required this.rrn, this.anchor});

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
        return _CapabilitiesView(robot: robot, anchor: anchor);
      },
    );
  }
}

class _CapabilitiesView extends StatelessWidget {
  final Robot robot;
  final String? anchor;
  const _CapabilitiesView({required this.robot, this.anchor});

  @override
  Widget build(BuildContext context) {
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
          // ── Scopes / Capabilities ─────────────────────────────────────────
          _SectionHeader('Supported Scopes'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CapabilityRow(capabilities: robot.capabilities),
                  const SizedBox(height: 12),
                  ...RobotCapability.values.map(
                    (cap) => _ScopeRow(
                      scope: cap,
                      enabled: robot.hasCapability(cap),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── RCAN v1.5 Features ────────────────────────────────────────────
          if (robot.isRcanV15) ...[
            _SectionHeader('RCAN v1.5 Features'),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _CapRow(
                      label: 'Replay Protection (GAP-03)',
                      icon: Icons.shield_outlined,
                      color: Colors.green,
                      enabled: true,
                      description:
                          'Prevents duplicate/replay command attacks via nonce cache.',
                    ),
                    _CapRow(
                      label: 'ESTOP QoS 2 (GAP-11)',
                      icon: Icons.check_circle_outline,
                      color: Colors.blue,
                      enabled: robot.supportsQos2,
                      description:
                          'Exactly-once delivery guarantee for ESTOP commands.',
                    ),
                    _CapRow(
                      label: 'Command Delegation (GAP-01)',
                      icon: Icons.account_tree_outlined,
                      color: Colors.teal,
                      enabled: robot.supportsDelegation,
                      description:
                          'Supports chained command delegation (human → cloud → robot).',
                    ),
                    _CapRow(
                      label: 'Offline Mode (GAP-06)',
                      icon: Icons.cloud_off_outlined,
                      color: Colors.orange,
                      enabled: robot.offlineCapable,
                      description:
                          'Operates with cached credentials when disconnected.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── RCAN v1.6 Features ────────────────────────────────────────────
          if (robot.isRcanV16) ...[
            _SectionHeader('RCAN v1.6 Features'),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _CapRow(
                      label: 'Multi-modal Commands (GAP-18)',
                      icon: Icons.image_outlined,
                      color: Colors.deepPurple,
                      enabled: robot.multimodalEnabled,
                      description:
                          'Accepts image/audio payloads in command instructions.',
                    ),
                    _CapRow(
                      label: 'LoA Enforcement (GAP-16)',
                      icon: Icons.verified_user_outlined,
                      color: Colors.green,
                      enabled: robot.loaEnforcement,
                      description:
                          'Level of Assurance policy enforced. Min LoA for control: ${robot.minLoaForControl}.',
                    ),
                    _CapRow(
                      label: 'Compact Transport (GAP-17)',
                      icon: Icons.compress_outlined,
                      color: Colors.indigo,
                      enabled: robot.supportsCompactTransport,
                      description:
                          'Binary compact encoding supported (bandwidth-efficient).',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Protocol 66 ───────────────────────────────────────────────────
          _SectionHeader('Protocol 66 Conformance'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _P66Row('§4.1 ESTOP never blocked', true),
                  _P66Row('§consent Confirmation dialogs', true),
                  _P66Row('§audit Sender type audit trail', true),
                  _P66Row('§rate-limit Command rate limiting', true),
                  _P66Row(
                      '§loa LoA enforcement',
                      robot.loaEnforcement),
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: () =>
                        launchUrl(Uri.parse(AppConstants.docsConsent)),
                    icon: const Icon(Icons.open_in_new, size: 14),
                    label: const Text('View P66 Consent Docs'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Identity & Registry ───────────────────────────────────────────
          _SectionHeader('Registry & Identity'),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _CapRow(
                    label: 'Registry Tier: ${robot.registryTier}',
                    icon: _registryIcon(robot.registryTier),
                    color: _registryColor(robot.registryTier),
                    enabled: true,
                    description:
                        'Robot is registered under the ${robot.registryTier} tier registry.',
                  ),
                  _CapRow(
                    label: 'Min LoA for Control: ${robot.minLoaForControl}',
                    icon: Icons.lock_outlined,
                    color: Colors.grey,
                    enabled: true,
                    description:
                        'Minimum identity assurance level required to issue control commands.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _registryIcon(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return Icons.star_outlined;
      case 'authoritative':
        return Icons.verified_outlined;
      default:
        return Icons.people_outline;
    }
  }

  Color _registryColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return Colors.amber;
      case 'authoritative':
        return Colors.cyan;
      default:
        return Colors.blueGrey;
    }
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context)
            .textTheme
            .labelLarge
            ?.copyWith(color: Theme.of(context).colorScheme.primary),
      ),
    );
  }
}

class _ScopeRow extends StatelessWidget {
  final RobotCapability scope;
  final bool enabled;
  const _ScopeRow({required this.scope, required this.enabled});

  static final _descriptions = <RobotCapability, String>{
    RobotCapability.discover: 'Robot discovery and registration queries',
    RobotCapability.status: 'Read telemetry and health status',
    RobotCapability.chat: 'Send natural language instructions',
    RobotCapability.control: 'Direct physical movement commands',
    RobotCapability.vision: 'Camera and visual perception data',
    RobotCapability.nav: 'Navigation and pathfinding commands',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle_outline : Icons.radio_button_unchecked,
            size: 16,
            color: enabled ? AppTheme.online : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scope.name.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                  ),
                ),
                Text(
                  _descriptions[scope] ?? '',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (!enabled)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'N/A',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _CapRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool enabled;
  final String description;

  const _CapRow({
    required this.label,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = enabled ? color : cs.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: effectiveColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: effectiveColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: effectiveColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(
            enabled ? Icons.check_circle : Icons.cancel_outlined,
            size: 16,
            color: enabled ? AppTheme.online : cs.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _P66Row extends StatelessWidget {
  final String label;
  final bool conforms;
  const _P66Row(this.label, this.conforms);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(
            conforms ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: conforms ? AppTheme.online : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: conforms ? cs.onSurface : cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}
