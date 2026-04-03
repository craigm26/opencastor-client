/// Pre-save harness safety validator.
///
/// Runs entirely client-side before any Firestore write.
/// Returns a [HarnessValidationResult] with pass/warn/block status.
library;

import '../../data/models/harness_config.dart';
import 'flow_graph.dart';

enum ValidationSeverity { pass, warn, block }

class ValidationIssue {
  final ValidationSeverity severity;
  final String code;
  final String message;
  final String? fix;
  const ValidationIssue({
    required this.severity,
    required this.code,
    required this.message,
    this.fix,
  });
}

class HarnessValidationResult {
  final List<ValidationIssue> issues;
  HarnessValidationResult(this.issues);

  bool get isBlocked =>
      issues.any((i) => i.severity == ValidationSeverity.block);
  bool get hasWarnings =>
      issues.any((i) => i.severity == ValidationSeverity.warn);
  List<ValidationIssue> get blocks =>
      issues.where((i) => i.severity == ValidationSeverity.block).toList();
  List<ValidationIssue> get warnings =>
      issues.where((i) => i.severity == ValidationSeverity.warn).toList();
}

class HarnessValidator {
  // Keys that must NEVER appear in any layer config
  static const _forbiddenKeys = {
    'safety',
    'auth',
    'p66',
    'estop',
    'motor',
    'motor_params',
    'hardware',
    'emergency_stop',
    'pin',
    'secret',
    'api_key',
    'token',
    'password',
    'private_key',
  };

  // Layer IDs that must always be present and enabled
  static const _alwaysOnIds = {'trajectory-logger', 'p66'};

