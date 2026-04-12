/// Shared placeholder widget used by IFU, Incidents, and EU Register screens.
library;

import 'package:flutter/material.dart';

class CompliancePlaceholderScreen extends StatelessWidget {
  final String title;
  final IconData icon;
  final String message;
  const CompliancePlaceholderScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Not yet available',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
