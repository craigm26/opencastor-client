import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/hub_config.dart';

// ── Comments ─────────────────────────────────────────────────────────────────

class HubComment {
  const HubComment({
    required this.id,
    required this.configId,
    required this.text,
    required this.authorName,
    required this.authorUid,
    required this.createdAt,
    this.edited = false,
  });

  final String id;
  final String configId;
  final String text;
  final String authorName;
  final String authorUid;
  final DateTime createdAt;
  final bool edited;

  factory HubComment.fromMap(Map<String, dynamic> m) => HubComment(
        id: m['id'] as String? ?? '',
        configId: m['config_id'] as String? ?? '',
        text: m['text'] as String? ?? '',
        authorName: m['author_name'] as String? ?? 'anonymous',
        authorUid: m['author_uid'] as String? ?? '',
        createdAt: _parseTs(m['created_at']),
        edited: m['edited'] as bool? ?? false,
      );

  static DateTime _parseTs(dynamic v) {
    if (v == null) return DateTime.now();
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    if (v is Map && v['_seconds'] != null) {
      return DateTime.fromMillisecondsSinceEpoch((v['_seconds'] as int) * 1000);
    }
    return DateTime.now();
  }
}

final commentsProvider =
    FutureProvider.family<List<HubComment>, String>((ref, configId) async {
  final fn = FirebaseFunctions.instance.httpsCallable('getComments');
  final result = await fn.call<dynamic>({'config_id': configId});
  final raw = result.data;
  final map =
      raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  final list = (map['comments'] as List?) ?? [];
  return list
      .whereType<Map>()
      .map((m) => HubComment.fromMap(_deepCastMap(m)))
      .toList();
});

Future<void> addComment(String configId, String text) async {
  final fn = FirebaseFunctions.instance.httpsCallable('addComment');
  await fn.call<Map<String, dynamic>>({'config_id': configId, 'text': text});
}

Future<void> deleteComment(String configId, String commentId) async {
  final fn = FirebaseFunctions.instance.httpsCallable('deleteComment');
  await fn.call<Map<String, dynamic>>(
      {'config_id': configId, 'comment_id': commentId});
}

// ── Fork ─────────────────────────────────────────────────────────────────────

Future<Map<String, String>> forkConfig(
    String configId, String title, List<String> tags) async {
  final fn = FirebaseFunctions.instance.httpsCallable('forkConfig');
  final result = await fn.call<Map<String, dynamic>>(
      {'id': configId, 'title': title, 'tags': tags});
  return {
    'id': result.data['id'] as String? ?? '',
    'url': result.data['url'] as String? ?? '',
    'install_cmd': result.data['install_cmd'] as String? ?? '',
  };
}

Future<void> publishFork(String configId) async {
  final fn = FirebaseFunctions.instance.httpsCallable('publishFork');
  await fn.call<Map<String, dynamic>>({'id': configId});
}

// ── My Stars ─────────────────────────────────────────────────────────────────

final myStarsProvider = FutureProvider<List<HubConfig>>((ref) async {
  final fn = FirebaseFunctions.instance.httpsCallable('getMyStars');
  final result = await fn.call<dynamic>({});
  final raw = result.data;
  final map =
      raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  final list = (map['configs'] as List?) ?? [];
  return list
      .whereType<Map>()
      .map((m) => HubConfig.fromMap(_deepCastMap(m)))
      .toList();
});

// ── My Configs ────────────────────────────────────────────────────────────────

final myConfigsProvider = FutureProvider<List<HubConfig>>((ref) async {
  final fn = FirebaseFunctions.instance.httpsCallable('getMyConfigs');
  final result = await fn.call<dynamic>({});
  final raw = result.data;
  final map =
      raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  final list = (map['configs'] as List?) ?? [];
  return list
      .whereType<Map>()
      .map((m) => HubConfig.fromMap(_deepCastMap(m)))
      .toList();
});

/// Deep-cast a `Map<Object?, Object?>` → `Map<String, dynamic>`.
/// Firebase Functions returns untyped maps; this normalises nested values.
Map<String, dynamic> _deepCastMap(Map m) => m.map(
      (k, v) => MapEntry(
        k?.toString() ?? '',
        v is Map
            ? _deepCastMap(v)
            : v is List
                ? v.map((e) => e is Map ? _deepCastMap(e) : e).toList()
                : v,
      ),
    );
