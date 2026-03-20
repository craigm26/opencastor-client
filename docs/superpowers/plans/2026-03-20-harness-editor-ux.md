# Harness Editor UX Overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 7 UX problems in the harness editor: smart block placement, placement toasts, zoom controls, drag-to-connect, auto-connect on add, block info overlays, and list↔flow sync.

**Architecture:** All changes are self-contained within `lib/ui/harness/` and `lib/data/models/harness_config.dart`. No new files needed. No new packages. MVVM pattern maintained — no safety-critical code touched.

**Tech Stack:** Flutter 3.x, Dart, no new packages.

---

## Pipeline Priority Order (canonical)

```
hook(p66=0/drift=9) → guard(1) → context(2) → memory(3) → skill(4)
→ model(5) → hitl(6) → cost_gate(7) → circuit_breaker(8)
→ hook/drift(9) → tracer(10) → dlq(11) → trajectory(99)
```

---

## Task 1: Smart type-aware placement in `harness_config.dart`

**Files:**
- Modify: `lib/data/models/harness_config.dart` — replace `withLayerAdded()`

- [ ] **Step 1:** Add `_kLayerPipelineOrder` const map and `_priorityFor()` helper above `withLayerAdded()`:

```dart
/// Pipeline priority order for smart block insertion.
/// Lower = earlier in the pipeline. Trajectory is always last (99).
/// p66 is canReorder=false so it never moves regardless of priority.
const _kLayerPipelineOrder = <String, int>{
  'guard': 1,
  'context': 2,
  'memory': 3,
  'skill': 4,
  'model': 5,
  'hitl': 6,
  'cost_gate': 7,
  'circuit_breaker': 8,
  'hook': 9,        // drift and other runtime hooks (p66 fixed via canReorder)
  'tracer': 10,
  'dlq': 11,
  'trajectory': 99, // always last — canReorder=false
};

int _priorityFor(String type) => _kLayerPipelineOrder[type] ?? 90;
```

- [ ] **Step 2:** Replace `withLayerAdded()` implementation (keep the method signature):

```dart
/// Returns a new config with [layer] inserted at its correct pipeline position
/// based on [_kLayerPipelineOrder]. Falls back to inserting before trajectory
/// for unknown types.
HarnessConfig withLayerAdded(HarnessLayer layer) {
  final newLayers = List<HarnessLayer>.from(layers);
  final newPriority = _priorityFor(layer.type);

  // Walk from end: find the last layer with priority ≤ newPriority.
  // We'll insert immediately after it.
  int insertIdx = newLayers.length; // default: append
  for (var i = newLayers.length - 1; i >= 0; i--) {
    final p = _priorityFor(newLayers[i].type);
    if (p <= newPriority) {
      insertIdx = i + 1;
      break;
    }
  }

  // Clamp: always before trajectory
  final trajIdx = newLayers.indexWhere((l) => l.type == 'trajectory');
  if (trajIdx >= 0 && insertIdx > trajIdx) {
    insertIdx = trajIdx;
  }

  newLayers.insert(insertIdx, layer);
  return copyWithLayers(newLayers);
}
```

- [ ] **Step 3:** Run `~/flutter/bin/flutter analyze lib/data/models/harness_config.dart` and fix any issues.

---

## Task 2: Placement preview toast in `harness_editor.dart`

**Files:**
- Modify: `lib/ui/harness/harness_editor.dart` — update `_addLayer()`

- [ ] **Step 1:** Replace `_addLayer()`:

```dart
void _addLayer(HarnessLayer layer) {
  setState(() {
    _config = _config.withLayerAdded(layer);
    _syncGraph();
  });

  // Show placement toast
  final newIdx = _config.layers.indexWhere((l) => l.id == layer.id);
  final prevLabel =
      newIdx > 0 ? _config.layers[newIdx - 1].label : '__input__';

  if (mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added ${layer.label} after $prevLabel'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'View in graph',
          onPressed: () => setState(() => _showFlow = true),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2:** Analyze and fix.

---

## Task 3: Zoom controls in `flow_canvas.dart`

**Files:**
- Modify: `lib/ui/harness/flow_canvas.dart`

- [ ] **Step 1:** Add `_transformController` to `_FlowCanvasState`:

```dart
final _transformController = TransformationController();

