/// Gated Providers sub-screen.
/// Route: /robot/:rrn/capabilities/providers
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../robot_detail/robot_detail_view_model.dart';
import '../shared/error_view.dart';
import '../shared/empty_view.dart';
import '../shared/loading_view.dart';
import 'capabilities_widgets.dart';

class ProvidersScreen extends ConsumerWidget {
  final String rrn;
  const ProvidersScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () =>
          const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Gated Providers')),
          body: ErrorView(error: e.toString())),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Gated Providers')),
              body: const EmptyView(title: 'Robot not found'));
        }
        return _ProvidersView(robot: robot);
      },
    );
  }
}

class _ProvidersView extends StatelessWidget {
  final Robot robot;
  const _ProvidersView({required this.robot});

  @override
  Widget build(BuildContext context) {
    final rawProviders =
        capsAsList(robot.telemetry['gated_providers']);
    return Scaffold(
      appBar: AppBar(title: Text('Providers — ${robot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GatedProvidersSection(providers: rawProviders),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
