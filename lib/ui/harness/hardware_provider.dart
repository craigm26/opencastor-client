/// hardware_provider.dart — Riverpod provider for robot hardware profile.
///
/// Fetches GET /api/hardware via the Firebase Cloud Function relay.
/// Falls back gracefully to an empty map (all models shown) if unavailable.
library;

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fetches the hardware profile for a robot by RRN.
///
/// Uses the `robotApiGet` Cloud Function to proxy the request to the robot's
/// `/api/hardware` endpoint. Falls back to an empty map on any error so the
/// Model Garage still works without hardware info (shows all models).
///
/// Example result shape:
/// ```json
/// {
///   "hostname": "robot",
///   "arch": "aarch64",
///   "hardware_tier": "pi5-8gb",
///   "ram_gb": 8.0,
///   "ram_available_gb": 4.2,
///   "accelerators": [],
///   "ollama_models": ["gemma3:1b"],
///   ...
/// }
/// ```
final hardwareProfileProvider =
    FutureProvider.family<Map<String, dynamic>, String>(
  (ref, rrn) async {
    try {
      final fn = FirebaseFunctions.instance;
      final callable = fn.httpsCallable(
        'robotApiGet',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      final result = await callable.call(<String, dynamic>{
        'rrn': rrn,
        'path': '/api/hardware',
      });
      final data = result.data;
      if (data is Map) {
        // Cloud Function may return the body as a JSON string or as a map.
        if (data['body'] is String) {
          return Map<String, dynamic>.from(
            jsonDecode(data['body'] as String) as Map,
          );
        }
        if (data['body'] is Map) {
          return Map<String, dynamic>.from(data['body'] as Map);
        }
        // Direct map response
        return Map<String, dynamic>.from(data);
      }
    } catch (_) {
      // Fail silently — garage works without hardware data, shows all models.
    }
    return const <String, dynamic>{};
  },
);
