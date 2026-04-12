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
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cloud_functions/cloud_functions.dart';
import '../../core/constants.dart';
import '../../core/media_service.dart';
import '../../core/speech_service.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/confirmation_dialog.dart';
import '../../ui/core/widgets/health_indicator.dart';
import '../../ui/chat/image_annotation_screen.dart';
import '../../data/models/command.dart' hide CommandScope;
import '../../data/models/slash_command.dart';
import '../../data/services/github_release_service.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;
import 'chat_bubble.dart';
import '../widgets/thinking_indicator.dart';
import 'lan_settings_card.dart';
import 'robot_detail_view_model.dart';
import '../../data/repositories/lan_mode_provider.dart';
import '../../data/services/ws_telemetry_service.dart';
import 'slash_command_palette.dart';
import 'slash_command_provider.dart';
import '../shared/error_view.dart';
import '../shared/empty_view.dart';
import '../shared/loading_view.dart';
import 'robot_telemetry_panel.dart';

enum _RobotAction { control, share, docs, capabilities, harness, lan }

class RobotDetailScreen extends ConsumerStatefulWidget {
  final String rrn;
  const RobotDetailScreen({super.key, required this.rrn});

  @override
  ConsumerState<RobotDetailScreen> createState() => _RobotDetailScreenState();
}

class _RobotDetailScreenState extends ConsumerState<RobotDetailScreen> {
  final _ctrl = TextEditingController();
  bool _sending = false;
  bool _thinking = false;
  String? _pendingCmdId; // command we're waiting on; null = not waiting
  Uint8List? _attachedImage;
  String _imageAnnotation = '';

  // In-memory set of hidden command IDs (resets on screen leave)
  final Set<String> _hiddenCmdIds = {};

  // Slash command palette state
  bool _showPalette = false;
  String _paletteQuery = '';

