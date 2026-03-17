/// Robot Detail Screen — RCAN v1.5/v1.6 status, chat, STT, media attachment.
///
/// Features:
///   - Status badge + OpenCastor version badge + single "Capabilities ▶" chip
///   - Speech-to-text chat input
///   - WhatsApp-style image annotation before sending
///   - Photo attachment in chat (base64 media_chunks)
///   - ESTOP always visible in app bar (Protocol 66 §4.1)
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
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/confirmation_dialog.dart';
import '../../ui/core/widgets/health_indicator.dart';
import '../../ui/chat/image_annotation_screen.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;
import 'chat_bubble.dart';
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
  String _imageAnnotation = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Build list items for the chat ListView (reverse order):
  /// each command → ChatBubble for instruction + ChatBubble for response.
  /// Inserts DateSeparator when the date changes.
  List<Widget> _buildChatItems(List<RobotCommand> cmds) {
    final items = <Widget>[];
    DateTime? lastDate;

    // cmds are already ordered newest-first (watchCommands descending)
    for (final cmd in cmds) {
      final date = cmd.issuedAt.toLocal();
      final dayKey = DateTime(date.year, date.month, date.day);

      // Robot response bubble (shown first in reverse list = shown after command)
      if (cmd.result?['raw_text'] != null) {
        items.add(ChatBubble(
          text: cmd.result!['raw_text'].toString(),
          isUser: false,
          timestamp: cmd.issuedAt,
        ));
      } else if (cmd.isFailed && cmd.error != null) {
        items.add(ChatBubble(
          text: '⚠ ${cmd.error}',
          isUser: false,
          timestamp: cmd.issuedAt,
        ));
      } else if (!cmd.isComplete && !cmd.isFailed) {
        // Still processing
        items.add(ChatBubble(
          text: '',
          isUser: false,
          isLoading: true,
          timestamp: cmd.issuedAt,
        ));
      }

      // User command bubble
      items.add(ChatBubble(
        text: cmd.instruction,
        isUser: true,
        timestamp: cmd.issuedAt,
      ));

      // Date separator (inserted after the bubble, so visible above it in reverse list)
      if (lastDate == null || lastDate != dayKey) {
        items.add(DateSeparator(date: date));
        lastDate = dayKey;
      }
    }
    return items;
  }

  Future<void> _sendChat(Robot robot) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty && _attachedImage == null) return;
    setState(() => _sending = true);
    final capturedText = text;
    final capturedImage = _attachedImage;
    final capturedAnnotation = _imageAnnotation;
    _ctrl.clear();
    setState(() {
      _attachedImage = null;
      _imageAnnotation = '';
    });
    try {
      String instruction = capturedText;
      List<Map<String, dynamic>>? mediaChunks;

      if (capturedImage != null) {
        final base64img = base64Encode(capturedImage);
        final mediaDesc = capturedAnnotation.isNotEmpty
            ? capturedAnnotation
            : 'an attached image';

        // Prepend image context to instruction so the robot agent sees it
        if (instruction.isEmpty) {
          instruction =
              "I'm sending you $mediaDesc. Please describe what you see.";
        } else {
          instruction = '$instruction [Image attached: $mediaDesc]';
        }

        mediaChunks = [
          {
            'mime_type': 'image/jpeg',
            'data': base64img,
            'description': mediaDesc,
          }
        ];
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

          // ── Telemetry + condensed badge row ───────────────────────────────
          _TelemetryPanel(robot: robot),
          const Divider(height: 1),

          // ── Chat history with ChatBubbles + date separators ───────────────
          Expanded(
            child: commandsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (cmds) {
                if (cmds.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet. Say hello!',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                  );
                }
                // Build flat list: messages in reverse + date separators
                final items = _buildChatItems(cmds);
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: items.length,
                  itemBuilder: (_, i) => items[i],
                );
              },
            ),
          ),

          // ── Image preview above input ──────────────────────────────────────
          if (_attachedImage != null)
            _ImagePreview(
              imageBytes: _attachedImage!,
              annotation: _imageAnnotation,
              onDismiss: () => setState(() {
                _attachedImage = null;
                _imageAnnotation = '';
              }),
            ),

          // ── Chat input with STT + attachment ──────────────────────────────
          if (robot.hasCapability(RobotCapability.chat) &&
              robot.isOnline &&
              !robot.isRevoked)
            _ChatInput(
              ctrl: _ctrl,
              sending: _sending,
              onSend: () => _sendChat(robot),
              onImageAttached: (bytes, annotation) => setState(() {
                _attachedImage = bytes;
                _imageAnnotation = annotation;
              }),
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
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: bg.withOpacity(0.4)))),
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

