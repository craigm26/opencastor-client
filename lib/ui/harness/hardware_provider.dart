/// hardware_provider.dart — Riverpod provider for robot hardware profile.
///
/// Reads from Firestore robots/{rrn}.system (pushed by bridge every 30s).
/// The Cloud Function relay cannot reach local-network robots, so we read
/// the telemetry data that the bridge already pushes to Firestore instead.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fetches the hardware profile for a robot by RRN from Firestore telemetry.
///
/// The bridge pushes system_info to robots/{rrn}.system every 30s.
/// Falls back to an empty map (all models shown) if unavailable.
///
/// Map keys mirror the Cloud Function response shape for compatibility:
/// - hardware_tier, ram_gb, ram_available_gb, accelerators, ollama_models,
///   cpu_model, cpu_cores, arch, platform, storage_free_gb
final hardwareProfileProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, rrn) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('robots')
          .doc(rrn)
          .get();
      final data = doc.data();
      if (data == null) return const {};
      final sys = data['system'] as Map<String, dynamic>?;
      if (sys == null || sys.isEmpty) return const {};

      // Map system_info keys → hardware profile shape expected by hardware_screen.
      final npuRaw    = sys['npu_detected'];
      final npuDetect = npuRaw is bool ? npuRaw : (npuRaw != null && npuRaw != false);
      final npuModel  = sys['npu_model'] as String? ??
          (npuRaw is String ? npuRaw : null);
      final npuTops   = (sys['npu_tops'] as num?)?.toDouble();

      final cpuModel = sys['cpu_model'] as String? ?? '';
      String tier = 'unknown';
      if (cpuModel.toLowerCase().contains('raspberry pi 5')) {
        tier = npuDetect ? 'pi5-hailo' : 'pi5-8gb';
      } else if (cpuModel.toLowerCase().contains('raspberry pi 4')) {
        tier = 'pi4';
      }

      final platform = sys['platform'] as String? ?? 'unknown';
      final arch = platform.contains('-') ? platform.split('-').last : platform;

      return {
        'cpu_model':        cpuModel,
        'cpu_cores':        (sys['cpu_count'] as num?)?.toInt() ?? 0,
        'arch':             arch,
        'platform':         platform,
        'ram_gb':           (sys['ram_total_gb'] as num?)?.toDouble() ?? 0.0,
        'ram_available_gb': (sys['ram_available_gb'] as num?)?.toDouble() ?? 0.0,
        'storage_free_gb':  (sys['disk_free_gb'] as num?)?.toDouble() ?? 0.0,
        'hardware_tier':    tier,
        'accelerators': <String>[
          if (npuDetect)
            '${npuModel ?? "NPU"}${npuTops != null ? " · ${npuTops.toStringAsFixed(0)} TOPS" : ""}',
          if (sys['gpu_detected'] == true) 'GPU detected',
        ],
        'ollama_models': <String>[],
        '_source': 'firestore_system',
      };
    } catch (_) {
      return const {};
    }
  },
);
