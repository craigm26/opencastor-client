/// Reusable M3 confirmation dialog for destructive / physical actions.
///
/// Usage:
/// ```dart
/// final ok = await showConfirmationDialog(
///   context: context,
///   title: 'Emergency Stop — Alex',
///   message: 'Send ESTOP to Alex immediately.',
///   confirmLabel: 'SEND ESTOP',
///   confirmColor: AppTheme.estop,
/// );
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_theme.dart';

/// Show an M3 AlertDialog and return [true] if the user confirmed.
Future<bool> showConfirmationDialog({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  Color? confirmColor,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ConfirmationDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      confirmColor: confirmColor,
    ),
  );
  return result ?? false;
}

/// ESTOP shortcut — red dialog, heavy haptic.
Future<bool> showEstopConfirmationDialog(
  BuildContext context,
  String robotName,
) async {
  HapticFeedback.heavyImpact();
  return showConfirmationDialog(
    context: context,
    title: 'Emergency Stop — $robotName',
    message:
        'Send ESTOP to $robotName immediately. The robot will halt all motion.',
    confirmLabel: 'SEND ESTOP',
    confirmColor: AppTheme.estop,
  );
}

class _ConfirmationDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color? confirmColor;

  const _ConfirmationDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDangerous = confirmColor != null;

    return AlertDialog(
      icon: isDangerous
          ? Icon(Icons.warning_amber_rounded,
              color: confirmColor, size: 32)
          : Icon(Icons.touch_app_outlined, color: cs.primary, size: 32),
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: confirmColor != null
              ? FilledButton.styleFrom(backgroundColor: confirmColor)
              : null,
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}
