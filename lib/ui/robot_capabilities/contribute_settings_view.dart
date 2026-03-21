/// Contribute settings: enable/disable toggle and project selection.
/// Covers issues #14 (toggle) and #13 (project selection).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/robot.dart';

/// Available science project categories.
const _kProjects = <String, String>{
  'climate': 'Climate Modeling',
  'biodiversity': 'Biodiversity Monitoring',
  'science': 'Protein Folding & Science',
  'humanitarian': 'Humanitarian AI',
};

class ContributeSettingsView extends ConsumerStatefulWidget {
  final Robot robot;

  const ContributeSettingsView({super.key, required this.robot});

  @override
  ConsumerState<ContributeSettingsView> createState() =>
      _ContributeSettingsViewState();
}

class _ContributeSettingsViewState
    extends ConsumerState<ContributeSettingsView> {
  bool _enabled = false;
  Set<String> _selectedProjects = {'climate', 'biodiversity', 'science'};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('robots')
          .doc(widget.robot.rrn)
          .get();
      if (!mounted) return;
      final data = doc.data();
      if (data != null) {
        final contribute = data['contribute'] as Map<String, dynamic>? ?? {};
        setState(() {
          _enabled = contribute['enabled'] as bool? ?? false;
          final projects = contribute['projects'] as List<dynamic>? ?? [];
          if (projects.isNotEmpty) {
            _selectedProjects = projects.cast<String>().toSet();
          }
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      // Send command through bridge
      final fn =
          FirebaseFunctions.instance.httpsCallable('sendRobotCommand');
      await fn.call<Map<String, dynamic>>({
        'rrn': widget.robot.rrn,
        'command': _enabled ? '/contribute start' : '/contribute stop',
      });

      // Update Firestore directly for UI responsiveness
      await FirebaseFirestore.instance
          .collection('robots')
          .doc(widget.robot.rrn)
          .set({
        'contribute': {
          'enabled': _enabled,
          'projects': _selectedProjects.toList(),
        },
      }, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Contribute ${_enabled ? "enabled" : "disabled"}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Enable/disable toggle (#14)
            Row(
              children: [
                Icon(Icons.science_outlined,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Compute Contribution Settings',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                if (_saving)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Switch.adaptive(
                    value: _enabled,
                    onChanged: (v) {
                      setState(() => _enabled = v);
                      _saveSettings();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _enabled
                  ? 'Robot is contributing — earning rank and Castor Credits'
                  : 'Enable to earn rank and Castor Credits from idle compute',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),

            if (_enabled) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // Project selection (#13)
              Text('Science Projects',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ..._kProjects.entries.map((entry) {
                final selected = _selectedProjects.contains(entry.key);
                return CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value,
                      style: theme.textTheme.bodyMedium),
                  value: selected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        _selectedProjects.add(entry.key);
                      } else if (_selectedProjects.length > 1) {
                        // Keep at least one project selected
                        _selectedProjects.remove(entry.key);
                      }
                    });
                    _saveSettings();
                  },
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}
