/// Hardware Components sub-screen.
/// Route: /robot/:rrn/capabilities/components
///
/// Shows all registered hardware components for a robot (RCAN v2.2 §7.3):
/// CPU, NPU, cameras, sensors, actuators.
/// Components are read from Firestore robots/{rrn}/components subcollection.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'capabilities_widgets.dart';

// ── Provider ──────────────────────────────────────────────────────────────────

final _componentsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, rrn) {
  return FirebaseFirestore.instance
      .collection('robots')
      .doc(rrn)
      .collection('components')
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()
            ..sort((a, b) => (a['type'] as String? ?? '').compareTo(b['type'] as String? ?? '')));
});

// ── Screen ────────────────────────────────────────────────────────────────────

class ComponentsScreen extends ConsumerWidget {
  final String rrn;
  const ComponentsScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compsAsync = ref.watch(_componentsProvider(rrn));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hardware Components'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            tooltip: 'Re-detect components',
            onPressed: () => ref.invalidate(_componentsProvider(rrn)),
          ),
        ],
      ),
      body: compsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (components) => components.isEmpty
            ? _EmptyComponents(rrn: rrn)
            : _ComponentsList(components: components, rrn: rrn),
      ),
    );
  }
}

// ── Component list ────────────────────────────────────────────────────────────

class _ComponentsList extends StatelessWidget {
  final List<Map<String, dynamic>> components;
  final String rrn;
  const _ComponentsList({required this.components, required this.rrn});

  @override
  Widget build(BuildContext context) {
    // Group by type
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final c in components) {
      final type = (c['type'] as String? ?? 'other').toLowerCase();
      grouped.putIfAbsent(type, () => []).add(c);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary chips
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: grouped.entries
              .map((e) => _TypeChip(type: e.key, count: e.value.length))
              .toList(),
        ),
        const SizedBox(height: 16),
        // Component cards per group
        for (final entry in grouped.entries) ...[
          CapSection(
            title: _typeLabel(entry.key),
            icon: _typeIcon(entry.key),
            rows: entry.value
                .map((c) => _componentRow(c))
                .toList(),
          ),
          const SizedBox(height: 8),
        ],
        // Registration note
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Components are registered via: castor components register\n'
                  'Run on the robot to auto-detect and sync hardware to the registry.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  CapabilityRow _componentRow(Map<String, dynamic> c) {
    final status = (c['status'] as String? ?? 'unknown').toLowerCase();
    final capStatus = status == 'active'
        ? CapStatus.ok
        : status == 'detected'
            ? CapStatus.info
            : CapStatus.warning;

    final model = c['model'] as String? ?? 'Unknown';
    final mfr = c['manufacturer'] as String? ?? '';
    final fw = c['firmware_version'] as String? ?? '';
    final caps = (c['capabilities'] as List<dynamic>?)?.cast<String>() ?? [];
    final capStr = caps.isNotEmpty ? ' [${caps.join(', ')}]' : '';

    final description = [
      if (mfr.isNotEmpty) mfr,
      if (fw.isNotEmpty && fw != 'unknown') 'fw: $fw',
      if (capStr.isNotEmpty) capStr.trim(),
      'id: ${c['id'] ?? '?'}',
    ].join(' · ');

    return CapabilityRow(
      label: model,
      status: capStatus,
      description: description,
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyComponents extends StatelessWidget {
  final String rrn;
  const _EmptyComponents({required this.rrn});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.developer_board_outlined, size: 48, color: cs.outlineVariant),
            const SizedBox(height: 16),
            Text('No components registered',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Register hardware components by running on the robot:',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'castor components register',
                style: TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'This auto-detects your NPU, cameras, sensors, and other hardware,\n'
              'then syncs them to the Robot Registry.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final String type;
  final int count;
  const _TypeChip({required this.type, required this.count});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_typeIcon(type), size: 14, color: cs.onPrimaryContainer),
          const SizedBox(width: 4),
          Text(
            '$count× ${_typeLabel(type)}',
            style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

String _typeLabel(String type) => switch (type) {
  'cpu' => 'CPU',
  'npu' => 'NPU',
  'gpu' => 'GPU',
  'camera' => 'Camera',
  'lidar' => 'LiDAR',
  'imu' => 'IMU',
  'motor' => 'Motor Controller',
  'battery' => 'Battery',
  'estop' => 'E-Stop',
  'gps' => 'GPS',
  'display' => 'Display',
  'radio' => 'Radio',
  'microphone' => 'Microphone',
  'speaker' => 'Speaker',
  _ => type[0].toUpperCase() + type.substring(1),
};

IconData _typeIcon(String type) => switch (type) {
  'cpu' => Icons.memory_outlined,
  'npu' => Icons.developer_board_outlined,
  'gpu' => Icons.videogame_asset_outlined,
  'camera' => Icons.camera_outlined,
  'lidar' => Icons.radar_outlined,
  'imu' => Icons.sensors_outlined,
  'motor' => Icons.settings_outlined,
  'battery' => Icons.battery_charging_full_outlined,
  'estop' => Icons.emergency_outlined,
  'gps' => Icons.gps_fixed_outlined,
  'display' => Icons.monitor_outlined,
  'radio' => Icons.wifi_outlined,
  'microphone' => Icons.mic_outlined,
  'speaker' => Icons.volume_up_outlined,
  _ => Icons.device_unknown_outlined,
};
