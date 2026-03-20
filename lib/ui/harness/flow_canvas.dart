/// FlowCanvas — visual node-graph editor for agent harnesses.
///
/// Dark canvas with draggable rounded-rect nodes, bezier directed edges,
/// curved feedback-loop arrows, and dashed-border group containers.
/// Uses only Flutter stdlib: CustomPainter, InteractiveViewer,
/// GestureDetector, Stack, Positioned.
library;

import 'package:flutter/material.dart';

import '../../data/models/harness_config.dart';
import 'flow_graph.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _kNodeW = 140.0;
const _kNodeH = 56.0;
const _kBg = Color(0xFF0D1117);
const _kNodeBorder = Color(0xFF30363D);
const _kNodeBg = Color(0xFF161B22);
const _kEdgeColor = Color(0xFF58A6FF);
const _kLoopColor = Color(0xFFF78166);
const _kGroupBorder = Color(0xFF3D444D);
const _kTextColor = Color(0xFFE6EDF3);
const _kMutedText = Color(0xFF8B949E);
const _kAccentGreen = Color(0xFF3FB950);

// ─── FlowCanvas ───────────────────────────────────────────────────────────────

class FlowCanvas extends StatefulWidget {
  final List<HarnessLayer> layers;
  final FlowGraph graph;
  final bool editable;
  final void Function(FlowGraph updated)? onGraphChanged;
  /// Called when a node is tapped in editable mode (to open the edit panel).
  final void Function(HarnessLayer layer)? onNodeTap;

  const FlowCanvas({
    super.key,
    required this.layers,
    required this.graph,
    this.editable = false,
    this.onGraphChanged,
    this.onNodeTap,
  });

  @override
  State<FlowCanvas> createState() => _FlowCanvasState();
}

class _FlowCanvasState extends State<FlowCanvas> {
  late FlowGraph _graph;

  @override
  void initState() {
    super.initState();
    _graph = widget.graph.positions.isEmpty
        ? FlowGraph.autoLayout(widget.layers.map((l) => l.id).toList())
        : widget.graph;
  }

  @override
  void didUpdateWidget(FlowCanvas old) {
    super.didUpdateWidget(old);
    if (old.graph != widget.graph || old.layers != widget.layers) {
      _graph = widget.graph.positions.isEmpty
          ? FlowGraph.autoLayout(widget.layers.map((l) => l.id).toList())
          : widget.graph;
    }
  }

  HarnessLayer? _layerById(String id) {
    if (id == '__input__' || id == '__output__') return null;
    try {
      return widget.layers.firstWhere((l) => l.id == id);
    } catch (_) {
      return null;
    }
  }

