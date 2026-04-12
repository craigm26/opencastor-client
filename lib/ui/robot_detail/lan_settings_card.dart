/// lan_settings_card.dart — UI for configuring direct LAN connection to a robot.
///
/// Shows:
///   - Platform availability warning (hidden on supported platforms)
///   - LAN mode toggle
///   - API token input field
///   - Ping button to verify reachability
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/lan_mode_provider.dart';
import '../../data/services/lan_robot_service.dart';

class LanSettingsCard extends ConsumerStatefulWidget {
  final String rrn;
  final String? localIp; // from robot telemetry

  const LanSettingsCard({
    super.key,
    required this.rrn,
    required this.localIp,
  });

  @override
  ConsumerState<LanSettingsCard> createState() => _LanSettingsCardState();
}

class _LanSettingsCardState extends ConsumerState<LanSettingsCard> {
  final _tokenCtrl = TextEditingController();
  bool _tokenObscured = true;
  bool _pinging = false;
  String? _pingResult;

  @override
  void initState() {
    super.initState();
    // Populate token field from stored value
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final tokenAsync = await ref.read(lanTokenProvider(widget.rrn).future);
      if (mounted && tokenAsync != null) _tokenCtrl.text = tokenAsync;
    });
  }

  @override
  void dispose() {
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _ping() async {
    final localIp = widget.localIp;
    if (localIp == null || localIp.isEmpty) {
      setState(() => _pingResult = 'No local IP in telemetry');
      return;
    }
    setState(() {
      _pinging = true;
      _pingResult = null;
    });
    final token = _tokenCtrl.text.trim();
    final svc = token.isNotEmpty
        ? LanRobotService(localIp: localIp, apiToken: token)
        : LanRobotService(localIp: localIp, apiToken: '');
    final ok = await svc.ping();
    if (!mounted) return;
    setState(() {
      _pinging = false;
      _pingResult = ok
          ? '✓ Reachable at $localIp:8000'
          : '✗ Not reachable — check WiFi and robot gateway';
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(lanModeProvider(widget.rrn));
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.wifi, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Local Network (LAN) Mode',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Send commands directly to the robot on your WiFi. '
              '~30 ms vs ~500 ms via cloud.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),

            // ── Platform warning (HTTPS web) ───────────────────────────────
            if (kIsWeb && Uri.base.scheme == 'https') ...[
              const SizedBox(height: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 16, color: cs.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'LAN mode is not available when the app is served over '
                        'HTTPS. Use the Android / iOS app or a local dev build.',
                        style: TextStyle(fontSize: 12, color: cs.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Local IP badge ─────────────────────────────────────────────
            if (widget.localIp != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.router, size: 14, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    'Robot IP: ${widget.localIp}:8000',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      fontFamily: 'JetBrainsMono',
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_pinging)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    InkWell(
                      onTap: _ping,
                      child: Text(
                        'Ping',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                ],
              ),
              if (_pingResult != null) ...[
                const SizedBox(height: 4),
                Text(
                  _pingResult!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _pingResult!.startsWith('✓')
                        ? Colors.green
                        : cs.error,
                  ),
                ),
              ],
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'No local IP detected — make sure the robot bridge is running '
                'and has reported telemetry.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],

            const SizedBox(height: 12),

            // ── API token field ────────────────────────────────────────────
            TextField(
              controller: _tokenCtrl,
              obscureText: _tokenObscured,
              decoration: InputDecoration(
                labelText: 'Robot API token',
                hintText: 'Bearer token from robot\'s .env',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(_tokenObscured
                          ? Icons.visibility_off
                          : Icons.visibility),
                      onPressed: () =>
                          setState(() => _tokenObscured = !_tokenObscured),
                      tooltip: _tokenObscured ? 'Show token' : 'Hide token',
                    ),
                  ],
                ),
              ),
              style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 13),
            ),

            const SizedBox(height: 12),

            // ── Toggle + Save ──────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    title: const Text('Enable LAN mode'),
                    subtitle: Text(
                      enabled ? 'Commands sent directly to robot' : 'Using cloud relay',
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: enabled,
                    contentPadding: EdgeInsets.zero,
                    onChanged: LanRobotService.isAvailableOnPlatform
                        ? (v) => setLanMode(ref, widget.rrn, enabled: v)
                        : null,
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () async {
                    final token = _tokenCtrl.text.trim();
                    if (token.isNotEmpty) {
                      await setLanToken(ref, widget.rrn, token);
                    }
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('LAN settings saved')),
                      );
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            ),

            // ── Clear button ───────────────────────────────────────────────
            if (enabled) ...[
              const SizedBox(height: 4),
              TextButton(
                onPressed: () async {
                  _tokenCtrl.clear();
                  await clearLanSettings(ref, widget.rrn);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('LAN settings cleared')),
                    );
                  }
                },
                style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error),
                child: const Text('Clear LAN settings'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
