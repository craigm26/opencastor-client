/// Robot Capabilities Screen — conformance score card + section index.
///
/// Each section tile navigates to its own dedicated sub-screen:
///   /robot/:rrn/capabilities/conformance
///   /robot/:rrn/capabilities/identity
///   /robot/:rrn/capabilities/safety
///   /robot/:rrn/capabilities/transport
///   /robot/:rrn/capabilities/ai
///   /robot/:rrn/capabilities/hardware
///   /robot/:rrn/capabilities/software
///   /robot/:rrn/capabilities/providers
///   /robot/:rrn/capabilities/contribute
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../core/widgets/health_indicator.dart';
import '../robot_detail/robot_detail_view_model.dart';
import 'capabilities_widgets.dart';

// Re-export helper so any callers that imported _asList from here still compile.
// ignore: unused_element
List<dynamic> _asList(dynamic value) => capsAsList(value);

class RobotCapabilitiesScreen extends ConsumerWidget {
  final String rrn;

  /// If non-null, navigate directly to the matching sub-screen after load
  /// (e.g. anchor == "safety" → push /robot/:rrn/capabilities/safety).
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

        // If anchor is set, immediately navigate to the matching sub-screen.
        if (anchor != null) {
          final validAnchors = [
            'conformance',
            'identity',
            'safety',
            'transport',
            'ai',
            'hardware',
            'software',
            'providers',
            'contribute',
          ];
          if (validAnchors.contains(anchor)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                context.push('/robot/$rrn/capabilities/$anchor');
              }
            });
          }
        }

        return _CapabilitiesIndex(robot: robot, rrn: rrn);
      },
    );
  }
}

// ── Index view ────────────────────────────────────────────────────────────────

class _CapabilitiesIndex extends StatelessWidget {
  final Robot robot;
  final String rrn;

  const _CapabilitiesIndex({required this.robot, required this.rrn});

  @override
  Widget build(BuildContext context) {
    final score = capConformanceScore(robot);
    final p66Pass = capP66PassCount(robot);

    return Scaffold(
      appBar: AppBar(
        title: Text('Capabilities — ${robot.name}'),
        actions: [
          HealthIndicator(isOnline: robot.isOnline, size: 8),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share as Harness',
            onPressed: () =>
                shareCapabilitiesAsHarness(context, robot),
          ),
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
          // ── Conformance score summary ─────────────────────────────────
          GestureDetector(
            onTap: () =>
                context.push('/robot/$rrn/capabilities/conformance'),
            child: ConformanceCard(
                robot: robot, score: score, p66Pass: p66Pass),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: const Text('View score breakdown',
                  style: TextStyle(fontSize: 12)),
              onPressed: () =>
                  context.push('/robot/$rrn/capabilities/conformance'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Section index ─────────────────────────────────────────────
          _SectionHeader(),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                _CapabilitiesIndexTile(
                  icon: Icons.badge_outlined,
                  color: Colors.blue,
                  title: 'Identity & Registry',
                  subtitle: capRegistryTierLabel(robot.registryTier),
                  onTap: () => context
                      .push('/robot/$rrn/capabilities/identity'),
                ),
                _divider(context),
                _CapabilitiesIndexTile(
                  icon: Icons.shield_outlined,
                  color: Colors.green,
                  title: 'Safety (Protocol 66)',
                  subtitle: '$p66Pass/5 checks passing',
                  onTap: () => context
                      .push('/robot/$rrn/capabilities/safety'),
                ),
                _divider(context),
                _CapabilitiesIndexTile(
                  icon: Icons.swap_horiz_outlined,
                  color: Colors.orange,
                  title: 'Transport',
                  subtitle: robot.supportedTransports.isNotEmpty
                      ? robot.supportedTransports.join(', ')
                      : 'Not configured',
                  onTap: () => context
                      .push('/robot/$rrn/capabilities/transport'),
                ),
                _divider(context),
                _CapabilitiesIndexTile(
                  icon: Icons.psychology_outlined,
                  color: Colors.purple,
                  title: 'AI Capabilities',
                  subtitle: robot.hasCapability(RobotCapability.vision)
                      ? 'Vision enabled'
                      : robot.supportsDelegation
                          ? 'Delegation enabled'
                          : 'Offline capable: ${robot.offlineCapable}',
                  onTap: () =>
                      context.push('/robot/$rrn/capabilities/ai'),
                ),
                _divider(context),
                _CapabilitiesIndexTile(
                  icon: Icons.memory_outlined,
                  color: Colors.teal,
                  title: 'Detected Hardware',
                  onTap: () => context
                      .push('/robot/$rrn/capabilities/hardware'),
                ),
                _divider(context),
                _CapabilitiesIndexTile(
                  icon: Icons.layers_outlined,
                  color: Colors.indigo,
                  title: 'Software Stack',
                  subtitle: robot.rcanVersion != null
                      ? 'RCAN v${robot.rcanVersion}'
                      : null,
                  onTap: () => context
                      .push('/robot/$rrn/capabilities/software'),
                ),
                _divider(context),
                _CapabilitiesIndexTile(
                  icon: Icons.vpn_key_outlined,
                  color: Colors.brown,
                  title: 'Gated Providers',
                  onTap: () => context
                      .push('/robot/$rrn/capabilities/providers'),
                ),
                _divider(context),
                _CapabilitiesIndexTile(
                  icon: Icons.volunteer_activism_outlined,
                  color: Colors.pink,
                  title: 'Contribute',
                  onTap: () => context
                      .push('/robot/$rrn/capabilities/contribute'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _divider(BuildContext context) {
    return Divider(
      height: 1,
      indent: 56,
      endIndent: 16,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.category_outlined, size: 14, color: cs.primary),
        const SizedBox(width: 6),
        Text(
          'Sections',
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: cs.primary),
        ),
      ],
    );
  }
}

// ── Index tile ────────────────────────────────────────────────────────────────

class _CapabilitiesIndexTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _CapabilitiesIndexTile({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(
                  fontSize: 12,
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant),
            )
          : null,
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }
}
