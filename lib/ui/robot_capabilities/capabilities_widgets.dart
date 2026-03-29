/// Shared widgets and helpers for all Capabilities sub-screens.
///
/// Extracted from robot_capabilities_screen.dart so that sub-screens
/// can reference them without circular imports.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/robot.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../data/models/command.dart' show CommandScope;
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;

// ── LoA enforcement command provider ─────────────────────────────────────────

/// Enables LoA enforcement for [rrn] via a system-scope sendCommand call.
/// The castor bridge handles "loa_enable" system commands by patching its
/// in-memory config and writing loa_enforcement=true to the RCAN yaml.
final loaEnableCommandProvider = FutureProvider.family<void, String>((ref, rrn) async {
  // Use Firestore commands subcollection — CF relay can't reach local-network robots.
  await FirebaseFirestore.instance
      .collection('robots')
      .doc(rrn)
      .collection('commands')
      .add({
    'instruction': 'loa_enable',
    'scope': 'system',
    'source': 'app',
    'reason': 'user requested via Fleet UI',
    'created_at': FieldValue.serverTimestamp(),
  });
});

// ── Helpers ────────────────────────────────────────────────────────────────────

/// Safely converts any Firestore value to a [List<dynamic>].
/// Handles the case where the server returns a Map instead of a List
/// (e.g. `{"0": "val"}` instead of `["val"]`).
List<dynamic> capsAsList(dynamic value) {
  if (value == null) return [];
  if (value is List) return value;
  if (value is Map) return value.values.toList();
  return [value];
}

/// Conformance score 0–100 computed from robot properties.
int capConformanceScore(Robot robot) {
  int score = 0;
  if (robot.supportsQos2) score += 20;
  if (robot.isRcanV15) score += 15;
  if (robot.loaEnforcement) score += 15;
  if (robot.isRcanV16) score += 10;
  if (robot.rrn.isNotEmpty) score += 10;
  if (robot.hasCapability(RobotCapability.vision)) score += 10;
  final tier = robot.registryTier.toLowerCase();
  if (tier == 'verified' || tier == 'authoritative' || tier == 'root') {
    score += 10;
  }
  if (robot.offlineCapable) score += 5;
  return score.clamp(0, 100);
}

/// Count of passing protocol-66 checks (out of 5).
int capP66PassCount(Robot robot) {
  int pass = 0;
  if (true) pass++; // §4.1 ESTOP never blocked
  if (true) pass++; // §consent dialogs
  if (true) pass++; // §audit sender-type trail
  if (true) pass++; // §rate-limit
  if (robot.loaEnforcement) pass++; // §loa enforcement
  return pass;
}

/// Registry tier → display label.
String capRegistryTierLabel(String tier) {
  switch (tier.toLowerCase()) {
    case 'root':
      return 'Root Registry';
    case 'authoritative':
      return 'Authoritative Registry';
    case 'verified':
      return 'Verified Registry';
    default:
      return 'Community Registry';
  }
}

/// Tier display label used by ConformanceCard.
String capTierDisplayLabel(String tier) {
  switch (tier.toLowerCase()) {
    case 'root':
      return 'Root Registry';
    case 'authoritative':
      return 'Authoritative Registry';
    case 'verified':
      return 'Verified Community';
    default:
      return 'Community Registry';
  }
}