  // Compute bounding box for a group
  Rect _groupRect(FlowGroup group) {
    final pm = _graph.posMap;
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final id in group.memberIds) {
      final pos = pm[id];
      if (pos == null) continue;
      if (pos.x < minX) minX = pos.x;
      if (pos.y < minY) minY = pos.y;
      if (pos.x + _kNodeW > maxX) maxX = pos.x + _kNodeW;
      if (pos.y + _kNodeH > maxY) maxY = pos.y + _kNodeH;
    }
    const pad = 24.0;
    return Rect.fromLTRB(
        minX - pad, minY - pad - 24, maxX + pad, maxY + pad);
  }

  void _onNodeDragUpdate(String id, Offset delta) {
    if (!widget.editable) return;
    setState(() {
      final pos = _graph.posMap[id];
      if (pos != null) {
        pos.x += delta.dx;
        pos.y += delta.dy;
      }
    });
    widget.onGraphChanged?.call(_graph);
  }

  void _addLoop(String fromId, String toId) {
    setState(() {
      _graph.edges.add(FlowEdge(
        id: 'loop_${fromId}_$toId',
        fromId: fromId,
        toId: toId,
        label: 'loop',
        isLoop: true,
      ));
    });
    widget.onGraphChanged?.call(_graph);
  }

  // Canvas total size derived from node positions
  Size get _canvasSize {
    double maxX = 600, maxY = 600;
    for (final p in _graph.positions) {
      if (p.x + _kNodeW + 60 > maxX) maxX = p.x + _kNodeW + 60;
      if (p.y + _kNodeH + 60 > maxY) maxY = p.y + _kNodeH + 60;
    }
    return Size(maxX, maxY);
  }

  @override
  Widget build(BuildContext context) {
    final posMap = _graph.posMap;
    final canvasSize = _canvasSize;

    return Container(
      color: _kBg,
      child: InteractiveViewer(
        constrained: false,
        minScale: 0.4,
        maxScale: 2.5,
        child: SizedBox(
          width: canvasSize.width,
          height: canvasSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Edge painter (bottom layer) ─────────────────────────────
              Positioned.fill(
                child: CustomPaint(
                  painter: _EdgePainter(
                    graph: _graph,
                    posMap: posMap,
                  ),
                ),
              ),

              // ── Group containers ────────────────────────────────────────
              for (final group in _graph.groups)
                _GroupContainer(
                    group: group, rect: _groupRect(group)),

              // ── Nodes ───────────────────────────────────────────────────
              for (final pos in _graph.positions)
                _buildNode(pos),

              // ── Edge connector tap targets (edit mode only) ──────────────
              if (widget.editable)
                for (final edge in _graph.edges)
                  _buildEdgeTapTarget(edge),

              // ── Add loop FAB (edit mode only) ───────────────────────────
              if (widget.editable)
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _AddLoopButton(
                    layers: widget.layers,
                    onAdd: _addLoop,
                  ),
                ),

              // ── Node-type palette (edit mode only) ───────────────────────
              if (widget.editable)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _NodeTypePalette(
                    onTypeSelected: (type) => _addNodeOfType(type),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNode(FlowNodePos pos) {
    final id = pos.layerId;
    final layer = _layerById(id);
    final isInput = id == '__input__';
    final isOutput = id == '__output__';
    final isAlwaysOn = layer?.canDisable == false;

    return Positioned(
      left: pos.x,
      top: pos.y,
      child: GestureDetector(
        onPanUpdate:
            widget.editable ? (d) => _onNodeDragUpdate(id, d.delta) : null,
        onTap: (widget.editable && layer != null && widget.onNodeTap != null)
            ? () => widget.onNodeTap!(layer)
            : null,
        child: _FlowNode(
          id: id,
          label: pos.label ??
              (isInput
                  ? 'RCAN\ncommand'
                  : isOutput
                      ? 'Response'
                      : (layer?.label ?? id)),
          nodeType: pos.type,
          isAlwaysOn: isAlwaysOn,
          enabled: layer?.enabled ?? true,
          tappable: widget.editable && layer != null && widget.onNodeTap != null,
        ),
      ),
    );
  }

  /// Build an invisible tap target at the midpoint of an edge to edit its label.
  Widget _buildEdgeTapTarget(FlowEdge edge) {
    final from = _graph.posMap[edge.fromId];
    final to = _graph.posMap[edge.toId];
    if (from == null || to == null) return const SizedBox.shrink();

    final midX = ((from.x + _kNodeW / 2) + (to.x + _kNodeW / 2)) / 2 - 20;
    final midY = ((from.y + _kNodeH) + to.y) / 2 - 10;

    return Positioned(
      left: midX,
      top: midY,
      child: GestureDetector(
        onTap: () => _editEdgeLabel(edge),
        child: Container(
          width: 40,
          height: 20,
          decoration: BoxDecoration(
            color: const Color(0x22FFFFFF),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: edge.isLoop ? _kLoopColor.withValues(alpha: 0.5) : _kEdgeColor.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Center(
            child: Text(
              edge.label.isEmpty ? '…' : edge.label,
              style: TextStyle(
                color: edge.isLoop ? _kLoopColor : _kEdgeColor,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Show a dialog to edit the edge connector label and optionally delete it.
  void _editEdgeLabel(FlowEdge edge) {
    const connectorTypes = [
      '',
      'YES',
      'NO',
      'loop',
      'error',
      'timeout',
      'data',
      'fallback',
    ];
    String selected = connectorTypes.contains(edge.label) ? edge.label : '';

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: Row(
            children: [
              const Text('Connector', style: TextStyle(color: _kTextColor, fontSize: 15)),
              const SizedBox(width: 8),
              Text(
                '${edge.fromId} → ${edge.toId}',
                style: const TextStyle(color: _kMutedText, fontSize: 11),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Label / type:',
                  style: TextStyle(color: _kMutedText, fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: connectorTypes.map((t) {
                  final isSelected = selected == t;
                  Color chipColor;
                  switch (t) {
                    case 'YES':
                      chipColor = _kAccentGreen;
                    case 'NO':
                      chipColor = const Color(0xFFF44336);
                    case 'error':
                      chipColor = const Color(0xFFF78166);
                    case 'loop':
                      chipColor = _kLoopColor;
                    default:
                      chipColor = _kEdgeColor;
                  }
                  return GestureDetector(
                    onTap: () => setSt(() => selected = t),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? chipColor.withValues(alpha: 0.2)
                            : const Color(0xFF1C2128),
                        border: Border.all(
                          color: isSelected ? chipColor : const Color(0xFF3D444D),
                          width: isSelected ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        t.isEmpty ? '(none)' : t,
                        style: TextStyle(
                          color: isSelected ? chipColor : _kMutedText,
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                // Delete this edge
                setState(() => _graph.edges.remove(edge));
                widget.onGraphChanged?.call(_graph);
                Navigator.pop(ctx);
              },
              child: const Text('Delete',
                  style: TextStyle(color: Color(0xFFF44336))),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: _kMutedText)),
            ),
            TextButton(
              onPressed: () {
                setState(() => edge.label = selected);
                widget.onGraphChanged?.call(_graph);
                Navigator.pop(ctx);
              },
              child: const Text('Save',
                  style: TextStyle(color: _kEdgeColor)),
            ),
          ],
        ),
      ),
    );
  }

  /// Add a new node of [type] to the canvas at a default drop position.
  void _addNodeOfType(FlowNodeType type) {
    setState(() {
      final newId = '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
      _graph.positions.add(FlowNodePos(
        layerId: newId,
        x: 80,
        y: 80 + _graph.positions.length * 40.0,
        type: type,
        label: type.name,
      ));
    });
    if (widget.onGraphChanged != null) widget.onGraphChanged!(_graph);
  }
}

// ─── Edge painter ─────────────────────────────────────────────────────────────

class _EdgePainter extends CustomPainter {
  final FlowGraph graph;
  final Map<String, FlowNodePos> posMap;

  _EdgePainter({required this.graph, required this.posMap});

  Offset _nodeBottom(FlowNodePos pos) =>
      Offset(pos.x + _kNodeW / 2, pos.y + _kNodeH);

  Offset _nodeTop(FlowNodePos pos) =>
      Offset(pos.x + _kNodeW / 2, pos.y);

  Offset _nodeLeft(FlowNodePos pos) =>
      Offset(pos.x, pos.y + _kNodeH / 2);

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in graph.edges) {
      final from = posMap[edge.fromId];
      final to = posMap[edge.toId];
      if (from == null || to == null) continue;

      final paint = Paint()
        ..color = edge.isLoop ? _kLoopColor : _kEdgeColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      final arrowPaint = Paint()
        ..color = edge.isLoop ? _kLoopColor : _kEdgeColor
        ..style = PaintingStyle.fill;

      if (edge.isLoop) {
        // Curved loop — goes out the left side and back around
        final start = _nodeLeft(from);
        final end = _nodeLeft(to);
        final loopX =
            (start.dx < end.dx ? start.dx : end.dx) - 60;
        final midY = (start.dy + end.dy) / 2;

        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
              loopX, start.dy, loopX, end.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
        _drawArrow(canvas, arrowPaint,
            Offset(loopX, end.dy), end);

        // Loop label
        if (edge.label.isNotEmpty) {
          _drawLabel(canvas, edge.label,
              Offset(loopX - 20, midY - 8));
        }
      } else {
        // Bezier downward arrow
        final start = _nodeBottom(from);
        final end = _nodeTop(to);
        final dy = end.dy - start.dy;
        final cp1 = Offset(start.dx, start.dy + dy * 0.4);
        final cp2 = Offset(end.dx, end.dy - dy * 0.4);

        final path = Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
              cp1.dx, cp1.dy, cp2.dx, cp2.dy, end.dx, end.dy);
        canvas.drawPath(path, paint);
        _drawArrow(canvas, arrowPaint, cp2, end);

        // Edge label
        if (edge.label.isNotEmpty) {
          final midPt = Offset(
              (start.dx + end.dx) / 2 + 8,
              (start.dy + end.dy) / 2);
          _drawLabel(canvas, edge.label, midPt);
        }
      }
    }
  }

  void _drawArrow(Canvas canvas, Paint paint, Offset from, Offset to) {
    const arrowSize = 8.0;
    final dir = to - from;
    if (dir.distance < 0.01) return;
    final norm = dir / dir.distance;
    final perp = Offset(-norm.dy, norm.dx);
    final p1 = to - norm * arrowSize + perp * (arrowSize * 0.5);
    final p2 = to - norm * arrowSize - perp * (arrowSize * 0.5);
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      paint,
    );
  }

  void _drawLabel(Canvas canvas, String text, Offset pos) {
    Color labelColor = _kMutedText;
    if (text == 'YES') labelColor = const Color(0xFF3FB950); // green
    if (text == 'NO') labelColor = const Color(0xFFF44336);  // red

    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: (text == 'YES' || text == 'NO')
                ? FontWeight.bold
                : FontWeight.normal,
          )),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_EdgePainter old) => true;
}

// ─── Flow node widget ─────────────────────────────────────────────────────────

class _FlowNode extends StatelessWidget {
  final String id;
  final String label;
  final bool isAlwaysOn;
  final bool enabled;
  final FlowNodeType nodeType;
  final bool tappable;

  const _FlowNode({
    required this.id,
    required this.label,
    required this.nodeType,
    this.isAlwaysOn = false,
    this.enabled = true,
    this.tappable = false,
  });

  // ── Type-specific styling ─────────────────────────────────────────────────

  Color get _borderColor {
    if (isAlwaysOn) return _kAccentGreen;
    switch (nodeType) {
      case FlowNodeType.conditional:
        return const Color(0xFFFFCA28); // amber
      case FlowNodeType.hitl:
        return const Color(0xFF2196F3); // blue
      case FlowNodeType.timeout:
        return const Color(0xFFFF9800); // orange
      case FlowNodeType.parallel:
      case FlowNodeType.join:
        return const Color(0xFF9C27B0); // purple
      case FlowNodeType.costGate:
        return const Color(0xFFF44336); // red
      case FlowNodeType.modality:
        return const Color(0xFF2196F3); // blue
      case FlowNodeType.input:
      case FlowNodeType.output:
        return _kAccentGreen;
      default:
        return enabled ? _kNodeBorder : _kNodeBorder.withValues(alpha: 0.4);
    }
  }

  double get _borderWidth {
    switch (nodeType) {
      case FlowNodeType.conditional:
      case FlowNodeType.hitl:
      case FlowNodeType.timeout:
      case FlowNodeType.parallel:
      case FlowNodeType.join:
      case FlowNodeType.costGate:
      case FlowNodeType.modality:
        return 2.0;
      default:
        return isAlwaysOn ? 2.0 : 1.0;
    }
  }

  String? get _typeIcon {
    switch (nodeType) {
      case FlowNodeType.parallel:
        return '⑂';
      case FlowNodeType.join:
        return '⑃';
      case FlowNodeType.hitl:
        return '👤';
      case FlowNodeType.timeout:
        return '↺'; // loop/retry indicator for timeout
      case FlowNodeType.costGate:
        return '💰';
      case FlowNodeType.modality:
        return '⇒';
      default:
        return null;
    }
  }

  BorderRadius get _borderRadius {
    switch (nodeType) {
      case FlowNodeType.input:
      case FlowNodeType.output:
        return BorderRadius.circular(28);
      case FlowNodeType.parallel:
      case FlowNodeType.join:
        return BorderRadius.circular(4);
      default:
        return BorderRadius.circular(8);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = enabled ? _kTextColor : _kMutedText;
    final icon = _typeIcon;

    // Conditional → amber diamond shape via Transform.rotate
    if (nodeType == FlowNodeType.conditional) {
      const amberBorder = Color(0xFFFFCA28);
      return SizedBox(
        width: _kNodeW,
        height: _kNodeH,
        child: Center(
          child: Transform.rotate(
            angle: 0.785398, // 45°
            child: Container(
              width: _kNodeH * 0.82,
              height: _kNodeH * 0.82,
              decoration: BoxDecoration(
                color: const Color(0xFF1A1500),
                border: Border.all(color: amberBorder, width: 2.0),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Transform.rotate(
                angle: -0.785398,
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFFCA28),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: _kNodeW,
      height: _kNodeH,
      child: Stack(
        children: [
      Container(
        width: _kNodeW,
        height: _kNodeH,
        decoration: BoxDecoration(
          color: _kNodeBg,
          border: Border.all(
            color: tappable ? _borderColor.withValues(alpha: 0.9) : _borderColor,
            width: _borderWidth,
          ),
          borderRadius: _borderRadius,
        ),
        child: Center(
          child: icon != null
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      icon,
                      style: TextStyle(
                        fontSize: 13,
                        color: _borderColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        label,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                )
              : Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 12,
                    fontWeight:
                        isAlwaysOn ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
          // Tap-to-edit indicator (pencil in top-right corner)
          if (tappable)
            Positioned(
              top: 3,
              right: 4,
              child: Icon(
                Icons.edit_outlined,
                size: 10,
                color: _kMutedText.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Group container widget ───────────────────────────────────────────────────

class _GroupContainer extends StatelessWidget {
  final FlowGroup group;
  final Rect rect;

  const _GroupContainer({required this.group, required this.rect});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: Stack(
        children: [
          CustomPaint(
            size: rect.size,
            painter: _DashedBorderPainter(),
          ),
          Positioned(
            left: 12,
            top: 4,
            child: Text(
              group.label,
              style: const TextStyle(
                  color: _kMutedText,
                  fontSize: 11,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kGroupBorder
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dashW = 6.0, gapW = 4.0;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          const Radius.circular(12)));

    // Dash the path via path metrics
    for (final m in path.computeMetrics()) {
      double dist = 0;
      while (dist < m.length) {
        final seg = m.extractPath(dist, dist + dashW);
        canvas.drawPath(seg, paint);
        dist += dashW + gapW;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter _) => false;
}

// ─── Node-type palette ────────────────────────────────────────────────────────

/// Row of buttons to add different node types to the canvas in edit mode.
class _NodeTypePalette extends StatelessWidget {
  final void Function(FlowNodeType type) onTypeSelected;

  const _NodeTypePalette({required this.onTypeSelected});

  static const _paletteTypes = [
    FlowNodeType.conditional,
    FlowNodeType.parallel,
    FlowNodeType.join,
    FlowNodeType.hitl,
    FlowNodeType.timeout,
    FlowNodeType.costGate,
    FlowNodeType.modality,
  ];

  static const _paletteIcons = [
    '◆',
    '⑂',
    '⑃',
    '👤',
    '↺',
    '💰',
    '⇒',
  ];

  static const _paletteLabels = [
    'Cond',
    'Fork',
    'Join',
    'HITL',
    'Time',
    'Cost',
    'Route',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xCC0A0A0F),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'Add:',
                style: TextStyle(
                  color: Color(0xFF8888AA),
                  fontSize: 11,
                ),
              ),
            ),
            for (var i = 0; i < _paletteTypes.length; i++)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () => onTypeSelected(_paletteTypes[i]),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161E),
                      border: Border.all(
                          color: const Color(0xFF333355), width: 1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _paletteIcons[i],
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          _paletteLabels[i],
                          style: const TextStyle(
                            color: Color(0xFFCCCCDD),
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Add loop FAB ─────────────────────────────────────────────────────────────

class _AddLoopButton extends StatelessWidget {
  final List<HarnessLayer> layers;
  final void Function(String fromId, String toId) onAdd;

  const _AddLoopButton(
      {required this.layers, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: 'add_loop',
      backgroundColor: _kLoopColor,
      tooltip: 'Add feedback loop',
      onPressed: () => _showLoopDialog(context),
      child: const Icon(Icons.loop, size: 18, color: Colors.white),
    );
  }

  void _showLoopDialog(BuildContext context) {
    String? fromId;
    String? toId;
    final allIds = layers.map((l) => l.id).toList();

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Add feedback loop',
              style: TextStyle(color: _kTextColor)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                hint: const Text('From (output)',
                    style: TextStyle(color: _kMutedText)),
                value: fromId,
                dropdownColor: const Color(0xFF1C2128),
                isExpanded: true,
                items: allIds
                    .map((id) => DropdownMenuItem(
                          value: id,
                          child: Text(id,
                              style: const TextStyle(
                                  color: _kTextColor, fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setSt(() => fromId = v),
              ),
              const SizedBox(height: 8),
              DropdownButton<String>(
                hint: const Text('To (input)',
                    style: TextStyle(color: _kMutedText)),
                value: toId,
                dropdownColor: const Color(0xFF1C2128),
                isExpanded: true,
                items: allIds
                    .map((id) => DropdownMenuItem(
                          value: id,
                          child: Text(id,
                              style: const TextStyle(
                                  color: _kTextColor, fontSize: 13)),
                        ))
                    .toList(),
                onChanged: (v) => setSt(() => toId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel',
                  style: TextStyle(color: _kMutedText)),
            ),
            TextButton(
              onPressed: fromId != null && toId != null
                  ? () {
                      Navigator.pop(ctx);
                      onAdd(fromId!, toId!);
                    }
                  : null,
              child: const Text('Add loop',
                  style: TextStyle(color: _kLoopColor)),
            ),
          ],
        ),
      ),
    );
  }
}
