import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'screens/alerts/alerts_screen.dart';
import 'screens/consent/consent_screen.dart';
import 'screens/control/control_screen.dart';
import 'screens/fleet/fleet_screen.dart';
import 'screens/robot_detail/robot_detail_screen.dart';
import 'theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

final authStateProvider = StreamProvider<User?>((_) {
  return FirebaseAuth.instance.authStateChanges();
});

Future<void> signInWithGoogle() async {
  final gs = GoogleSignIn();
  final account = await gs.signIn();
  if (account == null) return;
  final auth = await account.authentication;
  final cred = GoogleAuthProvider.credential(
    accessToken: auth.accessToken,
    idToken: auth.idToken,
  );
  await FirebaseAuth.instance.signInWithCredential(cred);
}

Future<void> signOut() async {
  await GoogleSignIn().signOut();
  await FirebaseAuth.instance.signOut();
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final _router = GoRouter(
  initialLocation: '/fleet',
  redirect: (context, state) {
    final user = FirebaseAuth.instance.currentUser;
    final isAuth = user != null;
    final isLogin = state.matchedLocation == '/login';
    if (!isAuth && !isLogin) return '/login';
    if (isAuth && isLogin) return '/fleet';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      builder: (_, __) => const _LoginScreen(),
    ),
    ShellRoute(
      builder: (ctx, state, child) => _AppShell(child: child),
      routes: [
        GoRoute(
          path: '/fleet',
          builder: (_, __) => const FleetScreen(),
        ),
        GoRoute(
          path: '/robot/:rrn',
          builder: (_, state) =>
              RobotDetailScreen(rrn: state.pathParameters['rrn']!),
        ),
        GoRoute(
          path: '/robot/:rrn/control',
          builder: (_, state) =>
              ControlScreen(rrn: state.pathParameters['rrn']!),
        ),
        GoRoute(
          path: '/consent',
          builder: (_, __) => const ConsentScreen(),
        ),
        GoRoute(
          path: '/alerts',
          builder: (_, __) => const AlertsScreen(),
        ),
        GoRoute(
          path: '/account',
          builder: (_, __) => const _AccountScreen(),
        ),
      ],
    ),
  ],
);

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class OpenCastorApp extends ConsumerWidget {
  const OpenCastorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'OpenCastor',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------------------------------------------------------------------------
// App shell with bottom nav
// ---------------------------------------------------------------------------

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    int selectedIndex = 0;
    if (location.startsWith('/fleet')) selectedIndex = 0;
    if (location.startsWith('/consent')) selectedIndex = 1;
    if (location.startsWith('/alerts')) selectedIndex = 2;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (i) {
          switch (i) {
            case 0: context.go('/fleet');
            case 1: context.go('/consent');
            case 2: context.go('/alerts');
          }
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: 'Fleet',
          ),
          NavigationDestination(
            icon: Icon(Icons.handshake_outlined),
            selectedIcon: Icon(Icons.handshake),
            label: 'Access',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Alerts',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Login screen
// ---------------------------------------------------------------------------

class _LoginScreen extends StatefulWidget {
  const _LoginScreen();

  @override
  State<_LoginScreen> createState() => _LoginState();
}

class _LoginState extends State<_LoginScreen> {
  bool _loading = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() { _loading = true; _error = null; });
    try {
      await signInWithGoogle();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.precision_manufacturing_outlined, size: 72),
              const SizedBox(height: 16),
              Text('OpenCastor',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Remote fleet management',
                  style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 40),
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: AppTheme.danger)),
                const SizedBox(height: 16),
              ],
              _loading
                  ? const CircularProgressIndicator()
                  : FilledButton.icon(
                      onPressed: _signIn,
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with Google'),
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(240, 48)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Account screen
// ---------------------------------------------------------------------------

class _AccountScreen extends StatelessWidget {
  const _AccountScreen();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (user?.photoURL != null)
            Center(
              child: CircleAvatar(
                radius: 40,
                backgroundImage: NetworkImage(user!.photoURL!),
              ),
            ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(user?.displayName ?? 'Unknown'),
          ),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: Text(user?.email ?? ''),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: AppTheme.danger),
            title: const Text('Sign out',
                style: TextStyle(color: AppTheme.danger)),
            onTap: () async {
              await signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
    );
  }
}