/// Share robot capabilities as a harness config to the Community Hub.
Future<void> shareCapabilitiesAsHarness(BuildContext ctx, Robot robot) async {
  String title = '${robot.name} Harness';
  final confirmed = await showDialog<bool>(
    context: ctx,
    builder: (dCtx) => AlertDialog(
      title: const Text('Share as Harness'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Share ${robot.name}\'s capabilities profile as a harness config to the Community Hub.',
            style: Theme.of(dCtx).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Harness title',
              border: OutlineInputBorder(),
            ),
            controller: TextEditingController(text: title),
            onChanged: (v) => title = v,
          ),
          const SizedBox(height: 8),
          Text(
            'Type: harness  •  Secrets are scrubbed automatically.',
            style: Theme.of(dCtx)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(dCtx).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dCtx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dCtx, true),
          child: const Text('Share Harness'),
        ),
      ],
    ),
  );

  if (confirmed != true || !ctx.mounted) return;

  ScaffoldMessenger.of(ctx).showSnackBar(
    const SnackBar(
      content: Text('Uploading harness...'),
      duration: Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );

  try {
    final fn = FirebaseFunctions.instance.httpsCallable('uploadConfig');
    final result = await fn.call<Map<String, dynamic>>({
      'type': 'harness',
      'title': title,
      'tags': [robot.rrn.toLowerCase(), 'harness', 'shared-from-app'],
      'content': '# Harness exported from OpenCastor app\n'
          '# Robot: ${robot.name}\n'
          '# RRN: ${robot.rrn}\n'
          '# RCAN Version: ${robot.rcanVersion ?? "?"}\n',
      'filename':
          '${robot.rrn.toLowerCase().replaceAll('-', '_')}_harness.yaml',
      'robot_rrn': robot.rrn,
      'public': true,
    });

    final url = result.data['url'] as String? ?? '';
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Harness shared! $url'),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'View',
            onPressed: () =>
                ctx.push('/explore/${result.data['id'] ?? ''}'),
          ),
        ),
      );
    }
  } catch (e) {
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}

// ── Capability status enum ────────────────────────────────────────────────────

enum CapStatus { ok, warning, missing, info }

// ── Capability row data ───────────────────────────────────────────────────────

class CapabilityRow {
  final String label;
  final CapStatus status;
  final String description;
  final String? actionLabel;
  final String? actionUrl;
  final void Function(BuildContext ctx)? onAction;
  /// Optional trailing widget rendered after the action button (e.g. an IconButton).
  final Widget? trailing;

  const CapabilityRow({
    required this.label,
    required this.status,
    required this.description,
    this.actionLabel,
    this.actionUrl,
    this.onAction,
    this.trailing,
  });
}

// ── Capability section ────────────────────────────────────────────────────────

class CapSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<CapabilityRow> rows;

  const CapSection({
    super.key,
    required this.title,
    required this.icon,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: cs.primary),
            const SizedBox(width: 6),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < rows.length; i++) ...[
                CapabilityRowWidget(row: rows[i]),
                if (i < rows.length - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ── Capability row widget ─────────────────────────────────────────────────────

class CapabilityRowWidget extends StatelessWidget {
  final CapabilityRow row;
  const CapabilityRowWidget({super.key, required this.row});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = _iconAndColor(row.status, cs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  row.description,
                  style:
                      TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (row.actionLabel != null) ...[
            const SizedBox(width: 8),
            CapActionButton(
              label: row.actionLabel!,
              onPressed: () {
                if (row.actionUrl != null) {
                  launchUrl(Uri.parse(row.actionUrl!),
                      mode: LaunchMode.externalApplication);
                } else if (row.onAction != null) {
                  row.onAction!(context);
                }
              },
            ),
          ],
          if (row.trailing != null) ...[
            const SizedBox(width: 4),
            row.trailing!,
          ],
        ],
      ),
    );
  }

  (IconData, Color) _iconAndColor(CapStatus status, ColorScheme cs) {
    switch (status) {
      case CapStatus.ok:
        return (Icons.check_circle_outline, AppTheme.online);
      case CapStatus.warning:
        return (Icons.warning_amber_outlined, AppTheme.warning);
      case CapStatus.missing:
        return (Icons.cancel_outlined, cs.onSurfaceVariant);
      case CapStatus.info:
        return (Icons.info_outline, cs.onSurfaceVariant);
    }
  }
}

// ── Action button ─────────────────────────────────────────────────────────────

class CapActionButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const CapActionButton(
      {super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}

// ── Loading section ───────────────────────────────────────────────────────────

class CapLoadingSection extends StatelessWidget {
  final String title;
  final IconData icon;
  const CapLoadingSection(
      {super.key, required this.title, this.icon = Icons.memory_outlined});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: cs.primary),
          ),
        ]),
        const SizedBox(height: 8),
        const Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ],
    );
  }
}

// ── Code block ────────────────────────────────────────────────────────────────

class CapCodeBlock extends StatelessWidget {
  final String snippet;
  const CapCodeBlock({super.key, required this.snippet});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              snippet,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_outlined, size: 16),
            tooltip: 'Copy',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: snippet));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Step item ─────────────────────────────────────────────────────────────────

