/// FRIA document viewer screen.
/// Route: /robot/:rrn/compliance/fria
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/error_view.dart';
import '../shared/loading_view.dart';
import 'compliance_view_model.dart';

class FriaScreen extends ConsumerWidget {
  final String rrn;
  const FriaScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friaAsync = ref.watch(friaProvider(rrn));
    return Scaffold(
      appBar: AppBar(title: const Text('FRIA Document')),
      body: friaAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (doc) => doc == null
            ? const _NoFriaView()
            : _FriaBody(doc: doc),
      ),
    );
  }
}

class _NoFriaView extends StatelessWidget {
  const _NoFriaView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.description_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'No FRIA submitted',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Submit a FRIA document via the rcan.dev API to enable compliance tracking.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _FriaBody extends StatelessWidget {
  final FriaDocument doc;
  const _FriaBody({required this.doc});

  @override
  Widget build(BuildContext context) {
    final system = doc.system;
    final deployment = doc.deployment;
    final conformance = doc.conformance;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SectionCard(
          title: 'Document',
          children: [
            _Row('Schema', doc.schema),
            _Row('Generated', doc.generatedAt),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Robot System',
          children: [
            if (system['rrn'] != null) _Row('RRN', system['rrn'].toString()),
            if (system['robot_name'] != null) _Row('Name', system['robot_name'].toString()),
            if (system['rcan_version'] != null) _Row('RCAN', system['rcan_version'].toString()),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Deployment',
          children: [
            if (deployment['annex_iii_basis'] != null)
              _Row('Annex III basis', deployment['annex_iii_basis'].toString()),
            _Row(
              'Prerequisite waived',
              (deployment['prerequisite_waived'] == true) ? 'Yes' : 'No',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Signing Key',
          children: [
            _Row('Algorithm', (doc.signingKey['alg'] ?? '—').toString()),
            _Row('Key ID', (doc.signingKey['kid'] ?? '—').toString()),
          ],
        ),
        if (conformance != null) ...[
          const SizedBox(height: 12),
          _ConformanceCard(conformance: conformance),
        ] else ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Conformance scores not yet computed.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _ConformanceCard extends StatelessWidget {
  final FriaConformance conformance;
  const _ConformanceCard({required this.conformance});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Conformance', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: conformance.score.clamp(0.0, 1.0),
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 8),
            Text(
              '${(conformance.score * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _CountChip(label: 'Pass', count: conformance.passCount, color: Colors.green),
                _CountChip(label: 'Warn', count: conformance.warnCount, color: Colors.amber.shade700),
                _CountChip(label: 'Fail', count: conformance.failCount, color: Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _CountChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 18)),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const Divider(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
          ),
          Expanded(child: Text(value, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}