  static HarnessValidationResult validate(
      List<HarnessLayer> layers, FlowGraph graph) {
    final issues = <ValidationIssue>[];

    // ── Check 1: Always-on layers present and enabled ──────────────────────
    for (final id in _alwaysOnIds) {
      final layer = layers.where((l) => l.id == id).firstOrNull;
      if (layer == null) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.block,
          code: 'ALWAYS_ON_MISSING',
          message: 'Required layer "$id" is missing.',
          fix: 'Add the $id layer back to the harness.',
        ));
      } else if (!layer.enabled) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.block,
          code: 'ALWAYS_ON_DISABLED',
          message: 'Layer "$id" must always be enabled and cannot be disabled.',
          fix: 'Re-enable the $id layer.',
        ));
      }
    }

    // ── Check 2: Forbidden keys in layer configs ───────────────────────────
    for (final layer in layers) {
      final config = layer.config;
      if (config.isEmpty) continue;
      for (final key in config.keys) {
        if (_forbiddenKeys.contains(key.toLowerCase())) {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.block,
            code: 'FORBIDDEN_KEY',
            message:
                'Layer "${layer.label}" contains forbidden config key "$key".',
            fix: 'Remove the "$key" key from this layer\'s configuration.',
          ));
        }
      }
    }

    // ── Check 3: Infinite loop detection in FlowGraph ─────────────────────
    // A cycle is only safe if there is at least one exit edge from the cycle
    // (an edge that goes to a node outside the cycle) OR a node labeled
    // 'timeout' or 'deadline' is in the cycle.
    if (graph.edges.isNotEmpty) {
      final cycles = _findCycles(graph);
      for (final cycle in cycles) {
        final hasSafeExit = _cycleHasSafeExit(cycle, graph, layers);
        if (!hasSafeExit) {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.block,
            code: 'INFINITE_LOOP',
            message:
                'Flow graph contains an unescapable loop: ${cycle.join(' → ')}.',
            fix: 'Add an exit edge from the loop, or add a timeout/deadline node inside it.',
          ));
        } else {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.warn,
            code: 'LOOP_WITH_EXIT',
            message:
                'Flow graph contains a loop (${cycle.join(' → ')}) — verify the exit condition is reachable.',
            fix: 'Ensure the exit condition triggers reliably to prevent the robot from looping indefinitely.',
          ));
        }
      }
    }

    // ── Check 4: Disconnected nodes (skill will never be reached) ─────────
    if (graph.edges.isNotEmpty && graph.positions.isNotEmpty) {
      final reachable = _reachableFrom('__input__', graph);
      for (final pos in graph.positions) {
        final id = pos.layerId;
        if (id == '__input__' || id == '__output__') continue;
        if (!reachable.contains(id)) {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.warn,
            code: 'UNREACHABLE_NODE',
            message:
                'Layer "${_labelFor(id, layers)}" is not reachable from the input node.',
            fix: 'Connect this layer to the flow or remove it.',
          ));
        }
      }
    }

    // ── Check 5: Output node reachability ──────────────────────────────────
    if (graph.edges.isNotEmpty) {
      final reachable = _reachableFrom('__input__', graph);
      if (!reachable.contains('__output__')) {
        issues.add(const ValidationIssue(
          severity: ValidationSeverity.block,
          code: 'NO_PATH_TO_OUTPUT',
          message: 'No path from the input node to the output (response) node.',
          fix: 'Ensure there is a connected chain from the input to the output node.',
        ));
      }
    }

    // ── Check 6: Scope escalation in layer config ──────────────────────────
    const scopeLevels = {
      'discover': 0,
      'transparency': 0,
      'status': 1,
      'chat': 2,
      'control': 3,
      'system': 3,
      'safety': 99,
    };
    for (final layer in layers) {
      final config = layer.config;
      if (config.isEmpty) continue;
      final scopeStr = (config['scope'] as String?)?.toLowerCase();
      if (scopeStr != null) {
        final level = scopeLevels[scopeStr] ?? -1;
        if (level >= 3 && layer.type != 'builtin') {
          issues.add(ValidationIssue(
            severity: ValidationSeverity.warn,
            code: 'HIGH_SCOPE_CUSTOM_LAYER',
            message: 'Layer "${layer.label}" requests scope "$scopeStr" '
                '(level $level). Custom layers should not request system or control scope.',
            fix: 'Lower the scope to "chat" or "status" for this layer.',
          ));
        }
      }
    }

    // ── Check 7: Empty harness ─────────────────────────────────────────────
    if (layers.isEmpty) {
      issues.add(const ValidationIssue(
        severity: ValidationSeverity.warn,
        code: 'EMPTY_HARNESS',
        message: 'Harness has no layers.',
        fix: 'Add at least a Trajectory Logger and one skill layer.',
      ));
    }

    // ── Check 8: Duplicate layer IDs ──────────────────────────────────────
    final seenIds = <String>{};
    for (final layer in layers) {
      if (!seenIds.add(layer.id)) {
        issues.add(ValidationIssue(
          severity: ValidationSeverity.block,
          code: 'DUPLICATE_LAYER_ID',
          message: 'Duplicate layer id "${layer.id}" found.',
          fix: 'Each layer must have a unique ID.',
        ));
      }
    }

    return HarnessValidationResult(issues);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  static String _labelFor(String id, List<HarnessLayer> layers) {
    try {
      return layers.firstWhere((l) => l.id == id).label;
    } catch (_) {
      return id;
    }
  }

  /// DFS to find all simple cycles in the directed graph.
  static List<List<String>> _findCycles(FlowGraph graph) {
    // Build adjacency
    final adj = <String, List<String>>{};
    for (final e in graph.edges) {
      adj.putIfAbsent(e.fromId, () => []).add(e.toId);
    }
    final allNodes = {for (final p in graph.positions) p.layerId};

    final cycles = <List<String>>[];
    final visited = <String>{};
    final stack = <String>[];
    final inStack = <String>{};

    void dfs(String node) {
      if (inStack.contains(node)) {
        // Found a cycle — extract it from the stack
        final start = stack.indexOf(node);
        if (start >= 0) cycles.add([...stack.sublist(start), node]);
        return;
      }
      if (visited.contains(node)) return;
      visited.add(node);
      inStack.add(node);
      stack.add(node);
      for (final next in (adj[node] ?? [])) {
        dfs(next);
      }
      stack.removeLast();
      inStack.remove(node);
    }

    for (final node in allNodes) {
      dfs(node);
    }
    return cycles;
  }

  /// Returns true if the cycle has at least one exit edge to a node outside
  /// the cycle, OR if the cycle contains a node with 'timeout' or 'deadline'
  /// in its id or label.
  static bool _cycleHasSafeExit(
      List<String> cycle, FlowGraph graph, List<HarnessLayer> layers) {
    final cycleSet = cycle.toSet();
    // Check for timeout/deadline node in cycle
    for (final id in cycle) {
      if (id.contains('timeout') || id.contains('deadline')) return true;
      try {
        final layer = layers.firstWhere((l) => l.id == id);
        if (layer.label.toLowerCase().contains('timeout') ||
            layer.label.toLowerCase().contains('deadline')) { return true; }
      } catch (_) {}
    }
    // Check for exit edge
    for (final edge in graph.edges) {
      if (cycleSet.contains(edge.fromId) && !cycleSet.contains(edge.toId)) {
        return true;
      }
    }
    return false;
  }

  /// BFS reachability from a start node.
  static Set<String> _reachableFrom(String start, FlowGraph graph) {
    final adj = <String, List<String>>{};
    for (final e in graph.edges) {
      adj.putIfAbsent(e.fromId, () => []).add(e.toId);
    }
    final visited = <String>{};
    final queue = [start];
    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      if (!visited.add(node)) continue;
      queue.addAll(adj[node] ?? []);
    }
    return visited;
  }
}