@override
void dispose() {
  _transformController.dispose();
  super.dispose();
}
```

- [ ] **Step 2:** Pass controller to `InteractiveViewer`:

```dart
child: InteractiveViewer(
  transformationController: _transformController,
  constrained: false,
  minScale: 0.4,
  maxScale: 2.5,
  ...
```

- [ ] **Step 3:** Wrap the outer `Container` in a `Stack` to add viewport-fixed zoom controls:

Change `build()` return to:
```dart
return Container(
  color: _kBg,
  child: Stack(
    children: [
      InteractiveViewer(
        transformationController: _transformController,
        constrained: false,
        minScale: 0.4,
        maxScale: 2.5,
        child: SizedBox(
          width: canvasSize.width,
          height: canvasSize.height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ... existing children (EdgePainter, groups, nodes, loop FAB, palette)
            ],
          ),
        ),
      ),
      // Viewport-fixed zoom controls
      if (widget.editable)
        Positioned(
          right: 16,
          bottom: 80,
          child: _ZoomControls(controller: _transformController),
        ),
    ],
  ),
);
```

- [ ] **Step 4:** Add `_ZoomControls` widget at bottom of file:

```dart
class _ZoomControls extends StatelessWidget {
  final TransformationController controller;
  const _ZoomControls({required this.controller});

  void _zoomIn() {
    controller.value = controller.value.clone()
      ..scale(1.25);
  }

  void _zoomOut() {
    controller.value = controller.value.clone()
      ..scale(0.8);
  }

  void _reset() {
    controller.value = Matrix4.identity();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ZoomBtn(icon: Icons.add, tooltip: 'Zoom in', onTap: _zoomIn),
        const SizedBox(height: 4),
        _ZoomBtn(icon: Icons.remove, tooltip: 'Zoom out', onTap: _zoomOut),
        const SizedBox(height: 4),
        _ZoomBtn(icon: Icons.fit_screen, tooltip: 'Reset zoom', onTap: _reset),
      ],
    );
  }
}

class _ZoomBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ZoomBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF21262D),
            border: Border.all(color: _kNodeBorder),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 16, color: _kTextColor),
        ),
      ),
    );
  }
}
```

Note: `Matrix4.scale()` doesn't exist directly — use `Matrix4.copy(controller.value)..scale(factor)` or multiply via `Matrix4.diagonal3Values`.

Correct zoom implementation:
```dart
void _zoomIn() {
  final m = controller.value.clone();
  m.scale(1.25, 1.25);
  controller.value = m;
}

void _zoomOut() {
  final m = controller.value.clone();
  m.scale(0.8, 0.8);
  controller.value = m;
}

void _reset() {
  controller.value = Matrix4.identity();
}
```

- [ ] **Step 5:** Analyze and fix.

---

## Task 4: Drag-to-connect (connect mode) in `flow_canvas.dart`

**Files:**
- Modify: `lib/ui/harness/flow_canvas.dart`

- [ ] **Step 1:** Add connect mode state to `_FlowCanvasState`:

```dart
bool _connectMode = false;
String? _connectFromId;
Offset? _connectDragEnd; // for dotted line
```

- [ ] **Step 2:** Add connect mode toggle FAB to the viewport Stack (above zoom controls):

In the outer Stack's children, add:
```dart
if (widget.editable)
  Positioned(
    right: 16,
    bottom: 200, // above zoom controls at 80
    child: Tooltip(
      message: _connectMode ? 'Cancel connect' : 'Draw connection',
      child: GestureDetector(
        onTap: () => setState(() {
          _connectMode = !_connectMode;
          _connectFromId = null;
          _connectDragEnd = null;
        }),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _connectMode
                ? _kEdgeColor.withValues(alpha: 0.2)
                : const Color(0xFF21262D),
            border: Border.all(
              color: _connectMode ? _kEdgeColor : _kNodeBorder,
              width: _connectMode ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.cable_outlined,
            size: 18,
            color: _connectMode ? _kEdgeColor : _kMutedText,
          ),
        ),
      ),
    ),
  ),
```

- [ ] **Step 3:** Add dotted-line overlay CustomPainter for connect mode drag. Add to the inner canvas Stack's children:

```dart
// Connect-mode drag line overlay
if (_connectMode && _connectFromId != null && _connectDragEnd != null)
  Positioned.fill(
    child: IgnorePointer(
      child: CustomPaint(
        painter: _DragLinePainter(
          from: Offset(
            (posMap[_connectFromId]?.x ?? 0) + _kNodeW / 2,
            (posMap[_connectFromId]?.y ?? 0) + _kNodeH,
          ),
          to: _connectDragEnd!,
        ),
      ),
    ),
  ),
