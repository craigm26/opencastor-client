/// App root: MaterialApp.router + GoRouter.
///
/// This file contains ONLY:
///   - [OpenCastorApp] — MaterialApp wrapper
///   - [_AppShell]     — adaptive navigation shell
///   - [_LoginScreen]  — authentication entry point
///   - The [GoRouter] configuration
///
/// Auth logic lives in [AuthService].
/// Screen-level state lives in the per-feature ViewModels.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'data/models/harness_config.dart';
import 'data/services/auth_service.dart';
import 'ui/alerts/alerts_screen.dart';
import 'ui/consent/consent_screen.dart';
import 'ui/consent/pending_consent_screen.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/explore/explore_screen.dart';
import 'ui/explore/qr_scanner_screen.dart';
import 'ui/fleet/fleet_screen.dart';
import 'ui/fleet/fleet_view_model.dart' show authStateProvider;
import 'ui/robot_detail/robot_detail_view_model.dart';
import 'ui/login/ecosystem_section.dart';
import 'ui/physical_control/physical_control_screen.dart';
import 'ui/harness/harness_editor.dart';
import 'ui/harness/harness_viewer.dart';
import 'ui/robot_capabilities/robot_capabilities_screen.dart';
import 'ui/robot_detail/robot_detail_screen.dart';
import 'ui/robot_status/robot_status_screen.dart';
import 'ui/settings/settings_screen.dart';
import 'ui/settings/theme_mode_provider.dart';
import 'ui/setup/setup_screen.dart';
import 'ui/account/account_screen.dart';
import 'ui/shared/adaptive_navigation.dart';
import 'ui/shared/google_sign_in_button.dart';
import 'ui/fleet_leaderboard/fleet_leaderboard_screen.dart';
import 'ui/mission/mission_list_screen.dart';
import 'ui/mission/mission_screen.dart';

// ---------------------------------------------------------------------------
// RouterNotifier — Riverpod-aware GoRouter refresh bridge
// ---------------------------------------------------------------------------

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue>(authStateProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authAsync = _ref.read(authStateProvider);
    final loc = state.matchedLocation;

    if (authAsync.isLoading || authAsync.hasError) {
      return loc == '/splash' ? null : '/splash';
    }

    final user = authAsync.asData?.value;
    final isAuth = user != null;
    final isPublic =
        loc == '/login' || loc == '/splash' || loc.startsWith('/setup');

    // Not signed in: redirect to login (including from splash)
    if (!isAuth) return isPublic ? (loc == '/splash' ? '/login' : null) : '/login';
    // Signed in: leave protected pages alone; bounce off public pages to fleet
    if (isAuth && isPublic) return '/fleet';
    return null;
  }
}

