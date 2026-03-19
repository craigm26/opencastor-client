/// LLMFit — hardware-aware model catalog for the Model Garage.
///
/// Provides [HardwareTier], [ModelSpec], and [kModelCatalog] — all static,
/// no network calls required for the catalog itself.
library;

// ---------------------------------------------------------------------------
// Hardware tier enum
// ---------------------------------------------------------------------------

/// Ordered hardware tiers from weakest to strongest.
///
/// The ordinal index corresponds to tier power — a model compatible with
/// [pi4_4gb] is also compatible with all higher tiers.
enum HardwareTier {
  minimal,
  pi4_4gb,
  pi4_8gb,
  pi5_4gb,
  pi5_8gb,
  // ignore: constant_identifier_names
  pi5Hailo,
  server,
}

extension HardwareTierX on HardwareTier {
  /// Human-readable label for display in the garage banner.
  String get label => switch (this) {
        HardwareTier.minimal => 'Minimal',
        HardwareTier.pi4_4gb => 'Pi 4 · 4GB',
        HardwareTier.pi4_8gb => 'Pi 4 · 8GB',
        HardwareTier.pi5_4gb => 'Pi 5 · 4GB',
        HardwareTier.pi5_8gb => 'Pi 5 · 8GB',
        HardwareTier.pi5Hailo => 'Pi 5 · Hailo',
        HardwareTier.server => 'Server',
      };

  /// Parse the string returned by /api/hardware hardware_tier field.
  static HardwareTier fromApi(String? s) => switch (s) {
        'pi4-4gb' => HardwareTier.pi4_4gb,
        'pi4-8gb' => HardwareTier.pi4_8gb,
        'pi5-4gb' => HardwareTier.pi5_4gb,
        'pi5-8gb' => HardwareTier.pi5_8gb,
        'pi5-hailo' => HardwareTier.pi5Hailo,
        'server' => HardwareTier.server,
        _ => HardwareTier.minimal,
      };
}

// ---------------------------------------------------------------------------
// ModelSpec
// ---------------------------------------------------------------------------

class ModelSpec {
  final String provider; // 'ollama' | 'google' | 'anthropic' | 'openai' etc.
  final String model; // model id used in RCAN config
  final String displayName;
  final double ramGb; // estimated RAM/VRAM required (0 for cloud models)
  final int paramsBillion; // approximate parameter count (0 for cloud)
  final String quality; // 'fast' | 'balanced' | 'capable' | 'frontier'

  /// Minimum tier required. The model fits any tier >= this tier.
  /// Empty list means compatible with ALL tiers (cloud models, tiny models).
  final List<HardwareTier> compatibleTiers;

  final bool localOnly; // true for ollama models
  final String? notes;

  const ModelSpec({
    required this.provider,
    required this.model,
    required this.displayName,
    required this.ramGb,
    required this.paramsBillion,
    required this.quality,
    required this.compatibleTiers,
    required this.localOnly,
    this.notes,
  });

  /// Returns true when this model can run on [tier].
  ///
  /// Cloud (non-local) models always fit — no RAM constraint.
  bool fitsHardware(HardwareTier tier) {
    if (!localOnly) return true;
    if (compatibleTiers.isEmpty) return true;
    // The model fits if the robot's tier is >= the minimum required tier.
    final minTier = compatibleTiers.reduce(
      (a, b) => a.index < b.index ? a : b,
    );
    return tier.index >= minTier.index;
  }

  /// Fit score: 1.0 = perfect fit, 0.0 = won't run.
  ///
  /// For local models, also checks against [availableRamGb].
  double fitScore(HardwareTier tier, double availableRamGb) {
    if (!localOnly) return 1.0;
    if (ramGb == 0) return 1.0;
    if (!fitsHardware(tier)) return 0.0;
    if (availableRamGb > 0 && ramGb > availableRamGb) return 0.0;
    return (availableRamGb > 0) ? (1.0 - (ramGb / availableRamGb)).clamp(0.1, 1.0) : 1.0;
  }
}

// ---------------------------------------------------------------------------
// Static model catalog
// ---------------------------------------------------------------------------

/// All hardware tiers (shorthand for "compatible with everything").
const _allTiers = HardwareTier.values;

/// Tiers from pi4-4gb and up.
const _pi4_4gbPlus = [
  HardwareTier.pi4_4gb,
  HardwareTier.pi4_8gb,
  HardwareTier.pi5_4gb,
  HardwareTier.pi5_8gb,
  HardwareTier.pi5Hailo,
  HardwareTier.server,
];

