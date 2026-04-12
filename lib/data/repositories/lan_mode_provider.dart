/// lan_mode_provider.dart — Riverpod providers for per-robot LAN connection mode.
///
/// LAN mode routes command sending directly to the robot's local REST API
/// (http://[local_ip]:8000) instead of through Firebase Cloud Functions.
///
/// State is persisted in SharedPreferences using keys:
///   lan_mode_{rrn}  → bool (enabled/disabled)
///   lan_token_{rrn} → String (robot's local API bearer token)
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/command.dart';
import '../services/lan_robot_service.dart';

export '../services/lan_robot_service.dart';

// ── SharedPreferences key helpers ─────────────────────────────────────────────

String _modeKey(String rrn) => 'lan_mode_$rrn';
String _tokenKey(String rrn) => 'lan_token_$rrn';

// ── In-memory LAN mode toggle ─────────────────────────────────────────────────

/// Whether LAN mode is currently enabled for [rrn].
///
/// Default false. Call [initLanMode] on first screen build to restore the
/// persisted preference from SharedPreferences.
final lanModeProvider = StateProvider.family<bool, String>((ref, rrn) => false);

/// Loads the persisted LAN mode flag and updates [lanModeProvider].
///
/// Watch in initState / first build:
/// ```dart
/// ref.listen(lanModeInitProvider(rrn), (_, __) {});
/// ```
final lanModeInitProvider = FutureProvider.family<void, String>((ref, rrn) async {
  final prefs = await SharedPreferences.getInstance();
  final enabled = prefs.getBool(_modeKey(rrn)) ?? false;
  ref.read(lanModeProvider(rrn).notifier).state = enabled;
});

// ── Per-robot LAN API token ───────────────────────────────────────────────────

/// The stored LAN API token for [rrn], null if not yet configured.
final lanTokenProvider = FutureProvider.family<String?, String>((ref, rrn) async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_tokenKey(rrn));
});

// ── Persisted mutation helpers ─────────────────────────────────────────────────

/// Toggle LAN mode and persist the new value.
Future<void> setLanMode(WidgetRef ref, String rrn, {required bool enabled}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_modeKey(rrn), enabled);
  ref.read(lanModeProvider(rrn).notifier).state = enabled;
}

/// Save the LAN API token and invalidate the cached provider.
Future<void> setLanToken(WidgetRef ref, String rrn, String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_tokenKey(rrn), token);
  ref.invalidate(lanTokenProvider(rrn));
}

/// Remove the stored LAN token and disable LAN mode.
Future<void> clearLanSettings(WidgetRef ref, String rrn) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_tokenKey(rrn));
  await prefs.setBool(_modeKey(rrn), false);
  ref.read(lanModeProvider(rrn).notifier).state = false;
  ref.invalidate(lanTokenProvider(rrn));
}

// ── In-memory LAN command log ─────────────────────────────────────────────────

/// In-memory list of synthetic [RobotCommand]s created by LAN sends.
///
/// These are not persisted to Firestore — they live only for the current session.
/// Prepended to the command history stream so LAN responses appear in chat.
final lanLocalCommandsProvider =
    StateProvider.family<List<RobotCommand>, String>((ref, rrn) => const []);

/// Append a completed LAN command to the in-memory log for [rrn].
void addLanCommand(WidgetRef ref, String rrn, RobotCommand cmd) {
  final current = ref.read(lanLocalCommandsProvider(rrn));
  ref.read(lanLocalCommandsProvider(rrn).notifier).state = [cmd, ...current];
}

// ── LAN service builder ───────────────────────────────────────────────────────

/// Build a [LanRobotService] for [rrn] if LAN mode is enabled and configured.
///
/// Returns null when:
///   - LAN mode is disabled
///   - [localIp] is absent from robot telemetry
///   - No API token has been stored
///   - The platform blocks http:// connections (HTTPS web)
Future<LanRobotService?> buildLanService(
  Ref ref,
  String rrn, {
  required String? localIp,
}) async {
  if (!LanRobotService.isAvailableOnPlatform) return null;
  if (!ref.read(lanModeProvider(rrn))) return null;
  if (localIp == null || localIp.isEmpty) return null;

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(_tokenKey(rrn));
  if (token == null || token.isEmpty) return null;

  return LanRobotService(localIp: localIp, apiToken: token);
}

/// Build a [LanRobotService] using a [WidgetRef] (convenience overload).
Future<LanRobotService?> buildLanServiceW(
  WidgetRef ref,
  String rrn, {
  required String? localIp,
}) async {
  if (!LanRobotService.isAvailableOnPlatform) return null;
  if (!ref.read(lanModeProvider(rrn))) return null;
  if (localIp == null || localIp.isEmpty) return null;

  final prefs = await SharedPreferences.getInstance();
  final token = prefs.getString(_tokenKey(rrn));
  if (token == null || token.isEmpty) return null;

  return LanRobotService(localIp: localIp, apiToken: token);
}
