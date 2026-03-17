/// Robot Detail Screen — RCAN v1.5/v1.6 status, chat, STT, media attachment.
///
/// Features:
///   - RCAN v1.5/v1.6 badge row with navigational chiplets
///   - Speech-to-text chat input
///   - Photo attachment in chat (base64 media_chunks)
///   - OpenCastor version badge in header
///   - Docs link in app bar
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants.dart';
import '../../core/media_service.dart';
import '../../core/speech_service.dart';
import '../../data/models/robot.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/capability_badge.dart';
import '../../ui/core/widgets/confirmation_dialog.dart';
import '../../ui/core/widgets/health_indicator.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;
import 'robot_detail_view_model.dart';

class RobotDetailScreen extends ConsumerStatefulWidget {
  final String rrn;
  const RobotDetailScreen({super.key, required this.rrn});

  @override
  ConsumerState<RobotDetailScreen> createState() => _RobotDetailScreenState();
}

class _RobotDetailScreenState extends ConsumerState<RobotDetailScreen> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  Uint8List? _attachedImage;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendChat(Robot robot) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _attachedImage == null) return;
    setState(() => _sending = true);
    final capturedText = text;
    final capturedImage = _attachedImage;
    _ctrl.clear();
    setState(() => _attachedImage = null);
    try {
      // Build instruction; if image attached, append base64 note
      String instruction = capturedText;
      String? mediaChunks;
      if (capturedImage != null) {
        mediaChunks = base64Encode(capturedImage);
        if (instruction.isEmpty) instruction = '[image attached]';
      }
      await ref.read(sendChatProvider.notifier).send(
            rrn: robot.rrn,
            instruction: instruction,
            mediaChunks: mediaChunks,
          );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final robotAsync = ref.watch(robotDetailProvider(widget.rrn));
    final commandsAsync = ref.watch(commandsProvider(widget.rrn));

    return robotAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return const Scaffold(body: Center(child: Text('Robot not found')));
        }
        return _buildScaffold(context, robot, commandsAsync);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    Robot robot,
    AsyncValue<List<RobotCommand>> commandsAsync,
  ) {
    final repo = ref.read(robotRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(robot.name),
        actions: [
          HealthIndicator(isOnline: robot.isOnline, size: 8),
          const SizedBox(width: 8),
          // Docs link
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Fleet UI Docs',
            onPressed: () =>
                launchUrl(Uri.parse(AppConstants.docsFleetUi)),
          ),
          if (robot.hasCapability(RobotCapability.control))
            IconButton(
              icon: const Icon(Icons.precision_manufacturing_outlined),
              tooltip: 'Control',
              onPressed: () => context.push('/robot/${robot.rrn}/control'),
            ),
          // ESTOP — always available (Protocol 66 §4.1)
          if (robot.isOnline && !robot.isRevoked)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined,
                  color: AppTheme.estop),
              tooltip: 'ESTOP',
              onPressed: () async {
                final ok = await showEstopDialog(context, robot.name);
                if (ok && context.mounted) await repo.sendEstop(robot.rrn);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // ── Revocation/offline banners ─────────────────────────────────────
          _RevocationBanner(robot: robot),
          _OfflineBanner(robot: robot),

          // ── Telemetry + badges ─────────────────────────────────────────────
          _TelemetryPanel(robot: robot),
          const Divider(height: 1),

          // ── Command history ────────────────────────────────────────────────
          Expanded(
            child: commandsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (cmds) {
                if (cmds.isEmpty) {
                  return Center(
                    child: Text(
                      'No commands yet',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: cmds.length,
                  itemBuilder: (_, i) => _CommandTile(cmd: cmds[i]),
                );
              },
            ),
          ),

          // ── Image preview above input ──────────────────────────────────────
          if (_attachedImage != null)
            _ImagePreview(
              imageBytes: _attachedImage!,
              onDismiss: () => setState(() => _attachedImage = null),
            ),

          // ── Chat input with STT + attachment ──────────────────────────────
          if (robot.hasCapability(RobotCapability.chat) &&
              robot.isOnline &&
              !robot.isRevoked)
            _ChatInput(
              ctrl: _ctrl,
              sending: _sending,
              onSend: () => _sendChat(robot),
              onImagePicked: (bytes) =>
                  setState(() => _attachedImage = bytes),
              hasAttachment: _attachedImage != null,
            ),
        ],
      ),
    );
  }
}

// ── Revocation banner ─────────────────────────────────────────────────────────

