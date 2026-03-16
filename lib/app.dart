/// App root: MaterialApp.router + GoRouter.
///
/// This file contains ONLY:
///   - [OpenCastorApp] — MaterialApp wrapper
///   - [_AppShell]     — bottom nav shell
///   - [_LoginScreen]  — authentication entry point
///   - The [GoRouter] configuration
///
/// Auth logic lives in [AuthService].
/// Screen-level state lives in the per-feature ViewModels.
library;

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data/services/auth_service.dart';
import 'ui/account/account_screen.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/fleet/fleet_screen.dart';
import 'ui/fleet/fleet_view_model.dart' show authStateProvider;

// Screens not yet migrated to ui/ — pending move
import 'screens/alerts/alerts_screen.dart';
import 'screens/consent/consent_screen.dart';
import 'screens/control/control_screen.dart';
import 'screens/robot_detail/robot_detail_screen.dart';

// ---------------------------------------------------------------------------
// Auth → Router bridge
//
// GoRouter's redirect guard is a synchronous snapshot of auth state.
// Without refreshListenable, the router never re-evaluates after a
// signInWithRedirect completes — user lands on /login and gets stuck.
//
// _AuthStateNotifier bridges Firebase authStateChanges() to GoRouter so
// the router re-runs redirect whenever auth state changes (sign-in/out).
// ---------------------------------------------------------------------------

class _AuthStateNotifier extends ChangeNotifier {
  _AuthStateNotifier() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }

  late final StreamSubscription<User?> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _authNotifier = _AuthStateNotifier();

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

final _router = GoRouter(
  initialLocation: '/fleet',
  refreshListenable: _authNotifier, // re-run redirect on auth state change
  redirect: (context, state) {
    final user = AuthService.currentUser;
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
          builder: (_, __) => const AccountScreen(),
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
// App shell — bottom navigation
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
            case 0:
              context.go('/fleet');
            case 1:
              context.go('/consent');
            case 2:
              context.go('/alerts');
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
// Login screen — entry point for unauthenticated users
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthService.signInWithGoogle();
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
      backgroundColor:
          isDark ? const Color(0xFF0a0b1e) : const Color(0xFFF8FAFF),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo lockup
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset('assets/images/icon-128.png',
                        height: 48, width: 48),
                    const SizedBox(width: 14),
                    Text(
                      'OpenCastor',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(
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

                // Sign-in card
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
                        color: Colors.black
                            .withOpacity(isDark ? 0.4 : 0.06),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppTheme.danger.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline,
                                  color: AppTheme.danger, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: AppTheme.danger,
                                        fontSize: 13)),
                              ),
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
                          : _GoogleSignInButton(onPressed: _signIn),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Powered by ',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                    const Text('RCAN v1.4',
                        style: TextStyle(
                          color: Color(0xFF0ea5e9),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        )),
                    Text(' · Protocol 66 enforced',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12)),
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

// Official Google branding button
// https://developers.google.com/identity/branding-guidelines
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          elevation: 1,
          shadowColor: Colors.black26,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: Color(0xFFDADCE0)),
          ),
          padding: EdgeInsets.zero,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _GoogleLogo(),
            ),
            const Expanded(
              child: Text(
                'Sign in with Google',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF1F1F1F),
                  letterSpacing: 0.25,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
        width: 18, height: 18, child: CustomPaint(painter: _GoogleLogoPainter()));
  }
}

class _GoogleLogoPainter extends CustomPainter {
  static const _blue   = Color(0xFF4285F4);
  static const _red    = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green  = Color(0xFF34A853);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.22;
    paint.color = _red;
    canvas.drawArc(Rect.fromLTWH(s * 0.11, s * 0.11, s * 0.78, s * 0.78),
        -1.5708, 1.5708, false, paint);
    paint.color = _yellow;
    canvas.drawArc(Rect.fromLTWH(s * 0.11, s * 0.11, s * 0.78, s * 0.78),
        0, 1.5708, false, paint);
    paint.color = _green;
    canvas.drawArc(Rect.fromLTWH(s * 0.11, s * 0.11, s * 0.78, s * 0.78),
        1.5708, 1.5708, false, paint);
    paint.color = _blue;
    canvas.drawArc(Rect.fromLTWH(s * 0.11, s * 0.11, s * 0.78, s * 0.78),
        3.14159, 1.5708, false, paint);
    paint
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    canvas.drawRect(
        Rect.fromLTWH(s * 0.5, s * 0.38, s * 0.5, s * 0.24), paint);
    canvas.drawCircle(Offset(s / 2, s / 2), s * 0.28, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}
