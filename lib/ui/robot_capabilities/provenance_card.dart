/// ProvenanceCard — RCAN v2.2 §21 entity provenance chain.
/// Shows the full RRF registration chain for a robot:
///   RRN (robot) → RCNs (components) → RMNs (AI models) → RHN (harness)
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/robot.dart';
import '../core/theme/app_theme.dart';

class ProvenanceCard extends StatelessWidget {
  final Robot robot;
  const ProvenanceCard({super.key, required this.robot});

  static const _rrfBase = 'https://robotregistryfoundation.org';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rrrn   = robot.rrn;
    final rrcns  = robot.rrfRcns;
    final rrmns  = robot.rrfRmns;
    final rrhn   = robot.rrfRhn;
    // Harness display name from telemetry (if available)
    final harness = robot.telemetry['harness'] as Map<String, dynamic>?;

    final hasProvenance = rrcns.isNotEmpty || rrmns.isNotEmpty || rrhn != null;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.account_tree_outlined, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text('RRF Provenance Chain',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                _RcanSpecBadge(version: robot.rcanVersion ?? '2.2'),
              ],
            ),
            const SizedBox(height: 4),
            Text('RCAN v2.2 §21 — registry.opencastor.com',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant)),

            if (!hasProvenance) ...[
              const SizedBox(height: 12),
              Text('Not registered with RRF yet.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 4),
              Text('Run: castor rrf register --config bob.rcan.yaml',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: cs.onSurfaceVariant)),
            ] else ...[
              const SizedBox(height: 12),

              // Robot (RRN)
              _ProvenanceRow(
                icon: '🤖',
                label: 'Robot',
                id: rrrn,
                color: cs.primary,
                onTap: () => launchUrl(
                    Uri.parse('$_rrfBase/registry/entity/?type=robot&id=$rrrn')),
              ),

              // Components (RCN)
              if (rrcns.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Components (${rrcns.length})',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ...rrcns.map((rcn) => _ProvenanceRow(
                      icon: '🔌',
                      label: 'Component',
                      id: rcn,
                      color: const Color(0xFF22D3EE), // cyan-400
                      indent: true,
                      onTap: () => launchUrl(Uri.parse(
                          '$_rrfBase/registry/entity/?type=component&id=$rcn')),
                    )),
              ],

              // AI Models (RMN)
              if (rrmns.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('AI Models (${rrmns.length})',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ...rrmns.map((rmn) => _ProvenanceRow(
                      icon: '🧠',
                      label: 'Model',
                      id: rmn,
                      color: const Color(0xFFA78BFA), // purple-400
                      indent: true,
                      onTap: () => launchUrl(Uri.parse(
                          '$_rrfBase/registry/entity/?type=model&id=$rmn')),
                    )),
              ],

              // AI Harness (RHN)
              if (rrhn != null) ...[
                const SizedBox(height: 8),
                Text('AI Harness',
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                _ProvenanceRow(
                  icon: '⚙️',
                  label: harness?['name'] as String? ?? 'Harness',
                  id: rrhn,
                  color: const Color(0xFFFBBF24), // yellow-400
                  indent: true,
                  onTap: () => launchUrl(Uri.parse(
                      '$_rrfBase/registry/entity/?type=harness&id=$rrhn')),
                ),
              ],

              const SizedBox(height: 12),
              // View full chain link
              InkWell(
                onTap: () =>
                    launchUrl(Uri.parse('$_rrfBase/registry/')),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.open_in_new,
                          size: 14, color: cs.primary),
                      const SizedBox(width: 4),
                      Text('View full registry',
                          style: TextStyle(
                              fontSize: 12,
                              color: cs.primary,
                              decoration: TextDecoration.underline)),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Provenance row ─────────────────────────────────────────────────────────

class _ProvenanceRow extends StatelessWidget {
  final String icon;
  final String label;
  final String id;
  final Color color;
  final bool indent;
  final VoidCallback? onTap;

  const _ProvenanceRow({
    required this.icon,
    required this.label,
    required this.id,
    required this.color,
    this.indent = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: indent ? 12 : 0, bottom: 3),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(id,
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color)),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.open_in_new, size: 10, color: color.withValues(alpha: 0.7)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── RCAN spec badge ────────────────────────────────────────────────────────

class _RcanSpecBadge extends StatelessWidget {
  final String version;
  const _RcanSpecBadge({required this.version});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isV22 = version.startsWith('2.2') || version.startsWith('2.2.0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: isV22
            ? const Color(0xFF059669).withValues(alpha: 0.15)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
            color: isV22
                ? const Color(0xFF059669).withValues(alpha: 0.4)
                : cs.outline),
      ),
      child: Text(
        'RCAN $version',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: isV22 ? const Color(0xFF059669) : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}
