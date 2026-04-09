/// Slash command model for the chat command palette.
///
/// Supports both builtin CLI commands (e.g. /status, /reboot) and
/// skill-based commands (e.g. /navigate-to, /arm-manipulate).
library;

import 'package:flutter/material.dart';

import 'command.dart' show CommandScope;

export 'command.dart' show CommandScope;

// ---------------------------------------------------------------------------
// UI extensions on CommandScope (from command.dart)
// ---------------------------------------------------------------------------

extension CommandScopeUI on CommandScope {
  /// Parse from string (case-insensitive). Defaults to [CommandScope.chat].
  static CommandScope fromString(String s) {
    return CommandScope.values.firstWhere(
      (e) => e.name == s.toLowerCase(),
      orElse: () => CommandScope.chat,
    );
  }

  /// Human-readable label.
  String get scopeLabel => name;

  /// Badge color per RCAN scope level.
  Color get badgeColor => switch (this) {
        CommandScope.discover => const Color(0xFF9E9E9E), // grey
        CommandScope.status => const Color(0xFF1E88E5), // blue
        CommandScope.chat => const Color(0xFF43A047), // green
        CommandScope.control => const Color(0xFFFB8C00), // orange
        CommandScope.system => const Color(0xFFE53935), // red
        CommandScope.safety => const Color(0xFF8E24AA), // purple
        CommandScope.transparency => const Color(0xFF9E9E9E), // grey
      };
}

// ---------------------------------------------------------------------------
// SlashCommandArg
// ---------------------------------------------------------------------------

/// A single argument descriptor for a [SlashCommand].
class SlashCommandArg {
  /// Argument name, e.g. "destination", "version".
  final String name;

  /// Whether the argument can be omitted.
  final bool optional;

  /// Optional hint text shown in the palette, e.g. "kitchen", "v1.2.0".
  final String? hint;

  const SlashCommandArg({
    required this.name,
    this.optional = false,
    this.hint,
  });

  factory SlashCommandArg.fromJson(Map<String, dynamic> j) {
    return SlashCommandArg(
      name: j['name'] as String? ?? 'arg',
      optional: j['optional'] as bool? ?? false,
      hint: j['hint'] as String?,
    );
  }
}

// ---------------------------------------------------------------------------
// SlashCommand
// ---------------------------------------------------------------------------

/// A single entry in the slash command palette.
class SlashCommand {
  /// The slash command string, e.g. "/navigate-to".
  final String cmd;

  /// Short human-readable description shown in the palette.
  final String description;

  /// RCAN scope level for this command.
  final CommandScope scope;

  /// If true, selecting the command sends it immediately (no args to fill in).
  /// If false, the command is inserted into the text field for the user to
  /// complete with arguments.
  final bool instant;

  /// Ordered list of arguments the command accepts.
  final List<SlashCommandArg> args;

  /// Display group: "CLI" | "Skills" | "Custom".
  final String group;

  /// Icon shown in the palette row.
  final IconData icon;

  const SlashCommand({
    required this.cmd,
    required this.description,
    required this.scope,
    this.instant = false,
    this.args = const [],
    required this.group,
    required this.icon,
  });

  factory SlashCommand.fromJson(Map<String, dynamic> j, {String group = 'Skills'}) {
    final scopeStr = j['scope'] as String? ?? 'chat';
    final rawArgs = j['args'] as List<dynamic>? ?? [];
    return SlashCommand(
      cmd: j['cmd'] as String? ?? '/unknown',
      description: j['description'] as String? ?? '',
      scope: CommandScopeUI.fromString(scopeStr),
      instant: j['instant'] as bool? ?? false,
      args: rawArgs
          .whereType<Map<String, dynamic>>()
          .map(SlashCommandArg.fromJson)
          .toList(),
      group: group,
      icon: _iconForGroup(group, scopeStr),
    );
  }

