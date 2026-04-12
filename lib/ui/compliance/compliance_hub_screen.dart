/// Compliance hub screen — status overview + navigation to sub-screens.
/// Route: /robot/:rrn/compliance
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../shared/error_view.dart';
import '../shared/loading_view.dart';
import '../../routes.dart';
import 'compliance_view_model.dart';

class ComplianceHubScreen extends ConsumerWidget {
  final String rrn;
  const ComplianceHubScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(complianceStatusProvider(rrn));
    return Scaffold(
      appBar: AppBar(title: const Text('Compliance')),
      body: statusAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (status) => _HubBody(rrn: rrn, status: status),
      ),
    );
  }
}

class _HubBody extends StatelessWidget {
  final String rrn;
  final ComplianceStatus status;
  const _HubBody({required this.rrn, required this.status});

  Color _statusColor(BuildContext context, String s) => switch (s) {
        'compliant'     => Colors.green,
        'provisional'   => Colors.amber.shade700,
        'non_compliant' => Colors.red,
        _               => Colors.grey,
      };

  String _statusLabel(String s) => switch (s) {
        'compliant'     => 'Compliant',
        'provisional'   => 'Provisional',
        'non_compliant' => 'Non-compliant',
        'no_fria'       => 'No FRIA',
        _               => s,
      };

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status.complianceStatus);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status chip
        Center(
          child: Chip(
            label: Text(
              _statusLabel(status.complianceStatus),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: color,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
        const SizedBox(height: 8),
        if (status.friaSubmittedAt != null)
          Center(
            child: Text(
              'FRIA submitted: ${status.friaSubmittedAt}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        else
          Center(
            child: Text(
              'No FRIA submitted',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
            ),
          ),
        const SizedBox(height: 24),
        // Navigation tiles
        _NavTile(
          icon: Icons.verified_user_outlined,
          title: 'FRIA Document',
          subtitle: 'Fundamental Rights Impact Assessment',
          onTap: () => context.push(AppRoutes.robotComplianceFriaFor(rrn)),
        ),
        _NavTile(
          icon: Icons.speed_outlined,
          title: 'Safety Benchmark',
          subtitle: 'Protocol conformance scores',
          onTap: () => context.push(AppRoutes.robotComplianceBenchmarkFor(rrn)),
        ),
        _NavTile(
          icon: Icons.menu_book_outlined,
          title: 'Instructions for Use',
          subtitle: 'Operator deployment guidelines',
          onTap: () => context.push(AppRoutes.robotComplianceIfuFor(rrn)),
        ),
        _NavTile(
          icon: Icons.report_problem_outlined,
          title: 'Post-Market Incidents',
          subtitle: 'Safety and performance incidents',
          onTap: () => context.push(AppRoutes.robotComplianceIncidentsFor(rrn)),
        ),
        _NavTile(
          icon: Icons.account_balance_outlined,
          title: 'EU Register Entry',
          subtitle: 'High-risk AI systems register',
          onTap: () => context.push(AppRoutes.robotComplianceEuRegisterFor(rrn)),
        ),
      ],
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _NavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