```

- [ ] **Step 4:** Add `_DragLinePainter` at bottom of file:

```dart
class _DragLinePainter extends CustomPainter {
  final Offset from;
  final Offset to;
  const _DragLinePainter({required this.from, required this.to});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _kEdgeColor.withValues(alpha: 0.7)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const dashLen = 8.0, gapLen = 5.0;
    final dir = to - from;
    final dist = dir.distance;
    if (dist < 1) return;
    final step = dir / dist;
    double traveled = 0;
    bool drawing = true;
    final path = Path()..moveTo(from.dx, from.dy);
    var cur = from;
    while (traveled < dist) {
      final segLen = drawing ? dashLen : gapLen;
      final end = traveled + segLen > dist ? dist : traveled + segLen;
      final target = from + step * end;
      if (drawing) {
        path.lineTo(target.dx, target.dy);
      } else {
        path.moveTo(target.dx, target.dy);
      }
      traveled = end;
      cur = target;
      drawing = !drawing;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_DragLinePainter old) =>
      old.from != from || old.to != to;
}
```

- [ ] **Step 5:** Modify `_buildNode()` to handle connect-mode taps. When `_connectMode` is true, tapping a node either sets `_connectFromId` (first tap) or creates an edge (second tap):

```dart
onTap: () {
  if (_connectMode) {
    if (_connectFromId == null) {
      setState(() => _connectFromId = id);
    } else if (_connectFromId != id) {
      _addEdge(_connectFromId!, id);
      setState(() {
        _connectFromId = null;
        _connectDragEnd = null;
        _connectMode = false;
      });
    }
    return;
  }
  if (widget.editable && layer != null && widget.onNodeTap != null) {
    widget.onNodeTap!(layer);
  }
},
```

Also wrap node with GestureDetector to track drag position during connect mode:
```dart
onPanUpdate: _connectMode
    ? (d) => setState(() {
          final pos = _graph.posMap[id];
          if (pos != null) {
            _connectDragEnd = Offset(
              pos.x + _kNodeW / 2 + d.localPosition.dx,
              pos.y + _kNodeH / 2 + d.localPosition.dy,
            );
          }
        })
    : (widget.editable ? (d) => _onNodeDragUpdate(id, d.delta) : null),