// ── Telemetry panel — condensed 3-item header ─────────────────────────────────

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
          // ── Header card: avatar + name + status ────────────────────
          Row(
            children: [
              // Hero-wrapped robot avatar (matches fleet card animation)
              Hero(
                tag: 'robot-avatar-${robot.rrn}',
                child: CircleAvatar(
                  radius: 20,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(
                    Icons.precision_manufacturing_outlined,
                    size: 18,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 1. Online/Offline status badge
                        _StatusBadge(isOnline: robot.isOnline),
                        const SizedBox(width: 8),
                        // 2. OpenCastor version badge
                        _VersionBadge(version: robot.opencastorVersion),
                      ],
                    ),
                  ],
                ),
              ),
              // 3. Single Capabilities ActionChip
              ActionChip(
                label: const Text('Capabilities ▶'),
                avatar: const Icon(Icons.tune_outlined, size: 14),
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    context.push('/robot/${robot.rrn}/capabilities'),
              ),
            ],
          ),

          // ── Telemetry chips row ────────────────────────────────────
          if (t['cpu_temp'] != null ||
              t['disk_pct'] != null ||
              robot.version.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                if (t['cpu_temp'] != null)
                  _Metric(Icons.thermostat_outlined,
                      '${(t['cpu_temp'] as num).toStringAsFixed(0)}°C'),
                if (t['disk_pct'] != null)
                  _Metric(Icons.storage_outlined,
                      '${(t['disk_pct'] as num).toStringAsFixed(0)}%'),
                if (robot.version.isNotEmpty)
                  _Metric(Icons.tag_outlined, robot.version),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Status badge (dot + label) ────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final bool isOnline;
  const _StatusBadge({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.onlineColor(isOnline);
    final label = isOnline ? 'Online' : 'Offline';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: isOnline
                  ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)]
                  : null,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color),
          ),
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

// ── Image preview ─────────────────────────────────────────────────────────────

class _ImagePreview extends StatelessWidget {
  final Uint8List imageBytes;
  final String annotation;
  final VoidCallback onDismiss;

  const _ImagePreview({
    required this.imageBytes,
    required this.annotation,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final displayAnnotation = annotation.isNotEmpty
        ? (annotation.length > 40
            ? '${annotation.substring(0, 40)}…'
            : annotation)
        : 'Image attached';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: cs.surfaceContainerLow,
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(imageBytes,
                width: 48, height: 48, fit: BoxFit.cover),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayAnnotation,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
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
  final void Function(Uint8List bytes, String annotation) onImageAttached;
  final bool hasAttachment;

  const _ChatInput({
    required this.ctrl,
    required this.sending,
    required this.onSend,
    required this.onImageAttached,
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
          content:
              Text('Speech recognition is not available on this platform'),
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

  /// Pick an image, then push the annotation screen.
  /// Returns the annotated result (or null if cancelled).
  Future<void> _pickAndAnnotate({required bool fromCamera}) async {
    final bytes = await _mediaSvc.pickImage(fromCamera: fromCamera);
    if (bytes == null || !mounted) return;

    final result = await Navigator.of(context).push<ImageAnnotationResult>(
      MaterialPageRoute(
        builder: (_) => ImageAnnotationScreen(imageBytes: bytes),
      ),
    );

    if (result != null && mounted) {
      widget.onImageAttached(result.imageBytes, result.annotation);
    }
  }

  Future<void> _showAttachmentSheet() async {
    if (!kIsWeb) {
      final choice = await showModalBottomSheet<String>(
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
      if (choice == null) return;
      await _pickAndAnnotate(fromCamera: choice == 'camera');
    } else {
      // Web — file picker only, then annotation
      await _pickAndAnnotate(fromCamera: false);
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
                final scale =
                    _sttListening ? 1.0 + 0.15 * _pulseCtrl.value : 1.0;
                return Transform.scale(scale: scale, child: child);
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
