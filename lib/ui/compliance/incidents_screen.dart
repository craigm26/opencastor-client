/// Post-Market Incidents placeholder screen.
/// Route: /robot/:rrn/compliance/incidents
library;

import 'package:flutter/material.dart';
import '_placeholder_screen.dart';

class IncidentsScreen extends StatelessWidget {
  final String rrn;
  const IncidentsScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context) {
    return const CompliancePlaceholderScreen(
      title: 'Post-Market Incidents',
      icon: Icons.report_problem_outlined,
      message: 'Post-market incident reports will appear here once the incidents API endpoint is available on rcan.dev.',
    );
  }
}