```

- [ ] **Step 6:** Add `_addEdge()` helper to `_FlowCanvasState`:

```dart
void _addEdge(String fromId, String toId) {
  // Avoid duplicate edges
  final exists = _graph.edges.any(
    (e) => e.fromId == fromId && e.toId == toId && !e.isLoop,
  );
  if (exists) return;
  setState(() {
    _graph.edges.add(FlowEdge(
      id: 'conn_${fromId}_$toId',
      fromId: fromId,
      toId: toId,
    ));
  });
  widget.onGraphChanged?.call(_graph);
}
```

- [ ] **Step 7:** Add selected-node highlight (blue border) in `_buildNode()`:

Pass `isSelected` to `_FlowNode`:
```dart
isSelected: _connectMode && _connectFromId == id,
```

Add `isSelected` field to `_FlowNode` and in `build()` use a blue border overlay when selected.

- [ ] **Step 8:** Cancel connect mode by tapping blank canvas. Wrap the inner Stack with GestureDetector:

```dart
GestureDetector(
  onTap: () {
    if (_connectMode && _connectFromId != null) {
      setState(() {
        _connectFromId = null;
        _connectDragEnd = null;
      });
    }
  },
  child: Stack(...),
)
```

- [ ] **Step 9:** Analyze and fix.

---

## Task 5: Auto-connect on node add in `flow_canvas.dart`

**Files:**
- Modify: `lib/ui/harness/flow_canvas.dart` — update `_addNodeOfType()`

- [ ] **Step 1:** Replace `_addNodeOfType()`:

```dart
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

    // Auto-connect: last non-output node → new → __output__
    final nonOutput = _graph.positions
        .where((p) => p.layerId != '__output__' && p.layerId != newId)
        .map((p) => p.layerId)
        .toList();

    if (nonOutput.isNotEmpty) {
      final lastId = nonOutput.last;
      // Remove old edge from lastId → __output__ (if it exists)
      _graph.edges.removeWhere(
          (e) => e.fromId == lastId && e.toId == '__output__');
      _graph.edges.add(FlowEdge(
        id: 'auto_${lastId}_$newId',
        fromId: lastId,
        toId: newId,
      ));
    }

    // New node → __output__
    _graph.edges.add(FlowEdge(
      id: 'auto_${newId}___output__',
      fromId: newId,
      toId: '__output__',
    ));
  });
  widget.onGraphChanged?.call(_graph);
}
```

- [ ] **Step 2:** Analyze and fix.

---

## Task 6: Block info overlay in `harness_viewer.dart`

**Files:**
- Modify: `lib/ui/harness/harness_viewer.dart`

- [ ] **Step 1:** Add `_kLayerInfo` const map at top of file (after imports):

```dart
/// Info text for each layer type/id, shown when user taps the ℹ️ icon.
const _kLayerInfo = <String, _LayerInfoData>{
  'hook-p66': _LayerInfoData(
    what: 'Protocol 66 Safety Hook — intercepts every command and enforces ESTOP bypass, scope gating, and physical consent (R2RAM). Cannot be disabled.',
    why: 'Must run first so no command can ever bypass safety checks, regardless of other layers.',
    canDo: 'View audit log in Trajectory Logger.',
    interactions: 'Blocks all CommandScope.control commands that lack physical consent.',
  ),
  'prompt-guard': _LayerInfoData(
    what: 'Prompt injection and jailbreak filter. Scores each incoming message and blocks it if risk exceeds threshold.',
    why: 'Runs before context assembly so malicious payloads never reach the model.',
    canDo: 'Adjust risk_threshold (lower = stricter). Enable/disable.',
    interactions: 'Blocked messages are forwarded to the Dead Letter Queue if present.',
  ),
  'context': _LayerInfoData(
    what: 'Assembles the agent context: working memory, telemetry, system prompt, and skill definitions.',
    why: 'Runs before skills and model so all downstream layers have the full context.',
    canDo: 'Toggle individual context sources (memory, telemetry, system_prompt, skills_context).',
    interactions: 'Skills and the model depend on this layer\'s output.',
  ),
  'memory': _LayerInfoData(
    what: 'Per-session scratchpad for multi-step reasoning. Stores intermediate facts and sub-goals.',
    why: 'Runs after context assembly and before skills so reasoning state is available during skill execution.',
    canDo: 'Set max_entries and TTL. Disable persistence between sessions.',
    interactions: 'Context Builder reads from this layer. Trajectory Logger archives it.',
  ),
  'skill': _LayerInfoData(
    what: 'An executable capability the agent can invoke (navigation, vision, web search, etc.).',
    why: 'Skills run after context is assembled and before model inference.',
    canDo: 'Enable/disable, reorder via drag, edit config, or remove.',
    interactions: 'Circuit Breaker disables a skill after repeated failures. HITL Gate blocks physical skills pending approval.',
  ),
  'model': _LayerInfoData(
    what: 'LLM routing layer. Routes inferences to a fast local model or a slow cloud model based on confidence.',
    why: 'Runs after skills so model output depends on skill results and context.',
    canDo: 'Change fast/slow provider and model. Adjust confidence threshold.',
    interactions: 'Cost Gate halts cloud calls if budget is exceeded. Drift Detection flags off-task outputs.',
  ),
  'hitl': _LayerInfoData(
    what: 'Human-in-the-Loop gate. Pauses execution and waits for operator approval before physical actions proceed.',
    why: 'Sits between skills and post-processing so a human reviews before actuation.',
    canDo: 'Set timeout, on_timeout policy (block/allow), and action types requiring approval.',
    interactions: 'Times out to block by default. Works with P66 for double-gating physical commands.',
  ),
  'cost_gate': _LayerInfoData(
    what: 'Budget ceiling for LLM spend. Halts execution if the session cost exceeds budget_usd.',
    why: 'Runs after model to catch runaway spend before the next iteration.',
    canDo: 'Set budget_usd, on_exceed policy, and alert_at_pct threshold.',
    interactions: 'Works with Dual Model to limit slow (cloud) model invocations.',
  ),
  'circuit_breaker': _LayerInfoData(
    what: 'Disables a skill after failure_threshold consecutive errors and auto-resets after cooldown_s seconds.',
    why: 'Prevents cascading failures from a broken skill blocking the whole pipeline.',
    canDo: 'Set failure_threshold and cooldown_s. Toggle half-open probe.',
    interactions: 'Resets automatically. Works alongside HITL Gate for physical actions.',
  ),
  'hook': _LayerInfoData(
    what: 'Runtime hook that monitors pipeline execution (e.g. Drift Detection).',
    why: 'Runs after model to inspect outputs without blocking the main flow.',
    canDo: 'Enable/disable. Adjust threshold parameters.',
    interactions: 'Drift Detection triggers a warning that Trajectory Logger records.',
  ),
  'tracer': _LayerInfoData(
    what: 'OpenTelemetry-style span tracer. Records every layer execution as a named span in SQLite.',
    why: 'Runs near the end of the pipeline to capture full execution context including model outputs.',
    canDo: 'Change export format and db_path.',
    interactions: 'Feeds the same SQLite used by the trajectory logger for unified audit.',
  ),
  'dlq': _LayerInfoData(
    what: 'Dead Letter Queue. Captures failed commands and blocked messages for human review.',
    why: 'Sits near end of pipeline to catch anything that fell through upstream gates.',
    canDo: 'Set db_path and max_size.',
    interactions: 'Receives blocked messages from Prompt Guard and timed-out HITL gates.',
  ),
  'trajectory': _LayerInfoData(
    what: 'Always-on audit trail. Every agent run is logged to SQLite — required for RCAN compliance.',
    why: 'Must run last to capture the complete pipeline execution record.',
    canDo: 'Change sqlite_path.',
    interactions: 'Read by the robot\'s autoresearch system and required for R2RAM consent audits.',
  ),
};

