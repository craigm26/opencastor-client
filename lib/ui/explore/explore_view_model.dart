import 'dart:convert';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/hub_config.dart';

// ── Filter state ─────────────────────────────────────────────────────────────

enum ExploreFilter { all, preset, skill, harness }

final exploreFilterProvider = StateProvider<ExploreFilter>((_) => ExploreFilter.all);
final exploreSearchProvider = StateProvider<String>((_) => '');

// ── Configs from Hub ─────────────────────────────────────────────────────────

final exploreConfigsProvider = FutureProvider.family<List<HubConfig>, ExploreFilter>(
  (ref, filter) async {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('searchConfigs');

    final params = <String, dynamic>{'limit': 50};
    if (filter != ExploreFilter.all) {
      params['type'] = filter.name;
    }

    try {
      final result = await callable.call<dynamic>(params);
      final raw = result.data;
      final data = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
      final results = (data['results'] as List?) ?? [];
      return results
          .whereType<Map>()
          .map((m) => HubConfig.fromMap(_deepCast(m)))
          .toList();
    } catch (e) {
      // Return empty on error — user sees empty state with retry
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
    final map = raw is Map ? _deepCast(raw as Map) : <String, dynamic>{};
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
    final rmap = raw is Map ? Map<String, dynamic>.from(raw as Map) : <String, dynamic>{};
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
