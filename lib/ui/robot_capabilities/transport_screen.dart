/// Transport sub-screen.
/// Route: /robot/:rrn/capabilities/transport
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../robot_detail/robot_detail_view_model.dart';
import 'capabilities_widgets.dart';

class TransportScreen extends ConsumerWidget {
  final String rrn;
  const TransportScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Transport')),
          body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Transport')),
              body: const Center(child: Text('Robot not found')));
        }
        return _TransportView(robot: robot);
      },
    );
  }
}

class _TransportView extends StatelessWidget {
  final Robot robot;
  const _TransportView({required this.robot});

  @override
  Widget build(BuildContext context) {
    final transports = robot.supportedTransports.map((t) => t.toLowerCase()).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Transport — ${robot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CapSection(
            title: 'Transport',
            icon: Icons.swap_horiz_outlined,
            rows: [
              CapabilityRow(
                label: 'HTTP',
                status: transports.contains('http') ? CapStatus.ok : CapStatus.missing,
                description: 'HTTP/HTTPS transport encoding (GAP-17).',
              ),
              CapabilityRow(
                label: 'COMPACT',
                status: robot.supportsCompactTransport ? CapStatus.ok : CapStatus.missing,
                description: 'Binary compact encoding — bandwidth-efficient (GAP-17).',
              ),
              CapabilityRow(
                label: transports.contains('websocket')
                    ? 'WebSocket'
                    : 'WebSocket: not configured',
                status: transports.contains('websocket') ? CapStatus.ok : CapStatus.info,
                description: 'WebSocket transport for low-latency streaming.',
                actionLabel: 'Learn more ↗',
                actionUrl: AppConstants.rcanSpecUrl,
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
