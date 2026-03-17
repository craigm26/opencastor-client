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
    );
  }

  bool get isOnline => status.online;

  bool hasCapability(RobotCapability cap) => capabilities.contains(cap);

  // RCAN v1.5/v1.6 stubs for legacy screen compatibility
  String? get rcanVersion => telemetry['rcan_version'] as String?;
  bool get loaEnforcement => telemetry['loa_enforcement'] as bool? ?? false;
  int get minLoaForControl => telemetry['min_loa_for_control'] as int? ?? 1;
  bool get isRcanV16 {
    final v = rcanVersion;
    if (v == null) return false;
    final parts = v.split('.');
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return major > 1 || (major == 1 && minor >= 6);
  }

  static RobotCapability? _parseCapability(String s) {
    return RobotCapability.values.where((c) => c.name == s).firstOrNull;
  }
}
