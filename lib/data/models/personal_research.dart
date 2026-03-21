/// Personal Research models — local algo-eval runs and community submission.
library;

/// A single personal research run result.
class PersonalRun {
  final String runId;
  final String candidateId;
  final double score;
  final Map<String, dynamic> metrics;
  final String hardwareTier;
  final String? modelId;
  final DateTime? createdAt;

  const PersonalRun({
    required this.runId,
    required this.candidateId,
    required this.score,
    required this.metrics,
    required this.hardwareTier,
    this.modelId,
    this.createdAt,
  });

  factory PersonalRun.fromJson(Map<String, dynamic> json) {
    DateTime? createdAt;
    final raw = json['created_at'] ?? json['timestamp'];
    if (raw is String && raw.isNotEmpty) createdAt = DateTime.tryParse(raw);

    return PersonalRun(
      runId: json['run_id'] as String? ?? '',
      candidateId: json['candidate_id'] as String? ?? '',
      score: (json['score'] as num?)?.toDouble() ?? 0.0,
      metrics: json['metrics'] is Map
          ? Map<String, dynamic>.from(json['metrics'] as Map)
          : const {},
      hardwareTier: json['hardware_tier'] as String? ?? 'unknown',
      modelId: json['model_id'] as String?,
      createdAt: createdAt,
    );
  }
}

/// Aggregated summary of the user's personal research runs.
class PersonalResearchSummary {
  final PersonalRun? bestRun;
  final int totalRuns;
  final DateTime? lastRunAt;

  const PersonalResearchSummary({
    this.bestRun,
    required this.totalRuns,
    this.lastRunAt,
  });

  factory PersonalResearchSummary.fromJson(Map<String, dynamic> json) {
    PersonalRun? bestRun;
    final rawBest = json['best_run'];
    if (rawBest is Map) {
      bestRun = PersonalRun.fromJson(Map<String, dynamic>.from(rawBest));
    }

    DateTime? lastRunAt;
    final rawLast = json['last_run_at'] ?? json['last_run'];
    if (rawLast is String && rawLast.isNotEmpty) {
      lastRunAt = DateTime.tryParse(rawLast);
    }

    return PersonalResearchSummary(
      bestRun: bestRun,
      totalRuns: (json['total_runs'] as num?)?.toInt() ?? 0,
      lastRunAt: lastRunAt,
    );
  }
}
