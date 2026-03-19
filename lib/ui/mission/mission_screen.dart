import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/mission.dart';
import '../widgets/thinking_indicator.dart';

// ---------------------------------------------------------------------------
// Consistent color palette — shared by robots (by RRN) and humans (by uid)
// ---------------------------------------------------------------------------

const _participantColors = [
  Color(0xFF0ea5e9), // sky
  Color(0xFF8b5cf6), // violet
  Color(0xFF22c55e), // green
  Color(0xFFf59e0b), // amber
  Color(0xFFef4444), // red
  Color(0xFF06b6d4), // cyan
  Color(0xFFec4899), // pink
  Color(0xFF84cc16), // lime
  Color(0xFFf97316), // orange
];

Color _colorForId(String id) {
  final hash = id.codeUnits.fold(0, (a, b) => a + b);
  return _participantColors[hash % _participantColors.length];
}

// ---------------------------------------------------------------------------
// MissionScreen
// ---------------------------------------------------------------------------

class MissionScreen extends StatefulWidget {
  final String missionId;
  const MissionScreen({super.key, required this.missionId});

  @override
  State<MissionScreen> createState() => _MissionScreenState();
}

class _MissionScreenState extends State<MissionScreen> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _sending = false;
  bool _panelExpanded = false;
  String? _error;

  // @mention suggestions
  List<String> _mentionSuggestions = [];

  // Thinking indicators: rrn → time when thinking started
  final _thinkingRobots = <String, DateTime>{};
  Timer? _thinkingTimeout;

  // Delivered receipt: set after a successful send
  int? _deliveredRobotCount;

  @override
  void dispose() {
    _thinkingTimeout?.cancel();
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  /// Build @mention suggestions from all participants (robots by name/RRN, humans by name).
  void _onTextChanged(String value, Mission mission) {
    final atIdx = value.lastIndexOf('@');
    if (atIdx == -1) {
      if (_mentionSuggestions.isNotEmpty) setState(() => _mentionSuggestions = []);
      return;
    }
    final prefix = value.substring(atIdx + 1).toLowerCase();
    final suggestions = <String>[];
    for (final p in mission.participants) {
      if (p.name.toLowerCase().startsWith(prefix)) {
        suggestions.add(p.name);
      }
      if (p.rrn != null && p.rrn!.toLowerCase().contains(prefix)) {
        suggestions.add(p.rrn!);
      }
    }
    setState(() => _mentionSuggestions = suggestions.toSet().toList());
  }

  void _insertMention(String token) {
    final text = _textCtrl.text;
    final atIdx = text.lastIndexOf('@');
    if (atIdx == -1) return;
    final newText = '${text.substring(0, atIdx)}@$token ';
    _textCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    setState(() => _mentionSuggestions = []);
  }

  Future<void> _deleteMessage(
      BuildContext context, String missionId, MissionMessage msg) async {
    final confirmed = await showModalBottomSheet<bool>(
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
                  color: cs.onSurfaceVariant.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete message',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(ctx, true),
              ),
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => Navigator.pop(ctx, false),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    if (confirmed != true) return;

    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('deleteMissionMessage');
      await fn.call({'missionId': missionId, 'msgId': msg.id});
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _sendMessage(String missionId, Mission mission) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final myRole = myUid != null ? mission.roleOf(myUid) : null;

    // Client-side guard: observers can't send
    if (myRole == HumanRole.observer) {
      setState(() =>
          _error = 'You are an observer in this mission — read only.');
      return;
    }

    final content = _textCtrl.text.trim();
    if (content.isEmpty) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    _textCtrl.clear();
    setState(() => _mentionSuggestions = []);

    try {
      final fn =
          FirebaseFunctions.instance.httpsCallable('sendMissionMessage');
      await fn.call({'missionId': missionId, 'content': content});

      // Mark robot participants as thinking and show delivered receipt.
      final robots =
          mission.participants.where((p) => p.isRobot).toList();
      setState(() {
        for (final r in robots) {
          if (r.rrn != null) _thinkingRobots[r.rrn!] = DateTime.now();
        }
        _deliveredRobotCount = robots.length;
      });

      // Auto-clear after 45 s in case the robot is offline.
      _thinkingTimeout?.cancel();
      _thinkingTimeout = Timer(const Duration(seconds: 45), () {
        if (mounted) {
          setState(() {
            _thinkingRobots.clear();
            _deliveredRobotCount = null;
          });
        }
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('missions')
          .doc(widget.missionId)
          .snapshots(),
      builder: (context, missionSnap) {
        if (missionSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (!missionSnap.hasData || !missionSnap.data!.exists) {
          return const Scaffold(
              body: Center(child: Text('Mission not found')));
        }

        final mission = Mission.fromDocument(missionSnap.data!);
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final myRole = myUid != null ? mission.roleOf(myUid) : null;
        final canSend = myRole != HumanRole.observer;

        return Scaffold(
          appBar: _MissionAppBar(
            mission: mission,
            panelExpanded: _panelExpanded,
            onTogglePanel: () =>
                setState(() => _panelExpanded = !_panelExpanded),
          ),
          body: Column(
            children: [
              // Participants panel (expandable)
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                child: _panelExpanded
                    ? _ParticipantsPanel(
                        mission: mission, currentUid: myUid ?? '')
                    : const SizedBox.shrink(),
              ),

              // Messages
              Expanded(
                child: _MessagesList(
                  missionId: widget.missionId,
                  mission: mission,
                  scrollCtrl: _scrollCtrl,
                  currentUid: myUid ?? '',
                  missionOwnerUid: mission.createdBy,
                  onLongPressMessage: (msg) =>
                      _deleteMessage(context, widget.missionId, msg),
                  onRobotMessageArrived: (rrn) {
                    if (_thinkingRobots.containsKey(rrn)) {
                      setState(() {
                        _thinkingRobots.remove(rrn);
                        if (_thinkingRobots.isEmpty) {
                          _thinkingTimeout?.cancel();
                          _deliveredRobotCount = null;
                        }
                      });
                    }
                  },
                ),
              ),

              // Thinking indicators (one per pending robot)
              if (_thinkingRobots.isNotEmpty)
                ...mission.participants
                    .where((p) =>
                        p.isRobot && _thinkingRobots.containsKey(p.rrn))
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(
                            left: 12, right: 48, top: 4, bottom: 4),
                        child: ThinkingIndicator(
                          robotName: p.name,
                          color: _colorForId(p.rrn!),
                        ),
                      ),
                    ),

              // Delivered receipt
              if (_deliveredRobotCount != null && _deliveredRobotCount! > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 14, bottom: 2),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '✓ Delivered to $_deliveredRobotCount'
                      ' robot${_deliveredRobotCount! == 1 ? '' : 's'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),

              // Error banner
              if (_error != null) _ErrorBanner(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),

              // @mention suggestions
              if (_mentionSuggestions.isNotEmpty)
                _MentionSuggestions(
                  suggestions: _mentionSuggestions,
                  mission: mission,
                  onSelect: _insertMention,
                ),

              // Input bar (hidden / read-only label for observers)
              if (!canSend)
                _ObserverBanner()
              else
                _InputBar(
                  controller: _textCtrl,
                  sending: _sending,
                  mission: mission,
                  onChanged: (v) => _onTextChanged(v, mission),
                  onSend: () => _sendMessage(widget.missionId, mission),
                ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

class _MissionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Mission mission;
  final bool panelExpanded;
  final VoidCallback onTogglePanel;
  const _MissionAppBar({
    required this.mission,
    required this.panelExpanded,
    required this.onTogglePanel,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final humanCount = mission.humanCount;
    final robotCount = mission.robotCount;
    final subtitle =
        '$humanCount human${humanCount != 1 ? "s" : ""} · $robotCount robot${robotCount != 1 ? "s" : ""}';

    return AppBar(
      title: Row(
        children: [
          const Icon(Icons.track_changes, size: 18, color: Color(0xFF0ea5e9)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mission.title,
                    style: const TextStyle(fontSize: 15),
                    overflow: TextOverflow.ellipsis),
                Text(
                  subtitle,
                  style: const TextStyle(
                      fontSize: 11, color: Color(0xFF0ea5e9)),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(panelExpanded
              ? Icons.group
              : Icons.group_outlined),
          tooltip: 'Participants',
          onPressed: onTogglePanel,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Participants panel
// ---------------------------------------------------------------------------

class _ParticipantsPanel extends StatelessWidget {
  final Mission mission;
  final String currentUid;
  const _ParticipantsPanel({required this.mission, required this.currentUid});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      color: isDark ? const Color(0xFF12142b) : const Color(0xFFF1F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Participants',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.8)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final p in mission.participants)
                _ParticipantChipFull(
                  participant: p,
                  isCurrentUser: p.uid == currentUid,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParticipantChipFull extends StatelessWidget {
  final MissionParticipant participant;
  final bool isCurrentUser;
  const _ParticipantChipFull(
      {required this.participant, required this.isCurrentUser});

  Color get _accentColor {
    final id = participant.rrn ?? participant.uid ?? participant.name;
    return _colorForId(id);
  }

  @override
  Widget build(BuildContext context) {
    final label = isCurrentUser ? '${participant.name} (you)' : participant.name;
    final roleLabel =
        participant.isHuman && participant.role != null
            ? participant.role!.label
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _accentColor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accentColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            participant.isRobot
                ? Icons.smart_toy_outlined
                : Icons.person_outline,
            size: 12,
            color: _accentColor,
          ),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  color: _accentColor,
                  fontWeight: FontWeight.w600)),
          if (roleLabel != null) ...[
            const SizedBox(width: 4),
            Text('· $roleLabel',
                style: TextStyle(
                    fontSize: 10,
                    color: _accentColor.withOpacity(0.7))),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Messages list
// ---------------------------------------------------------------------------

class _MessagesList extends StatelessWidget {
  final String missionId;
  final Mission mission;
  final ScrollController scrollCtrl;
  final String currentUid;
  final String missionOwnerUid;
  /// Called when a new robot message is detected in the stream.
  final void Function(String rrn) onRobotMessageArrived;
  /// Called when user long-presses a message bubble.
  final void Function(MissionMessage msg) onLongPressMessage;

  const _MessagesList({
    required this.missionId,
    required this.mission,
    required this.scrollCtrl,
    required this.currentUid,
    required this.missionOwnerUid,
    required this.onRobotMessageArrived,
    required this.onLongPressMessage,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('missions')
          .doc(missionId)
          .collection('messages')
          .orderBy('timestamp')
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No messages yet.\nSay something to your robots!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        }

        // Notify parent when a robot message is detected so it can clear
        // the thinking indicator for that robot.
        if (docs.isNotEmpty) {
          final latestDoc = docs.last;
          final latestMsg = MissionMessage.fromDocument(latestDoc);
          if (latestMsg.isFromRobot && latestMsg.fromRrn != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onRobotMessageArrived(latestMsg.fromRrn!);
            });
          }
        }

        return ListView.builder(
          controller: scrollCtrl,
          padding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final msg = MissionMessage.fromDocument(docs[i]);
            final isMe =
                !msg.isFromRobot && msg.fromUid == currentUid;
            final canDelete = !msg.isDeleted &&
                (msg.fromUid == currentUid ||
                    currentUid == missionOwnerUid);

            Widget bubble;
            if (msg.isFromRobot) {
              final rrn = msg.fromRrn ?? '';
              bubble = _RobotMessageBubble(
                  msg: msg, accentColor: _colorForId(rrn));
            } else if (isMe) {
              bubble = _HumanMessageBubble(msg: msg, isMe: true);
            } else {
              final uid = msg.fromUid ?? msg.fromName;
              bubble = _HumanMessageBubble(
                  msg: msg,
                  isMe: false,
                  accentColor: _colorForId(uid));
            }

            if (canDelete) {
              return GestureDetector(
                onLongPress: () {
                  HapticFeedback.mediumImpact();
                  onLongPressMessage(msg);
                },
                child: bubble,
              );
            }
            return bubble;
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Message bubbles
// ---------------------------------------------------------------------------

class _HumanMessageBubble extends StatelessWidget {
  final MissionMessage msg;
  final bool isMe;
  final Color? accentColor; // null = self (blue)
  const _HumanMessageBubble(
      {required this.msg, required this.isMe, this.accentColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = accentColor ?? const Color(0xFF0ea5e9);
    final roleStr =
        msg.fromRole != null ? ' · ${msg.fromRole!.label}' : '';

    // Deleted placeholder
    if (msg.isDeleted) {
      return Padding(
        padding: EdgeInsets.only(
            bottom: 8, left: isMe ? 48 : 0, right: isMe ? 0 : 48),
        child: Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.delete_outline,
                  size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Text('This message was deleted',
                  style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 13,
                      fontStyle: FontStyle.italic)),
            ]),
          ),
        ),
      );
    }

    if (isMe) {
      // Right-aligned self bubble
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'You$roleStr · ${_timeLabel(msg.timestamp)}',
                    style: TextStyle(
                        fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: const BoxDecoration(
                      color: Color(0xFF0ea5e9),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(4),
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                    ),
                    child: Text(
                      msg.content,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Left-aligned other-human bubble with person avatar
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Person avatar
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 8, top: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: 1.5),
            ),
            child: Icon(Icons.person_outline, size: 16, color: color),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${msg.fromName}$roleStr · ${_timeLabel(msg.timestamp)}',
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: color, width: 3),
                    ),
                    color: isDark
                        ? const Color(0xFF1a1b2e)
                        : const Color(0xFFEDE9FE),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child:
                      Text(msg.content, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RobotMessageBubble extends StatelessWidget {
  final MissionMessage msg;
  final Color accentColor;
  const _RobotMessageBubble(
      {required this.msg, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Deleted placeholder
    if (msg.isDeleted) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8, right: 48),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.delete_outline, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text('This message was deleted',
                style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 13,
                    fontStyle: FontStyle.italic)),
          ]),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.only(right: 8, top: 4),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(color: accentColor, width: 1.5),
            ),
            child: Icon(Icons.smart_toy_outlined,
                size: 16, color: accentColor),
          ),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${msg.fromName} · ${_timeLabel(msg.timestamp)}',
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                        left: BorderSide(color: accentColor, width: 3)),
                    color: isDark
                        ? const Color(0xFF1a1b2e)
                        : const Color(0xFFF1F5F9),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(16),
                      bottomLeft: Radius.circular(4),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  child: Text(msg.content,
                      style: TextStyle(
                          color: cs.onSurface, fontSize: 14)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _timeLabel(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

// ---------------------------------------------------------------------------
// @Mention suggestions
// ---------------------------------------------------------------------------

class _MentionSuggestions extends StatelessWidget {
  final List<String> suggestions;
  final Mission mission;
  final ValueChanged<String> onSelect;
  const _MentionSuggestions(
      {required this.suggestions,
      required this.mission,
      required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceVariant,
      child: Column(
        children: suggestions
            .map((token) {
              // Figure out if this is a robot or human for icon
              final isRobot = mission.participants.any(
                  (p) => p.isRobot && (p.name == token || p.rrn == token));
              return ListTile(
                dense: true,
                leading: Icon(
                  isRobot
                      ? Icons.smart_toy_outlined
                      : Icons.person_outline,
                  size: 16,
                ),
                title: Text('@$token',
                    style: const TextStyle(fontSize: 13)),
                onTap: () => onSelect(token),
              );
            })
            .toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Observer banner
// ---------------------------------------------------------------------------

class _ObserverBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        color: cs.surfaceVariant,
        child: Row(
          children: [
            Icon(Icons.visibility_outlined,
                size: 16, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'Observer mode — you can read but not send messages.',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error banner
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onDismiss;
  const _ErrorBanner({required this.message, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      color: cs.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, color: cs.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text(message,
                  style: TextStyle(color: cs.error, fontSize: 12))),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final Mission mission;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.mission,
    required this.onChanged,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final robots = mission.robotParticipants;
    final humans = mission.humanParticipants;
    // Build hint: @Bob @Alex @Alice (first few)
    final all = [...robots, ...humans];
    final hintTokens =
        all.take(3).map((p) => '@${p.name}').join(' ');
    final hint = all.isEmpty
        ? 'Type a mission command…'
        : '$hintTokens · Type a mission command…';

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24)),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  isDense: true,
                ),
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            sending
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                        child:
                            CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton.filled(
                    onPressed: onSend,
                    icon: const Icon(Icons.send_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF0ea5e9),
                      foregroundColor: Colors.white,
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
