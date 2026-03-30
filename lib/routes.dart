/// Route path constants and helpers for the OpenCastor app.
///
/// Centralising paths here prevents brittle string duplication across
/// the codebase and makes refactoring safe and easy.
///
/// **Usage — static paths:**
/// ```dart
/// context.go(AppRoutes.fleet);
/// ```
///
/// **Usage — dynamic paths (substitute parameter):**
/// ```dart
/// context.push(AppRoutes.robot(rrn));
/// context.push(AppRoutes.mission(id));
/// ```
///
/// **Usage — tab index resolution (replaces hand-rolled startsWith chains):**
/// ```dart
/// final index = AppRoutes.selectedIndexFor(location);
/// context.go(AppRoutes.tabRouteFor(index));
/// ```
library;

abstract final class AppRoutes {
  // ── Top-level ────────────────────────────────────────────────────────────
  static const splash = '/splash';
  static const login = '/login';
  static const setup = '/setup';

  // ── Main shell tabs ──────────────────────────────────────────────────────
  static const fleet = '/fleet';
  static const explore = '/explore';
  static const alerts = '/alerts';
  static const settings = '/settings';
  static const account = '/account';
  static const pro = '/pro';

  // ── Fleet sub-routes ─────────────────────────────────────────────────────
  static const fleetLeaderboard = '/fleet/leaderboard';

  // ── Explore sub-routes ───────────────────────────────────────────────────
  static const exploreScan = '/explore/scan';

  /// `/explore/:id` — resolved path.
  static String exploreDetail(String id) => '/explore/$id';

  // ── Robot route templates (GoRoute path strings) ─────────────────────────
  static const robotDetail = '/robot/:rrn';
  static const robotControl = '/robot/:rrn/control';
  static const robotStatus = '/robot/:rrn/status';
  static const robotCapabilities = '/robot/:rrn/capabilities';
  static const robotCapabilitiesConformance =
      '/robot/:rrn/capabilities/conformance';
  static const robotCapabilitiesIdentity = '/robot/:rrn/capabilities/identity';
  static const robotCapabilitiesSafety = '/robot/:rrn/capabilities/safety';
  static const robotCapabilitiesTransport =
      '/robot/:rrn/capabilities/transport';
  static const robotCapabilitiesAi = '/robot/:rrn/capabilities/ai';
  static const robotCapabilitiesHardware = '/robot/:rrn/capabilities/hardware';
  static const robotCapabilitiesSoftware = '/robot/:rrn/capabilities/software';
  static const robotCapabilitiesProviders =
      '/robot/:rrn/capabilities/providers';
  static const robotCapabilitiesMcp = '/robot/:rrn/capabilities/mcp';
  static const robotCapabilitiesContribute =
      '/robot/:rrn/capabilities/contribute';
  static const robotCapabilitiesConsent = '/robot/:rrn/capabilities/consent';
  static const robotCapabilitiesComponents =
      '/robot/:rrn/capabilities/components';
  static const robotComplianceReport = '/robot/:rrn/compliance-report';
  static const robotAttestation = '/robot/:rrn/attestation';
  static const robotResearch = '/robot/:rrn/research';
  static const robotOrchestrators = '/robot/:rrn/orchestrators';
  static const robotHarness = '/robot/:rrn/harness';
  static const robotHarnessEdit = '/robot/:rrn/harness/edit';

  // ── Robot route helpers (substitute :rrn) ────────────────────────────────
  static String robot(String rrn) => '/robot/$rrn';
  static String robotControlFor(String rrn) => '/robot/$rrn/control';
  static String robotStatusFor(String rrn) => '/robot/$rrn/status';
  static String robotCapabilitiesFor(String rrn) => '/robot/$rrn/capabilities';
  static String robotCapabilitiesSection(String rrn, String section) =>
      '/robot/$rrn/capabilities/$section';
  static String robotComplianceReportFor(String rrn) =>
      '/robot/$rrn/compliance-report';
  static String robotResearchFor(String rrn) => '/robot/$rrn/research';
  static String robotOrchestratorsFor(String rrn) =>
      '/robot/$rrn/orchestrators';
  static String robotHarnessFor(String rrn) => '/robot/$rrn/harness';
  static String robotHarnessEditFor(String rrn) => '/robot/$rrn/harness/edit';

  // ── Consent ──────────────────────────────────────────────────────────────
  static const consent = '/consent';
  static const consentPending = '/consent/pending';

  // ── Missions ─────────────────────────────────────────────────────────────
  static const missions = '/missions';
  static const missionsNew = '/missions/new';
  static const missionDetail = '/missions/:id';

  /// `/missions/:id` — resolved path.
  static String mission(String id) => '/missions/$id';

  // ── Navigation tab helpers ───────────────────────────────────────────────

  /// Number of top-level shell tabs.
  static const int tabCount = 5;

  /// Tab destinations in order:
  ///   0 → Fleet, 1 → Explore, 2 → Compete (leaderboard),
  ///   3 → Alerts, 4 → Settings
  static const List<String> _tabRoots = [
    fleet,         // 0
    explore,       // 1
    fleetLeaderboard, // 2  (no dedicated /compete route yet)
    alerts,        // 3
    settings,      // 4
  ];

  /// Returns the initial route for a given tab [index].
  /// Falls back to [fleet] for out-of-range values.
  static String tabRouteFor(int index) =>
      (index >= 0 && index < _tabRoots.length) ? _tabRoots[index] : fleet;

  /// Returns the bottom-nav / rail selected index for a matched [location].
  ///
  /// Replaces the previous hand-rolled `startsWith` chain in `_AppShell`,
  /// which was order-sensitive and duplicated literal strings.
  /// Defaults to 0 (Fleet) for unknown or sub-routes under /robot.
  static int selectedIndexFor(String location) {
    // Compete tab: must be checked before fleet because /fleet/leaderboard
    // is a prefix-match of /fleet.
    if (location.startsWith(fleetLeaderboard) ||
        location.startsWith('/compete')) {
      return 2;
    }
    if (location.startsWith(fleet) || location.startsWith('/robot')) return 0;
    if (location.startsWith(explore)) return 1;
    if (location.startsWith(alerts)) return 3;
    if (location.startsWith(settings)) return 4;
    return 0;
  }
}
