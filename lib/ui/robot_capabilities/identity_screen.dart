/// Identity & Registry sub-screen.
/// Route: /robot/:rrn/capabilities/identity
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../robot_detail/robot_detail_view_model.dart';
import '../shared/error_view.dart';
import '../shared/empty_view.dart';
import '../shared/loading_view.dart';
import 'capabilities_widgets.dart';

class IdentityScreen extends ConsumerWidget {
  final String rrn;
  const IdentityScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Identity & Registry')),
          body: ErrorView(error: e.toString())),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Identity & Registry')),
              body: const EmptyView(title: 'Robot not found'));
        }
        return _IdentityView(robot: robot);
      },
    );
  }
}

class _IdentityView extends StatelessWidget {
  final Robot robot;
  const _IdentityView({required this.robot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Identity — ${robot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CapSection(
            title: 'Identity & Registry',
            icon: Icons.badge_outlined,
            rows: [
              CapabilityRow(
                label: capRegistryTierLabel(robot.registryTier),
                status: CapStatus.ok,
                description:
                    'Registered in the ${robot.registryTier} tier registry.',
                actionLabel: 'Upgrade to Verified ↗',
                actionUrl: AppConstants.rrfOpencastorUrl,
              ),
              CapabilityRow(
                label: robot.rcanVersion != null
                    ? 'RCAN v${robot.rcanVersion}'
                    : 'RCAN version unknown',
                status: robot.rcanVersion != null
                    ? CapStatus.ok
                    : CapStatus.missing,
                description:
                    'RCAN protocol version reported by the bridge.',
              ),
              CapabilityRow(
                label: robot.rrn.isNotEmpty ? 'RRN assigned' : 'No RRN',
                status: robot.rrn.isNotEmpty
                    ? CapStatus.ok
                    : CapStatus.missing,
                description: robot.rrn.isNotEmpty
                    ? 'Robot Resource Name: ${robot.rrn}'
                    : 'Robot has no assigned RRN.',
              ),
              CapabilityRow(
                label: 'RURI',
                status: robot.ruri.isNotEmpty ? CapStatus.ok : CapStatus.missing,
                description: robot.ruri.isNotEmpty ? robot.ruri : 'No RURI assigned',
                trailing: robot.ruri.isNotEmpty ? IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  onPressed: () => Clipboard.setData(ClipboardData(text: robot.ruri)),
                  tooltip: 'Copy RURI',
                ) : null,
              ),
              CapabilityRow(
                label: 'Revocation',
                status: robot.revocationStatus == RevocationStatus.active
                    ? CapStatus.ok
                    : robot.revocationStatus == RevocationStatus.suspended
                        ? CapStatus.warning
                        : CapStatus.missing,
                description: robot.revocationStatus.name.toUpperCase(),
              ),
              if (robot.pqKid != null && robot.pqKid!.isNotEmpty)
                CapabilityRow(
                  label: 'PQ Key',
                  status: CapStatus.ok,
                  description: 'kid: ${robot.pqKid!.length > 8 ? robot.pqKid!.substring(robot.pqKid!.length - 8) : robot.pqKid!}',
                ),
              CapabilityRow(
                label: 'Offline Mode',
                status: robot.offlineCapable ? CapStatus.ok : CapStatus.info,
                description: robot.offlineCapable ? 'Cached credentials available' : 'Requires network connectivity',
              ),
              if (robot.firmwareHash != null && robot.firmwareHash!.isNotEmpty)
                CapabilityRow(
                  label: 'Firmware Hash',
                  status: CapStatus.ok,
                  description: '${robot.firmwareHash!.substring(0, 16)}…',
                  trailing: IconButton(
                    icon: const Icon(Icons.copy, size: 16),
                    onPressed: () => Clipboard.setData(ClipboardData(text: robot.firmwareHash!)),
                    tooltip: 'Copy full hash',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
