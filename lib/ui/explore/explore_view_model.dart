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
      final result = await callable.call<Map<String, dynamic>>(params);
      final data = result.data;
      final results = data['results'] as List? ?? [];
      return results
          .whereType<Map>()
          .map((m) => HubConfig.fromMap(Map<String, dynamic>.from(m)))
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
    final result = await callable.call<Map<String, dynamic>>({'id': configId});
    return HubConfig.fromMap(Map<String, dynamic>.from(result.data));
  },
);

// ── Star toggle ──────────────────────────────────────────────────────────────

final starredConfigsProvider = StateProvider<Set<String>>((_) => {});

Future<bool> toggleStar(String configId, WidgetRef ref) async {
  try {
    final functions = FirebaseFunctions.instance;
    final callable = functions.httpsCallable('starConfig');
    final result = await callable.call<Map<String, dynamic>>({'id': configId});
    final starred = result.data['starred'] as bool? ?? false;

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
