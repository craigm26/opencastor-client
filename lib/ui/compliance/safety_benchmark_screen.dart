/// Safety Benchmark screen — shows conformance scores from the FRIA document.
/// Route: /robot/:rrn/compliance/benchmark
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/error_view.dart';
import '../shared/loading_view.dart';
import 'compliance_view_model.dart';

class SafetyBenchmarkScreen extends ConsumerWidget {
  final String rrn;
  const SafetyBenchmarkScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friaAsync = ref.watch(friaProvider(rrn));
    return Scaffold(
      appBar: AppBar(title: const Text('Safety Benchmark')),
      body: friaAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (doc) {
          if (doc == null) {
            return const _NoDataView(message: 'No FRIA document submitted — submit a FRIA to see safety benchmark results.');
          }
          final conformance = doc.conformance;
          if (conformance == null) {
            return const _NoDataView(message: 'FRIA submitted but conformance scores have not yet been computed.');
          }
          return _BenchmarkBody(conformance: conformance);
        },
      ),
    );
  }
}

class _NoDataView extends StatelessWidget {
  final String message;
  const _NoDataView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.speed_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _BenchmarkBody extends StatelessWidget {
  final FriaConformance conformance;
  const _BenchmarkBody({required this.conformance});

  @override
  Widget build(BuildContext context) {
    final total = conformance.passCount + conformance.warnCount + conformance.failCount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Overall Score', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: conformance.score.clamp(0.0, 1.0),
                  minHeight: 12,
                  borderRadius: BorderRadius.circular(6),
                  color: conformance.failCount == 0 ? Colors.green : Colors.orange,
                ),
                const SizedBox(height: 8),
                Text(
                  '${(conformance.score * 100).toStringAsFixed(1)}% (${conformance.passCount}/$total checks passed)',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Results', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ResultColumn(
                      label: 'Pass',
                      count: conformance.passCount,
                      icon: Icons.check_circle_outline,
                      color: Colors.green,
                    ),
                    _ResultColumn(
                      label: 'Warn',
                      count: conformance.warnCount,
                      icon: Icons.warning_amber_outlined,
                      color: Colors.amber.shade700,
                    ),
                    _ResultColumn(
                      label: 'Fail',
                      count: conformance.failCount,
                      icon: Icons.cancel_outlined,
                      color: Colors.red,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ResultColumn extends StatelessWidget {
  final String label;
  final int count;
  final IconData icon;
  final Color color;
  const _ResultColumn({
    required this.label,
    required this.count,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 4),
        Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
