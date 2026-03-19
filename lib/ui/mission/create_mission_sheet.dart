import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/robot.dart';

class CreateMissionSheet extends StatefulWidget {
  const CreateMissionSheet({super.key});

  @override
  State<CreateMissionSheet> createState() => _CreateMissionSheetState();
}

class _CreateMissionSheetState extends State<CreateMissionSheet> {
  final _titleController = TextEditingController();
  final Set<String> _selectedRrns = {};
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Please enter a mission title.');
      return;
    }
    if (_selectedRrns.isEmpty) {
      setState(() => _error = 'Select at least one robot.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fn = FirebaseFunctions.instance.httpsCallable('createMission');
      final result = await fn.call({
        'title': title,
        'robot_rrns': _selectedRrns.toList(),
      });
      final missionId = result.data['missionId'] as String;
      if (mounted) {
        Navigator.of(context).pop();
        context.push('/missions/$missionId');
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (context, scrollCtrl) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            children: [
              // Handle
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.track_changes,
                        color: Color(0xFF0ea5e9)),
                    const SizedBox(width: 10),
                    Text(
                      'New Mission',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    // Title input
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Mission title',
                        hintText: 'e.g. Kitchen Exploration',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.title),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Select robots',
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),

                    // Robot list
                    if (uid != null)
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('robots')
                            .where('firebase_uid', isEqualTo: uid)
                            .snapshots(),
                        builder: (ctx, snap) {
                          if (snap.connectionState ==
                              ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                  child: CircularProgressIndicator()),
                            );
                          }
                          final docs = snap.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'No robots registered yet.',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant),
                              ),
                            );
                          }
                          return Column(
                            children: docs.map((doc) {
                              final data =
                                  doc.data() as Map<String, dynamic>;
                              final rrn = doc.id;
                              final name =
                                  data['name'] as String? ?? rrn;
                              final isSelected =
                                  _selectedRrns.contains(rrn);
                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedRrns.add(rrn);
                                    } else {
                                      _selectedRrns.remove(rrn);
                                    }
                                  });
                                },
                                title: Text(name),
                                subtitle: Text(
                                  rrn,
                                  style: const TextStyle(fontSize: 11),
                                ),
                                secondary: const Icon(
                                    Icons.smart_toy_outlined,
                                    color: Color(0xFF0ea5e9)),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                tileColor: isSelected
                                    ? const Color(0xFF0ea5e9)
                                        .withOpacity(0.08)
                                    : null,
                              );
                            }).toList(),
                          );
                        },
                      ),

                    const SizedBox(height: 8),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              // Submit button
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _loading ? null : _submit,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white),
                          )
                        : const Icon(Icons.rocket_launch_outlined),
                    label: Text(_loading ? 'Creating…' : 'Start Mission'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
