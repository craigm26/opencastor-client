/// Account screen — signed-in user profile, Firebase UID, sign out.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/services/auth_service.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── Avatar + name ──────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 40,
                  backgroundColor: cs.primaryContainer,
                  backgroundImage: user?.photoURL != null
                      ? NetworkImage(user!.photoURL!)
                      : null,
                  child: user?.photoURL == null
                      ? Text(
                          (user?.displayName ?? user?.email ?? '?')[0]
                              .toUpperCase(),
                          style: TextStyle(
                              fontSize: 32,
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                Text(
                  user?.displayName ?? 'No name',
                  style:
                      tt.titleLarge?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? '',
                  style:
                      tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),
          const Divider(),
          const SizedBox(height: 8),

          // ── Info tiles ──────────────────────────────────────────────────
          _InfoTile(
            label: 'Firebase UID',
            value: user?.uid ?? '—',
            copyable: true,
          ),
          _InfoTile(
            label: 'Provider',
            value: user?.providerData.firstOrNull?.providerId ?? '—',
          ),
          _InfoTile(
            label: 'Email verified',
            value: (user?.emailVerified ?? false) ? 'Yes ✓' : 'No',
          ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 8),

          // ── Community Hub link ──────────────────────────────────────────
          ListTile(
            leading:
                const Icon(Icons.explore_outlined),
            title: const Text('My Configs'),
            subtitle: const Text('View your shared configs on the Hub'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              context.pop();
              context.go('/explore');
            },
          ),

          const SizedBox(height: 8),

          // ── Sign out ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
                foregroundColor:
                    Theme.of(context).colorScheme.onErrorContainer,
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text(
                        'You\'ll need to sign in again to access your fleet.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Sign out')),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await AuthService.signOut();
                }
              },
              child: const Text('Sign Out'),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile(
      {required this.label, required this.value, this.copyable = false});
  final String label;
  final String value;
  final bool copyable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      subtitle: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14)),
      trailing: copyable
          ? IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copy',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copied'),
                    duration: Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            )
          : null,
    );
  }
}