/// Tiers from pi5-8gb and up.
const _pi5_8gbPlus = [
  HardwareTier.pi5_8gb,
  HardwareTier.pi5Hailo,
  HardwareTier.server,
];

/// The full static model catalog used by the Model Garage.
///
/// No network calls — this is compile-time const data.
const List<ModelSpec> kModelCatalog = [
  // ── Local / Ollama ──────────────────────────────────────────────────────
  ModelSpec(
    provider: 'ollama',
    model: 'gemma3:1b',
    displayName: 'Gemma 3 1B',
    ramGb: 1.5,
    paramsBillion: 1,
    quality: 'fast',
    compatibleTiers: _allTiers,
    localOnly: true,
    notes: 'Tiny — great for fast inference on any Pi',
  ),
  ModelSpec(
    provider: 'ollama',
    model: 'gemma3:4b',
    displayName: 'Gemma 3 4B',
    ramGb: 3.5,
    paramsBillion: 4,
    quality: 'balanced',
    compatibleTiers: _pi4_4gbPlus,
    localOnly: true,
  ),
  ModelSpec(
    provider: 'ollama',
    model: 'llama3.2:3b',
    displayName: 'Llama 3.2 3B',
    ramGb: 2.5,
    paramsBillion: 3,
    quality: 'balanced',
    compatibleTiers: _pi4_4gbPlus,
    localOnly: true,
  ),
  ModelSpec(
    provider: 'ollama',
    model: 'mistral:7b',
    displayName: 'Mistral 7B',
    ramGb: 5.5,
    paramsBillion: 7,
    quality: 'capable',
    compatibleTiers: _pi5_8gbPlus,
    localOnly: true,
    notes: 'Needs 8GB+ RAM',
  ),
  ModelSpec(
    provider: 'ollama',
    model: 'phi3:mini',
    displayName: 'Phi-3 Mini',
    ramGb: 2.3,
    paramsBillion: 3,
    quality: 'balanced',
    compatibleTiers: _pi4_4gbPlus,
    localOnly: true,
  ),
  // ── Cloud / Google ─────────────────────────────────────────────────────
  ModelSpec(
    provider: 'google',
    model: 'gemini-2.0-flash-lite',
    displayName: 'Gemini Flash Lite',
    ramGb: 0,
    paramsBillion: 0,
    quality: 'fast',
    compatibleTiers: _allTiers,
    localOnly: false,
  ),
  ModelSpec(
    provider: 'google',
    model: 'gemini-2.0-flash',
    displayName: 'Gemini Flash',
    ramGb: 0,
    paramsBillion: 0,
    quality: 'balanced',
    compatibleTiers: _allTiers,
    localOnly: false,
  ),
  ModelSpec(
    provider: 'google',
    model: 'gemini-2.5-flash',
    displayName: 'Gemini 2.5 Flash',
    ramGb: 0,
    paramsBillion: 0,
    quality: 'capable',
    compatibleTiers: _allTiers,
    localOnly: false,
  ),
  ModelSpec(
    provider: 'google',
    model: 'gemini-2.5-pro',
    displayName: 'Gemini 2.5 Pro',
    ramGb: 0,
    paramsBillion: 0,
    quality: 'frontier',
    compatibleTiers: _allTiers,
    localOnly: false,
  ),
  // ── Cloud / Anthropic ──────────────────────────────────────────────────
  ModelSpec(
    provider: 'anthropic',
    model: 'claude-3-5-haiku-20241022',
    displayName: 'Claude Haiku 3.5',
    ramGb: 0,
    paramsBillion: 0,
    quality: 'fast',
    compatibleTiers: _allTiers,
    localOnly: false,
  ),
  ModelSpec(
    provider: 'anthropic',
    model: 'claude-sonnet-4-5',
    displayName: 'Claude Sonnet 4',
    ramGb: 0,
    paramsBillion: 0,
    quality: 'capable',
    compatibleTiers: _allTiers,
    localOnly: false,
  ),
  // ── Cloud / OpenAI ─────────────────────────────────────────────────────
  ModelSpec(
    provider: 'openai',
    model: 'gpt-4o-mini',
    displayName: 'GPT-4o Mini',
    ramGb: 0,
    paramsBillion: 0,
    quality: 'fast',
    compatibleTiers: _allTiers,
    localOnly: false,
  ),
  ModelSpec(
    provider: 'openai',
    model: 'gpt-4o',
    displayName: 'GPT-4o',
    ramGb: 0,
    paramsBillion: 0,
    quality: 'capable',
    compatibleTiers: _allTiers,
    localOnly: false,
  ),
];
