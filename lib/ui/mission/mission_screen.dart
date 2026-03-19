import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../data/models/mission.dart';

// ---------------------------------------------------------------------------
// Robot color palette — consistent color per RRN across messages
// ---------------------------------------------------------------------------

const _robotColors = [
  Color(0xFF0ea5e9), // sky
  Color(0xFF8b5cf6), // violet
  Color(0xFF22c55e), // green
  Color(0xFFf59e0b), // amber
  Color(0xFFef4444), // red
  Color(0xFF06b6d4), // cyan
  Color(0xFFec4899), // pink
];

Color _colorForRrn(String rrn) {
  final hash = rrn.codeUnits.fold(0, (a, b) => a + b);
  return _robotColors[hash % _robotColors.length];
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
  String? _error;

  // @mention auto-suggest state
  List<String> _mentionSuggestions = [];
  List<MissionParticipant> _robotParticipants = [];

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged(String value, Mission mission) {
    _robotParticipants = mission.robotParticipants;
    final atIdx = value.lastIndexOf('@');
    if (atIdx == -1) {
      if (_mentionSuggestions.isNotEmpty) {
        setState(() => _mentionSuggestions = []);
      }
      return;
    }
    final prefix = value.substring(atIdx + 1).toLowerCase();
    final suggestions = _robotParticipants
        .where((r) => r.name.toLowerCase().startsWith(prefix) ||
            (r.rrn ?? '').toLowerCase().contains(prefix))
        .map((r) => r.name)
        .toList();
    setState(() => _mentionSuggestions = suggestions);
  }

  void _insertMention(String robotName) {
    final text = _textCtrl.text;
    final atIdx = text.lastIndexOf('@');
    if (atIdx == -1) return;
    final newText = '${text.substring(0, atIdx)}@$robotName ';
    _textCtrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    setState(() => _mentionSuggestions = []);
  }

  Future<void> _sendMessage(String missionId) async {
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

      // Scroll to bottom
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

        return Scaffold(
          appBar: _MissionAppBar(mission: mission),
          body: Column(
            children: [
              // Messages list
              Expanded(
                child: _MessagesList(
                  missionId: widget.missionId,
                  mission: mission,
                  scrollCtrl: _scrollCtrl,
                ),
              ),

              // Error banner
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                          size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _error = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

              // @mention suggestions
              if (_mentionSuggestions.isNotEmpty)
                Container(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  child: Column(
                    children: _mentionSuggestions
                        .map((name) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.smart_toy_outlined,
                                  size: 16),
                              title: Text('@$name'),
                              onTap: () => _insertMention(name),
                            ))
                        .toList(),
                  ),
                ),

              // Input bar
              _InputBar(
                controller: _textCtrl,
                sending: _sending,
                mission: mission,
                onChanged: (v) => _onTextChanged(v, mission),
                onSend: () => _sendMessage(widget.missionId),
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
  const _MissionAppBar({required this.mission});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final robots = mission.robotParticipants;
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
                if (robots.isNotEmpty)
                  Text(
                    robots.map((r) => r.name).join(', '),
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF0ea5e9)),
                  ),
              ],
            ),
          ),
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

  const _MessagesList({
    required this.missionId,
    required this.mission,
    required this.scrollCtrl,
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
                  color:
                      Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          );
        }

        return ListView.builder(
          controller: scrollCtrl,
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final msg = MissionMessage.fromDocument(docs[i]);
            final currentUid = FirebaseAuth.instance.currentUser?.uid;
            final isMe = !msg.isFromRobot && msg.fromUid == currentUid;

            if (isMe) {
              return _HumanMessageBubble(msg: msg);
            } else {
              final rrn = msg.fromRrn ?? '';
              final color = _colorForRrn(rrn);
              return _RobotMessageBubble(msg: msg, accentColor: color);
            }
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
  const _HumanMessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                  '${msg.fromName} · ${_timeLabel(msg.timestamp)}',
                  style:
                      TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0ea5e9),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(4),
                      bottomLeft: Radius.circular(16),
                      bottomRight: Radius.circular(16),
                    ),
                  ),
                  child: Text(
                    msg.content,
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
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
  const _RobotMessageBubble({required this.msg, required this.accentColor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Robot avatar
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
                  style:
                      TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 2),
                // Colored left border for robot messages
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(color: accentColor, width: 3),
                    ),
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
                  child: Text(
                    msg.content,
                    style: TextStyle(
                        color: cs.onSurface, fontSize: 14),
                  ),
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
    final cs = Theme.of(context).colorScheme;
    final robots = mission.robotParticipants;
    final hint = robots.isEmpty
        ? 'Type a mission command…'
        : '[${robots.map((r) => "@${r.name}").join(" ")}] Type a mission command…';

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
                  hintStyle: const TextStyle(fontSize: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
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
