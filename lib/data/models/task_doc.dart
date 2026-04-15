/// TaskDoc — live task progress document from Firestore.
///
/// Streamed from `robots/{rrn}/tasks/{taskId}`.
/// Status values: pending_confirmation | running | complete | failed | cancelled
/// Phase values: SCAN | APPROACH | GRASP | PLACE
library;

class TaskDoc {
  final String taskId;
  final String type;
  final String target;
  final String destination;
  final String status;
  final String phase;
  final String? frameB64;
  final List<String> detectedObjects;
  final String? error;
  final bool confirmed;

  const TaskDoc({
    required this.taskId,
    required this.type,
    required this.target,
    required this.destination,
    required this.status,
    required this.phase,
    this.frameB64,
    required this.detectedObjects,
    this.error,
    required this.confirmed,
  });

  factory TaskDoc.fromMap(String id, Map<String, dynamic> m) {
    return TaskDoc(
      taskId: id,
      type: m['type'] as String? ?? 'pick_place',
      target: m['target'] as String? ?? '',
      destination: m['destination'] as String? ?? '',
      status: m['status'] as String? ?? 'pending_confirmation',
      phase: m['phase'] as String? ?? 'SCAN',
      frameB64: m['frame_b64'] as String?,
      detectedObjects: (m['detected_objects'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      error: m['error'] as String?,
      confirmed: m['confirmed'] as bool? ?? false,
    );
  }

  bool get isPendingConfirmation => status == 'pending_confirmation';
  bool get isRunning => status == 'running';
  bool get isComplete => status == 'complete';
  bool get isFailed => status == 'failed' || status == 'cancelled';
}
