import 'package:cloud_firestore/cloud_firestore.dart';

enum RobotCapability { chat, nav, control, vision, status, discover }

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
  });

  factory Robot.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return Robot(
      rrn: m['rrn'] as String? ?? doc.id,
      name: m['name'] as String? ?? 'Unknown',
      owner: m['owner'] as String? ?? '',
      firebaseUid: m['firebase_uid'] as String? ?? '',
      ruri: m['ruri'] as String? ?? '',
      capabilities: ((m['capabilities'] as List<dynamic>?) ?? [])
          .map((c) => _parseCapability(c as String))
          .whereType<RobotCapability>()
          .toList(),
      version: m['version'] as String? ?? 'unknown',
      bridgeVersion: m['bridge_version'] as String? ?? 'unknown',
      registeredAt: m['registered_at'] != null
          ? DateTime.parse(m['registered_at'] as String)
          : DateTime.now(),
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
    );
  }

  bool get isOnline => status.online;

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
}
