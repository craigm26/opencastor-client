/// RCAN v3.0 compliance data models (§22–§26).
///
/// All classes are immutable. JSON field names match the rcan.dev wire format
/// (snake_case). Dart fields use camelCase per Dart conventions.
library;

// ── Compliance Status ─────────────────────────────────────────────────────────

class ComplianceStatus {
  final String rrn;
  /// One of: "compliant" | "provisional" | "non_compliant" | "no_fria"
  final String complianceStatus;
  /// ISO-8601 timestamp, or null if no FRIA submitted.
  final String? friaSubmittedAt;
  final bool sigVerified;
  final bool overallPass;
  final bool prerequisiteWaived;

  const ComplianceStatus({
    required this.rrn,
    required this.complianceStatus,
    required this.friaSubmittedAt,
    required this.sigVerified,
    required this.overallPass,
    required this.prerequisiteWaived,
  });

  factory ComplianceStatus.fromJson(Map<String, dynamic> json) {
    // rcan.dev API nests FRIA fields under a 'fria' object; fall back to
    // top-level keys for forward-compat if the API shape is ever flattened.
    final fria = json['fria'] as Map<String, dynamic>?;
    return ComplianceStatus(
      rrn: json['rrn'] as String,
      complianceStatus: json['compliance_status'] as String,
      friaSubmittedAt: (fria?['submitted_at'] ?? json['fria_submitted_at']) as String?,
      sigVerified: (fria?['sig_verified'] ?? json['sig_verified'] as bool?) ?? false,
      overallPass: (fria?['overall_pass'] ?? json['overall_pass'] as bool?) ?? false,
      prerequisiteWaived: (fria?['prerequisite_waived'] ?? json['prerequisite_waived'] as bool?) ?? false,
    );
  }
}

// ── FRIA Document (§22) ───────────────────────────────────────────────────────

class FriaConformance {
  final double score;
  final int passCount;
  final int warnCount;
  final int failCount;

  const FriaConformance({
    required this.score,
    required this.passCount,
    required this.warnCount,
    required this.failCount,
  });

  factory FriaConformance.fromJson(Map<String, dynamic> json) {
    return FriaConformance(
      score: (json['score'] as num).toDouble(),
      passCount: (json['pass_count'] ?? json['pass'] ?? 0) as int,
      warnCount: (json['warn_count'] ?? json['warn'] ?? 0) as int,
      failCount: (json['fail_count'] ?? json['fail'] ?? 0) as int,
    );
  }
}

class FriaDocument {
  final String schema;
  final String generatedAt;
  final Map<String, dynamic> system;
  final Map<String, dynamic> deployment;
  final Map<String, dynamic> signingKey;
  final Map<String, dynamic> sig;
  final FriaConformance? conformance;

  const FriaDocument({
    required this.schema,
    required this.generatedAt,
    required this.system,
    required this.deployment,
    required this.signingKey,
    required this.sig,
    required this.conformance,
  });

  factory FriaDocument.fromJson(Map<String, dynamic> json) {
    // rcan.dev API wraps the signed blob under a 'document' key.
    // Fall back to root if callers pass the inner document directly.
    final doc = (json['document'] as Map<String, dynamic>?) ?? json;
    final conformanceJson = doc['conformance'] as Map<String, dynamic>?;
    return FriaDocument(
      schema: (doc['schema'] as String?) ?? '',
      generatedAt: (doc['generated_at'] as String?) ?? '',
      system: (doc['system'] as Map<String, dynamic>?) ?? {},
      deployment: (doc['deployment'] as Map<String, dynamic>?) ?? {},
      signingKey: (doc['signing_key'] as Map<String, dynamic>?) ?? {},
      sig: (doc['sig'] as Map<String, dynamic>?) ?? {},
      conformance: conformanceJson != null
          ? FriaConformance.fromJson(conformanceJson)
          : null,
    );
  }
}

// ── Safety Benchmark (§23) ────────────────────────────────────────────────────

class SafetyBenchmark {
  final String protocol;
  final double score;
  final int passCount;
  final int failCount;
  final String runAt;
  final String rrn;

  const SafetyBenchmark({
    required this.protocol,
    required this.score,
    required this.passCount,
    required this.failCount,
    required this.runAt,
    required this.rrn,
  });

  factory SafetyBenchmark.fromJson(Map<String, dynamic> json) {
    return SafetyBenchmark(
      protocol: json['protocol'] as String,
      score: (json['score'] as num).toDouble(),
      passCount: (json['pass_count'] ?? json['pass'] ?? 0) as int,
      failCount: (json['fail_count'] ?? json['fail'] ?? 0) as int,
      runAt: json['run_at'] as String,
      rrn: json['rrn'] as String,
    );
  }
}

// ── Instructions for Use (§24) ────────────────────────────────────────────────

class InstructionsForUse {
  final String rrn;
  final String robotName;
  final String intendedUse;
  final String operatingEnvironment;
  final List<String> contraindications;
  final String version;
  final String issuedAt;

  const InstructionsForUse({
    required this.rrn,
    required this.robotName,
    required this.intendedUse,
    required this.operatingEnvironment,
    required this.contraindications,
    required this.version,
    required this.issuedAt,
  });

  factory InstructionsForUse.fromJson(Map<String, dynamic> json) {
    return InstructionsForUse(
      rrn: json['rrn'] as String,
      robotName: json['robot_name'] as String,
      intendedUse: json['intended_use'] as String,
      operatingEnvironment: json['operating_environment'] as String,
      contraindications: (json['contraindications'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      version: json['version'] as String,
      issuedAt: json['issued_at'] as String,
    );
  }
}

// ── Post-Market Incident (§25) ────────────────────────────────────────────────

class PostMarketIncident {
  final String rrn;
  final String incidentId;
  final String severity;
  final String description;
  final String occurredAt;
  final String reportedAt;
  final String status;

  const PostMarketIncident({
    required this.rrn,
    required this.incidentId,
    required this.severity,
    required this.description,
    required this.occurredAt,
    required this.reportedAt,
    required this.status,
  });

  factory PostMarketIncident.fromJson(Map<String, dynamic> json) {
    return PostMarketIncident(
      rrn: json['rrn'] as String,
      incidentId: json['incident_id'] as String,
      severity: json['severity'] as String,
      description: json['description'] as String,
      occurredAt: json['occurred_at'] as String,
      reportedAt: json['reported_at'] as String,
      status: json['status'] as String,
    );
  }
}

// ── EU Register Entry (§26) ───────────────────────────────────────────────────

class EuRegisterEntry {
  final String rrn;
  final String robotName;
  final String manufacturer;
  final String annexIiiBasis;
  final String? friaSubmittedAt;
  final String complianceStatus;
  final String registeredAt;

  const EuRegisterEntry({
    required this.rrn,
    required this.robotName,
    required this.manufacturer,
    required this.annexIiiBasis,
    required this.friaSubmittedAt,
    required this.complianceStatus,
    required this.registeredAt,
  });

  factory EuRegisterEntry.fromJson(Map<String, dynamic> json) {
    return EuRegisterEntry(
      rrn: json['rrn'] as String,
      robotName: json['robot_name'] as String,
      manufacturer: json['manufacturer'] as String,
      annexIiiBasis: json['annex_iii_basis'] as String,
      friaSubmittedAt: json['fria_submitted_at'] as String?,
      complianceStatus: json['compliance_status'] as String,
      registeredAt: json['registered_at'] as String,
    );
  }
}
