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

import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'data/models/harness_config.dart';
import 'data/services/auth_service.dart';
import 'data/services/notification_service.dart';
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
import 'ui/harness/flow_graph.dart';
import 'ui/harness/harness_editor.dart';
import 'ui/harness/harness_viewer.dart';
import 'ui/robot_capabilities/ai_screen.dart';
import 'ui/robot_capabilities/components_screen.dart';
import 'ui/robot_capabilities/contribute_screen.dart';
import 'ui/robot_capabilities/mcp_screen.dart';
import 'ui/robot_capabilities/conformance_screen.dart';
import 'ui/robot_detail/compliance_report_screen.dart';
import 'ui/compliance/compliance_hub_screen.dart';
import 'ui/compliance/fria_screen.dart';
import 'ui/compliance/safety_benchmark_screen.dart';
import 'ui/compliance/ifu_screen.dart';
import 'ui/compliance/incidents_screen.dart';
import 'ui/compliance/eu_register_screen.dart';
import 'ui/robot_detail/orchestrator_screen.dart';
import 'ui/robot_capabilities/hardware_screen.dart';
import 'ui/robot_capabilities/identity_screen.dart';
import 'ui/robot_capabilities/providers_screen.dart';
import 'ui/robot_capabilities/research_screen.dart';
import 'ui/robot_capabilities/robot_capabilities_screen.dart';
import 'ui/robot_capabilities/safety_screen.dart';
import 'ui/robot_capabilities/software_screen.dart';
import 'ui/robot_capabilities/transport_screen.dart';
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
import 'ui/pro/pro_screen.dart';
import 'routes.dart';

// ---------------------------------------------------------------------------
// RouterNotifier — Riverpod-aware GoRouter refresh bridge
// ---------------------------------------------------------------------------

final _pkgInfoProvider = FutureProvider<PackageInfo>((ref) => PackageInfo.fromPlatform());

/// Singleton NotificationService — exposes message and tap streams to the UI.
final _notificationServiceProvider = Provider<NotificationService>(
  (_) => NotificationService(),
);

class _RouterNotifier extends ChangeNotifier {
  _RouterNotifier(this._ref) {
    _ref.listen<AsyncValue>(authStateProvider, (_, __) => notifyListeners());
  }

  final Ref _ref;

