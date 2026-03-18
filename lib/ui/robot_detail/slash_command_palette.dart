/// Slash command palette overlay widget.
///
/// Displays a filterable list of slash commands grouped by category (Skills,
/// CLI, Custom). Appears when the user types "/" in the chat input.
///
/// Usage:
/// ```dart
/// SlashCommandPalette(
///   commands: commands,
///   query: 'nav',           // text after the leading /
///   onSelect: (cmd) { ... },
///   onDismiss: () { ... },
/// )
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/slash_command.dart';

// ---------------------------------------------------------------------------
// SlashCommandPalette
// ---------------------------------------------------------------------------

/// Filterable command palette shown above the chat text field.
class SlashCommandPalette extends StatefulWidget {
  /// Full list of slash commands from the provider.
  final List<SlashCommand> commands;

  /// Current filter query — the text typed after the leading '/'.
  final String query;

  /// Called when the user confirms a selection (tap or Enter).
  final void Function(SlashCommand) onSelect;

  /// Called when the user presses Esc or taps outside.
  final VoidCallback onDismiss;

  /// Maximum height for the palette card. Defaults to 280.
  final double maxHeight;

  const SlashCommandPalette({
    super.key,
    required this.commands,
    required this.query,
    required this.onSelect,
    required this.onDismiss,
    this.maxHeight = 280,
  });

  @override
  State<SlashCommandPalette> createState() => _SlashCommandPaletteState();
}

class _SlashCommandPaletteState extends State<SlashCommandPalette> {
  int _focusedIndex = 0;
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<SlashCommand> get _filtered {
    if (widget.query.isEmpty) return widget.commands;
    final q = widget.query.toLowerCase();
    return widget.commands.where((c) {
      return c.cmd.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q) ||
          c.group.toLowerCase().contains(q);
    }).toList();
  }

  // ── Grouped sections ───────────────────────────────────────────────────────

  /// Returns an ordered list of (group, [commands]) pairs, preserving
  /// the natural order: Skills → CLI → Custom.
  List<MapEntry<String, List<SlashCommand>>> _grouped(List<SlashCommand> cmds) {
    const groupOrder = ['Skills', 'CLI', 'Custom'];
    final map = <String, List<SlashCommand>>{};
    for (final cmd in cmds) {
      map.putIfAbsent(cmd.group, () => []).add(cmd);
    }
    // Sort groups by canonical order, unknown groups go last
    final keys = map.keys.toList()
      ..sort((a, b) {
        final ai = groupOrder.indexOf(a);
        final bi = groupOrder.indexOf(b);
        if (ai == -1 && bi == -1) return a.compareTo(b);
        if (ai == -1) return 1;
        if (bi == -1) return -1;
        return ai.compareTo(bi);
      });
    return keys.map((k) => MapEntry(k, map[k]!)).toList();
  }

  // ── Keyboard navigation ───────────────────────────────────────────────────

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final filtered = _filtered;
    if (filtered.isEmpty) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _focusedIndex = (_focusedIndex + 1).clamp(0, filtered.length - 1);
      });
      _scrollToFocused(filtered.length);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _focusedIndex = (_focusedIndex - 1).clamp(0, filtered.length - 1);
      });
      _scrollToFocused(filtered.length);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_focusedIndex < filtered.length) {
        widget.onSelect(filtered[_focusedIndex]);
      }
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _scrollToFocused(int total) {
    if (!_scrollCtrl.hasClients) return;
    const itemHeight = 64.0; // approx row height
    final targetOffset = _focusedIndex * itemHeight;
    _scrollCtrl.animateTo(
      targetOffset.clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  void didUpdateWidget(SlashCommandPalette old) {
    super.didUpdateWidget(old);
    if (old.query != widget.query) {
      // Reset focused index when query changes
      _focusedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final grouped = _grouped(filtered);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (filtered.isEmpty) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'No commands match "/${widget.query}"',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    // Build flat list of items (with section headers)
    final items = <_PaletteItem>[];
    var flatIndex = 0;
    for (final entry in grouped) {
      items.add(_PaletteItem.header(entry.key));
      for (final cmd in entry.value) {
        items.add(_PaletteItem.command(cmd, flatIndex));
        flatIndex++;
      }
    }

    return Focus(
      onKeyEvent: _handleKey,
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 8,
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: widget.maxHeight),
          child: ListView.builder(
            controller: _scrollCtrl,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (context, i) {
              final item = items[i];
              if (item.isHeader) {
                return _SectionHeader(label: item.headerLabel!);
              }
              final cmd = item.command!;
              final cmdFlatIndex = item.flatIndex!;
              final isFocused = cmdFlatIndex == _focusedIndex;
              return _CommandRow(
                command: cmd,
                focused: isFocused,
                onTap: () => widget.onSelect(cmd),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Internal data model for palette list items
// ---------------------------------------------------------------------------

class _PaletteItem {
  final bool isHeader;
  final String? headerLabel;
  final SlashCommand? command;
  final int? flatIndex;

  const _PaletteItem._({
    required this.isHeader,
    this.headerLabel,
    this.command,
    this.flatIndex,
  });

  factory _PaletteItem.header(String label) =>
      _PaletteItem._(isHeader: true, headerLabel: label);

  factory _PaletteItem.command(SlashCommand cmd, int idx) =>
      _PaletteItem._(isHeader: false, command: cmd, flatIndex: idx);
}

// ---------------------------------------------------------------------------
// Section header widget
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 2),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Individual command row
// ---------------------------------------------------------------------------

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.command,
    required this.focused,
    required this.onTap,
  });

  final SlashCommand command;
  final bool focused;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: focused
            ? colorScheme.primaryContainer.withValues(alpha: 0.45)
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            // Icon
            Icon(
              command.icon,
              size: 18,
              color: focused ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            // Text column
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        command.cmd,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: focused ? colorScheme.primary : null,
                        ),
                      ),
                      // Args hint
                      if (command.args.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Text(
                          command.args
                              .map((a) => a.optional ? '[${a.name}]' : '<${a.name}>')
                              .join(' '),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                      const Spacer(),
                      // Scope badge
                      _ScopeBadge(scope: command.scope),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    command.description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scope badge chip
// ---------------------------------------------------------------------------

class _ScopeBadge extends StatelessWidget {
  const _ScopeBadge({required this.scope});
  final CommandScope scope;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scope.badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scope.badgeColor.withValues(alpha: 0.6), width: 0.8),
      ),
      child: Text(
        scope.scopeLabel,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: scope.badgeColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