  // Version update banner
  String? _latestVersion;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onTextChanged);
    _fetchLatestVersion();
  }

  Future<void> _fetchLatestVersion() async {
    final v = await GitHubReleaseService.getLatestVersion();
    if (mounted && v != null) setState(() => _latestVersion = v);
  }

  void _showLanSettings(Robot robot) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: LanSettingsCard(
          rrn: robot.rrn,
          localIp: robot.telemetry['local_ip'] as String?,
        ),
      ),
    );
  }

  void _onTextChanged() {
    final text = _ctrl.text;
    if (text.startsWith('/')) {
      // Show palette with query = everything after the leading /
      final query = text.substring(1);
      // Don't show palette if there's a space (user is typing args, not selecting cmd)
      final hasArgs = query.contains(' ');
      if (!hasArgs) {
        if (!_showPalette || _paletteQuery != query) {
          setState(() {
            _showPalette = true;
            _paletteQuery = query;
          });
        }
        return;
      }
    }
    if (_showPalette) {
      setState(() => _showPalette = false);
    }
  }

  void _dismissPalette() {
    if (mounted && _showPalette) {
      setState(() => _showPalette = false);
    }
  }

  /// Called when user selects a command from the palette.
  void _onCommandSelected(SlashCommand cmd, Robot robot) {
    _dismissPalette();
    if (cmd.args.isEmpty && cmd.instant) {
      // Send immediately
      _ctrl.clear();
      _sendSlashCommand(cmd.cmd, [], robot);
    } else {
      // Fill input with command and space for args
      _ctrl.text = '${cmd.cmd} ';
      _ctrl.selection = TextSelection.collapsed(offset: _ctrl.text.length);
    }
  }

  /// Send a slash command by mapping to RCAN instruction + scope.
  Future<void> _sendSlashCommand(
      String cmd, List<String> args, Robot robot) async {
    setState(() => _sending = true);
    try {
      // Map slash command to RCAN instruction + scope
      final (instruction, scope) = _mapSlashCommand(cmd, args);
      final cmdId = await ref.read(robotRepositoryProvider).sendCommand(
            rrn: robot.rrn,
            instruction: instruction,
            scope: scope,
          );
      if (mounted) setState(() => _pendingCmdId = cmdId);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  /// Extract a human-readable response string from a command result map.
  ///
  /// Handles two result shapes:
  ///  - Chat/control: {raw_text, action, model_used, harness}
  ///  - Status: rich status dict with robot_name, version, brain_primary, etc.
  static String? _extractResponseText(Map<String, dynamic>? result, String? scope) {
    if (result == null) return null;

    // Chat-style response
    final rawText = result['raw_text'] as String?;
    if (rawText != null && rawText.isNotEmpty) return rawText;
    final response = result['response'] as String?;
    if (response != null && response.isNotEmpty) return response;
    final thought = result['thought'] as String?;
    if (thought != null && thought.isNotEmpty) return thought;

    // Status-scope result — format as a readable summary card
    if (result.containsKey('robot_name') || result.containsKey('version') ||
        result.containsKey('brain_primary')) {
      return _formatStatusResult(result);
    }

    // LIST_SKILLS result
    if (result.containsKey('skills') || result.containsKey('skill_list')) {
      final skills = (result['skills'] ?? result['skill_list']) as List?;
      if (skills != null && skills.isNotEmpty) {
        return '📦 Skills loaded:\n${skills.map((s) => '• $s').join('\n')}';
      }
    }

    return null;
  }

  static String _formatStatusResult(Map<String, dynamic> r) {
    final lines = <String>[];
    final name = r['robot_name'] as String?;
    if (name != null) lines.add('🤖 $name');
    final version = r['version'] as String?;
    if (version != null) lines.add('📦 v$version');
    final primary = r['brain_primary'] as Map?;
    if (primary != null) {
      lines.add('🧠 ${primary['provider']}/${primary['model']}');
    }
    final lastThought = r['last_thought'] as Map?;
    if (lastThought != null) {
      final lt = lastThought['raw_text'] as String?;
      if (lt != null && lt.isNotEmpty) lines.add('💭 "$lt"');
    }
    final security = r['security_posture'] as Map?;
    if (security != null) {
      final mode = security['mode'] as String?;
      final reasons = (security['reasons'] as List?)?.cast<String>() ?? [];
      String secLabel;
      String secDetail = '';
      switch (mode) {
        case 'full':
          secLabel = '🔒 Security: full (signed boot + RCAN token)';
          break;
        case 'degraded':
          secLabel = '⚠️ Security: degraded (dev mode — no hardware token)';
          if (reasons.isNotEmpty) {
            final readable = reasons.map((r) => r.replaceAll('_', ' ')).join(', ');
            secDetail = '   Missing: $readable';
          }
          break;
        default:
          secLabel = '🔓 Security: ${mode ?? 'unknown'}';
      }
      lines.add(secLabel);
      if (secDetail.isNotEmpty) lines.add(secDetail);
    }
    final speaking = r['speaking'] as bool?;
    lines.add(speaking == true ? '🔊 Speaking' : '🔇 Idle');
    final channels = r['channels_available'] as Map?;
    if (channels != null) {
      final active = channels.entries.where((e) => e.value == true).map((e) => e.key).join(', ');
      if (active.isNotEmpty) lines.add('📡 $active');
    }
    return lines.join('\n');
  }

  /// Normalize bare command names to slash form.
  /// e.g. "status", "STATUS", "/status" → "/status"
  static const _knownCommands = {
    'status', 'skills', 'optimize', 'upgrade', 'reboot',
    'stop', 'help', 'navigate', 'arm', 'camera',
  };
  static String _normalizeCommand(String text) {
    final lower = text.trim().toLowerCase();
    final bare = lower.startsWith('/') ? lower.substring(1).split(' ').first : lower.split(' ').first;
    if (_knownCommands.contains(bare)) {
      // Re-attach any arguments after the command name
      final rest = text.trim().split(' ').skip(1).join(' ');
      return rest.isEmpty ? '/$bare' : '/$bare $rest';
    }
    return text;
  }

  /// Map a slash command to (instruction, CommandScope).
  static (String, CommandScope) _mapSlashCommand(String cmd, List<String> args) {
    return switch (cmd) {
      '/status' => ('STATUS', CommandScope.status),
      '/skills' => ('LIST_SKILLS', CommandScope.status),
      '/optimize' => ('OPTIMIZE', CommandScope.system),
      '/upgrade' => (
          args.isNotEmpty ? 'UPGRADE: ${args.first}' : 'UPGRADE',
          CommandScope.system
        ),
      '/reboot' => ('REBOOT', CommandScope.system),
      '/reload-config' => ('RELOAD_CONFIG', CommandScope.system),
      '/share' => ('SHARE_CONFIG', CommandScope.system),
      '/install' => ('INSTALL: ${args.isNotEmpty ? args.first : ''}', CommandScope.system),
      '/pause' => ('PAUSE', CommandScope.system),
      '/resume' => ('RESUME', CommandScope.system),
      '/shutdown' => ('SHUTDOWN', CommandScope.system),
      '/snapshot' => ('SNAPSHOT', CommandScope.status),
      _ when cmd.startsWith('/') => (cmd.substring(1).toUpperCase() +
            (args.isNotEmpty ? ': ${args.join(' ')}' : ''),
          CommandScope.chat),
      _ => (cmd, CommandScope.chat),
    };
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onTextChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _showRrnQrCode(BuildContext context, String rrn, String robotName) {
    final qrData = rrn; // bare RRN — parseable by parseRrnFromScan
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(robotName,
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Scan to connect or request access',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
              QrImageView(
                data: qrData,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
                padding: const EdgeInsets.all(12),
              ),
              const SizedBox(height: 16),
              SelectableText(
                rrn,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    fontSize: 15),
              ),
              const SizedBox(height: 4),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 14),
                label: const Text('Copy RRN'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: rrn));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('RRN copied'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _shareConfigToHub(
      BuildContext ctx, String rrn, String robotName) async {
    // Prompt for title and tags
    String title = robotName;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Share Config to Hub'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Share $robotName\'s config to opencastor.com/explore?',
                style: Theme.of(dCtx).textTheme.bodyMedium),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              controller: TextEditingController(text: robotName),
              onChanged: (v) => title = v,
            ),
            const SizedBox(height: 8),
            Text(
              'Secrets (api_key, token, password) will be scrubbed automatically.',
              style: Theme.of(dCtx).textTheme.labelSmall?.copyWith(
                    color: Theme.of(dCtx).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: const Text('Share')),
        ],
      ),
    );

    if (confirmed != true || !ctx.mounted) return;

    // Show progress
    ScaffoldMessenger.of(ctx).showSnackBar(
      const SnackBar(
        content: Text('Uploading config to Hub...'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final functions = FirebaseFunctions.instance;
      final callable = functions.httpsCallable('uploadConfig');
      // Fetch the robot's config from its Firestore profile
      final result = await callable.call<Map<String, dynamic>>({
        'type': 'preset',
        'title': title,
        'tags': [rrn.toLowerCase(), 'shared-from-app'],
        'content': '# Config uploaded from OpenCastor app\n# RRN: $rrn\n',
        'filename': '${rrn.toLowerCase().replaceAll('-', '_')}.rcan.yaml',
        'robot_rrn': rrn,
        'public': true,
      });

      final data = result.data;
      final configUrl = data['url'] as String? ?? 'opencastor.com/explore';
      final installCmd = data['install_cmd'] as String? ?? '';

      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Shared! $configUrl'),
            duration: const Duration(seconds: 4),
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'View',
              onPressed: () => launchUrl(
                Uri.parse('https://$configUrl'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Show bottom sheet to hide a command from local view.
  void _showHideCmdSheet(BuildContext context, String cmdId) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.visibility_off_outlined),
                title: const Text('Hide message'),
                subtitle:
                    const Text('Hidden until you leave this screen'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _hiddenCmdIds.add(cmdId));
                },
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// Build list items for the chat ListView (reverse order):
  /// each command → ChatBubble for instruction + ChatBubble for response.
  /// Inserts DateSeparator when the date changes.
  List<Widget> _buildChatItems(List<RobotCommand> cmds) {
    final items = <Widget>[];
    DateTime? lastDate;

    // cmds are already ordered newest-first (watchCommands descending)
    for (final cmd in cmds) {
      // Skip hidden commands
      if (_hiddenCmdIds.contains(cmd.id)) continue;

      final date = cmd.issuedAt.toLocal();
      final dayKey = DateTime(date.year, date.month, date.day);

      // Robot response bubble (shown first in reverse list = shown after command)
      Widget? responseBubble;
      final responseText = _extractResponseText(cmd.result, cmd.scope.name);
      if (responseText != null) {
        responseBubble = GestureDetector(
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showHideCmdSheet(context, cmd.id);
          },
          child: ChatBubble(
            text: responseText,
            isUser: false,
            timestamp: cmd.issuedAt,
          ),
        );
      } else if (cmd.isFailed && cmd.error != null) {
        responseBubble = GestureDetector(
          onLongPress: () {
            HapticFeedback.mediumImpact();
            _showHideCmdSheet(context, cmd.id);
          },
          child: ChatBubble(
            text: '⚠ ${cmd.error}',
            isUser: false,
            timestamp: cmd.issuedAt,
          ),
        );
      } else if (!cmd.isComplete && !cmd.isFailed) {
        // Still processing — no long-press on loading bubble
        responseBubble = ChatBubble(
          text: '',
          isUser: false,
          isLoading: true,
          timestamp: cmd.issuedAt,
        );
      }

      if (responseBubble != null) items.add(responseBubble);

      // User command bubble with long-press to hide
      items.add(GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _showHideCmdSheet(context, cmd.id);
        },
        child: ChatBubble(
          text: cmd.instruction,
          isUser: true,
          isCommand: cmd.instruction.startsWith('/') ||
              _knownCommands.contains(cmd.instruction.toLowerCase().split(' ').first),
          timestamp: cmd.issuedAt,
        ),
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
    _dismissPalette();
    setState(() {
      _sending = true;
      _thinking = true;
    });
    final sendTime = DateTime.now();
    final capturedText = text;
    final capturedImage = _attachedImage;
    final capturedAnnotation = _imageAnnotation;
    _ctrl.clear();
    setState(() {
      _attachedImage = null;
      _imageAnnotation = '';
    });

    // 30-second hard timeout for thinking indicator.
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted && _thinking) setState(() { _thinking = false; _pendingCmdId = null; });
    });

    // Normalize bare command names to slash form (e.g. "status" → "/status")
    final normalizedText = _normalizeCommand(capturedText);

    // Handle slash commands typed directly into the input field
    if (normalizedText.startsWith('/') && capturedImage == null) {
      try {
        final parts = normalizedText.trim().split(' ');
        final cmd = parts.first;
        final args = parts.skip(1).toList();
        await _sendSlashCommand(cmd, args, robot);
      } finally {
        final elapsed = DateTime.now().difference(sendTime).inMilliseconds;
        final remaining = 1500 - elapsed;
        if (remaining > 0) {
          await Future.delayed(Duration(milliseconds: remaining));
        }
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

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

      final cmdId = await ref.read(sendChatProvider.notifier).send(
            rrn: robot.rrn,
            instruction: instruction,
            mediaChunks: mediaChunks,
          );
      if (mounted && cmdId != null) setState(() => _pendingCmdId = cmdId);
    } finally {
      final elapsed = DateTime.now().difference(sendTime).inMilliseconds;
      final remaining = 1500 - elapsed;
      if (remaining > 0) {
        await Future.delayed(Duration(milliseconds: remaining));
      }
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hydrate persisted LAN mode on first build
    ref.watch(lanModeInitProvider(widget.rrn));

    final robotAsync = ref.watch(robotDetailProvider(widget.rrn));
    // mergedCommandsProvider combines in-memory LAN commands + Firestore history
    final commandsAsync = ref.watch(mergedCommandsProvider(widget.rrn));

    return robotAsync.when(
      loading: () =>
          const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(body: ErrorView(error: e.toString())),
      data: (robot) {
        if (robot == null) {
          return const Scaffold(body: EmptyView(title: 'Robot not found'));
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
    // Clear thinking indicator only when OUR specific pending command completes.
    // Checking cmds.first was a race: it matched the PREVIOUS completed command
    // before the new one appeared in Firestore, clearing thinking immediately.
    ref.listen<AsyncValue<List<RobotCommand>>>(
      mergedCommandsProvider(widget.rrn),
      (prev, next) {
        next.whenData((cmds) {
          if (!_thinking) return;
          final id = _pendingCmdId;
          if (id == null) return; // no specific command to wait for
          final match = cmds.where((c) => c.id == id).firstOrNull;
          if (match != null && (match.isComplete || match.isFailed)) {
            if (mounted) setState(() { _thinking = false; _pendingCmdId = null; });
          }
        });
      },
    );

    final repo = ref.read(robotRepositoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(robot.name),
        actions: [
          HealthIndicator(isOnline: robot.isOnline, size: 8),
          const SizedBox(width: 4),
          // QR code — always visible (primary scan action)
          IconButton(
            icon: const Icon(Icons.qr_code_outlined),
            tooltip: 'Show Robot QR Code',
            onPressed: () => _showRrnQrCode(context, robot.rrn, robot.name),
          ),
          // ESTOP — always visible on mobile (Protocol 66 §4.1)
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
          // LAN mode indicator — shown when LAN is active
          if (ref.watch(lanModeProvider(widget.rrn)))
            Tooltip(
              message: 'LAN mode active — commands sent directly to robot',
              child: Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(Icons.wifi, size: 18,
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          // Overflow menu — secondary actions that don't need top-bar real estate
          PopupMenuButton<_RobotAction>(
            icon: const Icon(Icons.more_vert),
            tooltip: 'More',
            onSelected: (action) {
              switch (action) {
                case _RobotAction.control:
                  context.push('/robot/${robot.rrn}/control');
                case _RobotAction.share:
                  _shareConfigToHub(context, robot.rrn, robot.name);
                case _RobotAction.docs:
                  launchUrl(Uri.parse(AppConstants.docsFleetUi));
                case _RobotAction.capabilities:
                  context.push('/robot/${robot.rrn}/capabilities');
                case _RobotAction.harness:
                  context.push('/robot/${robot.rrn}/harness');
                case _RobotAction.lan:
                  _showLanSettings(robot);
              }
            },
            itemBuilder: (_) => [
              if (robot.hasCapability(RobotCapability.control))
                const PopupMenuItem(
                  value: _RobotAction.control,
                  child: ListTile(
                    leading: Icon(Icons.precision_manufacturing_outlined),
                    title: Text('Control'),
                    dense: true,
                  ),
                ),
              const PopupMenuItem(
                value: _RobotAction.capabilities,
                child: ListTile(
                  leading: Icon(Icons.tune_outlined),
                  title: Text('Capabilities'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: _RobotAction.harness,
                child: ListTile(
                  leading: Icon(Icons.account_tree_outlined),
                  title: Text('Harness'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: _RobotAction.share,
                child: ListTile(
                  leading: Icon(Icons.share_outlined),
                  title: Text('Share Config to Hub'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: _RobotAction.lan,
                child: ListTile(
                  leading: Icon(Icons.wifi),
                  title: Text('LAN Settings'),
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: _RobotAction.docs,
                child: ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Docs'),
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Revocation/offline/update banners ─────────────────────────────
          _RevocationBanner(robot: robot),
          _OfflineBanner(robot: robot),
          _UpdateBanner(
            currentVersion: robot.opencastorVersion,
            latestVersion: _latestVersion,
          ),

          // ── Telemetry + condensed badge row ───────────────────────────────
          _TelemetryPanel(robot: robot),
          RobotTelemetryPanel(robot: robot),
          _ShortcutRow(robot: robot),
          const Divider(height: 1),

          // ── Chat history with ChatBubbles + date separators ───────────────
          Expanded(
            child: commandsAsync.when(
              loading: () =>
                  const LoadingView(),
              error: (e, _) => ErrorView(error: e.toString()),
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

          // ── Robot thinking indicator ───────────────────────────────────────
          if (_thinking)
            Padding(
              padding:
                  const EdgeInsets.only(left: 12, right: 48, bottom: 8),
              child: ThinkingIndicator(robotName: robot.name),
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



          // ── Chat input with slash command palette ─────────────────────────
          if (robot.hasCapability(RobotCapability.chat) &&
              robot.isOnline &&
              !robot.isRevoked)
            _ChatInputWithPalette(
              ctrl: _ctrl,
              sending: _sending,
              onSend: () => _sendChat(robot),
              onImageAttached: (bytes, annotation) => setState(() {
                _attachedImage = bytes;
                _imageAnnotation = annotation;
              }),
              hasAttachment: _attachedImage != null,
              showPalette: _showPalette,
              paletteQuery: _paletteQuery,
              onPaletteSelect: (cmd) => _onCommandSelected(cmd, robot),
              onPaletteDismiss: _dismissPalette,
              rrn: widget.rrn,
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
      color: bg.withValues(alpha: 0.12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: bg.withValues(alpha: 0.4)))),
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
      color: AppTheme.warning.withValues(alpha: 0.08),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: AppTheme.warning.withValues(alpha: 0.3)))),
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

// ── Update banner ─────────────────────────────────────────────────────────────

class _UpdateBanner extends StatelessWidget {
  final String? currentVersion;
  final String? latestVersion;

  const _UpdateBanner({this.currentVersion, this.latestVersion});

  @override
  Widget build(BuildContext context) {
    if (latestVersion == null) return const SizedBox.shrink();
    final current = currentVersion;
    if (current == null || current == 'unknown' || current == latestVersion) {
      return const SizedBox.shrink();
    }
    const color = Color(0xFFE65100); // deep orange
    return Material(
      color: color.withValues(alpha: 0.10),
      child: InkWell(
        onTap: () => launchUrl(
          Uri.parse('https://github.com/craigm26/OpenCastor/releases/latest'),
          mode: LaunchMode.externalApplication,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: color.withValues(alpha: 0.35)))),
          child: Row(
            children: [
              Icon(Icons.system_update_alt_outlined, size: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Update available: v$current → v$latestVersion',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: color),
                ),
              ),
              Text(
                'View release notes',
                style: TextStyle(
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    color: color),
              ),
              const SizedBox(width: 4),
              Icon(Icons.open_in_new, size: 12, color: color),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Telemetry panel — condensed 3-item header ─────────────────────────────────

class _TelemetryPanel extends ConsumerWidget {
  final Robot robot;
  const _TelemetryPanel({required this.robot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final wsAsync = ref.watch(wsTelemetryProvider(robot.rrn));
    final liveData = wsAsync.valueOrNull;
    final isLive = liveData != null;

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Compact status row: avatar + status + version ─────────
          Row(
            children: [
              Hero(
                tag: 'robot-avatar-${robot.rrn}',
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: cs.primaryContainer,
                  child: Icon(Icons.precision_manufacturing_outlined,
                      size: 14, color: cs.onPrimaryContainer),
                ),
              ),
              const SizedBox(width: 8),
              _StatusBadge(isOnline: robot.isOnline),
              const SizedBox(width: 6),
              _VersionBadge(
                  version: robot.opencastorVersion ?? robot.version,
                  rrn: robot.rrn),
              if (isLive) ...[
                const SizedBox(width: 6),
                // Live WebSocket indicator dot
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22c55e), // green-500
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const Spacer(),
              _RobotProfileChip(rrn: robot.rrn),
            ],
          ),

        ],
      ),
    );
  }
}

// ── Shortcut pill row ─────────────────────────────────────────────────────────

class _ShortcutRow extends StatelessWidget {
  final Robot robot;
  const _ShortcutRow({required this.robot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Build list of shortcuts dynamically based on robot capabilities
    final shortcuts = <_Shortcut>[
      _Shortcut(
        icon: Icons.tune_outlined,
        label: 'Capabilities',
        onTap: () => context.push('/robot/${robot.rrn}/capabilities'),
      ),
      _Shortcut(
        icon: Icons.account_tree_outlined,
        label: 'Harness',
        onTap: () => context.push('/robot/${robot.rrn}/harness'),
      ),
      if (robot.hasCapability(RobotCapability.control))
        _Shortcut(
          icon: Icons.gamepad_outlined,
          label: 'Control',
          onTap: () => context.push('/robot/${robot.rrn}/control'),
        ),
      _Shortcut(
        icon: Icons.developer_board_outlined,
        label: 'Components',
        onTap: () => context.push('/robot/${robot.rrn}/capabilities/components'),
      ),
      _Shortcut(
        icon: Icons.handshake_outlined,
        label: 'Consent',
        onTap: () => context.push('/robot/${robot.rrn}/capabilities/consent'),
      ),
      _Shortcut(
        icon: Icons.science_outlined,
        label: 'Research',
        onTap: () => context.push('/robot/${robot.rrn}/research'),
      ),
      _Shortcut(
        icon: Icons.hub_outlined,
        label: 'MCP',
        onTap: () => context.push('/robot/${robot.rrn}/capabilities/mcp'),
      ),
      _Shortcut(
        icon: Icons.fact_check_outlined,
        label: 'Compliance',
        onTap: () => context.push('/robot/${robot.rrn}/compliance-report'),
      ),
    ];

    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: shortcuts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 4),
        itemBuilder: (_, i) => _ShortcutPill(s: shortcuts[i]),
      ),
    );
  }
}

class _Shortcut {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Shortcut({required this.icon, required this.label, required this.onTap});
}

class _ShortcutPill extends StatelessWidget {
  final _Shortcut s;
  const _ShortcutPill({required this.s});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: s.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Icon(s.icon, size: 18, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 3),
          Text(
            s.label,
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
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
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
                  ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)]
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

// ── OpenCastor version badge + latest version check ──────────────────────────

class _VersionBadge extends ConsumerWidget {
  final String? version;
  final String rrn;
  const _VersionBadge({required this.version, required this.rrn});

  /// Compares two date-based versions like 2026.3.14.6 and 2026.3.17.13.
  bool _isOutdated(String current, String latest) {
    final c = current.split('.').map(int.tryParse).whereType<int>().toList();
    final l = latest.split('.').map(int.tryParse).whereType<int>().toList();
    for (var i = 0; i < l.length && i < c.length; i++) {
      if (l[i] > c[i]) return true;
      if (l[i] < c[i]) return false;
    }
    return l.length > c.length;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final latestAsync = ref.watch(latestVersionProvider);
    final current = version;

    final currentBadge = Tooltip(
      message: current != null ? 'OpenCastor v$current (installed)' : 'Version unknown',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          current != null ? 'v$current' : 'v?',
          style: TextStyle(
              fontSize: 10,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600),
        ),
      ),
    );

    return latestAsync.when(
      loading: () => currentBadge,
      error: (_, __) => currentBadge,
      data: (latest) {
        if (latest == null || current == null) return currentBadge;
        final outdated = _isOutdated(current, latest);
        if (!outdated) return currentBadge;

        // Show update available badge next to current version
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            currentBadge,
            const SizedBox(width: 4),
            Tooltip(
              message: 'Update available: v$latest — tap to update this robot',
              child: GestureDetector(
                onTap: () => _confirmUpdate(context, ref, latest),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: cs.tertiary.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_upward,
                          size: 9, color: cs.onTertiaryContainer),
                      const SizedBox(width: 3),
                      Text(
                        'v$latest',
                        style: TextStyle(
                            fontSize: 10,
                            color: cs.onTertiaryContainer,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmUpdate(
      BuildContext context, WidgetRef ref, String latest) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update OpenCastor?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update robot $rrn to the latest release:'),
            const SizedBox(height: 8),
            Row(children: [
              Text('Installed: ',
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 13)),
              Text('v$version',
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 13)),
            ]),
            Row(children: [
              Text('Latest:    ',
                  style: TextStyle(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      fontSize: 13)),
              Text('v$latest',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(ctx).colorScheme.tertiary)),
            ]),
            const SizedBox(height: 12),
            Text(
              'This sends a pip install --upgrade opencastor command to the robot via RCAN chat scope.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Update')),
        ],
      ),
    );

    if (ok != true || !context.mounted) return;

    // Send UPGRADE via system scope — bridge routes to /api/system/upgrade
    try {
      final repo = ref.read(robotRepositoryProvider);
      await repo.sendCommand(
        rrn: rrn,
        instruction: 'UPGRADE: $latest',
        scope: CommandScope.system,
        reason: 'OTA update to v$latest requested from OpenCastor app',
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upgrading $rrn to v$latest — takes ~30s'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
        // Refresh badge after delay (pip takes ~20–30s)
        Future.delayed(const Duration(seconds: 35), () {
          if (context.mounted) ref.invalidate(latestVersionProvider);
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send upgrade: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}




// ── Hardware section — RAM, disk, temp, NPU ──────────────────────────────────

class _HardwareSection extends StatelessWidget {
  final Map<String, dynamic> t;
  const _HardwareSection({required this.t});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sys = t['system'] as Map<String, dynamic>?;
    if (sys == null || sys.isEmpty) return const SizedBox.shrink();

    final ramAvail = sys['ram_available_gb'] as num?;
    final ramTotal = sys['ram_total_gb'] as num?;
    final diskFree = sys['disk_free_gb'] as num?;
    final diskTotal = sys['disk_total_gb'] as num?;
    final cpuTemp = sys['cpu_temp_c'] as num?;
    // npu_detected may be bool (new bridge) or String (legacy) — handle both
    final npuRaw = sys['npu_detected'];
    final npu = npuRaw is bool ? (npuRaw ? (sys['npu_model'] as String? ?? 'NPU') : null) : npuRaw as String?;
    final npuTops = sys['npu_tops'] as num?;
    final gpuRaw = sys['gpu_detected'];
    final gpu = gpuRaw is bool ? (gpuRaw ? 'GPU' : null) : gpuRaw as String?;

    final chips = <Widget>[];

    if (ramAvail != null && ramTotal != null) {
      chips.add(_HwChip(
        Icons.memory_outlined,
        '${ramAvail.toStringAsFixed(1)} / ${ramTotal.toStringAsFixed(0)} GB',
        label: 'RAM',
        color: _ramColor(context, ramAvail.toDouble(), ramTotal.toDouble()),
      ));
    }
    if (diskFree != null && diskTotal != null) {
      chips.add(_HwChip(
        Icons.storage_outlined,
        '${diskFree.toStringAsFixed(0)} GB free',
        label: 'Disk',
      ));
    }
    if (cpuTemp != null) {
      chips.add(_HwChip(
        Icons.thermostat_outlined,
        '${cpuTemp.toStringAsFixed(0)}°C',
        label: 'CPU',
        color: _tempColor(context, cpuTemp.toDouble()),
      ));
    }
    if (npu != null) {
      final topsLabel = npuTops != null ? ' · ${npuTops.toStringAsFixed(0)} TOPS' : '';
      chips.add(_HwChip(Icons.bolt_outlined, '$npu$topsLabel', label: 'NPU',
          color: cs.primary));
    }
    if (gpu != null) {
      chips.add(_HwChip(Icons.videocam_outlined, gpu, label: 'GPU'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(spacing: 8, runSpacing: 6, children: chips),
    );
  }

  Color _ramColor(BuildContext ctx, double avail, double total) {
    final cs = Theme.of(ctx).colorScheme;
    final pct = avail / total;
    if (pct < 0.15) return cs.error;
    if (pct < 0.30) return Colors.orange;
    return cs.onSurfaceVariant;
  }

  Color _tempColor(BuildContext ctx, double t) {
    final cs = Theme.of(ctx).colorScheme;
    if (t >= 80) return cs.error;
    if (t >= 65) return Colors.orange;
    return cs.onSurfaceVariant;
  }
}

// ── Model runtime section — model, KV compression, llmfit ────────────────────

class _ModelRuntimeSection extends StatelessWidget {
  final Map<String, dynamic> t;
  const _ModelRuntimeSection({required this.t});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mr = t['model_runtime'] as Map<String, dynamic>?;
    if (mr == null || mr.isEmpty) return const SizedBox.shrink();

    final model = mr['active_model'] as String?;
    final provider = mr['provider'] as String?;
    final modelGb = mr['model_size_gb'] as num?;
    final ctx = mr['context_window'] as num?;
    final kvComp = mr['kv_compression'] as String?;
    final kvBits = mr['kv_bits'] as num?;
    final llmfitStatus = mr['llmfit_status'] as String?;
    final headroom = mr['llmfit_headroom_gb'] as num?;
    final tps = mr['tokens_per_sec'] as num?;

    if (model == null || model == 'unknown') return const SizedBox.shrink();

    final chips = <Widget>[];

    // Model + size
    final sizeLabel = modelGb != null ? ' · ${modelGb.toStringAsFixed(1)} GB' : '';
    chips.add(_HwChip(Icons.psychology_outlined, '$model$sizeLabel',
        label: provider ?? 'model'));

    // Context window
    if (ctx != null) {
      final ctxK = (ctx / 1024).round();
      chips.add(_HwChip(Icons.chat_bubble_outline, '${ctxK}k ctx', label: 'ctx'));
    }

    // TurboQuant KV
    if (kvComp != null && kvComp != 'none') {
      chips.add(_HwChip(
        Icons.compress_outlined,
        '${kvComp}${kvBits != null ? ' ${kvBits}-bit' : ''}',
        label: 'KV',
        color: cs.primary,
      ));
    }

    // LLMFit
    if (llmfitStatus != null) {
      final fitIcon = llmfitStatus == 'ok' ? Icons.check_circle_outline : Icons.warning_amber_outlined;
      final fitColor = llmfitStatus == 'ok' ? Colors.green : cs.error;
      final headroomLabel = headroom != null
          ? (llmfitStatus == 'ok'
              ? '+${headroom.toStringAsFixed(1)} GB'
              : '${headroom.abs().toStringAsFixed(1)} GB OOM')
          : '';
      chips.add(_HwChip(fitIcon, headroomLabel.isNotEmpty ? headroomLabel : llmfitStatus,
          label: 'fit', color: fitColor));
    }

    // Tokens/sec
    if (tps != null) {
      chips.add(_HwChip(Icons.speed_outlined, '${tps.toStringAsFixed(0)} tok/s',
          label: 'speed'));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(spacing: 8, runSpacing: 6, children: chips),
    );
  }
}

// ── Hardware chip ──────────────────────────────────────────────────────────────

class _HwChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? color;
  const _HwChip(this.icon, this.value, {required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fg),
          const SizedBox(width: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
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

// ── Chat input wrapper with slash command palette ─────────────────────────────

class _ChatInputWithPalette extends ConsumerWidget {
  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;
  final void Function(Uint8List, String) onImageAttached;
  final bool hasAttachment;
  final bool showPalette;
  final String paletteQuery;
  final void Function(SlashCommand) onPaletteSelect;
  final VoidCallback onPaletteDismiss;
  final String rrn;

  const _ChatInputWithPalette({
    required this.ctrl,
    required this.sending,
    required this.onSend,
    required this.onImageAttached,
    required this.hasAttachment,
    required this.showPalette,
    required this.paletteQuery,
    required this.onPaletteSelect,
    required this.onPaletteDismiss,
    required this.rrn,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commandsAsync = ref.watch(slashCommandsProvider(rrn));
    final commands = commandsAsync.maybeWhen(
      data: (cmds) => cmds,
      orElse: () => kStaticBuiltinCommands,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Palette shown above the text field
        if (showPalette)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: SlashCommandPalette(
              commands: commands,
              query: paletteQuery,
              onSelect: onPaletteSelect,
              onDismiss: onPaletteDismiss,
            ),
          ),
        _ChatInput(
          ctrl: ctrl,
          sending: sending,
          onSend: onSend,
          onImageAttached: onImageAttached,
          hasAttachment: hasAttachment,
        ),
      ],
    );
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

// ── Robot public profile chip ─────────────────────────────────────────────────

class _RobotProfileChip extends StatelessWidget {
  const _RobotProfileChip({required this.rrn});
  final String rrn;

  @override
  Widget build(BuildContext context) {
    final slug = rrn.toLowerCase().replaceAll('/', '-');
    final profileUrl = 'https://opencastor.com/robot/$slug';

    return ActionChip(
      label: const Text('Profile ↗'),
      avatar: const Icon(Icons.public_outlined, size: 14),
      visualDensity: VisualDensity.compact,
      tooltip: 'View public robot profile',
      onPressed: () => launchUrl(
        Uri.parse(profileUrl),
        mode: LaunchMode.externalApplication,
      ),
    );
  }
}
