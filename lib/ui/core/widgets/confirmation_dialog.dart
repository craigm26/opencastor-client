import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Safety confirmation dialog for destructive/physical actions.
/// Required before any control-scope or safety command.
Future<bool> showConfirmationDialog(
  BuildContext context, {
  required String title,
  required String body,
  String confirmLabel = 'Confirm',
  bool isDangerous = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ConfirmationDialog(
      title: title,
      body: body,
      confirmLabel: confirmLabel,
      isDangerous: isDangerous,
    ),
  );
  return result ?? false;
}

class _ConfirmationDialog extends StatelessWidget {
  final String title;
  final String body;
  final String confirmLabel;
  final bool isDangerous;

  const _ConfirmationDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
    required this.isDangerous,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      icon: Icon(
        isDangerous ? Icons.warning_amber_rounded : Icons.touch_app_outlined,
        color: isDangerous ? AppTheme.danger : cs.primary,
        size: 32,
      ),
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(body),
          if (isDangerous) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 14, color: AppTheme.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will physically move the robot arm.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: isDangerous
              ? FilledButton.styleFrom(backgroundColor: AppTheme.danger)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

/// ESTOP confirmation — red, prominent, single large button.
Future<bool> showEstopDialog(BuildContext context, String robotName) {
  return showConfirmationDialog(
    context,
    title: 'Emergency Stop — $robotName',
    body: 'Send ESTOP to $robotName immediately. The robot will halt all motion.',
    confirmLabel: 'SEND ESTOP',
    isDangerous: true,
  );
}
