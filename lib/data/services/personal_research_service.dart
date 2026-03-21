/// PersonalResearchService — proxies personal research API calls via robotApiGet.
///
/// All requests are routed through the Firebase `robotApiGet` callable, which
/// authenticates with the robot gateway server-side. Fails gracefully (null/false)
/// on any error so UI always degrades offline cleanly.
library;

import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';

import '../models/personal_research.dart';

class PersonalResearchService {
  static final _callable = FirebaseFunctions.instance.httpsCallable(
    'robotApiGet',
    options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
  );

  /// Fetches the personal research summary for [rrn].
  ///
  /// Returns null on any network/auth/decode error.
  Future<PersonalResearchSummary?> getSummary(String rrn) async {
    if (rrn.isEmpty) return null;
    try {
      final result = await _callable.call(<String, dynamic>{
        'rrn': rrn,
        'path': '/api/research/personal',
      });
      final body = _parseBody(result.data);
      if (body == null) return null;
      return PersonalResearchSummary.fromJson(body);
    } catch (_) {
      return null;
    }
  }

  /// Submits [runId] to the community leaderboard for verification.
  ///
  /// Returns true on HTTP 200, false otherwise.
  Future<bool> submitToCommunity(String rrn, String runId) async {
    if (rrn.isEmpty) return false;
    try {
      await _callable.call(<String, dynamic>{
        'rrn': rrn,
        'path': '/api/research/submit',
        'method': 'POST',
        'body': {'run_id': runId},
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Triggers a personal research run on the robot.
  ///
  /// Returns true on success, false otherwise.
  Future<bool> triggerRun(String rrn) async {
    if (rrn.isEmpty) return false;
    try {
      await _callable.call(<String, dynamic>{
        'rrn': rrn,
        'path': '/api/research/run',
        'method': 'POST',
        'body': {'personal': true},
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Parses the Cloud Function response body (handles string-encoded JSON,
  /// direct Map, or null).
  static Map<String, dynamic>? _parseBody(dynamic data) {
    if (data is! Map) return null;
    final raw = data['body'];
    if (raw is String) {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return Map<String, dynamic>.from(data);
  }
}
