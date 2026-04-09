/// ws_telemetry_service.dart — WebSocket real-time telemetry stream.
///
/// Connects to `ws://<robot-local-ip>:8001/ws/telemetry` when the robot
/// is on the same local network, and emits live telemetry maps at ~200 ms.
///
/// Falls back silently to Firestore telemetry when:
///   - The WebSocket URL is not configured in the robot doc
///   - The connection fails or times out
///   - The device is not on the local network
///
/// Usage:
///   ref.watch(wsTelemetryProvider(rrn))  → `AsyncValue<Map<String,dynamic>>`
///
/// The provider auto-reconnects with exponential back-off (max 30s).
/// It cancels cleanly when the widget is disposed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../ui/robot_detail/robot_detail_view_model.dart';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Emits the latest raw telemetry map from the robot's WebSocket stream.
/// Falls back to Firestore telemetry when WS is unavailable.
final wsTelemetryProvider =
    StreamProvider.family.autoDispose<Map<String, dynamic>, String>(
  (ref, rrn) async* {
    // Get robot doc to find WS endpoint
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    final robot = robotAsync.valueOrNull;

    // Resolve WS URL from robot config or well-known local port
    final wsUrl = _resolveWsUrl(robot?.telemetry);

    if (wsUrl == null) {
      // No WS URL — yield nothing, let callers fall back to Firestore
      return;
    }

    yield* _connectWithRetry(wsUrl);
  },
);

// ---------------------------------------------------------------------------
// WebSocket connection with auto-reconnect
// ---------------------------------------------------------------------------

/// Attempts to connect to [wsUrl] and yields telemetry maps.
/// Reconnects with exponential back-off on disconnect/error.
Stream<Map<String, dynamic>> _connectWithRetry(String wsUrl) async* {
  int retryDelayMs = 500;
  const maxDelayMs = 30000;

  while (true) {
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      // Wait for handshake (throws if server unreachable)
      await channel.ready.timeout(const Duration(seconds: 4));

      retryDelayMs = 500; // reset on successful connect

      await for (final raw in channel.stream) {
        if (raw is String) {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map<String, dynamic>) {
              yield decoded;
            }
          } catch (_) {
            // skip malformed JSON
          }
        }
      }
      // Stream ended cleanly — reconnect
    } catch (_) {
      // Connection failed or timed out — fall through to back-off
    } finally {
      channel?.sink.close();
    }

    await Future<void>.delayed(Duration(milliseconds: retryDelayMs));
    retryDelayMs = (retryDelayMs * 2).clamp(0, maxDelayMs);
  }
}

// ---------------------------------------------------------------------------
// URL resolution
// ---------------------------------------------------------------------------

/// Derives the WebSocket telemetry URL from the robot's telemetry map.
///
/// Priority:
///   1. telemetry['ws_telemetry_url'] (explicit, set by bridge)
///   2. telemetry['local_ip'] + well-known port/path
///   3. null (no WS available)
String? _resolveWsUrl(Map<String, dynamic>? telemetry) {
  if (telemetry == null) return null;

  // Explicit URL from bridge
  final explicit = telemetry['ws_telemetry_url'] as String?;
  if (explicit != null && explicit.isNotEmpty) {
    return _guardMixedContent(explicit);
  }

  // Derive from local IP — always ws://, only usable on HTTP or native
  final localIp = telemetry['local_ip'] as String?;
  if (localIp != null && localIp.isNotEmpty) {
    return _guardMixedContent('ws://$localIp:8001/ws/telemetry');
  }

  // Derive from gateway_url — replaceFirst(r'^http', 'ws') converts:
  //   http://foo  → ws://foo
  //   https://foo → wss://foo  (correct; regex matches 'http' not 'https')
  final gwUrl = telemetry['gateway_url'] as String?;
  if (gwUrl != null && gwUrl.isNotEmpty) {
    final base = gwUrl.replaceFirst(RegExp(r'^http'), 'ws');
    return _guardMixedContent('$base/ws/telemetry');
  }

  return null;
}

/// Returns null if [url] would be blocked as mixed content.
///
/// Browsers block ws:// connections from HTTPS pages. When the app is served
/// over HTTPS and the resolved URL is ws:// (e.g. a local robot IP without
/// TLS), there is no way to connect — skip it and let callers fall back to
/// Firestore telemetry instead of spamming mixed-content errors.
String? _guardMixedContent(String url) {
  if (kIsWeb && url.startsWith('ws://') && Uri.base.scheme == 'https') {
    return null;
  }
  return url;
}