class _LayerInfoData {
  final String what;
  final String why;
  final String canDo;
  final String interactions;
  const _LayerInfoData({
    required this.what,
    required this.why,
    required this.canDo,
    required this.interactions,
  });
}
```

- [ ] **Step 2:** Add `_showLayerInfo()` helper in `_HarnessViewerState`:

```dart
void _showLayerInfo(HarnessLayer layer) {
  final key = _kLayerInfo.containsKey(layer.id)
      ? layer.id
      : layer.type;
  final info = _kLayerInfo[key];
  if (info == null) return;

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          Icon(_iconForLayer(layer),
              size: 20, color: _borderColorForType(layer.type)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(layer.label,
                style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _InfoSection(label: 'What it does', text: info.what),
            const SizedBox(height: 12),
            _InfoSection(label: 'Why it\'s here', text: info.why),
            const SizedBox(height: 12),
            _InfoSection(label: 'What you can do', text: info.canDo),
            const SizedBox(height: 12),
            _InfoSection(label: 'Interactions', text: info.interactions),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 3:** Add `_InfoSection` widget at bottom of file:

```dart
class _InfoSection extends StatelessWidget {
  final String label;
  final String text;
  const _InfoSection({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 2),
        Text(text,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
}
```

- [ ] **Step 4:** Add info icon to `_LayerCard` header row. In `_LayerCard.build()`, add an info `IconButton` next to the edit button:

```dart
// Add before the edit button:
IconButton(
  icon: const Icon(Icons.info_outline, size: 16),
  tooltip: 'About this block',
  visualDensity: VisualDensity.compact,
  onPressed: onInfo,
),
```

Add `onInfo` callback to `_LayerCard`. Pass it from `_HarnessViewerState._buildPipelineItem()` via `_showLayerInfo(layer)`.

- [ ] **Step 5:** Also add info icon to `_SkillGroupCard` header (for the skills group itself):

Show skill group info for the 'skill' type in `_kLayerInfo`.

- [ ] **Step 6:** Analyze and fix.

---

## Task 7: List ↔ Flow sync in `harness_viewer.dart`

**Files:**
- Modify: `lib/ui/harness/harness_viewer.dart`

- [ ] **Step 1:** Add `didUpdateWidget` to `_HarnessViewerState`:

```dart
@override
void didUpdateWidget(HarnessViewer old) {
  super.didUpdateWidget(old);
  if (old.config.layers != widget.config.layers) {
    // Rebuild internal flow graph to match new layer order
    setState(() {
      _flowGraph = FlowGraph.autoLayout(
        widget.config.layers.map((l) => l.id).toList(),
      );
    });
  }
}
```

- [ ] **Step 2:** Initialize `_flowGraph` from config in `initState` (instead of `FlowGraph.empty()`):

```dart
@override
void initState() {
  super.initState();
  _flowGraph = FlowGraph.autoLayout(
    widget.config.layers.map((l) => l.id).toList(),
  );
}
```

- [ ] **Step 3:** Analyze and fix.

---

## Final Steps

- [ ] **Run full analyze:** `~/flutter/bin/flutter analyze lib/ui/harness/`
- [ ] **Fix all analyzer errors**
- [ ] **Build:** `~/flutter/bin/flutter build web --release`
- [ ] **Commit:** `git add -A && git commit -m "feat(harness): smart placement, zoom controls, drag-to-connect, block info (#harness-ux)"`
- [ ] **Push:** `git push`
- [ ] **Signal completion:** `openclaw system event --text "Done: harness editor UX overhaul — smart placement, zoom controls, drag-to-connect, block info tooltips. Build clean, committed and pushed." --mode now`
