import 'package:cloud_firestore/cloud_firestore.dart';

enum RobotCapability { chat, nav, control, vision, status, discover }

/// Idle compute contribution stats from telemetry.contribute.
class ContributeStats {
  final bool enabled;
  final bool active;
  final String? project;
  final int workUnitsTotal;
  final int contributeMinutesToday;
  final int contributeMinutesLifetime;

  const ContributeStats({
    this.enabled = false,
    this.active = false,
    this.project,
    this.workUnitsTotal = 0,
    this.contributeMinutesToday = 0,
    this.contributeMinutesLifetime = 0,
  });

  factory ContributeStats.fromMap(Map<String, dynamic> map) => ContributeStats(
        enabled: map['enabled'] as bool? ?? false,
        active: map['active'] as bool? ?? false,
        project: map['project'] as String?,
        workUnitsTotal: (map['work_units_total'] as num?)?.toInt() ?? 0,
        contributeMinutesToday:
            (map['contribute_minutes_today'] as num?)?.toInt() ?? 0,
        contributeMinutesLifetime:
            (map['contribute_minutes_lifetime'] as num?)?.toInt() ?? 0,
      );
}

class RobotStatus {
  final bool online;
  final DateTime lastSeen;
  final String? error;

  const RobotStatus({
    required this.online,
    required this.lastSeen,
    this.error,
  });

  factory RobotStatus.fromMap(Map<String, dynamic> m) => RobotStatus(
        online: m['online'] as bool? ?? false,
        lastSeen: m['last_seen'] != null
            ? DateTime.parse(m['last_seen'] as String)
            : DateTime.fromMillisecondsSinceEpoch(0),
        error: m['error'] as String?,
      );
}

/// RCAN v1.5 — revocation status values (GAP-02 §13).
///
/// - [active]    Normal operation.
/// - [revoked]   Permanently revoked; commands blocked (ESTOP still accepted).
/// - [suspended] Temporarily restricted; commands blocked.
enum RevocationStatus { active, revoked, suspended }

class Robot {
  final String rrn;
  final String name;
  final String owner;
  final String firebaseUid;
  final String ruri;
  final List<RobotCapability> capabilities;
  final String version;
  final String bridgeVersion;
  final DateTime registeredAt;
  final RobotStatus status;
  final Map<String, dynamic> telemetry;

  // ── RCAN v1.5 fields ──────────────────────────────────────────────────────

  /// RCAN spec version this robot supports, e.g. "1.5" (GAP-12).
  final String? rcanVersion;

  /// Current revocation status (GAP-02 §13). Defaults to [RevocationStatus.active].
  final RevocationStatus revocationStatus;

  /// Whether this robot supports QoS level 2 (exactly-once) for ESTOP (GAP-11).
  final bool supportsQos2;

  /// Whether this robot supports command delegation chains (GAP-01).
  final bool supportsDelegation;

  /// Whether this robot can operate offline with cached credentials (GAP-06).
  final bool offlineCapable;

  // ── RCAN v1.6 fields ──────────────────────────────────────────────────────

  /// Supported transport encodings, e.g. ["http", "compact"] (GAP-17).
  final List<String> supportedTransports;

  /// Minimum Level of Assurance required for control-scope commands (GAP-16).
  final int minLoaForControl;

  /// Whether LoA policy is enforced (false = log-only, true = enforce) (GAP-16).
  final bool loaEnforcement;

  /// Whether this robot accepts multi-modal (image/audio) commands (GAP-18).
  final bool multimodalEnabled;

  /// Registry tier: "root" | "authoritative" | "community" (GAP-14).
  final String registryTier;

  /// OpenCastor runtime version reported by the robot bridge, e.g. "2026.3.17.1".
  final String? opencastorVersion;

  /// Idle compute contribution stats (from telemetry.contribute).
  final ContributeStats contribute;

  // ── RCAN v2.1 fields ──────────────────────────────────────────────────────

  /// SHA-256 of the signed firmware manifest (envelope field 13). null if not attested.
  final String? firmwareHash;

  /// URL to /.well-known/rcan-sbom.json (envelope field 14). null if not published.
  final String? attestationRef;

  /// Whether the robot has an AUTHORITY_ACCESS (41) handler registered.
  final bool authorityHandlerEnabled;

