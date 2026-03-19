import 'package:cloud_firestore/cloud_firestore.dart';

// ---------------------------------------------------------------------------
// MissionParticipant
// ---------------------------------------------------------------------------

enum ParticipantType { human, robot }

class MissionParticipant {
  final ParticipantType type;
  final String? uid;   // human
  final String? rrn;   // robot
  final String name;

  const MissionParticipant({
    required this.type,
    this.uid,
    this.rrn,
    required this.name,
  });

  factory MissionParticipant.fromMap(Map<String, dynamic> m) {
    final typeStr = m['type'] as String? ?? 'human';
    return MissionParticipant(
      type: typeStr == 'robot' ? ParticipantType.robot : ParticipantType.human,
      uid: m['uid'] as String?,
      rrn: m['rrn'] as String?,
      name: m['name'] as String? ?? 'Unknown',
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type == ParticipantType.robot ? 'robot' : 'human',
        if (uid != null) 'uid': uid,
        if (rrn != null) 'rrn': rrn,
        'name': name,
      };

  bool get isRobot => type == ParticipantType.robot;
  bool get isHuman => type == ParticipantType.human;
}

// ---------------------------------------------------------------------------
// Mission
// ---------------------------------------------------------------------------

enum MissionStatus { active, paused, completed }

class Mission {
  final String id;
  final String title;
  final String createdBy;       // firebase uid
  final DateTime createdAt;
  final List<MissionParticipant> participants;
  final MissionStatus status;
  final DateTime lastMessageAt;

  const Mission({
    required this.id,
    required this.title,
    required this.createdBy,
    required this.createdAt,
    required this.participants,
    required this.status,
    required this.lastMessageAt,
  });

  factory Mission.fromMap(String docId, Map<String, dynamic> m) {
    MissionStatus statusFromStr(String s) {
      switch (s) {
        case 'paused':
          return MissionStatus.paused;
        case 'completed':
          return MissionStatus.completed;
        default:
          return MissionStatus.active;
      }
    }

    DateTime _parseTs(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    final rawParts = (m['participants'] as List<dynamic>?) ?? [];
    return Mission(
      id: docId,
      title: m['title'] as String? ?? 'Untitled Mission',
      createdBy: m['created_by'] as String? ?? '',
      createdAt: _parseTs(m['created_at']),
      participants: rawParts
          .map((p) => MissionParticipant.fromMap(p as Map<String, dynamic>))
          .toList(),
      status: statusFromStr(m['status'] as String? ?? 'active'),
      lastMessageAt: _parseTs(m['last_message_at']),
    );
  }

  factory Mission.fromDocument(DocumentSnapshot doc) =>
      Mission.fromMap(doc.id, doc.data() as Map<String, dynamic>);

  List<MissionParticipant> get robotParticipants =>
      participants.where((p) => p.isRobot).toList();

  List<MissionParticipant> get humanParticipants =>
      participants.where((p) => p.isHuman).toList();
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
  final String content;
  final List<String> mentions;   // mentioned robot RRNs
  final DateTime timestamp;
  final MissionMessageStatus status;

  const MissionMessage({
    required this.id,
    required this.isFromRobot,
    this.fromUid,
    this.fromRrn,
    required this.fromName,
    required this.content,
    required this.mentions,
    required this.timestamp,
    required this.status,
  });

  factory MissionMessage.fromMap(String docId, Map<String, dynamic> m) {
    MissionMessageStatus statusFromStr(String s) {
      switch (s) {
        case 'processing':
          return MissionMessageStatus.processing;
        case 'responded':
          return MissionMessageStatus.responded;
        default:
          return MissionMessageStatus.delivered;
      }
    }

    DateTime _parseTs(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    final rawMentions = (m['mentions'] as List<dynamic>?) ?? [];
    return MissionMessage(
      id: docId,
      isFromRobot: (m['from_type'] as String? ?? 'human') == 'robot',
      fromUid: m['from_uid'] as String?,
      fromRrn: m['from_rrn'] as String?,
      fromName: m['from_name'] as String? ?? 'Unknown',
      content: m['content'] as String? ?? '',
      mentions: rawMentions.map((e) => e as String).toList(),
      timestamp: _parseTs(m['timestamp']),
      status: statusFromStr(m['status'] as String? ?? 'delivered'),
    );
  }

  factory MissionMessage.fromDocument(DocumentSnapshot doc) =>
      MissionMessage.fromMap(doc.id, doc.data() as Map<String, dynamic>);
}
