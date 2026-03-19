/// FlowGraph — data model for the visual harness flow-graph editor.
///
/// Stores node positions, directed edges (including feedback loops),
/// and group containers. Serialises to/from plain Map<String,dynamic>
/// for YAML persistence alongside the harness layers.
library;

// ─────────────────────────────────────────────────────────────────────────────

/// Position of a node on the canvas.
class FlowNodePos {
  final String layerId;
  double x;
  double y;

  FlowNodePos({required this.layerId, required this.x, required this.y});

  Map<String, dynamic> toJson() => {'layerId': layerId, 'x': x, 'y': y};

  factory FlowNodePos.fromJson(Map<String, dynamic> j) => FlowNodePos(
        layerId: j['layerId'] as String,
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────

/// A directed edge between two nodes.
class FlowEdge {
  final String id;
  final String fromId; // layerId
  final String toId; // layerId
  final String label; // e.g. "on_fail", "loop", "→"
  final bool isLoop; // true = draw curved back-arrow

  FlowEdge({
    required this.id,
    required this.fromId,
    required this.toId,
    this.label = '',
    this.isLoop = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'fromId': fromId,
        'toId': toId,
        'label': label,
        'isLoop': isLoop,
      };

  factory FlowEdge.fromJson(Map<String, dynamic> j) => FlowEdge(
        id: j['id'] as String? ?? '',
        fromId: j['fromId'] as String? ?? '',
        toId: j['toId'] as String? ?? '',
        label: j['label'] as String? ?? '',
        isLoop: j['isLoop'] as bool? ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────

/// A group container (dashed border) around a set of nodes.
class FlowGroup {
  final String id;
  final String label;
  final List<String> memberIds; // layerIds inside this group

  FlowGroup({required this.id, required this.label, required this.memberIds});

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'memberIds': memberIds,
      };

  factory FlowGroup.fromJson(Map<String, dynamic> j) => FlowGroup(
        id: j['id'] as String? ?? '',
        label: j['label'] as String? ?? '',
        memberIds: (j['memberIds'] as List?)?.cast<String>() ?? [],
      );
}

// ─────────────────────────────────────────────────────────────────────────────

/// Complete flow graph state — positions + edges + groups.
class FlowGraph {
  final List<FlowNodePos> positions;
  final List<FlowEdge> edges;
  final List<FlowGroup> groups;

  FlowGraph({
    required this.positions,
    required this.edges,
    required this.groups,
  });

  static FlowGraph empty() =>
      FlowGraph(positions: [], edges: [], groups: []);

  /// Auto-layout: place nodes in a vertical chain, INPUT → layers → OUTPUT.
  static FlowGraph autoLayout(List<String> layerIds) {
    const startX = 160.0;
    const startY = 80.0;
    const stepY = 120.0;

    final positions = <FlowNodePos>[];
    // INPUT sentinel
    positions.add(FlowNodePos(layerId: '__input__', x: startX, y: startY));
    for (var i = 0; i < layerIds.length; i++) {
      positions.add(FlowNodePos(
        layerId: layerIds[i],
        x: startX,
        y: startY + stepY * (i + 1),
      ));
    }
    // OUTPUT sentinel
    positions.add(FlowNodePos(
      layerId: '__output__',
      x: startX,
      y: startY + stepY * (layerIds.length + 1),
    ));

    // Auto-edges: INPUT → first → ... → last → OUTPUT
    final edges = <FlowEdge>[];
    final allIds = ['__input__', ...layerIds, '__output__'];
    for (var i = 0; i < allIds.length - 1; i++) {
      edges.add(FlowEdge(
        id: 'auto_${allIds[i]}_${allIds[i + 1]}',
        fromId: allIds[i],
        toId: allIds[i + 1],
      ));
    }

    return FlowGraph(positions: positions, edges: edges, groups: []);
  }

  /// Fast lookup: layerId → FlowNodePos.
  Map<String, FlowNodePos> get posMap =>
      {for (final p in positions) p.layerId: p};

  Map<String, dynamic> toJson() => {
        'positions': positions.map((p) => p.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'groups': groups.map((g) => g.toJson()).toList(),
      };

  factory FlowGraph.fromJson(Map<String, dynamic> j) => FlowGraph(
        positions: (j['positions'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(FlowNodePos.fromJson)
            .toList(),
        edges: (j['edges'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(FlowEdge.fromJson)
            .toList(),
        groups: (j['groups'] as List? ?? [])
            .cast<Map<String, dynamic>>()
            .map(FlowGroup.fromJson)
            .toList(),
      );
}