  /// Configured audit retention in days (EU AI Act Art. 12). null if not configured.
  final int? auditRetentionDays;

  // ── RCAN v2.2 fields — RRF provenance chain (§21) ─────────────────────────

  /// RRF-assigned component numbers linked to this robot.
  final List<String> rrfRcns;

  /// RRF-assigned model numbers used by this robot.
  final List<String> rrfRmns;

  /// RRF-assigned harness number for this robot's AI harness.
  final String? rrfRhn;

  /// ML-DSA-65 key ID (8-char hex).
  final String? pqKid;

  /// Hardware manufacturer.
  final String? manufacturer;

  /// Hardware model identifier.
  final String? hardwareModel;

  const Robot({
    required this.rrn,
    required this.name,
    required this.owner,
    required this.firebaseUid,
    required this.ruri,
    required this.capabilities,
    required this.version,
    required this.bridgeVersion,
    required this.registeredAt,
    required this.status,
    required this.telemetry,
    // v1.5 fields — all have safe defaults
    this.rcanVersion,
    this.revocationStatus = RevocationStatus.active,
    this.supportsQos2 = false,
    this.supportsDelegation = false,
    this.offlineCapable = false,
    // v1.6 fields — all have safe defaults
    this.supportedTransports = const ['http'],
    this.minLoaForControl = 1,
    this.loaEnforcement = false,
    this.multimodalEnabled = true,
    this.registryTier = 'community',
    this.opencastorVersion,
    this.contribute = const ContributeStats(),
    // v2.1 fields
    this.firmwareHash,
    this.attestationRef,
    this.authorityHandlerEnabled = false,
    this.auditRetentionDays,
    // v2.2 fields
    this.rrfRcns = const [],
    this.rrfRmns = const [],
    this.rrfRhn,
    this.pqKid,
    this.manufacturer,
    this.hardwareModel,
  });