class _RevocationBanner extends StatelessWidget {
  final Robot robot;
  const _RevocationBanner({required this.robot});

  @override
  Widget build(BuildContext context) {
    if (robot.revocationStatus == RevocationStatus.active) {
      return const SizedBox.shrink();
    }
    final isRevoked = robot.revocationStatus == RevocationStatus.revoked;
    final bg = isRevoked ? AppTheme.danger : AppTheme.warning;
    final icon = isRevoked
        ? Icons.block_outlined
        : Icons.pause_circle_outline;
    final label = isRevoked
        ? 'REVOKED — All commands blocked'
        : 'SUSPENDED — Commands temporarily blocked';
    return Material(
      color: bg.withOpacity(0.12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: bg.withOpacity(0.4)))),
        child: Row(
          children: [
            Icon(icon, size: 16, color: bg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: bg)),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Offline banner ────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  final Robot robot;
  const _OfflineBanner({required this.robot});

  @override
  Widget build(BuildContext context) {
    if (robot.isOnline || !robot.offlineCapable) return const SizedBox.shrink();
    return Material(
      color: AppTheme.warning.withOpacity(0.08),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: AppTheme.warning.withOpacity(0.3)))),
        child: Row(
          children: [
            Icon(Icons.wifi_off_outlined,
                size: 14, color: AppTheme.warning),
            const SizedBox(width: 8),
            Text(
              'OFFLINE — Robot operating on cached credentials',
              style: TextStyle(fontSize: 12, color: AppTheme.warning),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Telemetry panel ───────────────────────────────────────────────────────────

class _TelemetryPanel extends StatelessWidget {
  final Robot robot;
  const _TelemetryPanel({required this.robot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = robot.telemetry;

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Version badge + metrics row
          Row(
            children: [
              Expanded(
                child:
                    CapabilityRow(capabilities: robot.capabilities, compact: true),
              ),
              // OpenCastor version badge
              if (robot.opencastorVersion != null)
                _VersionBadge(version: robot.opencastorVersion!)
              else
                _VersionBadge(version: null),
              if (t['cpu_temp'] != null)
                _Metric(Icons.thermostat_outlined,
                    '${(t['cpu_temp'] as num).toStringAsFixed(0)}°C'),
              if (t['disk_pct'] != null)
                _Metric(Icons.storage_outlined,
                    '${(t['disk_pct'] as num).toStringAsFixed(0)}%'),
              _Metric(Icons.tag_outlined, robot.version),
            ],
          ),

          // RCAN v1.5 navigational chiplet row
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              // Online/Offline → status screen
              _NavChiplet(
                label: robot.isOnline ? 'Online' : 'Offline',
                icon: robot.isOnline ? Icons.wifi : Icons.wifi_off,
                color: AppTheme.onlineColor(robot.isOnline),
                tooltip: 'View full status & telemetry',
                onTap: () =>
                    context.push('/robot/${robot.rrn}/status'),
              ),
              if (robot.isRcanV15) ...[
                // RCAN version → capabilities screen
                _NavChiplet(
                  label: 'RCAN v${robot.rcanVersion}',
                  icon: Icons.verified_outlined,
                  color: Colors.purple,
                  tooltip: 'View RCAN capabilities',
                  onTap: () =>
                      context.push('/robot/${robot.rrn}/capabilities'),
                ),
                _NavChiplet(
                  label: 'Replay Protected',
                  icon: Icons.shield_outlined,
                  color: Colors.green,
                  tooltip: 'Replay attack prevention (GAP-03)',
                  onTap: () =>
                      context.push('/robot/${robot.rrn}/capabilities'),
                ),
              ],
              if (robot.supportsQos2)
                _NavChiplet(
                  label: 'ESTOP QoS ✓',
                  icon: Icons.check_circle_outline,
                  color: Colors.blue,
                  tooltip: 'Exactly-once ESTOP delivery — tap for capabilities',
                  onTap: () => context
                      .push('/robot/${robot.rrn}/capabilities#qos'),
                ),
              if (robot.supportsDelegation)
                _NavChiplet(
                  label: 'Delegation',
                  icon: Icons.account_tree_outlined,
                  color: Colors.teal,
                  tooltip: 'Command delegation supported (GAP-01)',
                  onTap: () =>
                      context.push('/robot/${robot.rrn}/capabilities'),
                ),
              if (robot.offlineCapable)
                _NavChiplet(
                  label: 'Offline Mode',
                  icon: Icons.cloud_off_outlined,
                  color: Colors.orange,
                  tooltip: 'Operates offline with cached credentials',
                  onTap: () =>
                      context.push('/robot/${robot.rrn}/capabilities'),
                ),
              // Control chiplet
              if (robot.hasCapability(RobotCapability.control))
                _NavChiplet(
                  label: 'Control',
                  icon: Icons.gamepad_outlined,
                  color: AppTheme.estop,
                  tooltip: 'Physical D-pad control',
                  onTap: () =>
                      context.push('/robot/${robot.rrn}/control'),
                ),
            ],
          ),

          // RCAN v1.6 badge row
          if (robot.isRcanV16) ...[
            const SizedBox(height: 4),
            _V16BadgeRow(robot: robot),
          ],
        ],
      ),
    );
  }
}

