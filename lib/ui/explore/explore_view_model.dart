import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../data/models/hub_config.dart';

// GCS public configs bucket — served via CDN, zero Firestore reads.
const _kGcsBase = 'https://storage.googleapis.com/opencastor-configs/configs';

// ── Filter state ─────────────────────────────────────────────────────────────

enum ExploreFilter { all, preset, skill, harness }

final exploreFilterProvider = StateProvider<ExploreFilter>((_) => ExploreFilter.all);
final exploreSearchProvider = StateProvider<String>((_) => '');

// ── Configs from Hub ─────────────────────────────────────────────────────────

final exploreConfigsProvider = FutureProvider.family<List<HubConfig>, ExploreFilter>(
  (ref, filter) async {
    // Primary: GCS public bucket (zero Firestore reads, CDN-cached, free at any scale)
    try {
      final indexRes = await http
          .get(Uri.parse('$_kGcsBase/index.json'))
          .timeout(const Duration(seconds: 5));
      if (indexRes.statusCode == 200) {
        final index = jsonDecode(indexRes.body) as Map<String, dynamic>;
        final ids = (index['ids'] as List?)?.cast<String>() ?? [];

        final futures = ids.map((id) async {
          try {
            final r = await http
                .get(Uri.parse('$_kGcsBase/$id.json'))
                .timeout(const Duration(seconds: 4));
            if (r.statusCode == 200) {
              return HubConfig.fromMap(_deepCast(jsonDecode(r.body) as Map));
            }
          } catch (_) {}
          return null;
        });

        final all = (await Future.wait(futures)).whereType<HubConfig>().toList();
        final configs = filter == ExploreFilter.all
            ? all
            : all.where((c) => c.type == filter.name).toList();
        configs.sort((a, b) {
          if (a.isOfficial && !b.isOfficial) return -1;
          if (!a.isOfficial && b.isOfficial) return 1;
          return b.stars.compareTo(a.stars);
        });
        if (configs.isNotEmpty) return configs;
      }
    } catch (_) {
      // GCS unreachable — fall through to CF
    }

    // Fallback: Firebase CF searchConfigs (reads from GCS-backed cache in CF)
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('searchConfigs');
      final params = <String, dynamic>{'limit': 50};
      if (filter != ExploreFilter.all) params['type'] = filter.name;
      final result = await callable.call<dynamic>(params);
      final raw = result.data;
      final data = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final results = (data['results'] as List?) ?? [];
      final configs =
          results.whereType<Map>().map((m) => HubConfig.fromMap(_deepCast(m))).toList();
      configs.sort((a, b) {
        if (a.isOfficial && !b.isOfficial) return -1;
        if (!a.isOfficial && b.isOfficial) return 1;
        return b.stars.compareTo(a.stars);
      });
      return configs;
    } catch (e) {
      throw Exception('Could not load hub configs: $e');
    }
  },
);

// ── Single config detail ─────────────────────────────────────────────────────

final hubConfigDetailProvider = FutureProvider.family<HubConfig, String>(
  (ref, configId) async {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('getConfig');
    final result = await callable.call<dynamic>({'id': configId});
    final raw = result.data;
    final map = raw is Map ? _deepCast(raw) : <String, dynamic>{};
    return HubConfig.fromMap(map);
  },
);

// ── Star toggle ──────────────────────────────────────────────────────────────

final starredConfigsProvider = StateProvider<Set<String>>((_) => {});

Future<bool> toggleStar(String configId, WidgetRef ref) async {
  try {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('starConfig');
    final result = await callable.call<dynamic>({'id': configId});
    final raw = result.data;
    final rmap =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final starred = rmap['starred'] as bool? ?? false;

    ref.read(starredConfigsProvider.notifier).update((s) {
      final updated = Set<String>.from(s);
      if (starred) {
        updated.add(configId);
      } else {
        updated.remove(configId);
      }
      return updated;
    });
    return starred;
  } catch (_) {
    return false;
  }
}

/// Deep-cast Map<Object?, Object?> → Map<String, dynamic> for Firebase responses.
Map<String, dynamic> _deepCast(Map m) => m.map(
      (k, v) => MapEntry(
        k?.toString() ?? '',
        v is Map
            ? _deepCast(v)
            : v is List
                ? v.map((e) => e is Map ? _deepCast(e) : e).toList()
                : v,
      ),
    );
