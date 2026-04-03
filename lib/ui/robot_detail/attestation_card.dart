/// AttestationCard — RCAN v2.1 firmware + SBOM attestation status widget.
/// Used in the robot detail screen to display supply chain compliance.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/robot.dart';

class AttestationCard extends StatelessWidget {
  final Robot robot;
  const AttestationCard({super.key, required this.robot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined,
                    color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text('Supply Chain Attestation',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                _RcanBadge(version: robot.rcanVersion ?? '?'),
              ],
            ),
            const SizedBox(height: 16),
            _AttestRow(
              label: 'Firmware Manifest',
              status: robot.isFirmwareAttested
                  ? _AttestStatus.ok
                  : _AttestStatus.missing,
              detail: robot.isFirmwareAttested
                  ? 'Signed — ${robot.firmwareHash!.substring(0, 20)}…'
                  : 'Run: castor attest generate && castor attest sign',
            ),
            const SizedBox(height: 8),
            _AttestRow(
              label: 'SBOM Published',
              status: robot.isSbomPublished
                  ? _AttestStatus.ok
                  : _AttestStatus.missing,
              detail: robot.isSbomPublished ? robot.attestationRef! : 'Run: castor sbom generate',
              onTap: robot.isSbomPublished
                  ? () => launchUrl(Uri.parse(robot.attestationRef!))
                  : null,
            ),
            const SizedBox(height: 8),
            _AttestRow(
              label: 'Authority Handler',
              status: robot.authorityHandlerEnabled
                  ? _AttestStatus.ok
                  : _AttestStatus.warn,
              detail: robot.authorityHandlerEnabled
                  ? 'Registered — EU AI Act Art. 16(j) ready'
                  : 'Add authority_handler_enabled: true to config',
            ),
            const SizedBox(height: 8),
            _AttestRow(
              label: 'Audit Retention',
              status: (robot.auditRetentionDays ?? 0) >= 3650
                  ? _AttestStatus.ok
                  : _AttestStatus.warn,
              detail: robot.auditRetentionDays != null
                  ? '${robot.auditRetentionDays} days'
                      '${(robot.auditRetentionDays! < 3650) ? ' (need ≥ 3650 for EU AI Act Art. 12)' : ' ✓'}'
                  : 'Not configured — need ≥ 3650 days (EU AI Act Art. 12)',
            ),
            const SizedBox(height: 12),
            _ConformanceLevelBar(level: robot.conformanceLevel),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status enum + row widget
// ---------------------------------------------------------------------------

enum _AttestStatus { ok, warn, missing }

class _AttestRow extends StatelessWidget {
  final String label;
  final _AttestStatus status;
  final String detail;
  final VoidCallback? onTap;

  const _AttestRow({
    required this.label,
    required this.status,
    required this.detail,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (status) {
      _AttestStatus.ok      => const Icon(Icons.check_circle, color: Colors.green, size: 18),
      _AttestStatus.warn    => const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
      _AttestStatus.missing => const Icon(Icons.cancel_outlined, color: Colors.red, size: 18),
    };

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            icon,
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text(detail,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                        decoration: onTap != null ? TextDecoration.underline : null,
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Conformance level progress bar
// ---------------------------------------------------------------------------

class _ConformanceLevelBar extends StatelessWidget {
  final int level; // 1–5
  const _ConformanceLevelBar({required this.level});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final levelColor = switch (level) {
      5 => Colors.green,
      4 => Colors.lightGreen,
      3 => Colors.orange,
      _ => Colors.red,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Conformance Level',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: levelColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: levelColor.withValues(alpha: 0.5)),
              ),
              child: Text('L$level',
                  style: TextStyle(
                      fontSize: 12, color: levelColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: level / 5.0,
            minHeight: 6,
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(levelColor),
          ),
        ),
        if (level < 5) ...[
          const SizedBox(height: 4),
          Text(
            _nextLevelHint(level),
            style: TextStyle(fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ],
    );
  }

  String _nextLevelHint(int current) => switch (current) {
    1 => 'L2: Enable RCAN v2.1 + signed RURI',
    2 => 'L3: Enable ESTOP QoS2 + replay protection',
    3 => 'L4: Run castor attest + castor sbom',
    4 => 'L5: Enable authority handler + 10yr audit retention (EU AI Act)',
    _ => '',
  };
}

// ---------------------------------------------------------------------------
// RCAN version badge
// ---------------------------------------------------------------------------

class _RcanBadge extends StatelessWidget {
  final String version;
  const _RcanBadge({required this.version});

  @override
  Widget build(BuildContext context) {
    final isV21 = version.startsWith('2.1') || version.startsWith('2.');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isV21
            ? Colors.green.withValues(alpha: 0.1)
            : Colors.orange.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: isV21
                ? Colors.green.withValues(alpha: 0.5)
                : Colors.orange.withValues(alpha: 0.5)),
      ),
      child: Text(
        'RCAN $version',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: isV21 ? Colors.green : Colors.orange,
        ),
      ),
    );
  }
}
