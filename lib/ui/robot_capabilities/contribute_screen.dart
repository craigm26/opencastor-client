/// Contribute sub-screen (capabilities area).
/// Distinct from fleet_contribute_screen.dart — this is the robot-specific
/// contribute settings reachable from /robot/:rrn/capabilities/contribute.
/// Route: /robot/:rrn/capabilities/contribute
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../robot_detail/robot_detail_view_model.dart';
import 'contribute_history_view.dart';
import 'contribute_section.dart';
import 'contribute_settings_view.dart';

class CapContributeScreen extends ConsumerWidget {
  final String rrn;
  const CapContributeScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Contribute')),
          body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Contribute')),
              body: const Center(child: Text('Robot not found')));
        }
        return Scaffold(
          appBar:
              AppBar(title: Text('Contribute — ${robot.name}')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              ContributeSection(stats: robot.contribute),
              const SizedBox(height: 12),
              ContributeSettingsView(robot: robot),
              const SizedBox(height: 12),
              ContributeHistoryView(rrn: robot.rrn),
              const SizedBox(height: 32),
            ],
          ),
        );
      },
    );
  }
}
