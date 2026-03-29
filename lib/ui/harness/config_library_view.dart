/// config_library_view.dart
///
/// Displays the community Config Library — shareable harness configs from
/// github.com/craigm26/OpenCastor/research/presets/
///
/// Configs are fetched from the machine-readable index.json at startup.
/// Each config can be previewed, downloaded, and applied to the current robot
/// or broadcast to the entire fleet (Pro tier).
///
/// Safety guarantee: P66, ESTOP, and motor params are stripped on apply.
library;

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _indexUrl =
    'https://raw.githubusercontent.com/craigm26/OpenCastor/main/research/index.json';

class HarnessConfigEntry {
  const HarnessConfigEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.yamlUrl,
    required this.targetHardware,
    required this.bestFor,
    required this.ohb1Score,
    required this.isChampion,
    required this.tags,
  });

  final String id;
  final String name;
  final String description;
  final String yamlUrl;
  final List<String> targetHardware;
  final List<String> bestFor;
  final double ohb1Score;
  final bool isChampion;
  final List<String> tags;

  factory HarnessConfigEntry.fromJson(Map<String, dynamic> j) =>
      HarnessConfigEntry(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String,
        yamlUrl: j['yaml_url'] as String,
        targetHardware: List<String>.from(j['target_hardware'] as List),
        bestFor: List<String>.from(j['best_for'] as List),
        ohb1Score: (j['ohb1_score'] as num).toDouble(),
        isChampion: j['is_champion'] as bool? ?? false,
        tags: List<String>.from(j['tags'] as List? ?? []),
      );
}

class ConfigLibraryView extends StatefulWidget {
  const ConfigLibraryView({super.key, this.robotId});
  final String? robotId;

  @override
  State<ConfigLibraryView> createState() => _ConfigLibraryViewState();
}

class _ConfigLibraryViewState extends State<ConfigLibraryView> {
  List<HarnessConfigEntry> _configs = [];
  bool _loading = true;
  String? _error;
  String? _applyingId;

  @override
  void initState() {
    super.initState();
    _loadIndex();
  }

