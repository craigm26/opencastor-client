/// Full-screen error state widget.
library;

import 'package:flutter/material.dart';

class ErrorView extends StatelessWidget {
  final String? error;
  final VoidCallback? onRetry;
  final String title;

  const ErrorView({
    super.key,
    this.error,
    this.onRetry,
    this.title = 'Something went wrong',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayError = error != null && error!.length > 200
        ? '${error!.substring(0, 200)}…'
        : error;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            if (displayError != null) ...[
              const SizedBox(height: 8),
              Text(
                displayError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: onRetry,
                child: const Text('Try again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
