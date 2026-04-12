/// EU Register Entry placeholder screen.
/// Route: /robot/:rrn/compliance/eu-register
library;

import 'package:flutter/material.dart';
import '_placeholder_screen.dart';

class EuRegisterScreen extends StatelessWidget {
  final String rrn;
  const EuRegisterScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context) {
    return const CompliancePlaceholderScreen(
      title: 'EU Register Entry',
      icon: Icons.account_balance_outlined,
      message: 'EU high-risk AI systems register data will appear here once the EU register API endpoint is available on rcan.dev.',
    );
  }
}
