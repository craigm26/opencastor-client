/// Detected Hardware sub-screen.
/// Route: /robot/:rrn/capabilities/hardware
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../harness/hardware_provider.dart';
import '../robot_detail/robot_detail_view_model.dart';
import 'capabilities_widgets.dart';
import 'provenance_card.dart';

class HardwareScreen extends ConsumerWidget {
  final String rrn;
  const HardwareScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hwAsync = ref.watch(hardwareProfileProvider(rrn));
    final robotAsync = ref.watch(robotDetailProvider(rrn));

    return hwAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Hardware')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => Scaffold(
        appBar: AppBar(title: const Text('Hardware')),
        body: _buildBody(context, null, robotAsync),
      ),
      data: (hw) => Scaffold(
        appBar: AppBar(title: _hardwareTitle(hw)),
        body: _buildBody(context, hw, robotAsync),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    Map<String, dynamic>? hw,
    AsyncValue robotAsync,
  ) {
    // Live telemetry from /api/status → system + model_runtime
    final robot = robotAsync.valueOrNull;
    final t = (robot?.telemetry ?? {}) as Map<String, dynamic>;
    final sys = t['system'] as Map<String, dynamic>?;
    final mr = t['model_runtime'] as Map<String, dynamic>?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Live stats (from /api/status telemetry push) ─────────────────
        if (sys != null && sys.isNotEmpty) ...[
          _LiveStatsSection(sys: sys, mr: mr),
          const SizedBox(height: 16),
        ],

        // ── Detected hardware profile ─────────────────────────────────────
        if (hw != null && hw.isNotEmpty)
          CapSection(
            title: 'Detected Hardware',
            icon: Icons.memory_outlined,
            rows: _buildRows(hw),
          )
        else
          CapSection(
            title: 'Detected Hardware',
            icon: Icons.memory_outlined,
            rows: [
              CapabilityRow(
                label: 'Hardware data unavailable',
                status: CapStatus.info,
                description: 'Robot may be offline or still starting up',
              ),
            ],
          ),

        const SizedBox(height: 32),

        // ── RRF Provenance Chain (RCAN v2.2 §21) ──────────────────────────
        if (robot != null)
          ProvenanceCard(robot: robot),

        const SizedBox(height: 16),
      ],
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

// ── Live stats section ────────────────────────────────────────────────────────

class _LiveStatsSection extends StatelessWidget {
  final Map<String, dynamic> sys;
  final Map<String, dynamic>? mr;
  const _LiveStatsSection({required this.sys, this.mr});

  @override
  Widget build(BuildContext context) {
    final rows = <CapabilityRow>[];

    // RAM
    final ramAvail = sys['ram_available_gb'] as num?;
    final ramTotal = sys['ram_total_gb'] as num?;
    if (ramAvail != null && ramTotal != null) {
      final pct = ramAvail / ramTotal;
      final status = pct < 0.15
          ? CapStatus.missing
          : pct < 0.30
              ? CapStatus.warning
              : CapStatus.ok;
      rows.add(CapabilityRow(
        label: '${ramAvail.toStringAsFixed(1)} / ${ramTotal.toStringAsFixed(0)} GB RAM',
        status: status,
        description: '${(pct * 100).round()}% available',
      ));
    }

    // Disk
    final diskFree = sys['disk_free_gb'] as num?;
    final diskTotal = sys['disk_total_gb'] as num?;
    if (diskFree != null && diskTotal != null) {
      rows.add(CapabilityRow(
        label: '${diskFree.toStringAsFixed(0)} GB disk free',
        status: CapStatus.ok,
        description: 'of ${diskTotal.toStringAsFixed(0)} GB total',
      ));
    }

    // CPU temp
    final temp = sys['cpu_temp_c'] as num?;
    if (temp != null) {
      final status = temp >= 80
          ? CapStatus.missing
          : temp >= 65
              ? CapStatus.warning
              : CapStatus.ok;
      rows.add(CapabilityRow(
        label: '${temp.toStringAsFixed(0)}°C CPU',
        status: status,
        description: temp >= 80
            ? 'Thermal throttling likely'
            : temp >= 65
                ? 'Warm — watch thermals'
                : 'Normal operating temperature',
      ));
    }

    // NPU
    final npu = sys['npu_detected'] as String?;
    final npuTops = sys['npu_tops'] as num?;
    if (npu != null) {
      rows.add(CapabilityRow(
        label: npu,
        status: CapStatus.ok,
        description: npuTops != null
            ? '${npuTops.toStringAsFixed(0)} TOPS · hardware accelerator'
            : 'NPU detected',
      ));
    }

    // GPU
    final gpu = sys['gpu_detected'] as String?;
    if (gpu != null) {
      rows.add(CapabilityRow(
        label: gpu,
        status: CapStatus.ok,
        description: 'GPU detected',
      ));
    }

    // Active model
    if (mr != null && mr!['active_model'] != null && mr!['active_model'] != 'unknown') {
      final model = mr!['active_model'] as String;
      final provider = mr!['provider'] as String? ?? '';
      final modelGb = mr!['model_size_gb'] as num?;
      final ctx = mr!['context_window'] as num?;
      final kvComp = mr!['kv_compression'] as String?;
      final fitStatus = mr!['llmfit_status'] as String?;
      final headroom = mr!['llmfit_headroom_gb'] as num?;
      final tps = mr!['tokens_per_sec'] as num?;

      final sizeLabel = modelGb != null ? ' · ${modelGb.toStringAsFixed(1)} GB' : '';
      final ctxLabel = ctx != null ? ' · ${(ctx / 1024).round()}k ctx' : '';
      final fitLabel = fitStatus == 'ok' && headroom != null
          ? '+${headroom.toStringAsFixed(1)} GB headroom'
          : fitStatus == 'oom' && headroom != null
              ? '${headroom.abs().toStringAsFixed(1)} GB over limit'
              : '';
      final kvLabel = (kvComp != null && kvComp != 'none') ? ' · KV: $kvComp' : '';

      rows.add(CapabilityRow(
        label: '$model$sizeLabel',
        status: fitStatus == 'oom' ? CapStatus.missing : CapStatus.ok,
        description: '${provider.isNotEmpty ? "$provider" : ""}$ctxLabel$kvLabel'
            '${fitLabel.isNotEmpty ? " · $fitLabel" : ""}'
            '${tps != null ? " · ${tps.toStringAsFixed(0)} tok/s" : ""}',
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return CapSection(
      title: 'Live Stats',
      icon: Icons.monitor_heart_outlined,
      rows: rows,
    );
  }
}