  static IconData _iconForGroup(String group, String scope) {
    if (group == 'Skills') {
      return switch (scope) {
        'control' => Icons.smart_toy_outlined,
        'status' => Icons.visibility_outlined,
        'chat' => Icons.chat_bubble_outline,
        _ => Icons.extension_outlined,
      };
    }
    // CLI commands
    return switch (scope) {
      'system' => Icons.settings_outlined,
      'status' => Icons.info_outline,
      _ => Icons.terminal,
    };
  }

  /// Usage string shown as placeholder, e.g. "/navigate-to `<destination>`".
  String get usageString {
    if (args.isEmpty) return cmd;
    final parts = args.map((a) => a.optional ? '[${a.name}]' : '<${a.name}>');
    return '$cmd ${parts.join(' ')}';
  }
}

// ---------------------------------------------------------------------------
// Static builtin command list (fallback when robot is offline)
// ---------------------------------------------------------------------------

/// Static list of builtin slash commands used as fallback when robot is
/// unreachable. Mirrors [_BUILTIN_CLI_COMMANDS] in api.py.
const List<SlashCommand> kStaticBuiltinCommands = [
  SlashCommand(
    cmd: '/status',
    description: 'Get robot status',
    scope: CommandScope.status,
    instant: true,
    group: 'CLI',
    icon: Icons.info_outline,
  ),
  SlashCommand(
    cmd: '/skills',
    description: 'List active skills',
    scope: CommandScope.status,
    instant: true,
    group: 'CLI',
    icon: Icons.extension_outlined,
  ),
  SlashCommand(
    cmd: '/optimize',
    description: 'Run optimizer pass',
    scope: CommandScope.system,
    instant: false,
    group: 'CLI',
    icon: Icons.tune_outlined,
  ),
  SlashCommand(
    cmd: '/upgrade',
    description: 'Upgrade to latest version',
    scope: CommandScope.system,
    instant: false,
    args: [SlashCommandArg(name: 'version', optional: true)],
    group: 'CLI',
    icon: Icons.system_update_alt_outlined,
  ),
  SlashCommand(
    cmd: '/reboot',
    description: 'Reboot robot',
    scope: CommandScope.system,
    instant: false,
    group: 'CLI',
    icon: Icons.restart_alt_outlined,
  ),
  SlashCommand(
    cmd: '/reload-config',
    description: 'Reload RCAN config',
    scope: CommandScope.system,
    instant: false,
    group: 'CLI',
    icon: Icons.refresh_outlined,
  ),
  SlashCommand(
    cmd: '/share',
    description: 'Share config to hub',
    scope: CommandScope.system,
    instant: false,
    group: 'CLI',
    icon: Icons.share_outlined,
  ),
  SlashCommand(
    cmd: '/install',
    description: 'Install config from hub',
    scope: CommandScope.system,
    instant: false,
    args: [SlashCommandArg(name: 'id', optional: false)],
    group: 'CLI',
    icon: Icons.download_outlined,
  ),
  SlashCommand(
    cmd: '/pause',
    description: 'Pause the perception-action loop',
    scope: CommandScope.system,
    instant: false,
    group: 'CLI',
    icon: Icons.pause_circle_outline,
  ),
  SlashCommand(
    cmd: '/resume',
    description: 'Resume the perception-action loop',
    scope: CommandScope.system,
    instant: false,
    group: 'CLI',
    icon: Icons.play_circle_outline,
  ),
  SlashCommand(
    cmd: '/shutdown',
    description: 'Shutdown robot host',
    scope: CommandScope.system,
    instant: false,
    group: 'CLI',
    icon: Icons.power_settings_new_outlined,
  ),
  SlashCommand(
    cmd: '/snapshot',
    description: 'Take a diagnostic snapshot',
    scope: CommandScope.status,
    instant: true,
    group: 'CLI',
    icon: Icons.camera_alt_outlined,
  ),
  SlashCommand(
    cmd: '/contribute',
    description: 'Show idle compute contribution status',
    scope: CommandScope.status,
    instant: true,
    group: 'CLI',
    icon: Icons.volunteer_activism_outlined,
  ),
];
