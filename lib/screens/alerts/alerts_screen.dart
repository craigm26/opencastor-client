import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/robot.dart';
import '../../services/robot_service.dart';
import '../../theme/app_theme.dart';

final _svcProvider = Provider((_) => RobotService());
final _fleetProvider2 = StreamProvider<List<Robot>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  return ref.read(_svcProvider).watchFleet(uid);
});
final _alertsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, rrn) {
  return ref.read(_svcProvider).watchAlerts(rrn);
});

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleetAsync = ref.watch(_fleetProvider2);

    return Scaffold(
      appBar: AppBar(title: const Text('Alerts')),
      body: fleetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (robots) {
          if (robots.isEmpty) {
            return const Center(child: Text('No robots in fleet.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: robots
                .map((r) => _RobotAlerts(robot: r))
                .toList(),
          );
        },
      ),
    );
  }
}

class _RobotAlerts extends ConsumerWidget {
  final Robot robot;
  const _RobotAlerts({required this.robot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(_alertsProvider(robot.rrn));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(robot.name,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.bold)),
        ),
        alertsAsync.when(
          loading: () => const LinearProgressIndicator(),
          error: (_, __) => const SizedBox.shrink(),
          data: (alerts) {
            if (alerts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text('No alerts',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12)),
              );
            }
            return Column(
              children: alerts
                  .map((a) => _AlertTile(alert: a))
                  .toList(),
            );
          },
        ),
        const Divider(),
      ],
    );
  }
}

class _AlertTile extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final type = alert['type'] as String? ?? 'UNKNOWN';
    final reason = alert['reason'] as String? ?? '';
    final firedAt = alert['fired_at'] != null
        ? DateTime.tryParse(alert['fired_at'] as String)
        : null;

    final isEstop = type == 'ESTOP';
    final color = isEstop ? AppTheme.estop : AppTheme.warning;
    final icon = isEstop ? Icons.stop_circle_outlined : Icons.warning_amber_outlined;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color, size: 20),
        title: Text(type,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 13)),
        subtitle: reason.isNotEmpty ? Text(reason, style: const TextStyle(fontSize: 12)) : null,
        trailing: firedAt != null
            ? Text(timeago.format(firedAt),
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant))
            : null,
      ),
    );
  }
}
