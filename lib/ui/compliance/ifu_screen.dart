/// Instructions for Use placeholder screen.
/// Route: /robot/:rrn/compliance/ifu
library;

import 'package:flutter/material.dart';
import '_placeholder_screen.dart';

class IfuScreen extends StatelessWidget {
  final String rrn;
  const IfuScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context) {
    return const CompliancePlaceholderScreen(
      title: 'Instructions for Use',
      icon: Icons.menu_book_outlined,
      message: 'Instructions for Use data will appear here once the IFU API endpoint is available on rcan.dev.',
    );
  }
}
