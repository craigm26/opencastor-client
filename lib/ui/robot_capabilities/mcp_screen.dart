/// MCP screen — shows registered MCP clients and their LoA tier.
/// Reached from /robot/:rrn/capabilities/mcp
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../robot_detail/robot_detail_view_model.dart';
import '../shared/error_view.dart';
import '../shared/loading_view.dart';

class McpScreen extends ConsumerWidget {
  final String rrn;
  const McpScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final robotAsync = ref.watch(robotDetailProvider(rrn));

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('MCP Clients'),
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: robotAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (robot) => _McpBody(rrn: rrn),
      ),
    );
  }
}

class _McpBody extends StatelessWidget {
  final String rrn;
  const _McpBody({required this.rrn});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('robots').doc(rrn).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() as Map<String, dynamic>?;
        final clients = (data?['mcp_clients'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.hub_outlined, size: 20, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Model Context Protocol',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Any AI agent with a token can use these tools. '
                          'Access level is set per token, not per model.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Client list
            if (clients.isEmpty) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cs.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.key_off_outlined, size: 28, color: cs.onSurfaceVariant),
                    const SizedBox(height: 8),
                    Text(
                      'No MCP clients registered',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Add tokens in bob.rcan.yaml:\n'
                      'castor mcp token --name NAME --loa N',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                '${clients.length} registered client${clients.length == 1 ? '' : 's'}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              ...clients.map((c) => _ClientTile(client: c)),
            ],

            const SizedBox(height: 24),
            // CLI quick-ref
            _CliCard(),
          ],
        );
      },
    );
  }
}

class _ClientTile extends StatelessWidget {
  final Map<String, dynamic> client;
  const _ClientTile({required this.client});

  static const _loaColors = {
    0: Color(0xFF6b7280), // grey — read-only
    1: Color(0xFF0ea5e9), // sky — operate
    3: Color(0xFFf59e0b), // amber — admin
  };

  static const _loaLabels = {0: 'Read', 1: 'Operate', 3: 'Admin'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final loa = client['loa'] as int? ?? 0;
    final color = _loaColors[loa] ?? const Color(0xFF6b7280);
    final label = _loaLabels[loa] ?? 'LoA $loa';
    final hash = (client['token_hash'] as String? ?? '').replaceFirst('sha256:', '');
    final shortHash = hash.length > 12 ? '${hash.substring(0, 12)}…' : hash;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.vpn_key_outlined, size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    client['name'] as String? ?? 'unnamed',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'sha256:$shortHash',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CliCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Quick reference',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          _cliLine('Generate token', 'castor mcp token --name NAME --loa 1', context),
          _cliLine('List clients', 'castor mcp clients', context),
          _cliLine('Start server', 'castor mcp --token \$TOKEN', context),
          _cliLine('Add to Claude Code', 'castor mcp install --client claude', context),
        ],
      ),
    );
  }

  Widget _cliLine(String label, String cmd, BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              cmd,
              style: theme.textTheme.labelSmall?.copyWith(
                fontFamily: 'JetBrains Mono',
                color: cs.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
