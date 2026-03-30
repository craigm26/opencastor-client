/// Settings Screen — appearance, account info, about, sign out.
///
/// Theme preference is persisted via SharedPreferences.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:package_info_plus/package_info_plus.dart';

import '../../core/constants.dart';
import '../../data/services/auth_service.dart';
import '../../ui/core/theme/app_theme.dart';
import 'theme_mode_provider.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>((ref) async {
  return PackageInfo.fromPlatform();
});

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final user = AuthService.currentUser;
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Appearance ────────────────────────────────────────────────
          _SectionHeader(label: 'Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Theme', style: theme.textTheme.bodyLarge),
                  ),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Light'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Dark'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto_outlined),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (modes) {
                      if (modes.isNotEmpty) {
                        ref
                            .read(themeModeProvider.notifier)
                            .setMode(modes.first);
                      }
                    },
                    showSelectedIcon: false,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // ── Account ───────────────────────────────────────────────────
          _SectionHeader(label: 'Account'),
          Card(
            child: Column(
              children: [
                if (user?.photoURL != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: CircleAvatar(
                      radius: 32,
                      backgroundImage: NetworkImage(user!.photoURL!),
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(user?.displayName ?? 'Unknown'),
                ),
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(user?.email ?? ''),
                ),
                ListTile(
                  leading: const Icon(Icons.tag_outlined),
                  title: Text(
                    user?.uid ?? '',
                    style: AppTheme.mono
                        .copyWith(fontSize: 12, color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: const Text('Firebase UID — tap to copy'),
                  onTap: () {
                    if (user?.uid != null) {
                      Clipboard.setData(ClipboardData(text: user!.uid));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('UID copied to clipboard'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Pro ───────────────────────────────────────────────────────
          _SectionHeader(label: 'Subscription'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.workspace_premium_outlined),
              title: const Text('OpenCastor Pro'),
              subtitle: const Text('Waitlist · \$19/month launching soon'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/pro'),
            ),
          ),

          const SizedBox(height: 8),

          // ── About ─────────────────────────────────────────────────────
          _SectionHeader(label: 'About'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('OpenCastor Client'),
                  subtitle: ref.watch(_packageInfoProvider).when(
                    data: (info) => Text('v${info.version}+${info.buildNumber}'),
                    loading: () => Text('v\${AppConstants.appVersion}'),
                    error: (_, __) => Text('v\${AppConstants.appVersion}'),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.hub_outlined),
                  title: const Text('RCAN Protocol'),
                  subtitle: Text('v${AppConstants.rcanVersion}'),
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new_outlined),
                  title: const Text('opencastor.com'),
                  onTap: () => launchUrl(Uri.parse(AppConstants.docsRoot)),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                ),
                ListTile(
                  leading: const Icon(Icons.open_in_new_outlined),
                  title: const Text('rcan.dev'),
                  onTap: () => launchUrl(Uri.parse('https://rcan.dev')),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Sign out ──────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await AuthService.signOut();
                if (context.mounted) context.go('/login');
              },
              icon: const Icon(Icons.logout),
              label: const Text('Sign out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                minimumSize: const Size(0, 48),
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
