/// model_garage.dart — Hardware-aware LLMFit model selection for the harness.
///
/// Opens as a full-screen modal from the harness editor's model tier section.
/// Fetches /api/hardware to determine the robot's tier, then shows models
/// colour-coded green (fits) or red/dimmed (won't run).
///
/// Usage:
/// ```dart
/// final result = await ModelGarage.open(
///   context,
///   rrn: rrn,
///   currentFastProvider: 'ollama',
///   currentFastModel: 'gemma3:1b',
///   currentSlowProvider: 'google',
///   currentSlowModel: 'gemini-2.0-flash',
/// );
/// if (result != null) {
///   // result.tier is 'fast' | 'slow'
///   onUpdate('${result.tier}_provider', result.provider);
///   onUpdate('${result.tier}_model', result.model);
/// }
/// ```
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/llm_fit.dart';
import 'hardware_provider.dart';
import '../shared/loading_view.dart';

// ---------------------------------------------------------------------------
// Result type
// ---------------------------------------------------------------------------

class GarageSelection {
  final String tier; // 'fast' | 'slow'
  final String provider;
  final String model;

  const GarageSelection({
    required this.tier,
    required this.provider,
    required this.model,
  });
}

// ---------------------------------------------------------------------------
// ModelGarage widget
// ---------------------------------------------------------------------------

class ModelGarage extends ConsumerStatefulWidget {
  final String rrn;
  final String currentFastProvider;
  final String currentFastModel;
  final String currentSlowProvider;
  final String currentSlowModel;

  const ModelGarage({
    super.key,
    required this.rrn,
    required this.currentFastProvider,
    required this.currentFastModel,
    required this.currentSlowProvider,
    required this.currentSlowModel,
  });

  /// Open the Model Garage as a full-screen modal.
  ///
  /// Returns a [GarageSelection] if the user taps "Set Model", or null if
  /// they dismiss.
  static Future<GarageSelection?> open(
    BuildContext context, {
    required String rrn,
    required String currentFastProvider,
    required String currentFastModel,
    required String currentSlowProvider,
    required String currentSlowModel,
  }) {
    return Navigator.of(context).push<GarageSelection>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ModelGarage(
          rrn: rrn,
          currentFastProvider: currentFastProvider,
          currentFastModel: currentFastModel,
          currentSlowProvider: currentSlowProvider,
          currentSlowModel: currentSlowModel,
        ),
      ),
    );
  }

  @override
  ConsumerState<ModelGarage> createState() => _ModelGarageState();
}

