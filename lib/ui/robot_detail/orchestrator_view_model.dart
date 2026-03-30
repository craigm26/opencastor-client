/// ViewModel for the Orchestrator Management screen.
///
/// Exposes [orchestratorsProvider] — fetches pending + active orchestrators
/// for a robot from the RRF API.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

const _rrfBaseUrl = 'https://api.rrf.rcan.dev';

/// Fetches the list of orchestrators (pending + active) for [rrn] from RRF.
final orchestratorsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, rrn) async {
    final resp = await http.get(
      Uri.parse('$_rrfBaseUrl/v2/orchestrators?fleet_rrn=$rrn'),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(
          data['orchestrators'] as List? ?? []);
    }
    return [];
  },
);
