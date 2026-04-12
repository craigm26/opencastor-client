/// lan_robot_service.dart — Direct HTTP command sender for local-network robots.
///
/// Sends commands directly to the robot's OpenCastor REST API (port 8000)
/// instead of routing through Firebase Cloud Functions.
///
/// LAN commands offer ~30 ms round-trip vs ~500 ms via Firebase cloud relay.
/// The response payload is returned synchronously; no Firestore polling needed.
///
/// IMPORTANT — mixed-content restriction:
///   This only works on native mobile / desktop, or when the web app is served
///   over plain HTTP (never from app.opencastor.com which is HTTPS).
///   Use [isAvailableOnPlatform] to gate the UI toggle.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Result of a successful LAN command call.
class LanCommandResult {
  final String rawText;
  final String cmdId; // synthetic — not in Firestore
  final String? action;

  const LanCommandResult({
    required this.rawText,
    required this.cmdId,
    this.action,
  });
}

/// Sends commands directly to a robot's local REST API.
///
/// Usage:
/// ```dart
/// final svc = LanRobotService(localIp: '192.168.68.61', apiToken: 'secret');
/// final result = await svc.sendCommand(instruction: 'turn left');
/// ```
class LanRobotService {
  final String localIp;
  final String apiToken;

  static const int _port = 8000;
  static const Duration _timeout = Duration(seconds: 30);

  LanRobotService({required this.localIp, required this.apiToken});

  String get baseUrl => 'http://$localIp:$_port';

  /// True if direct HTTP calls are usable in the current platform context.
  ///
  /// On web over HTTPS the browser blocks http:// requests as mixed content.
  /// On native (Android / iOS / desktop), always returns true.
  static bool get isAvailableOnPlatform {
    if (!kIsWeb) return true;
    return Uri.base.scheme == 'http';
  }

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
      };

  /// Send a chat or control instruction to the robot brain.
  ///
  /// Maps to `POST /api/command` on the OpenCastor REST API.
  /// The API processes the instruction synchronously and returns the response text.
  Future<LanCommandResult> sendCommand({
    required String instruction,
    List<Map<String, dynamic>>? mediaChunks,
  }) async {
    final body = jsonEncode({
      'instruction': instruction,
      'channel': 'opencastor_app',
      if (mediaChunks != null && mediaChunks.isNotEmpty)
        'media_chunks': mediaChunks,
    });

    final resp = await http
        .post(Uri.parse('$baseUrl/api/command'), headers: _headers, body: body)
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw LanServiceException(
        'Command failed (HTTP ${resp.statusCode})',
        statusCode: resp.statusCode,
        body: resp.body,
      );
    }

    final data = _decode(resp.body);
    final rawText = (data['raw_text'] ?? data['thought'] ?? data['text'] ?? '').toString();
    final action = data['action']?.toString();
    final cmdId = 'lan-${DateTime.now().millisecondsSinceEpoch}';

    return LanCommandResult(rawText: rawText, cmdId: cmdId, action: action);
  }

  /// Send ESTOP — immediately halts all motors.
  ///
  /// Maps to `POST /api/stop` on the OpenCastor REST API.
  /// Uses a shorter 5 s timeout since safety commands must resolve quickly.
  Future<void> sendEstop() async {
    final resp = await http
        .post(Uri.parse('$baseUrl/api/stop'), headers: _headers)
        .timeout(const Duration(seconds: 5));

    if (resp.statusCode != 200) {
      throw LanServiceException(
        'ESTOP failed (HTTP ${resp.statusCode})',
        statusCode: resp.statusCode,
        body: resp.body,
      );
    }
  }

  /// Resume robot operation after ESTOP or pause.
  ///
  /// Maps to `POST /api/runtime/resume` on the OpenCastor REST API.
  Future<void> sendResume() async {
    final resp = await http
        .post(Uri.parse('$baseUrl/api/runtime/resume'), headers: _headers)
        .timeout(_timeout);

    if (resp.statusCode != 200) {
      throw LanServiceException(
        'Resume failed (HTTP ${resp.statusCode})',
        statusCode: resp.statusCode,
        body: resp.body,
      );
    }
  }

  /// Ping the robot to check LAN reachability.
  ///
  /// Calls `GET /health` (no auth required) with a 3 s timeout.
  Future<bool> ping() async {
    try {
      final resp = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Map<String, dynamic> _decode(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) return parsed;
    } catch (_) {}
    return {};
  }
}

/// Thrown when the robot's local API returns an error or is unreachable.
class LanServiceException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  const LanServiceException(this.message, {this.statusCode, this.body});

  @override
  String toString() => 'LanServiceException: $message';
}