final _routerProvider = Provider<GoRouter>((ref) {
  final notifier = _RouterNotifier(ref);
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: notifier,
    redirect: notifier.redirect,
    routes: [
      // Redirect bare "/" to splash (handles web deep-links and deferred navigations)
      GoRoute(
        path: '/',
        redirect: (_, __) => '/splash',
      ),
      GoRoute(
        path: '/splash',
        builder: (_, __) => const _SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const _LoginScreen(),
      ),
      GoRoute(
        path: '/setup',
        builder: (_, state) => SetupScreen(
          robotName: state.uri.queryParameters['robot'],
          ownerName: state.uri.queryParameters['owner'],
        ),
      ),
      ShellRoute(
        builder: (ctx, state, child) => _AppShell(child: child),
        routes: [
          GoRoute(
            path: '/fleet',
            builder: (_, __) => const FleetScreen(),
            pageBuilder: (_, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const FleetScreen(),
              transitionsBuilder: (ctx, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/explore',
            builder: (_, __) => const ExploreScreen(),
            pageBuilder: (_, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ExploreScreen(),
              transitionsBuilder: (ctx, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/explore/scan',
            builder: (_, __) => const QrScannerScreen(),
          ),
          GoRoute(
            path: '/explore/:id',
            pageBuilder: (_, state) => CustomTransitionPage(
              key: state.pageKey,
              child: ExploreDetailScreen(
                  configId: state.pathParameters['id']!),
              transitionsBuilder: (ctx, animation, secondary, child) {
                final slide = Tween(
                  begin: const Offset(0, 0.08),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                    parent: animation, curve: Curves.easeOutCubic));
                return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child));
              },
            ),
          ),
          GoRoute(
            path: '/robot/:rrn',
            pageBuilder: (_, state) {
              final rrn = state.pathParameters['rrn']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: RobotDetailScreen(rrn: rrn),
                transitionsBuilder: (ctx, animation, secondary, child) {
                  final slide = Tween(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                  ));
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(position: slide, child: child),
                  );
                },
              );
            },
          ),
          GoRoute(
            path: '/robot/:rrn/control',
            builder: (_, state) =>
                PhysicalControlScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/status',
            builder: (_, state) =>
                RobotStatusScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities',
            builder: (_, state) => RobotCapabilitiesScreen(
              rrn: state.pathParameters['rrn']!,
              anchor: state.uri.fragment.isNotEmpty
                  ? state.uri.fragment
                  : null,
            ),
          ),
          GoRoute(
            path: '/robot/:rrn/harness',
            builder: (_, state) {
              final rrn = state.pathParameters['rrn']!;
              return _HarnessViewerPage(rrn: rrn);
            },
          ),
          GoRoute(
            path: '/robot/:rrn/harness/edit',
            builder: (_, state) {
              final rrn = state.pathParameters['rrn']!;
              final extra = state.extra as _HarnessEditorArgs?;
              return HarnessEditorScreen(
                rrn: rrn,
                robotName: extra?.robotName ?? rrn,
                initialConfig: extra?.config ??
                    HarnessConfig.defaults(robotRrn: rrn),
              );
            },
          ),
          GoRoute(
            path: '/fleet/leaderboard',
            builder: (_, __) => const FleetLeaderboardScreen(),
          ),
          GoRoute(
            path: '/consent',
            builder: (_, __) => const ConsentScreen(),
          ),
          GoRoute(
            path: '/consent/pending',
            builder: (_, __) => const PendingConsentScreen(),
          ),
          GoRoute(
            path: '/alerts',
            builder: (_, __) => const AlertsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/account',
            builder: (_, __) => const AccountScreen(),
          ),
          GoRoute(
            path: '/missions',
            builder: (_, __) => const MissionListScreen(),
            pageBuilder: (_, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const MissionListScreen(),
              transitionsBuilder: (ctx, animation, secondary, child) =>
                  FadeTransition(opacity: animation, child: child),
            ),
          ),
          GoRoute(
            path: '/missions/new',
            redirect: (_, __) => '/missions',
          ),
          GoRoute(
            path: '/missions/:id',
            builder: (_, state) =>
                MissionScreen(missionId: state.pathParameters['id']!),
            pageBuilder: (_, state) {
              final id = state.pathParameters['id']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: MissionScreen(missionId: id),
                transitionsBuilder: (ctx, animation, secondary, child) {
                  final slide = Tween(
                    begin: const Offset(0, 0.08),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic));
                  return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(position: slide, child: child));
                },
              );
            },
          ),
        ],
      ),
    ],
  );
});

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class OpenCastorApp extends ConsumerWidget {
  const OpenCastorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(_routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'OpenCastor',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Harness route helpers
// ---------------------------------------------------------------------------

/// Arguments for the harness editor route (/robot/:rrn/harness/edit).
class _HarnessEditorArgs {
  final String robotName;
  final HarnessConfig config;
  const _HarnessEditorArgs({required this.robotName, required this.config});
}

/// Standalone harness viewer page — wraps HarnessViewer + Edit Harness button.
/// Loads the robot's actual harness config from telemetry, falling back to
/// defaults if not yet published by the bridge.
class _HarnessViewerPage extends ConsumerWidget {
  final String rrn;
  const _HarnessViewerPage({required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    final config = robotAsync.whenData((robot) {
      if (robot == null) return HarnessConfig.defaults(robotRrn: rrn);
      final harnessData = robot.telemetry['harness_config'];
      if (harnessData is Map<String, dynamic>) {
        return HarnessConfig.fromApiJson(rrn, harnessData);
      }
      return HarnessConfig.defaults(robotRrn: rrn);
    });

    return config.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Harness')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Harness')),
        body: Center(child: Text('Error loading harness: $e')),
      ),
      data: (harnessConfig) => Scaffold(
        appBar: AppBar(
          title: const Text('Harness'),
          actions: [
            FilledButton.icon(
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit Harness'),
              onPressed: () => context.push(
                '/robot/$rrn/harness/edit',
                extra: _HarnessEditorArgs(
                  robotName: rrn,
                  config: harnessConfig,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: HarnessViewer(config: harnessConfig),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Splash screen
// ---------------------------------------------------------------------------

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0a0b1e) : const Color(0xFFF8FAFF),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/images/icon-128.png', width: 72, height: 72),
            const SizedBox(height: 24),
            const CircularProgressIndicator(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App shell — adaptive navigation (Fleet · Alerts · Settings)
// ---------------------------------------------------------------------------

class _AppShell extends StatelessWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    int selectedIndex = 0;
    if (location.startsWith('/fleet') || location.startsWith('/robot')) {
      selectedIndex = 0;
    } else if (location.startsWith('/explore')) {
      selectedIndex = 1;
    } else if (location.startsWith('/alerts')) {
      selectedIndex = 2;
    } else if (location.startsWith('/settings')) {
      selectedIndex = 3;
    } else if (location.startsWith('/missions')) {
      selectedIndex = 4;
    }

    const destinations = [
      NavigationDestination(
        icon: Icon(Icons.precision_manufacturing_outlined),
        selectedIcon: Icon(Icons.precision_manufacturing),
        label: 'Fleet',
      ),
      NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore),
        label: 'Explore',
      ),
      NavigationDestination(
        icon: Icon(Icons.notifications_outlined),
        selectedIcon: Icon(Icons.notifications),
        label: 'Alerts',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: 'Settings',
      ),
      NavigationDestination(
        icon: Icon(Icons.track_changes_outlined),
        selectedIcon: Icon(Icons.track_changes),
        label: 'Missions',
      ),
    ];

    return AdaptiveScaffold(
      selectedIndex: selectedIndex,
      onDestinationSelected: (i) {
        switch (i) {
          case 0:
            context.go('/fleet');
          case 1:
            context.go('/explore');
          case 2:
            context.go('/alerts');
          case 3:
            context.go('/settings');
          case 4:
            context.go('/missions');
        }
      },
      destinations: destinations,
      body: child,
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Logo ───────────────────────────────────────────────
                  Image.asset('assets/images/icon-128.png',
                      height: 200, width: 200),
                  const SizedBox(height: 16),
                  Text(
                    'OpenCastor',
                    style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0ea5e9),
                          letterSpacing: -0.5,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Open robot fleet management',
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 15,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 48),

                  // ── Sign-in card ───────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF12142b)
                          : Colors.white,
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
                                  color:
                                      AppTheme.danger.withOpacity(0.3)),
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
                                padding:
                                    EdgeInsets.symmetric(vertical: 12),
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

                  const SizedBox(height: 24),
                  const EcosystemSection(),
                  const SizedBox(height: 32),

                  // ── Footer ─────────────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Powered by ',
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12)),
                      const Text('RCAN v${AppConstants.rcanVersion}',
                          style: TextStyle(
                            color: Color(0xFF0ea5e9),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          )),
                      Text(' · Protocol 66 enforced',
                          style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppConstants.versionLabel,
                    style: TextStyle(
                        color: cs.onSurfaceVariant.withOpacity(0.5),
                        fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Official Google branding button
/// Thin wrapper so call-sites in app.dart don't need to change.
class _GoogleSignInButton extends StatelessWidget {
  const _GoogleSignInButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) =>
      GoogleSignInButton(onPressed: onPressed);
}

/// Renders the official Google G logo using the standard multicolor SVG paths.
/// Faithfully replicates the Google G at 18×18 logical pixels per branding spec.
// _GoogleGLogo and _GoogleGPainter are now in ui/shared/google_sign_in_button.dart