class _ModelGarageState extends ConsumerState<ModelGarage>
    with SingleTickerProviderStateMixin {
  ModelSpec? _selected;
  String _tier = 'fast'; // 'fast' | 'slow'
  late TabController _tab; // 0 = local, 1 = cloud

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  HardwareTier _tierFrom(Map<String, dynamic> hw) =>
      HardwareTierX.fromApi(hw['hardware_tier'] as String?);

  double _availableRam(Map<String, dynamic> hw) =>
      (hw['ram_available_gb'] as num?)?.toDouble() ?? 0.0;

  List<String> _ollamaModels(Map<String, dynamic> hw) {
    final raw = hw['ollama_models'];
    if (raw is List) return raw.cast<String>();
    return const [];
  }

  String _hwLabel(Map<String, dynamic> hw) {
    final tier = _tierFrom(hw);
    final accels = (hw['accelerators'] as List?)?.cast<String>() ?? [];
    if (accels.isNotEmpty) {
      return '${tier.label} · ${accels.join(', ')}';
    }
    return tier.label;
  }

  // ── Model lists ────────────────────────────────────────────────────────────

  List<ModelSpec> get _localModels =>
      kModelCatalog.where((m) => m.localOnly).toList();

  List<ModelSpec> get _cloudModels =>
      kModelCatalog.where((m) => !m.localOnly).toList();

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hwAsync = ref.watch(hardwareProfileProvider(widget.rrn));
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('🔧 Model Garage'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Local (Ollama)'),
            Tab(text: 'Cloud API'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Hardware banner ──────────────────────────────────────────────
          hwAsync.when(
            data: (hw) => hw.isEmpty
                ? _UnknownHardwareBanner(cs: cs)
                : _HardwareBanner(
                    label: _hwLabel(hw),
                    hw: hw,
                    cs: cs,
                  ),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => _UnknownHardwareBanner(cs: cs),
          ),

          // ── Model lists ──────────────────────────────────────────────────
          Expanded(
            child: hwAsync.when(
              data: (hw) => _ModelLists(
                tab: _tab,
                localModels: _localModels,
                cloudModels: _cloudModels,
                hardwareTier: _tierFrom(hw),
                availableRamGb: _availableRam(hw),
                pulledModels: _ollamaModels(hw),
                selected: _selected,
                onSelected: (m) => setState(() => _selected = m),
              ),
              loading: () => const LoadingView(),
              error: (_, __) => _ModelLists(
                tab: _tab,
                localModels: _localModels,
                cloudModels: _cloudModels,
                hardwareTier: HardwareTier.minimal,
                availableRamGb: 0,
                pulledModels: const [],
                selected: _selected,
                onSelected: (m) => setState(() => _selected = m),
              ),
            ),
          ),

          // ── Footer: tier selector + set button ───────────────────────────
          _GarageFooter(
            selected: _selected,
            tier: _tier,
            onTierChanged: (t) => setState(() => _tier = t),
            onSet: _selected == null
                ? null
                : () => Navigator.of(context).pop(
                      GarageSelection(
                        tier: _tier,
                        provider: _selected!.provider,
                        model: _selected!.model,
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hardware banner
// ---------------------------------------------------------------------------

class _HardwareBanner extends StatelessWidget {
  final String label;
  final Map<String, dynamic> hw;
  final ColorScheme cs;

  const _HardwareBanner({
    required this.label,
    required this.hw,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final hostname = hw['hostname'] as String? ?? 'robot';
    final ramGb = (hw['ram_gb'] as num?)?.toDouble() ?? 0.0;
    final accels = (hw['accelerators'] as List?)?.cast<String>() ?? [];

    return Container(
      color: cs.secondaryContainer.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hostname,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                Text(
                  label,
                  style: TextStyle(
                      fontSize: 12, color: cs.onSecondaryContainer),
                ),
              ],
            ),
          ),
          if (ramGb > 0)
            Chip(
              label: Text('${ramGb.toStringAsFixed(0)}GB RAM',
                  style: const TextStyle(fontSize: 11)),
              padding: EdgeInsets.zero,
              visualDensity: VisualDensity.compact,
            ),
          const SizedBox(width: 4),
          ...accels.map(
            (a) => Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Chip(
                label: Text(a, style: const TextStyle(fontSize: 11)),
                backgroundColor: Colors.green.withValues(alpha: 0.2),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnknownHardwareBanner extends StatelessWidget {
  final ColorScheme cs;
  const _UnknownHardwareBanner({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: cs.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.help_outline, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Text(
            'Hardware unknown — showing all models',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Model lists (tabbed local / cloud)
// ---------------------------------------------------------------------------

class _ModelLists extends StatelessWidget {
  final TabController tab;
  final List<ModelSpec> localModels;
  final List<ModelSpec> cloudModels;
  final HardwareTier hardwareTier;
  final double availableRamGb;
  final List<String> pulledModels;
  final ModelSpec? selected;
  final void Function(ModelSpec) onSelected;

  const _ModelLists({
    required this.tab,
    required this.localModels,
    required this.cloudModels,
    required this.hardwareTier,
    required this.availableRamGb,
    required this.pulledModels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: tab,
      children: [
        // ── Local tab ────────────────────────────────────────────────────
        ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: localModels.length,
          itemBuilder: (ctx, i) {
            final m = localModels[i];
            final fits = m.fitsHardware(hardwareTier);
            final ramOk = availableRamGb == 0 ||
                m.ramGb == 0 ||
                m.ramGb <= availableRamGb;
            final isPulled = pulledModels.contains(m.model);
            return _LocalModelTile(
              spec: m,
              fits: fits && ramOk,
              isPulled: isPulled,
              availableRamGb: availableRamGb,
              isSelected: selected?.model == m.model &&
                  selected?.provider == m.provider,
              onTap: () => onSelected(m),
            );
          },
        ),
        // ── Cloud tab ────────────────────────────────────────────────────
        ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: cloudModels.length,
          itemBuilder: (ctx, i) {
            final m = cloudModels[i];
            return _CloudModelTile(
              spec: m,
              isSelected: selected?.model == m.model &&
                  selected?.provider == m.provider,
              onTap: () => onSelected(m),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Local model tile
// ---------------------------------------------------------------------------

class _LocalModelTile extends StatelessWidget {
  final ModelSpec spec;
  final bool fits;
  final bool isPulled;
  final double availableRamGb;
  final bool isSelected;
  final VoidCallback onTap;

  const _LocalModelTile({
    required this.spec,
    required this.fits,
    required this.isPulled,
    required this.availableRamGb,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dimmed = !fits;

    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: ListTile(
        selected: isSelected,
        selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
        leading: Icon(
          isPulled ? Icons.circle : Icons.circle_outlined,
          color: isPulled ? Colors.green : cs.onSurfaceVariant,
          size: 18,
        ),
        title: Text(
          spec.displayName,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                fits
                    ? const Text('✅ Fits',
                        style: TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.w600))
                    : Text(
                        '❌ Too big — needs ${spec.ramGb}GB'
                        '${availableRamGb > 0 ? ', you have ${availableRamGb.toStringAsFixed(1)}GB' : ''}',
                        style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w600),
                      ),
                const SizedBox(width: 8),
                Text('${spec.ramGb}GB · ${spec.quality}',
                    style: const TextStyle(fontSize: 11)),
              ],
            ),
            if (fits && availableRamGb > 0 && spec.ramGb > 0) ...[
              const SizedBox(height: 3),
              LinearProgressIndicator(
                value: (spec.ramGb / availableRamGb).clamp(0.0, 1.0),
                minHeight: 4,
                color: Colors.green,
                backgroundColor: cs.surfaceContainerHighest,
              ),
            ],
          ],
        ),
        trailing: _QualityChip(quality: spec.quality),
        onTap: fits ? onTap : null,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cloud model tile
// ---------------------------------------------------------------------------

class _CloudModelTile extends StatelessWidget {
  final ModelSpec spec;
  final bool isSelected;
  final VoidCallback onTap;

  const _CloudModelTile({
    required this.spec,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListTile(
      selected: isSelected,
      selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
      leading: Icon(
        Icons.cloud_outlined,
        color: cs.primary,
        size: 20,
      ),
      title: Text(
        spec.displayName,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Row(
        children: [
          const Text('✅ Compatible',
              style: TextStyle(
                  color: Colors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Text(spec.provider, style: const TextStyle(fontSize: 11)),
        ],
      ),
      trailing: _QualityChip(quality: spec.quality),
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Quality chip
// ---------------------------------------------------------------------------

class _QualityChip extends StatelessWidget {
  final String quality;
  const _QualityChip({required this.quality});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (quality) {
      'fast' => (Colors.blue, 'fast'),
      'balanced' => (Colors.teal, 'balanced'),
      'capable' => (Colors.purple, 'capable'),
      'frontier' => (Colors.orange, 'frontier'),
      _ => (Colors.grey, quality),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer
// ---------------------------------------------------------------------------

class _GarageFooter extends StatelessWidget {
  final ModelSpec? selected;
  final String tier;
  final void Function(String) onTierChanged;
  final VoidCallback? onSet;

  const _GarageFooter({
    required this.selected,
    required this.tier,
    required this.onTierChanged,
    required this.onSet,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Text('Set as:', style: TextStyle(fontSize: 13)),
          const SizedBox(width: 8),
          DropdownButton<String>(
            value: tier,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: const [
              DropdownMenuItem(value: 'fast', child: Text('Fast tier')),
              DropdownMenuItem(value: 'slow', child: Text('Slow tier')),
            ],
            onChanged: (v) => onTierChanged(v ?? tier),
          ),
          const Spacer(),
          if (selected != null)
            Text(
              selected!.displayName,
              style: const TextStyle(
                  fontSize: 12, fontStyle: FontStyle.italic),
            ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onSet,
            child: const Text('Set Model'),
          ),
        ],
      ),
    );
  }
}