  String? redirect(BuildContext context, GoRouterState state) {
    final authAsync = _ref.read(authStateProvider);
    final loc = state.matchedLocation;

    if (authAsync.isLoading) {
      return loc == '/splash' ? null : '/splash';
    }
    // Auth stream failed — avoid infinite splash; let user retry sign-in.
    if (authAsync.hasError) {
      debugPrint('authStateProvider error: ${authAsync.error}');
      return loc == '/login' ? null : '/login';
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
            path: '/robot/:rrn/capabilities/conformance',
            builder: (_, state) =>
                ConformanceScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/identity',
            builder: (_, state) =>
                IdentityScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/safety',
            builder: (_, state) =>
                SafetyScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/transport',
            builder: (_, state) =>
                TransportScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/ai',
            builder: (_, state) =>
                AiCapabilitiesScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/hardware',
            builder: (_, state) =>
                HardwareScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/software',
            builder: (_, state) =>
                SoftwareScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/providers',
            builder: (_, state) =>
                ProvidersScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/mcp',
            builder: (_, state) =>
                McpScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/contribute',
            builder: (_, state) =>
                CapContributeScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/consent',
            builder: (_, state) =>
                ConsentScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/capabilities/components',
            builder: (_, state) =>
                ComponentsScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance-report',
            builder: (_, state) =>
                ComplianceReportScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance',
            builder: (_, state) =>
                ComplianceHubScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/fria',
            builder: (_, state) =>
                FriaScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/benchmark',
            builder: (_, state) =>
                SafetyBenchmarkScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/ifu',
            builder: (_, state) =>
                IfuScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/incidents',
            builder: (_, state) =>
                IncidentsScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/compliance/eu-register',
            builder: (_, state) =>
                EuRegisterScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/research',
            builder: (_, state) =>
                ResearchScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            // #766: direct deep-link to compliance report (alias)
            path: '/robot/:rrn/attestation',
            builder: (_, state) =>
                ComplianceReportScreen(rrn: state.pathParameters['rrn']!),
          ),
          GoRoute(
            path: '/robot/:rrn/orchestrators',
            builder: (_, state) =>
                OrchestratorScreen(rrn: state.pathParameters['rrn']!),
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
                initialGraph: extra?.savedGraph,
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
            path: '/pro',
            builder: (_, __) => const ProScreen(),
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
  final FlowGraph? savedGraph;
  const _HarnessEditorArgs({
    required this.robotName,
    required this.config,
    this.savedGraph,
  });
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

      // Priority: user_harness_config (app-saved) > telemetry.harness_config
      // (bridge-reported) > defaults
      final userSaved = robot.userHarnessConfig;
      if (userSaved != null) return userSaved;

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
      data: (harnessConfig) {
        // Restore saved flow graph from user_harness_config if available
        FlowGraph? savedGraph;
        final robot = robotAsync.valueOrNull;
        if (robot != null) {
          final savedMap = robot.userHarnessRaw;
          if (savedMap != null && savedMap['flow_graph'] is Map<String, dynamic>) {
            try {
              savedGraph = FlowGraph.fromJson(
                  savedMap['flow_graph'] as Map<String, dynamic>);
            } catch (_) {}
          }
        }

        return Scaffold(
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
                    savedGraph: savedGraph,
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          body: HarnessViewer(config: harnessConfig),
        );
      },
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
    // Use a visible background colour — avoid #0a0b1e which looks like a
    // black screen on device before the first frame renders properly.
    final bg = isDark ? const Color(0xFF111827) : const Color(0xFFF8FAFF);
    final fg = isDark ? Colors.white70 : Colors.black54;
    return Scaffold(
      backgroundColor: bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/images/icon-128.png',
              width: 80,
              height: 80,
              // If asset not found, show fallback icon instead of crashing
              errorBuilder: (_, __, ___) =>
                  Icon(Icons.precision_manufacturing_outlined, size: 64, color: fg),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: isDark ? const Color(0xFF55d7ed) : const Color(0xFF4F46E5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'OpenCastor',
              style: TextStyle(
                color: fg,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App shell — adaptive navigation (Fleet · Alerts · Settings)
// ---------------------------------------------------------------------------

class _AppShell extends ConsumerStatefulWidget {
  final Widget child;
  const _AppShell({required this.child});

  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _tapSub;

  @override
  void initState() {
    super.initState();
    final svc = ref.read(_notificationServiceProvider);
    _foregroundSub = svc.messageStream.listen(_handleForeground);
    _tapSub = svc.tapStream.listen(_handleTap);
    // App opened by tapping a notification from terminated state
    svc.getInitialMessage().then((msg) {
      if (msg != null && mounted) _handleTap(msg);
    });
  }

  @override
  void dispose() {
    _foregroundSub?.cancel();
    _tapSub?.cancel();
    super.dispose();
  }

  void _handleForeground(RemoteMessage message) {
    final type = message.data['type'] as String?;
    final name = message.data['name'] as String? ?? 'Robot';
    if (type == 'robot_offline') {
      final rrn = message.data['rrn'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name went offline'),
          action: rrn != null
              ? SnackBarAction(
                  label: 'View',
                  onPressed: () => context.go(AppRoutes.robot(rrn)),
                )
              : null,
        ),
      );
    }
  }

  void _handleTap(RemoteMessage message) {
    final rrn = message.data['rrn'] as String?;
    if (rrn == null) return;
    // addPostFrameCallback ensures the router is ready before navigating
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(AppRoutes.robot(rrn));
    });
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;

    // Use AppRoutes.selectedIndexFor() instead of a hand-rolled startsWith
    // chain — avoids brittle ordering issues (e.g. /fleet/leaderboard vs /fleet)
    // and keeps tab mapping in a single, tested place.
    final selectedIndex = AppRoutes.selectedIndexFor(location);

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
        icon: Icon(Icons.leaderboard_outlined),
        selectedIcon: Icon(Icons.leaderboard),
        label: 'Compete',
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
    ];

    return AdaptiveScaffold(
      selectedIndex: selectedIndex,
      // Navigate to the canonical root for each tab via AppRoutes constants.
      onDestinationSelected: (i) => context.go(AppRoutes.tabRouteFor(i)),
      destinations: destinations,
      body: widget.child,
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
                  Image.asset(
                    'assets/images/icon-128.png',
                    height: 200,
                    width: 200,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.precision_manufacturing_outlined,
                      size: 120,
                      color: cs.primary,
                    ),
                  ),
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
                            ? const Color(0xFF0ea5e9).withValues(alpha: 0.18)
                            : const Color(0xFFe2e8f0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withValues(alpha: isDark ? 0.4 : 0.06),
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
                              color: AppTheme.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color:
                                      AppTheme.danger.withValues(alpha: 0.3)),
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
                  Consumer(builder: (context, ref, _) {
                    final pkgAsync = ref.watch(_pkgInfoProvider);
                    final label = pkgAsync.maybeWhen(
                      data: (info) => 'v${info.version} · RCAN v${AppConstants.rcanVersion}',
                      orElse: () => AppConstants.versionLabel,
                    );
                    return Text(label,
                        style: TextStyle(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                            fontSize: 11));
                  }),
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
