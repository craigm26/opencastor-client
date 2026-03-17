/// Robot Status Screen — full telemetry and RCAN status for a single robot.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/models/robot.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/health_indicator.dart';
import '../robot_detail/robot_detail_view_model.dart';
import '../../core/constants.dart';

class RobotStatusScreen extends ConsumerWidget {
  final String rrn;
  const RobotStatusScreen({super.key, required this.rrn});

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
        return _StatusView(robot: robot);
      },
    );
  }
}

class _StatusView extends StatelessWidget {
  final Robot robot;
  const _StatusView({required this.robot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('Status — ${robot.name}'),
        actions: [
          HealthIndicator(isOnline: robot.isOnline, size: 8),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'RCAN Docs',
            onPressed: () =>
                launchUrl(Uri.parse(AppConstants.docsFleetUi)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Online status ──────────────────────────────────────────────────
          _SectionHeader('Connection Status'),
          _StatusCard(
            children: [
              _StatusRow(
                label: 'Status',
                value: robot.isOnline ? 'Online' : 'Offline',
                valueColor: AppTheme.onlineColor(robot.isOnline),
                icon: robot.isOnline
                    ? Icons.wifi_outlined
                    : Icons.wifi_off_outlined,
              ),
              _StatusRow(
                label: 'Last seen',
                value: _fmtDateTime(robot.status.lastSeen),
              ),
              if (robot.status.error != null)
                _StatusRow(
                  label: 'Last error',
                  value: robot.status.error!,
                  valueColor: AppTheme.danger,
                ),
              _StatusRow(
                label: 'Revocation',
                value: robot.revocationStatus.name.toUpperCase(),
                valueColor: robot.revocationStatus == RevocationStatus.active
                    ? AppTheme.online
                    : AppTheme.danger,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Identity ───────────────────────────────────────────────────────
          _SectionHeader('Identity'),
          _StatusCard(
            children: [
              _StatusRow(label: 'Name', value: robot.name),
              _StatusRow(label: 'RRN', value: robot.rrn, mono: true),
              _StatusRow(label: 'RURI', value: robot.ruri, mono: true),
              _StatusRow(label: 'Owner UID', value: robot.firebaseUid, mono: true),
              _StatusRow(
                  label: 'Registered',
                  value: _fmtDate(robot.registeredAt)),
              if (robot.opencastorVersion != null)
                _StatusRow(
                    label: 'OpenCastor',
                    value: 'v${robot.opencastorVersion}'),
              _StatusRow(
                  label: 'Bridge', value: robot.bridgeVersion, mono: true),
              _StatusRow(
                  label: 'Registry Tier', value: robot.registryTier),
            ],
          ),
          const SizedBox(height: 16),

          // ── RCAN ──────────────────────────────────────────────────────────
          _SectionHeader('RCAN Protocol'),
          _StatusCard(
            children: [
              _StatusRow(
                  label: 'RCAN Version',
                  value: robot.rcanVersion ?? 'Unknown'),
              _StatusRow(
                  label: 'RCAN v1.5',
                  value: robot.isRcanV15 ? 'Supported' : 'Not supported',
                  valueColor:
                      robot.isRcanV15 ? AppTheme.online : cs.onSurfaceVariant),
              _StatusRow(
                  label: 'RCAN v1.6',
                  value: robot.isRcanV16 ? 'Supported' : 'Not supported',
                  valueColor:
                      robot.isRcanV16 ? AppTheme.online : cs.onSurfaceVariant),
              _StatusRow(
                label: 'Transports',
                value: robot.supportedTransports.join(', ').toUpperCase(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Telemetry ──────────────────────────────────────────────────────
          if (robot.telemetry.isNotEmpty) ...[
            _SectionHeader('Telemetry'),
            _StatusCard(
              children: robot.telemetry.entries
                  .map((e) => _StatusRow(
                        label: e.key,
                        value: e.value?.toString() ?? 'null',
                        mono: true,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  String _fmtDateTime(DateTime dt) =>
      DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());

  String _fmtDate(DateTime dt) => DateFormat('yyyy-MM-dd').format(dt.toLocal());
}

// ── Widgets ───────────────────────────────────────────────────────────────────

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

class _StatusCard extends StatelessWidget {
  final List<Widget> children;
  const _StatusCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(children: children),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool mono;
  final IconData? icon;

  const _StatusRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.mono = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: valueColor ?? cs.onSurfaceVariant),
            const SizedBox(width: 6),
          ],
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: (mono ? AppTheme.mono : const TextStyle())
                  .copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: valueColor ?? cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
