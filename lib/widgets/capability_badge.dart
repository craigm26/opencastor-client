import 'package:flutter/material.dart';
import '../models/robot.dart';

const _labels = {
  RobotCapability.chat: ('Chat', Icons.chat_outlined),
  RobotCapability.nav: ('Nav', Icons.navigation_outlined),
  RobotCapability.control: ('Arm', Icons.precision_manufacturing_outlined),
  RobotCapability.vision: ('Vision', Icons.videocam_outlined),
  RobotCapability.status: ('Status', Icons.monitor_heart_outlined),
  RobotCapability.discover: ('Discover', Icons.radar_outlined),
};

class CapabilityBadge extends StatelessWidget {
  final RobotCapability capability;
  final bool compact;

  const CapabilityBadge({super.key, required this.capability, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (label, icon) = _labels[capability] ?? ('?', Icons.help_outline);
    final cs = Theme.of(context).colorScheme;

    if (compact) {
      return Tooltip(
        message: label,
        child: Icon(icon, size: 16, color: cs.primary),
      );
    }

    return Chip(
      avatar: Icon(icon, size: 14, color: cs.onPrimaryContainer),
      label: Text(label, style: const TextStyle(fontSize: 11)),
      backgroundColor: cs.primaryContainer,
      labelStyle: TextStyle(color: cs.onPrimaryContainer),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

class CapabilityRow extends StatelessWidget {
  final List<RobotCapability> capabilities;
  final bool compact;

  const CapabilityRow({
    super.key,
    required this.capabilities,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: compact ? 6 : 4,
      runSpacing: 4,
      children: capabilities
          .map((c) => CapabilityBadge(capability: c, compact: compact))
          .toList(),
    );
  }
}