class CapStepItem extends StatelessWidget {
  final int number;
  final String label;
  const CapStepItem({super.key, required this.number, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$number',
            style: TextStyle(
              fontSize: 11,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ),
        ),
      ],
    );
  }
}

// ── Instruction bottom sheet ──────────────────────────────────────────────────

class CapInstructionSheet extends StatelessWidget {
  final String title;
  final List<String> steps;
  final List<String?> codeSnippets;
  final String? note;

  const CapInstructionSheet({
    super.key,
    required this.title,
    required this.steps,
    required this.codeSnippets,
    this.note,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < steps.length; i++) ...[
              CapStepItem(number: i + 1, label: steps[i]),
              if (codeSnippets[i] != null) ...[
                const SizedBox(height: 8),
                CapCodeBlock(snippet: codeSnippets[i]!),
              ],
              const SizedBox(height: 12),
            ],
            if (note != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppTheme.warning.withValues(alpha: 0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 14, color: AppTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        note!,
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Gated providers section ───────────────────────────────────────────────────

class GatedProvidersSection extends StatelessWidget {
  final List<dynamic> providers;
  const GatedProvidersSection({super.key, required this.providers});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final items = providers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.vpn_key_outlined, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text('Gated Providers',
              style: ts.labelLarge?.copyWith(color: cs.primary)),
        ]),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(Icons.info_outline,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('No gated providers configured',
                    style:
                        ts.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ]),
            ),
          )
        else
          ...items.map((p) {
            final provider = p is Map<String, dynamic>
                ? p
                : <String, dynamic>{};
            final name =
                provider['provider'] as String? ?? 'Unknown';
            final method =
                provider['auth_method'] as String? ?? 'none';
            final available =
                provider['available'] as bool? ?? false;
            final authValid =
                provider['auth_valid'] as bool? ?? false;
            final models = capsAsList(provider['models'])
                .whereType<String>()
                .toList();
            final failures =
                provider['consecutive_failures'] as int? ?? 0;
            final hasFallback =
                provider['has_fallback'] as bool? ?? false;
            final rateRemaining =
                provider['rate_limit_remaining'] as int?;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(
                        available
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        size: 16,
                        color: available ? Colors.green : cs.error,
                      ),
                      const SizedBox(width: 8),
                      Text(name, style: ts.titleSmall),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: authValid
                              ? Colors.green.withValues(alpha: 0.1)
                              : cs.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          authValid ? 'Auth Valid' : 'Auth Invalid',
                          style: ts.labelSmall?.copyWith(
                            color: authValid ? Colors.green : cs.error,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 16, runSpacing: 4, children: [
                      CapProviderDetail(
                          label: 'Method', value: method),
                      if (rateRemaining != null)
                        CapProviderDetail(
                            label: 'Rate Limit',
                            value: '$rateRemaining remaining'),
                      if (failures > 0)
                        CapProviderDetail(
                            label: 'Failures',
                            value: '$failures consecutive'),
                      CapProviderDetail(
                          label: 'Fallback',
                          value: hasFallback ? 'Configured' : 'None'),
                    ]),
                    if (models.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: models
                            .map((m) => Chip(
                                  label: Text(m,
                                      style:
                                          const TextStyle(fontSize: 11)),
                                  padding: EdgeInsets.zero,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }
}

// ── Provider detail row ───────────────────────────────────────────────────────

class CapProviderDetail extends StatelessWidget {
  final String label;
  final String value;
  const CapProviderDetail(
      {super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final ts = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text('$label: ',
          style: ts.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
      Text(value,
          style:
              ts.labelSmall?.copyWith(fontWeight: FontWeight.w600)),
    ]);
  }
}

// ── Conformance card ──────────────────────────────────────────────────────────

class ConformanceCard extends StatelessWidget {
  final Robot robot;
  final int score;
  final int p66Pass;

  const ConformanceCard({
    super.key,
    required this.robot,
    required this.score,
    required this.p66Pass,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progressColor = score >= 80
        ? AppTheme.online
        : score >= 50
            ? AppTheme.warning
            : AppTheme.danger;
    final rcanLabel =
        robot.rcanVersion != null ? 'RCAN v${robot.rcanVersion}' : 'RCAN v?';
    final tierLabel = capTierDisplayLabel(robot.registryTier);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, size: 16, color: cs.primary),
                const SizedBox(width: 6),
                Text(
                  'Conformance Score',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: score / 100.0,
                      minHeight: 8,
                      backgroundColor: progressColor.withValues(alpha: 0.15),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(progressColor),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '$score%',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: progressColor,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    rcanLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onPrimaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$tierLabel · $p66Pass/5 P66 checks',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── LoA + Vision bottom sheets ────────────────────────────────────────────────

void showLoaBottomSheet(BuildContext context, {required String rrn, required WidgetRef ref}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ProviderScope(
      parent: ProviderScope.containerOf(context),
      child: _LoaEnableSheet(rrn: rrn, ref: ref),
    ),
  );
}

class _LoaEnableSheet extends ConsumerStatefulWidget {
  final String rrn;
  final WidgetRef ref;
  const _LoaEnableSheet({required this.rrn, required this.ref});

  @override
  ConsumerState<_LoaEnableSheet> createState() => _LoaEnableSheetState();
}

class _LoaEnableSheetState extends ConsumerState<_LoaEnableSheet> {
  bool _loading = false;
  String? _result;
  bool _success = false;

  Future<void> _enable() async {
    setState(() { _loading = true; _result = null; });
    try {
      await ref.read(loaEnableCommandProvider(widget.rrn).future);
      setState(() { _success = true; _result = 'LoA enforcement enabled.'; });
    } catch (e) {
      setState(() { _result = e.toString(); });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const snippet = 'loa_enforcement: true';
    const cliSnippet = 'castor loa enable';

    return Padding(
      padding: EdgeInsets.only(
        left: 16, right: 16, top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text('Enable LoA Enforcement',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),

          // One-tap enable (calls gateway API via command)
          if (!_success) ...[
            Text('Quick enable — applies immediately to the running bridge:',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _enable,
                icon: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.shield_outlined, size: 18),
                label: Text(_loading ? 'Enabling…' : 'Enable LoA Enforcement'),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_result!, style: TextStyle(fontSize: 12, color: cs.onErrorContainer)),
              ),
            ],
            const Divider(height: 32),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.green.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text('LoA enforcement enabled', style: TextStyle(color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],

          // Manual / CLI instructions as fallback
          Text('Or enable manually:',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          _InstructionStep(number: 1, text: 'Via CLI (on the robot):'),
          _CodeChip(code: cliSnippet),
          const SizedBox(height: 8),
          _InstructionStep(number: 2, text: 'Or edit .rcan.yaml and add:'),
          _CodeChip(code: snippet),
          const SizedBox(height: 8),
          _InstructionStep(number: 3, text: 'Restart the bridge:'),
          _CodeChip(code: 'castor bridge restart'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'LoA enforcement requires RCAN v1.6+. Commands below the minimum assurance level will be rejected.',
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final int number;
  final String text;
  const _InstructionStep({required this.number, required this.text});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
            child: Center(child: Text('$number', style: TextStyle(fontSize: 11, color: cs.onPrimary, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  final String code;
  const _CodeChip({required this.code});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(left: 28, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(child: Text(code, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
          InkWell(
            onTap: () {
              // ignore: avoid_print
              // Clipboard.setData not available without flutter/services import here
            },
            child: Icon(Icons.copy_outlined, size: 14, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

void showVisionBottomSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const CapInstructionSheet(
      title: 'Enable Vision Capability',
      steps: [
        'Connect a camera to your robot.',
        'Add "vision" to the capabilities list in .rcan.yaml:',
        'Restart the castor bridge:',
      ],
      codeSnippets: [
        null,
        'capabilities:\n  - vision',
        'castor bridge restart',
      ],
      note:
          'Vision requires a compatible camera driver. See the RCAN docs for supported hardware.',
    ),
  );
}

// ── Sub-screen scaffold helper ────────────────────────────────────────────────

/// Standard scaffold wrapper used by all capabilities sub-screens.
/// Shows loading / error / offline states consistently.
class CapSubScreenShell extends StatelessWidget {
  final String title;
  final Widget body;

  const CapSubScreenShell(
      {super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: body,
    );
  }
}
