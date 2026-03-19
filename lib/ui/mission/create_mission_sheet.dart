import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/mission.dart';

class CreateMissionSheet extends StatefulWidget {
  const CreateMissionSheet({super.key});

  @override
  State<CreateMissionSheet> createState() => _CreateMissionSheetState();
}

class _CreateMissionSheetState extends State<CreateMissionSheet> {
  final _titleController = TextEditingController();
  final _emailController = TextEditingController();
  final Set<String> _selectedRrns = {};

  // Invited humans: email → role
  final Map<String, HumanRole> _invitedEmails = {};

  bool _loading = false;
  String? _error;
  String? _inviteError;

  @override
  void dispose() {
    _titleController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _addInvite() {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    if (!email.contains('@')) {
      setState(() => _inviteError = 'Enter a valid email address.');
      return;
    }
    if (_invitedEmails.containsKey(email)) {
      setState(() => _inviteError = 'Already added.');
      return;
    }
    setState(() {
      _invitedEmails[email] = HumanRole.operator; // default role
      _emailController.clear();
      _inviteError = null;
    });
  }

  void _removeInvite(String email) {
    setState(() => _invitedEmails.remove(email));
  }

  void _setInviteRole(String email, HumanRole role) {
    setState(() => _invitedEmails[email] = role);
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
        if (_invitedEmails.isNotEmpty)
          'invite_emails': _invitedEmails.keys.toList(),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.80,
      maxChildSize: 0.97,
      builder: (context, scrollCtrl) {
        return Padding(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                    // ── Mission title ──────────────────────────────────────
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

                    // ── Select robots ──────────────────────────────────────
                    _SectionHeader(
                        icon: Icons.smart_toy_outlined, label: 'Select robots'),
                    const SizedBox(height: 8),
                    if (uid != null)
                      StreamBuilder<QuerySnapshot>(
                        stream: FirebaseFirestore.instance
                            .collection('robots')
                            .where('firebase_uid', isEqualTo: uid)
                            .snapshots(),
                        builder: (ctx, snap) {
                          if (snap.connectionState == ConnectionState.waiting) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          final docs = snap.data?.docs ?? [];
                          if (docs.isEmpty) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'No robots registered yet.',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            );
                          }
                          return Column(
                            children: docs.map((doc) {
                              final data =
                                  doc.data() as Map<String, dynamic>;
                              final rrn = doc.id;
                              final name = data['name'] as String? ?? rrn;
                              final isSelected = _selectedRrns.contains(rrn);
                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _selectedRrns.add(rrn);
                                  } else {
                                    _selectedRrns.remove(rrn);
                                  }
                                }),
                                title: Text(name),
                                subtitle: Text(rrn,
                                    style: const TextStyle(fontSize: 11)),
                                secondary: const Icon(Icons.smart_toy_outlined,
                                    color: Color(0xFF0ea5e9)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                                tileColor: isSelected
                                    ? const Color(0xFF0ea5e9).withOpacity(0.08)
                                    : null,
                              );
                            }).toList(),
                          );
                        },
                      ),

                    const SizedBox(height: 20),

                    // ── Invite teammates ───────────────────────────────────
                    _SectionHeader(
                        icon: Icons.group_add_outlined,
                        label: 'Invite teammates'),
                    const SizedBox(height: 4),
                    Text(
                      'Invite people by email. They\'ll be notified in the app.',
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),

                    // Email input row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _emailController,
                            decoration: InputDecoration(
                              labelText: 'Email address',
                              hintText: 'alice@example.com',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              errorText: _inviteError,
                              prefixIcon:
                                  const Icon(Icons.email_outlined, size: 18),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            onSubmitted: (_) => _addInvite(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _addInvite,
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Invited humans chips
                    if (_invitedEmails.isNotEmpty) ...[
                      ..._invitedEmails.entries.map((e) =>
                          _InviteeRow(
                            email: e.key,
                            role: e.value,
                            onRoleChanged: (r) => _setInviteRole(e.key, r),
                            onRemove: () => _removeInvite(e.key),
                          )),
                      const SizedBox(height: 8),
                    ],

                    // Error
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: cs.error, fontSize: 13),
                        ),
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // Submit
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
                                strokeWidth: 2, color: Colors.white),
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

// ---------------------------------------------------------------------------
// _SectionHeader
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Text(
          label,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _InviteeRow — email chip with role dropdown and remove button
// ---------------------------------------------------------------------------

class _InviteeRow extends StatelessWidget {
  final String email;
  final HumanRole role;
  final ValueChanged<HumanRole> onRoleChanged;
  final VoidCallback onRemove;

  const _InviteeRow({
    required this.email,
    required this.role,
    required this.onRoleChanged,
    required this.onRemove,
  });

  Color get _roleColor {
    switch (role) {
      case HumanRole.owner:
        return const Color(0xFFf59e0b);
      case HumanRole.operator:
        return const Color(0xFF0ea5e9);
      case HumanRole.observer:
        return const Color(0xFF6b7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.person_outline, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(email,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          // Role dropdown
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _roleColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<HumanRole>(
                value: role,
                isDense: true,
                items: HumanRole.values
                    .where((r) => r != HumanRole.owner) // can't invite as owner
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r.label,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: _roleColor,
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
                onChanged: (r) {
                  if (r != null) onRoleChanged(r);
                },
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
