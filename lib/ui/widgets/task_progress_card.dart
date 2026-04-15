library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/task_doc.dart';
import '../core/theme/app_theme.dart';
import '../robot_detail/robot_detail_view_model.dart'
    show taskDocProvider, confirmTaskProvider;

/// Inline task progress card rendered in the chat list when a command
/// has a [taskId] (i.e. a pick-and-place task is in progress).
class TaskProgressCard extends ConsumerWidget {
  final String rrn;
  final String taskId;

  const TaskProgressCard({
    super.key,
    required this.rrn,
    required this.taskId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync =
        ref.watch(taskDocProvider((rrn: rrn, taskId: taskId)));

    return taskAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (task) {
        if (task == null) return const SizedBox.shrink();
        return _TaskCard(rrn: rrn, task: task);
      },
    );
  }
}

class _TaskCard extends ConsumerWidget {
  final String rrn;
  final TaskDoc task;

  const _TaskCard({required this.rrn, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(Spacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──────────────────────────────────────────────────
              Row(
                children: [
                  const Icon(Icons.precision_manufacturing_outlined, size: 18),
                  const SizedBox(width: Spacing.sm),
                  Text('Pick & Place',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const Spacer(),
                  _StatusChip(task: task),
                ],
              ),
              const SizedBox(height: Spacing.sm),

              // ── Target → destination ────────────────────────────────────
              Text(
                '${task.target}  →  ${task.destination}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),

              // ── Scene snapshot ──────────────────────────────────────────
              if (task.frameB64 != null) ...[
                const SizedBox(height: Spacing.sm),
                ClipRRect(
                  borderRadius: const BorderRadius.all(AppRadius.md),
                  child: Image.memory(
                    base64Decode(task.frameB64!),
                    width: double.infinity,
                    height: 160,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ],

              // ── Detected objects ────────────────────────────────────────
              if (task.detectedObjects.isNotEmpty) ...[
                const SizedBox(height: Spacing.xs),
                Text(
                  'Detected: ${task.detectedObjects.join(', ')}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],

              const SizedBox(height: Spacing.md),

              // ── Phase stepper ───────────────────────────────────────────
              _PhaseList(task: task),

              // ── Confirm button (ask mode only) ──────────────────────────
              if (task.isPendingConfirmation) ...[
                const SizedBox(height: Spacing.md),
                FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(confirmTaskProvider.notifier)
                        .confirm(rrn: rrn, taskId: task.taskId);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Run'),
                ),
              ],

              // ── Error chip ──────────────────────────────────────────────
              if (task.isFailed && task.error != null) ...[
                const SizedBox(height: Spacing.sm),
                Text(
                  task.error!.replaceAll('_', ' '),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.danger),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Phase list ────────────────────────────────────────────────────────────────

const _kPhases = ['SCAN', 'APPROACH', 'GRASP', 'PLACE'];

class _PhaseList extends StatelessWidget {
  final TaskDoc task;
  const _PhaseList({required this.task});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: _kPhases.map((p) => _PhaseRow(phase: p, task: task)).toList(),
    );
  }
}

class _PhaseRow extends StatelessWidget {
  final String phase;
  final TaskDoc task;
  const _PhaseRow({required this.phase, required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final isCurrent = task.phase == phase;
    final isRunning = isCurrent && task.isRunning;
    final isDone = _phaseIndex(task.phase) > _phaseIndex(phase) ||
        (isCurrent && task.isComplete);
    final isFailed = isCurrent && task.isFailed;

    final Widget icon;
    if (isRunning) {
      icon = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: cs.primary,
        ),
      );
    } else if (isDone) {
      icon = const Icon(Icons.check_circle_rounded, size: 16, color: AppTheme.online);
    } else if (isFailed) {
      icon = const Icon(Icons.cancel_rounded, size: 16, color: AppTheme.danger);
    } else {
      icon = Icon(Icons.radio_button_unchecked,
          size: 16, color: cs.onSurfaceVariant);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          icon,
          const SizedBox(width: Spacing.sm),
          Text(
            phase,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isRunning
                  ? cs.primary
                  : isDone
                      ? cs.onSurface
                      : cs.onSurfaceVariant,
              fontWeight: isRunning ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }

  static int _phaseIndex(String phase) =>
      _kPhases.indexOf(phase).clamp(0, _kPhases.length - 1);
}

// ── Status chip ───────────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  final TaskDoc task;
  const _StatusChip({required this.task});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (label, color) = switch (task.status) {
      'pending_confirmation' => ('Awaiting confirmation', cs.secondary),
      'running'              => ('Running', cs.primary),
      'complete'             => ('Done', AppTheme.online),
      'failed'               => ('Failed', AppTheme.danger),
      'cancelled'            => ('Cancelled', cs.onSurfaceVariant),
      _                      => (task.status, cs.onSurfaceVariant),
    };

    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: color.withValues(alpha: 0.12),
      labelStyle: TextStyle(color: color),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
    );
  }
}
