import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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
  if (kIsWeb) {
    // Flutter web: use Firebase popup flow (google_sign_in mobile flow
    // returns null idToken on web — use signInWithPopup instead)
    final provider = GoogleAuthProvider();
    await FirebaseAuth.instance.signInWithPopup(provider);
    return;
  }
  // Mobile / desktop
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0a0b1e) : const Color(0xFFF8FAFF),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo lockup — icon + wordmark
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/icon-128.png',
                      height: 48,
                      width: 48,
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'OpenCastor',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0ea5e9),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Remote fleet management',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontSize: 15,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 48),

                // Card
                Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF12142b) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? const Color(0xFF0ea5e9).withOpacity(0.18)
                          : const Color(0xFFe2e8f0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(isDark ? 0.4 : 0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      if (_error != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.danger.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: AppTheme.danger, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!,
                                  style: TextStyle(color: AppTheme.danger, fontSize: 13))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],
                      _loading
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 12),
                              child: CircularProgressIndicator(),
                            )
                          : SizedBox(
                              width: double.infinity,
                              height: 48,
                              child: OutlinedButton.icon(
                                onPressed: _signIn,
                                icon: _GoogleIcon(),
                                label: const Text(
                                  'Continue with Google',
                                  style: TextStyle(fontWeight: FontWeight.w500),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: cs.onSurface,
                                  side: BorderSide(color: cs.outlineVariant),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                      const SizedBox(height: 20),
                      Text(
                        'Access your registered robots.\nControl requires R2RAM consent.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
                // Brand footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Powered by ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    Text('RCAN v1.4',
                        style: TextStyle(
                          color: const Color(0xFF0ea5e9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                    Text(' · Protocol 66 enforced',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Google "G" icon painted inline (no package dependency)
class _GoogleIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 18,
      child: CustomPaint(painter: _GoogleIconPainter()),
    );
  }
}

class _GoogleIconPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    // Simplified Google G coloured circle
    final segments = [
      (0.0, 0.5, const Color(0xFF4285F4)),
      (0.5, 0.75, const Color(0xFF34A853)),
      (0.75, 0.875, const Color(0xFFFBBC05)),
      (0.875, 1.0, const Color(0xFFEA4335)),
    ];
    for (final (start, end, color) in segments) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(r, r), radius: r),
        start * 2 * 3.14159,
        (end - start) * 2 * 3.14159,
        true,
        Paint()..color = color,
      );
    }
    // White inner circle
    canvas.drawCircle(Offset(r, r), r * 0.6, Paint()..color = Colors.white);
  }
  @override
  bool shouldRepaint(_) => false;
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