// ── OpenCastor version badge ──────────────────────────────────────────────────

class _VersionBadge extends StatelessWidget {
  final String? version;
  const _VersionBadge({required this.version});

  @override
  Widget build(BuildContext context) {
    final label =
        version != null ? 'OpenCastor v$version' : 'Version unknown';
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: label,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          version != null ? 'v$version' : 'v?',
          style: TextStyle(
              fontSize: 10,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

// ── Navigational chiplet (tappable badge) ─────────────────────────────────────

class _NavChiplet extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _NavChiplet({
    required this.label,
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.10),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 10, color: color.withOpacity(0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── RCAN v1.6 badge row ───────────────────────────────────────────────────────

class _V15Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String tooltip;
  const _V15Badge({
    required this.label,
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: color,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _V16BadgeRow extends StatelessWidget {
  final Robot robot;
  const _V16BadgeRow({required this.robot});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final t in robot.supportedTransports)
          _V15Badge(
            label: t.toUpperCase(),
            icon: _transportIcon(t),
            color: _transportColor(t),
            tooltip: 'Transport encoding: $t (GAP-17)',
          ),
        _V15Badge(
          label: robot.loaEnforcement
              ? 'LoA enforcement: ON'
              : 'LoA enforcement: OFF',
          icon: robot.loaEnforcement
              ? Icons.verified_user_outlined
              : Icons.person_outline,
          color: robot.loaEnforcement ? Colors.green : Colors.orange,
          tooltip: robot.loaEnforcement
              ? 'LoA policy enforced — min LoA ${robot.minLoaForControl} required (GAP-16)'
              : 'LoA policy log-only — enforcement disabled (GAP-16)',
        ),
        _V15Badge(
          label: _registryTierLabel(robot.registryTier),
          icon: _registryTierIcon(robot.registryTier),
          color: _registryTierColor(robot.registryTier),
          tooltip: 'Registry tier: ${robot.registryTier} (GAP-14)',
        ),
      ],
    );
  }

  IconData _transportIcon(String t) {
    switch (t.toLowerCase()) {
      case 'http':
        return Icons.http_outlined;
      case 'compact':
        return Icons.compress_outlined;
      case 'ble':
        return Icons.bluetooth_outlined;
      default:
        return Icons.swap_horiz_outlined;
    }
  }

  Color _transportColor(String t) {
    switch (t.toLowerCase()) {
      case 'http':
        return Colors.indigo;
      case 'compact':
        return Colors.deepPurple;
      case 'ble':
        return Colors.lightBlue;
      default:
        return Colors.blueGrey;
    }
  }

  String _registryTierLabel(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return 'Root Registry';
      case 'authoritative':
        return 'Authoritative Registry';
      default:
        return 'Community Registry';
    }
  }

  IconData _registryTierIcon(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return Icons.star_outlined;
      case 'authoritative':
        return Icons.verified_outlined;
      default:
        return Icons.people_outline;
    }
  }

  Color _registryTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return Colors.amber;
      case 'authoritative':
        return Colors.cyan;
      default:
        return Colors.blueGrey;
    }
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  const _Metric(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ── Command tile ──────────────────────────────────────────────────────────────

class _CommandTile extends StatelessWidget {
  final RobotCommand cmd;
  const _CommandTile({required this.cmd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color statusColor = cs.onSurfaceVariant;
    IconData statusIcon = Icons.schedule_outlined;
    if (cmd.isComplete) {
      statusColor = AppTheme.online;
      statusIcon = Icons.check_circle_outline;
    } else if (cmd.isFailed) {
      statusColor = AppTheme.danger;
      statusIcon = Icons.error_outline;
    } else if (cmd.isPending) {
      statusIcon = Icons.hourglass_empty;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cmd.instruction, style: const TextStyle(fontSize: 13)),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'sender_type: ${cmd.senderType ?? "human via OpenCastor app"}',
                    style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withOpacity(0.6),
                        fontFamily: 'monospace'),
                  ),
                ),
                if (cmd.result?['raw_text'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      cmd.result!['raw_text'].toString(),
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                if (cmd.error != null)
                  Text(cmd.error!,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.danger)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('HH:mm:ss').format(cmd.issuedAt.toLocal()),
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ── Image preview ─────────────────────────────────────────────────────────────

class _ImagePreview extends StatelessWidget {
  final Uint8List imageBytes;
  final VoidCallback onDismiss;
  const _ImagePreview({required this.imageBytes, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(imageBytes,
                width: 56, height: 56, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Image attached',
                style: TextStyle(
                    fontSize: 12,
                    color:
                        Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
            tooltip: 'Remove image',
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}

// ── Chat input with STT + media attachment ────────────────────────────────────

class _ChatInput extends StatefulWidget {
  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;
  final void Function(Uint8List bytes) onImagePicked;
  final bool hasAttachment;

  const _ChatInput({
    required this.ctrl,
    required this.sending,
    required this.onSend,
    required this.onImagePicked,
    required this.hasAttachment,
  });

  @override
  State<_ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<_ChatInput>
    with SingleTickerProviderStateMixin {
  final _speechSvc = SpeechService();
  final _mediaSvc = MediaService();
  bool _sttListening = false;
  bool _sttInitialized = false;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _initStt();
  }

  Future<void> _initStt() async {
    if (kIsWeb) return;
    final ok = await _speechSvc.initialize();
    if (mounted) setState(() => _sttInitialized = ok);
  }

  Future<void> _toggleStt() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Speech recognition is not available on this platform'),
        ),
      );
      return;
    }

    if (_sttListening) {
      await _speechSvc.stopListening();
      _pulseCtrl.stop();
      if (mounted) setState(() => _sttListening = false);
      return;
    }

    if (!_sttInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Microphone not available')),
      );
      return;
    }

    setState(() => _sttListening = true);
    _pulseCtrl.repeat(reverse: true);
    await _speechSvc.startListening(
      onResult: (text) {
        if (mounted) widget.ctrl.text = text;
      },
      onDone: () {
        if (mounted) {
          _pulseCtrl.stop();
          _pulseCtrl.reset();
          setState(() => _sttListening = false);
        }
      },
    );
  }

  Future<void> _showAttachmentSheet() async {
    if (!kIsWeb) {
      final result = await showModalBottomSheet<String>(
        context: context,
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, 'camera'),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Photo Library'),
                onTap: () => Navigator.pop(context, 'gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.attach_file_outlined),
                title: const Text('File'),
                onTap: () => Navigator.pop(context, 'file'),
              ),
            ],
          ),
        ),
      );
      if (result == null) return;
      final bytes = await _mediaSvc.pickImage(fromCamera: result == 'camera');
      if (bytes != null && mounted) widget.onImagePicked(bytes);
    } else {
      // Web — file picker only
      final bytes = await _mediaSvc.pickImage();
      if (bytes != null && mounted) widget.onImagePicked(bytes);
    }
  }

  @override
  void dispose() {
    _speechSvc.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            // Attachment button
            IconButton(
              icon: Icon(
                Icons.attach_file_outlined,
                color: widget.hasAttachment
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: 'Attach image',
              onPressed: widget.sending ? null : _showAttachmentSheet,
            ),

            // Text field
            Expanded(
              child: TextField(
                controller: widget.ctrl,
                decoration: const InputDecoration(
                  hintText: 'Send instruction…',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => widget.onSend(),
              ),
            ),
            const SizedBox(width: 6),

            // STT mic button
            AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, child) {
                final scale = _sttListening
                    ? 1.0 + 0.15 * _pulseCtrl.value
                    : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: child,
                );
              },
              child: Tooltip(
                message: kIsWeb
                    ? 'Mic not available on web'
                    : (_sttListening ? 'Stop listening' : 'Voice input'),
                child: IconButton(
                  icon: Icon(
                    _sttListening ? Icons.mic : Icons.mic_none_outlined,
                    color: _sttListening ? Colors.red : null,
                  ),
                  onPressed: widget.sending ? null : _toggleStt,
                ),
              ),
            ),
            const SizedBox(width: 4),

            // Send button
            widget.sending
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    onPressed: widget.onSend,
                    icon: const Icon(Icons.send_outlined),
                    iconSize: 18,
                  ),
          ],
        ),
      ),
    );
  }
}
