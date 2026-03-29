/// Compliance Report Screen — EU AI Act compliance report export (JSON).
/// Route: /robot/:rrn/compliance-report
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/robot.dart';
import '../robot_detail/robot_detail_view_model.dart';
import '../core/theme/app_theme.dart';

class ComplianceReportScreen extends ConsumerWidget {
  final String rrn;
  const ComplianceReportScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Compliance Report')),
        body: Center(child: Text('Error: $e')),
      ),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Compliance Report')),
            body: const Center(child: Text('Robot not found')),
          );
        }
        return _ComplianceReportView(robot: robot);
      },
    );
  }
}

class _ComplianceReportView extends StatelessWidget {
  final Robot robot;
  const _ComplianceReportView({required this.robot});

  Map<String, dynamic> _buildReport() {
    final level = robot.conformanceLevel;
    final checks = [
      {
        'id':     'firmware_manifest',
        'status': robot.isFirmwareAttested ? 'pass' : 'warn',
        'detail': robot.isFirmwareAttested
            ? 'Firmware manifest present and signed'
            : 'No firmware manifest — run: castor attest generate && castor attest sign',
      },
      {
        'id':     'sbom_attestation',
        'status': robot.isSbomPublished ? 'pass' : 'warn',
        'detail': robot.isSbomPublished
            ? 'SBOM published at ${robot.attestationRef}'
            : 'No SBOM — run: castor sbom generate && castor sbom publish',
      },
      {
        'id':     'authority_handler',
        'status': robot.authorityHandlerEnabled ? 'pass' : 'warn',
        'detail': robot.authorityHandlerEnabled
            ? 'AUTHORITY_ACCESS (41) handler registered'
            : 'Authority handler not enabled — add authority_handler_enabled: true',
      },
      {
        'id':     'audit_retention',
        'status': (robot.auditRetentionDays ?? 0) >= 3650 ? 'pass' : 'warn',
        'detail': robot.auditRetentionDays != null
            ? 'Audit retention: ${robot.auditRetentionDays} days'
            : 'Audit retention not configured — need ≥ 3650 days (EU AI Act Art. 12)',
      },
      {
        'id':     'rcan_version',
        'status': robot.isRcanV21 ? 'pass' : 'fail',
        'detail': 'RCAN version: ${robot.rcanVersion ?? 'unknown'}',
      },
    ];

    final statuses = checks.map((c) => c['status'] as String).toList();
    final overall = statuses.contains('fail')
        ? 'non_compliant'
        : statuses.contains('warn')
            ? 'partial'
            : 'compliant';

    return {
      'report_type':    'eu_ai_act_compliance',
      'generated_at':   DateTime.now().toIso8601String(),
      'deadline':       '2026-08-02',
      'rrn':            robot.rrn,
      'robot_name':     robot.name,
      'rcan_version':   robot.rcanVersion ?? 'unknown',
      'conformance_level': level,
      'overall_status': overall,
      'checks':         checks,
      'eu_ai_act_mapping': [
        {'article': 'Art. 16(a)', 'provision': '§12 SBOM',
         'status': robot.isSbomPublished ? 'pass' : 'warn'},
        {'article': 'Art. 16(d)', 'provision': '§11 Firmware Manifest',
         'status': robot.isFirmwareAttested ? 'pass' : 'warn'},
        {'article': 'Art. 12',   'provision': '§16 Audit Chain Retention',
         'status': (robot.auditRetentionDays ?? 0) >= 3650 ? 'pass' : 'warn'},
        {'article': 'Art. 16(j)', 'provision': '§13 Authority Access',
         'status': robot.authorityHandlerEnabled ? 'pass' : 'warn'},
      ],
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final report = _buildReport();
    final overall = report['overall_status'] as String;
    final statusColor = switch (overall) {
      'compliant'     => Colors.green,
      'partial'       => Colors.orange,
      _               => Colors.red,
    };
    final prettyJson = const JsonEncoder.withIndent('  ').convert(report);

    return Scaffold(
      appBar: AppBar(
        title: const Text('EU AI Act Compliance Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy JSON',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: prettyJson));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Report copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Overall status
          Card(
            color: statusColor.withValues(alpha: 0.08),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    overall == 'compliant'
                        ? Icons.verified
                        : overall == 'partial'
                            ? Icons.warning_amber
                            : Icons.dangerous,
                    color: statusColor,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        overall == 'compliant'
                            ? 'EU AI Act Compliant'
                            : overall == 'partial'
                                ? 'Partial Compliance'
                                : 'Non-Compliant',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: statusColor),
                      ),
                      Text(
                        'Conformance Level: L${report['conformance_level']}  •  Deadline: ${report['deadline']}',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Article mapping
          Text('EU AI Act Article Mapping',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...((report['eu_ai_act_mapping'] as List).map((item) {
            final m = item as Map<String, dynamic>;
            final isPass = m['status'] == 'pass';
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(isPass ? Icons.check_circle : Icons.warning_amber,
                      color: isPass ? Colors.green : Colors.orange, size: 16),
                  const SizedBox(width: 8),
                  Text('${m['article']}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 4),
                  Text(m['provision'] as String,
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.7))),
                ],
              ),
            );
          })),

          const SizedBox(height: 16),

          // JSON output
          Text('Full JSON Report',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              prettyJson,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