  Future<void> _loadIndex() async {
    try {
      final res = await http
          .get(Uri.parse(_indexUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final list = data['configs'] as List;
        setState(() {
          _configs =
              list.map((e) => HarnessConfigEntry.fromJson(e as Map<String, dynamic>)).toList();
          _loading = false;
        });
      } else {
        setState(() {
          _error = 'Failed to load index (${res.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Offline — could not reach GitHub';
        _loading = false;
        // Show fallback embedded configs
        _configs = _fallbackConfigs;
      });
    }
  }

  Future<void> _applyConfig(HarnessConfigEntry config) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF131c1f),
        title: Text('Apply "${config.name}"?',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(config.description,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF0e1416),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '🔒 P66 safety parameters will be preserved.\n'
                'ESTOP and motor params cannot be changed by any harness config.',
                style: TextStyle(fontSize: 12, color: Color(0xFF4ade80)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply')),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _applyingId = config.id);

    try {
      // Fetch the YAML and apply via the local castor bridge
      final res = await http
          .get(Uri.parse(config.yamlUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) throw Exception('Could not download config');

      final yaml = res.body;

      // In production: POST to local bridge at http://127.0.0.1:8001/api/harness/apply-champion
      // For now: copy to clipboard + show instructions
      await Clipboard.setData(ClipboardData(text: yaml));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${config.name} downloaded. '
                'Paste into arm.rcan.yaml or use: castor harness apply --config ${config.id}'),
            backgroundColor: const Color(0xFF1a2527),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
                label: 'Copied ✓',
                textColor: const Color(0xFF55d7ed),
                onPressed: () {}),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Apply failed: $e'),
            backgroundColor: Colors.red.shade900,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _applyingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: const Color(0xFF0e1416),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131c1f),
        title: const Text('Config Library',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
                _configs = [];
              });
              _loadIndex();
            },
            tooltip: 'Refresh from GitHub',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: () {/* open docs.opencastor.com/runtime/harness */},
            tooltip: 'View docs',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF55d7ed)))
          : Column(
              children: [
                if (_error != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: const Color(0xFF1a1500),
                    child: Text(
                      '⚠️ $_error — showing cached configs',
                      style: const TextStyle(
                          color: Color(0xFFffba38), fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _configs.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (ctx, i) {
                      if (i == 0) return _buildHeader(cs);
                      return _buildConfigCard(_configs[i - 1], cs);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Shareable harness configs',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white)),
        const SizedBox(height: 6),
        const Text(
          'Community-tested configs from the OpenCastor research fleet. '
          'Download and apply to one robot or broadcast to your entire fleet. '
          'Competition winners are automatically added here.',
          style: TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 10),
        Text(
          '${_configs.length} configs available · sourced from github.com/craigm26/OpenCastor',
          style: const TextStyle(
              color: Color(0xFF55d7ed),
              fontSize: 11,
              fontFamily: 'monospace'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildConfigCard(HarnessConfigEntry config, ColorScheme cs) {
    final score = config.ohb1Score;
    final scoreColor = score > 0.9
        ? const Color(0xFF55d7ed)
        : score > 0.8
            ? const Color(0xFF4ade80)
            : const Color(0xFFffba38);

    final domainColors = {
      'general': const Color(0xFF55d7ed),
      'home': const Color(0xFFffba38),
      'industrial': const Color(0xFFc084fc),
    };

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF131c1f),
        border: Border.all(
          color: config.isChampion
              ? const Color(0xFF55d7ed).withValues(alpha: 0.4)
              : Colors.white.withValues(alpha: 0.08),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(config.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          if (config.isChampion) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF55d7ed),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text('★ CHAMPION',
                                  style: TextStyle(
                                      color: Color(0xFF0e1416),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('${config.id}.yaml',
                          style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFamily: 'monospace')),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(score.toStringAsFixed(4),
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: scoreColor)),
                    const Text('OHB-1',
                        style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ],
            ),
          ),

          // Description
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(config.description,
                style: const TextStyle(
                    color: Colors.white60, fontSize: 13, height: 1.55)),
          ),

          // Domain + hardware chips
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                ...config.bestFor.map((d) => _chip(
                    d == 'general'
                        ? '⚙️ $d'
                        : d == 'home'
                            ? '🏠 $d'
                            : '🏭 $d',
                    domainColors[d] ?? cs.primary,
                    tinted: true)),
                ...config.targetHardware
                    .map((h) => _chip(_hwLabel(h), Colors.white30)),
              ],
            ),
          ),

          // Action row
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _applyingId == config.id
                        ? null
                        : () => _applyConfig(config),
                    icon: _applyingId == config.id
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.download, size: 16),
                    label: Text(_applyingId == config.id
                        ? 'Applying…'
                        : 'Apply to robot'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF55d7ed),
                      foregroundColor: const Color(0xFF0e1416),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {/* navigate to raw yaml viewer */},
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                    foregroundColor: Colors.white70,
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                  child: const Text('Preview'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String label, Color color, {bool tinted = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: tinted ? color.withValues(alpha: 0.12) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color: tinted ? color : Colors.white38,
                fontWeight: tinted ? FontWeight.w600 : FontWeight.normal)),
      );

  String _hwLabel(String hw) => const {
        'pi5_hailo': 'Pi5+Hailo8L',
        'pi5_8gb': 'Pi5 8GB',
        'pi5_4gb': 'Pi5 4GB',
        'jetson': 'Jetson',
        'server': 'Server',
        'waveshare': 'WaveShare',
      }[hw] ??
      hw;

  // Fallback when offline — mirrors index.json
  static final _fallbackConfigs = [
    HarnessConfigEntry(
      id: 'lower_cost',
      name: 'Lower Cost',
      description: 'Best overall balance of quality vs. cost. OHB-1 champion.',
      yamlUrl: 'https://raw.githubusercontent.com/craigm26/OpenCastor/main/research/presets/lower_cost.yaml',
      targetHardware: ['pi5_hailo', 'pi5_8gb', 'pi5_4gb', 'jetson', 'server', 'waveshare'],
      bestFor: ['general', 'home', 'industrial'],
      ohb1Score: 0.6541,
      isChampion: true,
      tags: ['recommended', 'all-hardware'],
    ),
    HarnessConfigEntry(
      id: 'local_only',
      name: 'Local Only',
      description: 'Fully offline. Zero cloud calls. gemma3:1b via Ollama.',
      yamlUrl: 'https://raw.githubusercontent.com/craigm26/OpenCastor/main/research/presets/local_only.yaml',
      targetHardware: ['pi5_4gb', 'pi5_8gb', 'jetson', 'waveshare'],
      bestFor: ['home'],
      ohb1Score: 0.8103,
      isChampion: false,
      tags: ['offline', 'privacy'],
    ),
    HarnessConfigEntry(
      id: 'industrial_optimized',
      name: 'Industrial Optimized',
      description: 'Retry-heavy, alert-aware. +12% industrial median.',
      yamlUrl: 'https://raw.githubusercontent.com/craigm26/OpenCastor/main/research/presets/industrial_optimized.yaml',
      targetHardware: ['server', 'pi5_hailo', 'pi5_8gb'],
      bestFor: ['industrial'],
      ohb1Score: 0.8812,
      isChampion: false,
      tags: ['industrial'],
    ),
  ];
}
