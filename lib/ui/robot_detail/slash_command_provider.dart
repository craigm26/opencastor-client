/// Provider for slash command registry.
///
/// Attempts to fetch live commands from the robot's GET /api/skills endpoint
/// via Firestore telemetry. Falls back to the static builtin list when the
/// robot is offline or the fetch fails.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/slash_command.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Fetches the slash command list for a robot identified by [rrn].
///
/// Reads `robots/{rrn}/telemetry/skills` from Firestore if available —
/// the robot bridge writes live skill info there when online.
///
/// Falls back to [kStaticBuiltinCommands] when:
/// - Firestore document doesn't exist
/// - Robot is offline
/// - Any error occurs
final slashCommandsProvider =
    FutureProvider.family<List<SlashCommand>, String>((ref, rrn) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('robots')
        .doc(rrn)
        .collection('telemetry')
        .doc('skills')
        .get();

    if (!doc.exists) {
      return _staticFallback();
    }

    final data = doc.data();
    if (data == null) return _staticFallback();

    return _parseSkillsDoc(data);
  } catch (_) {
    return _staticFallback();
  }
});

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

List<SlashCommand> _staticFallback() => List.unmodifiable(kStaticBuiltinCommands);

/// Parse a Firestore telemetry/skills doc produced by GET /api/skills.
///
/// Expected structure:
/// ```json
/// {
///   "builtin_commands": [...],
///   "skills": [...],
///   "rcan_version": "1.6",
///   "robot_rrn": "RRN-..."
/// }
/// ```
List<SlashCommand> _parseSkillsDoc(Map<String, dynamic> data) {
  final result = <SlashCommand>[];

  // Parse skill entries
  final rawSkills = data['skills'] as List<dynamic>? ?? [];
  for (final raw in rawSkills) {
    if (raw is Map<String, dynamic>) {
      try {
        result.add(SlashCommand.fromJson(raw, group: 'Skills'));
      } catch (_) {
        // skip malformed entries
      }
    }
  }

  // Parse builtin CLI commands
  final rawBuiltin = data['builtin_commands'] as List<dynamic>? ?? [];
  for (final raw in rawBuiltin) {
    if (raw is Map<String, dynamic>) {
      try {
        result.add(SlashCommand.fromJson(raw, group: 'CLI'));
      } catch (_) {
        // skip malformed entries
      }
    }
  }

  // If we got nothing useful, fall back to static list
  if (result.isEmpty) return _staticFallback();
  return List.unmodifiable(result);
}
