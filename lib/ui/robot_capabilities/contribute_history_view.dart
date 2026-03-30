/// Contribution history timeline view.
///
/// Shows daily contribution stats as a simple list (last 14 days).
/// Reads from telemetry.contribute_history in Firestore.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'contribute_history_view_model.dart';

import '../shared/error_view.dart';
import '../shared/loading_view.dart';


class ContributeHistoryView extends ConsumerWidget {
  final String rrn;

  const ContributeHistoryView({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(contributeHistoryProvider(rrn));
    final theme = Theme.of(context);

    return historyAsync.when(
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(error: e.toString()),
      data: (history) {
        if (history.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history_outlined,
                    size: 48, color: theme.colorScheme.outline),
                const SizedBox(height: 12),
                Text('No contribution history yet',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          );
        }

        final recent = history.length > 14
            ? history.sublist(history.length - 14)
            : history;

        return Card(
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.timeline_outlined,
                        size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text('Contribution History',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 12),
                ...recent.reversed.map((entry) {
                  final date = entry['date'] as String? ?? '—';
                  final minutes = (entry['minutes'] as num?)?.toInt() ?? 0;
                  final units = (entry['work_units'] as num?)?.toInt() ?? 0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 90,
                          child: Text(date,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  fontFamily: 'monospace',
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                        Expanded(
                          child: _BarIndicator(
                            value: minutes.toDouble(),
                            maxValue: recent
                                .map((e) =>
                                    ((e['minutes'] as num?)?.toDouble() ?? 0))
                                .fold<double>(1, (a, b) => a > b ? a : b),
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 65,
                          child: Text('${_fmt(minutes)} · $units',
                              textAlign: TextAlign.end,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Text('minutes · work units',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
        );
      },
    );
  }

  String _fmt(int m) {
    if (m == 0) return '—';
    if (m < 60) return '${m}m';
    return '${m ~/ 60}h${m % 60}m';
  }
}

class _BarIndicator extends StatelessWidget {
  final double value;
  final double maxValue;
  final Color color;

  const _BarIndicator(
      {required this.value, required this.maxValue, required this.color});

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue > 0 ? (value / maxValue).clamp(0.0, 1.0) : 0.0;
    return Container(
      height: 12,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: fraction,
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(6),
          ),
        ),
      ),
    );
  }
}