  factory Robot.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return Robot(
      rrn: m['rrn'] as String? ?? doc.id,
      name: (m['name'] ?? m['robot_name']) as String? ?? 'Unknown',
      owner: m['owner'] as String? ?? '',
      firebaseUid: m['firebase_uid'] as String? ?? '',
      ruri: (m['ruri'] as String?) ?? ((m['telemetry'] as Map<String, dynamic>?)?['ruri'] as String?) ?? '',
      capabilities: ((m['capabilities'] as List<dynamic>?) ?? [])
          .map((c) => _parseCapability(c as String))
          .whereType<RobotCapability>()
          .toList(),
      version: (m['version'] ?? m['opencastor_version'] ?? (m['telemetry'] as Map<String, dynamic>?)?['version']) as String? ?? 'unknown',
      bridgeVersion: m['bridge_version'] as String? ?? 'unknown',
      registeredAt: () {
        final raw = m['registered_at'];
        if (raw == null) return DateTime.now();
        if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
        // Firestore Timestamp — toDate() returns DateTime
        try { return (raw as dynamic).toDate() as DateTime; } catch (_) {}
        return DateTime.now();
      }(),
      status: m['status'] != null
          ? RobotStatus.fromMap(m['status'] as Map<String, dynamic>)
          : RobotStatus(online: false, lastSeen: DateTime.now()),
      telemetry: m['telemetry'] as Map<String, dynamic>? ?? {},
      // ── RCAN v1.5 fields — safe defaults preserve v1.4 behaviour ──────────
      rcanVersion: m['rcan_version'] as String?,
      revocationStatus: _parseRevocationStatus(
          m['revocation_status'] as String?),
      supportsQos2: m['supports_qos_2'] as bool? ?? false,
      supportsDelegation: m['supports_delegation'] as bool? ?? false,
      offlineCapable: m['offline_capable'] as bool? ?? false,
      // ── RCAN v1.6 fields — safe defaults preserve v1.5 behaviour ──────────
      supportedTransports: ((m['supported_transports'] as List<dynamic>?) ?? ['http'])
          .cast<String>(),
      minLoaForControl: (m['min_loa_for_control'] as int?) ?? 1,
      loaEnforcement: m['loa_enforcement'] as bool? ?? false,
      multimodalEnabled: m['multimodal_enabled'] as bool? ?? true,
      registryTier: m['registry_tier'] as String? ?? 'community',
      opencastorVersion: _resolveVersion(
          m['opencastor_version'] as String?,
          m['telemetry']?['opencastor_version'] as String?,
          m['telemetry']?['version'] as String?,
        ),
      contribute: () {
        final raw = m['telemetry']?['contribute'] as Map<String, dynamic>?;
        return raw != null ? ContributeStats.fromMap(raw) : const ContributeStats();
      }(),
      // ── RCAN v2.1 fields — safe defaults preserve v1.x behaviour ──────────
      firmwareHash: m['firmware_hash'] as String?,
      attestationRef: m['attestation_ref'] as String?,
      authorityHandlerEnabled: m['authority_handler_enabled'] as bool? ?? false,
      auditRetentionDays: m['audit_retention_days'] as int?,
      // v2.2 provenance fields
      rrfRcns: ((m['rrf_rcns'] as List<dynamic>?) ?? []).cast<String>(),
      rrfRmns: ((m['rrf_rmns'] as List<dynamic>?) ?? []).cast<String>(),
      rrfRhn:  m['rrf_rhn'] as String?,
      pqKid:   m['pq_kid'] as String?,
      manufacturer:  m['manufacturer'] as String?,
      hardwareModel: m['model'] as String?,
    );
  }

  bool get isOnline => status.online;

  /// Hardware snapshot from last telemetry push (may be null if not yet received).
  Map<String, dynamic>? get systemInfo =>
      telemetry['system'] as Map<String, dynamic>?;

  /// Active model runtime info from last telemetry push.
  Map<String, dynamic>? get modelRuntime =>
      telemetry['model_runtime'] as Map<String, dynamic>?;

  bool get isRevoked => revocationStatus == RevocationStatus.revoked;

  bool get isSuspended => revocationStatus == RevocationStatus.suspended;

  /// True if the robot supports RCAN v1.5 or later.
  bool get isRcanV15 {
    if (rcanVersion == null) return false;
    final parts = rcanVersion!.split('.');
    if (parts.isEmpty) return false;
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return major > 1 || (major == 1 && minor >= 5);
  }

  /// True if this robot supports RCAN v1.6 or later.
  bool get isRcanV16 {
    if (rcanVersion == null) return false;
    final parts = rcanVersion!.split('.');
    if (parts.isEmpty) return false;
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return major > 1 || (major == 1 && minor >= 6);
  }

  /// True if the robot supports RCAN v2.1 or later.
  bool get isRcanV21 {
    if (rcanVersion == null) return false;
    final parts = rcanVersion!.split('.');
    if (parts.isEmpty) return false;
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return major >= 2 && minor >= 1;
  }

  /// True if firmware has been signed and attested (RCAN v2.1 §11).
  bool get isFirmwareAttested =>
      firmwareHash != null && firmwareHash!.startsWith('sha256:');

  /// True if SBOM is published (RCAN v2.1 §12).
  bool get isSbomPublished => attestationRef != null && attestationRef!.isNotEmpty;

  /// RCAN conformance level (L1–L5).
  int get conformanceLevel {
    if (!isRcanV21) {
      if (!isRcanV16) return isRcanV15 ? 2 : 1;
      return supportsQos2 ? 3 : 2;
    }
    if (!isFirmwareAttested || !isSbomPublished) return 3;
    if (!authorityHandlerEnabled) return 4;
    if ((auditRetentionDays ?? 0) < 3650) return 4;
    return 5;
  }

  /// True if LoA enforcement is active (loa_enforcement=true).
  bool get isLoaEnforced => loaEnforcement;

  /// True if the robot supports compact transport encoding (GAP-17).
  bool get supportsCompactTransport => supportedTransports.contains('compact');

  bool hasCapability(RobotCapability cap) => capabilities.contains(cap);

  static RobotCapability? _parseCapability(String s) {
    return RobotCapability.values.where((c) => c.name == s).firstOrNull;
  }

  static RevocationStatus _parseRevocationStatus(String? s) {
    if (s == null) return RevocationStatus.active;
    return RevocationStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => RevocationStatus.active,
    );
  }

  /// Returns the first non-null, non-empty, non-"unknown" version string from
  /// the candidates, in priority order.  Falls back to null if none qualify.
  static String? _resolveVersion(String? v1, String? v2, String? v3) {
    for (final v in [v1, v2, v3]) {
      if (v != null && v.isNotEmpty && v != 'unknown') return v;
    }
    return null;
  }
}
