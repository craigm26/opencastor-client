/// Detected Hardware sub-screen.
/// Route: /robot/:rrn/capabilities/hardware
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../harness/hardware_provider.dart';
import 'capabilities_widgets.dart';

class HardwareScreen extends ConsumerWidget {
  final String rrn;
  const HardwareScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hwAsync = ref.watch(hardwareProfileProvider(rrn));
    return hwAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Detected Hardware')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Detected Hardware')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CapSection(
              title: 'Detected Hardware',
              icon: Icons.memory_outlined,
              rows: [
                CapabilityRow(
                  label: 'Hardware data unavailable',
                  status: CapStatus.info,
                  description: 'Robot may be offline',
                ),
              ],
            ),
          ],
        ),
      ),
      data: (hw) => Scaffold(
        appBar: AppBar(title: _hardwareTitle(hw)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CapSection(
              title: 'Detected Hardware',
              icon: Icons.memory_outlined,
              rows: _buildRows(hw),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _hardwareTitle(Map<String, dynamic> hw) {
    final tier = hw['hardware_tier'] as String? ?? 'unknown';
    return Text('Hardware — ${_tierLabel(tier)}');
  }

  List<CapabilityRow> _buildRows(Map<String, dynamic> hw) {
    if (hw.isEmpty) {
      return [
        CapabilityRow(
          label: 'Hardware data unavailable',
          status: CapStatus.info,
          description: 'Robot may be offline',
        ),
      ];
    }

    final cpuModel = hw['cpu_model'] as String? ?? '';
    final cpuCores = hw['cpu_cores'] as int? ?? 0;
    final arch = hw['arch'] as String? ?? 'unknown';
    final platform = hw['platform'] as String? ?? 'generic';
    final ramGb = (hw['ram_gb'] as num?)?.toStringAsFixed(1) ?? '?';
    final ramAvail =
        (hw['ram_available_gb'] as num?)?.toStringAsFixed(1) ?? '?';
    final storageFree =
        (hw['storage_free_gb'] as num?)?.toStringAsFixed(1) ?? '?';
    final tier = hw['hardware_tier'] as String? ?? 'unknown';
    final accel = capsAsList(hw['accelerators']);
    final ollama = capsAsList(hw['ollama_models']);

    final rows = <CapabilityRow>[
      CapabilityRow(
        label: cpuModel.isNotEmpty
            ? (cpuModel.length > 35
                ? '${cpuModel.substring(0, 35)}…'
                : cpuModel)
            : 'CPU: unknown',
        status: cpuModel.isNotEmpty ? CapStatus.ok : CapStatus.info,
        description: '$cpuCores cores · $arch · $platform',
      ),
      CapabilityRow(
        label: '$ramGb GB RAM',
        status: CapStatus.ok,
        description: '$ramAvail GB available · $storageFree GB disk free',
      ),
      CapabilityRow(
        label: _tierLabel(tier),
        status: CapStatus.ok,
        description: 'Hardware class for LLM model selection',
      ),
      if (accel.isEmpty)
        CapabilityRow(
          label: 'No accelerators detected',
          status: CapStatus.info,
          description: 'NPU/GPU not found',
        )
      else
        ...accel.map(
          (a) => CapabilityRow(
            label: a.toString(),
            status: CapStatus.ok,
            description: 'Hardware accelerator',
          ),
        ),
      if (ollama.isNotEmpty)
        CapabilityRow(
          label: 'Local models: ${ollama.join(", ")}',
          status: CapStatus.ok,
          description: '${ollama.length} model(s) available via Ollama',
        )
      else
        CapabilityRow(
          label: 'No local models',
          status: CapStatus.info,
          description: 'No Ollama models installed',
        ),
    ];
    return rows;
  }

  String _tierLabel(String t) => switch (t) {
        'pi5-hailo' => 'Pi 5 + Hailo-8 NPU',
        'pi5-8gb' => 'Pi 5 · 8 GB',
        'pi5-4gb' => 'Pi 5 · 4 GB',
        'pi4-8gb' => 'Pi 4 · 8 GB',
        'pi4-4gb' => 'Pi 4 · 4 GB',
        'server' => 'Server-class',
        'minimal' => 'Minimal',
        _ => t,
      };
}
