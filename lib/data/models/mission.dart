import 'package:cloud_firestore/cloud_firestore.dart';

// ---------------------------------------------------------------------------
// HumanRole  (§2.8.5)
// ---------------------------------------------------------------------------

enum HumanRole { owner, operator, observer }

extension HumanRoleExt on HumanRole {
  String get label {
    switch (this) {
      case HumanRole.owner:
        return 'Owner';
      case HumanRole.operator:
        return 'Operator';
      case HumanRole.observer:
        return 'Observer';
    }
  }

  bool get canSend => this != HumanRole.observer;
}

HumanRole humanRoleFromStr(String? s) {
  switch (s) {
    case 'operator':
      return HumanRole.operator;
    case 'observer':
      return HumanRole.observer;
    case 'owner':
    default:
      return HumanRole.owner;
  }
}

// ---------------------------------------------------------------------------
// MissionParticipant
// ---------------------------------------------------------------------------

enum ParticipantType { human, robot }

class MissionParticipant {
  final ParticipantType type;
  final String? uid;     // human
  final String? rrn;     // robot
  final String name;
  final HumanRole? role; // human-only
  final bool joined;     // false until joinMission() called for invitees

  const MissionParticipant({
    required this.type,
    this.uid,
    this.rrn,
    required this.name,
    this.role,
    this.joined = true,
  });

