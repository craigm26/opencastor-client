/// Chat bubble widget for robot command/response history.
///
/// User messages: right-aligned, primary color.
/// Robot responses: left-aligned, surfaceContainerHigh.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../widgets/thinking_indicator.dart';

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isLoading;
  final bool isCommand;
  final DateTime timestamp;
  final List<Map<String, dynamic>>? mediaChunks;

  const ChatBubble({
    super.key,
    required this.text,
    required this.isUser,
    this.isLoading = false,
    this.isCommand = false,
    required this.timestamp,
    this.mediaChunks,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final bubbleColor =
        isUser ? cs.primary : cs.surfaceContainerHigh;
    final textColor = isUser ? cs.onPrimary : cs.onSurface;
    final timeColor =
        isUser ? cs.onPrimary.withOpacity(0.6) : cs.onSurfaceVariant;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        child: Container(
          margin: EdgeInsets.only(
            left: isUser ? 48 : 0,
            right: isUser ? 0 : 48,
            bottom: 4,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Media thumbnail ───────────────────────────────────────
              if (mediaChunks != null && mediaChunks!.isNotEmpty)
                _MediaThumbnail(chunks: mediaChunks!),

              // ── Text / typing indicator ───────────────────────────────
              if (isLoading)
                ThinkingIndicator(robotName: '', compact: true, color: textColor)
              else if (isCommand && text.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.terminal_rounded,
                        size: 14, color: textColor.withOpacity(0.85)),
                    const SizedBox(width: 6),
                    Text(
                      text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: textColor,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                )
              else if (text.isNotEmpty)
                Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: textColor,
                  ),
                ),

              // ── Timestamp ─────────────────────────────────────────────
              const SizedBox(height: 4),
              Text(
                DateFormat('HH:mm').format(timestamp.toLocal()),
                style: TextStyle(fontSize: 10, color: timeColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date separator row ("Today", "Yesterday", or formatted date).
class DateSeparator extends StatelessWidget {
  final DateTime date;

  const DateSeparator({super.key, required this.date});

  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _label(),
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(child: Divider(color: cs.outlineVariant)),
        ],
      ),
    );
  }
}

// ── Media thumbnail ───────────────────────────────────────────────────────────

class _MediaThumbnail extends StatelessWidget {
  final List<Map<String, dynamic>> chunks;
  const _MediaThumbnail({required this.chunks});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 180,
          height: 120,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(
            child: Icon(Icons.image_outlined, size: 40),
          ),
        ),
      ),
    );
  }
}

// ── Typing indicator (animated dots) ─────────────────────────────────────────

class _TypingIndicator extends StatefulWidget {
  final Color color;
  const _TypingIndicator({required this.color});

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 16,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) {
              final phase = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
              final opacity = 0.3 + 0.7 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Opacity(
                  opacity: opacity,
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.color,
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