  factory MissionParticipant.fromMap(Map<String, dynamic> m) {
    final typeStr = m['type'] as String? ?? 'human';
    final isRobot = typeStr == 'robot';
    return MissionParticipant(
      type: isRobot ? ParticipantType.robot : ParticipantType.human,
      uid: m['uid'] as String?,
      rrn: m['rrn'] as String?,
      name: m['name'] as String? ?? 'Unknown',
      role: isRobot ? null : humanRoleFromStr(m['role'] as String?),
      joined: m['joined'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type == ParticipantType.robot ? 'robot' : 'human',
        if (uid != null) 'uid': uid,
        if (rrn != null) 'rrn': rrn,
        'name': name,
        if (role != null) 'role': role!.name,
        'joined': joined,
      };

  bool get isRobot => type == ParticipantType.robot;
  bool get isHuman => type == ParticipantType.human;

  /// Whether this human participant can send messages.
  bool get canSend => isHuman && (role?.canSend ?? false);
}

// ---------------------------------------------------------------------------
// Mission
// ---------------------------------------------------------------------------

enum MissionStatus { active, paused, completed }

class Mission {
  final String id;
  final String title;
  final String createdBy;
  final DateTime createdAt;
  final List<MissionParticipant> participants;
  final MissionStatus status;
  final DateTime lastMessageAt;
  final List<String> hiddenBy;

  const Mission({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.createdAt,
    required this.participants,
    required this.status,
    required this.lastMessageAt,
    this.hiddenBy = const [],
  });

  static DateTime _parseTs(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  static MissionStatus _statusFromStr(String? s) {
    switch (s) {
      case 'paused':
        return MissionStatus.paused;
      case 'completed':
        return MissionStatus.completed;
      default:
        return MissionStatus.active;
    }
  }

  factory Mission.fromMap(String docId, Map<String, dynamic> m) {
    final rawParts = (m['participants'] as List<dynamic>?) ?? [];
    final rawHiddenBy = (m['hidden_by'] as List<dynamic>?) ?? [];
    return Mission(
      id: docId,
      title: m['title'] as String? ?? 'Untitled Mission',
      createdBy: m['created_by'] as String? ?? '',
      createdAt: _parseTs(m['created_at']),
      participants: rawParts
          .map((p) => MissionParticipant.fromMap(p as Map<String, dynamic>))
          .toList(),
      status: _statusFromStr(m['status'] as String?),
      lastMessageAt: _parseTs(m['last_message_at']),
      hiddenBy: rawHiddenBy.map((e) => e as String).toList(),
    );
  }

  factory Mission.fromDocument(DocumentSnapshot doc) =>
      Mission.fromMap(doc.id, doc.data() as Map<String, dynamic>);

  List<MissionParticipant> get robotParticipants =>
      participants.where((p) => p.isRobot).toList();

  List<MissionParticipant> get humanParticipants =>
      participants.where((p) => p.isHuman).toList();

  int get robotCount => robotParticipants.length;
  int get humanCount => humanParticipants.length;

  /// Returns the role of the given uid, or null if not a participant.
  HumanRole? roleOf(String uid) {
    for (final p in participants) {
      if (p.isHuman && p.uid == uid) return p.role;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// MissionMessage
// ---------------------------------------------------------------------------

enum MissionMessageStatus { delivered, processing, responded }

class MissionMessage {
  final String id;
  final bool isFromRobot;
  final String? fromUid;
  final String? fromRrn;
  final String fromName;
  final HumanRole? fromRole; // present when from_type == human
  final String content;
  final List<String> mentions;
  final DateTime timestamp;
  final MissionMessageStatus status;
  final bool isDeleted;

  const MissionMessage({
    required this.id,
    required this.isFromRobot,
    this.fromUid,
    this.fromRrn,
    required this.fromName,
    this.fromRole,
    required this.content,
    required this.mentions,
    required this.timestamp,
    required this.status,
    this.isDeleted = false,
  });

  static DateTime _parseTs(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  static MissionMessageStatus _statusFromStr(String? s) {
    switch (s) {
      case 'processing':
        return MissionMessageStatus.processing;
      case 'responded':
        return MissionMessageStatus.responded;
      default:
        return MissionMessageStatus.delivered;
    }
  }

  /// Strips raw Python dict repr that leaked before bridge fix (e.g.
  /// "{'raw_text': 'Hello', 'action': None, 'model_used': 'unknown', ...}")
  static String _cleanContent(String raw) {
    final s = raw.trim();
    // Looks like a Python dict with raw_text key — extract the value
    final match = RegExp(r"'raw_text'\s*:\s*'([^']*)'").firstMatch(s);
    if (match != null) return match.group(1)!.trim();
    // Looks like a generic dict/map dump — return as-is (best effort)
    return s;
  }

  factory MissionMessage.fromMap(String docId, Map<String, dynamic> m) {
    final rawMentions = (m['mentions'] as List<dynamic>?) ?? [];
    return MissionMessage(
      id: docId,
      isFromRobot: (m['from_type'] as String? ?? 'human') == 'robot',
      fromUid: m['from_uid'] as String?,
      fromRrn: m['from_rrn'] as String?,
      fromName: m['from_name'] as String? ?? 'Unknown',
      fromRole: humanRoleFromStr(m['from_role'] as String?),
      content: _cleanContent(m['content'] as String? ?? ''),
      mentions: rawMentions.map((e) => e as String).toList(),
      timestamp: _parseTs(m['timestamp']),
      status: _statusFromStr(m['status'] as String?),
      isDeleted: m['deleted'] as bool? ?? false,
    );
  }

  factory MissionMessage.fromDocument(DocumentSnapshot doc) =>
      MissionMessage.fromMap(doc.id, doc.data() as Map<String, dynamic>);
}

// ---------------------------------------------------------------------------
// MissionInvite  — for the invite banner on fleet screen
// ---------------------------------------------------------------------------

class MissionInvite {
  final String missionId;
  final String missionTitle;
  final String invitedByUid;
  final String invitedByName;
  final HumanRole role;
  final DateTime invitedAt;
  final String status; // pending | accepted | declined

  const MissionInvite({
    required this.missionId,
    required this.missionTitle,
    required this.invitedByUid,
    required this.invitedByName,
    required this.role,
    required this.invitedAt,
    required this.status,
  });

  factory MissionInvite.fromMap(String docId, Map<String, dynamic> m) {
    dynamic rawTs = m['invited_at'];
    DateTime ts;
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs) ?? DateTime.now();
    } else {
      ts = DateTime.now();
    }
    return MissionInvite(
      missionId: docId,
      missionTitle: m['mission_title'] as String? ?? 'Mission',
      invitedByUid: m['invited_by_uid'] as String? ?? '',
      invitedByName: m['invited_by_name'] as String? ?? 'Someone',
      role: humanRoleFromStr(m['role'] as String?),
      invitedAt: ts,
      status: m['status'] as String? ?? 'pending',
    );
  }

  factory MissionInvite.fromDocument(DocumentSnapshot doc) =>
      MissionInvite.fromMap(doc.id, doc.data() as Map<String, dynamic>);
}
