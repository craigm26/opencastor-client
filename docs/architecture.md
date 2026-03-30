# opencastor-client Architecture

> **App version audited:** v1.4.4 (pubspec.yaml)  
> **Audit date:** 2026-03-29  
> **Auditor:** Clawd (automated codebase review)

---

## Current State (v1.4.4)

### Screen Inventory

| Screen | Route | Data Sources | Has ViewModel? | Error State |
|--------|-------|-------------|----------------|-------------|
| FleetScreen | `/fleet` | Firestore (via `fleetProvider`) | ✅ fleet_view_model | `_ErrorView` (private) |
| ExploreScreen | `/explore` | GCS → CF fallback | ✅ explore_view_model | inline `Center(Text)` |
| ExploreDetailScreen | `/explore/:id` | CF `getConfig` | ✅ explore_view_model | inline |
| QrScannerScreen | `/explore/scan` | Camera | — | — |
| RobotDetailScreen | `/robot/:rrn` | Firestore (stream), CF (write) | ✅ robot_detail_view_model | inline |
| PhysicalControlScreen | `/robot/:rrn/control` | Firestore (stream + write via repo) | partial (control_view_model) | inline `Center(Text)` |
| RobotStatusScreen | `/robot/:rrn/status` | Firestore telemetry | — | inline |
| RobotCapabilitiesScreen | `/robot/:rrn/capabilities` | Firestore (via robotDetailProvider) | — | inline `Center(Text)` |
| ConformanceScreen | `/robot/:rrn/capabilities/conformance` | Firestore | — | inline `Center(Text)` |
| IdentityScreen | `/robot/:rrn/capabilities/identity` | Firestore | — | inline `Center(Text)` |
| SafetyScreen | `/robot/:rrn/capabilities/safety` | Firestore | — | inline `Center(Text)` |
| TransportScreen | `/robot/:rrn/capabilities/transport` | Firestore | — | inline `Center(Text)` |
| AiCapabilitiesScreen | `/robot/:rrn/capabilities/ai` | Firestore | — | inline `Center(Text)` |
| HardwareScreen | `/robot/:rrn/capabilities/hardware` | Firestore direct + WebSocket | — | inline |
| SoftwareScreen | `/robot/:rrn/capabilities/software` | Firestore, slash commands CF | — | inline |
| ProvidersScreen | `/robot/:rrn/capabilities/providers` | Firestore | — | inline |
| McpScreen | `/robot/:rrn/capabilities/mcp` | Firestore direct | — | inline `Center(Text)` |
| CapContributeScreen | `/robot/:rrn/capabilities/contribute` | Firestore **direct write** | — | inline |
| ConsentScreen | `/robot/:rrn/capabilities/consent` | Firestore + CF (via ConsentRepository) | — | inline |
| ComponentsScreen | `/robot/:rrn/capabilities/components` | Firestore **direct** stream | — | inline |
| ResearchScreen | `/robot/:rrn/research` | Firestore (via personalResearchProvider) | — | inline |
| ComplianceReportScreen | `/robot/:rrn/compliance-report` | Firestore | — | inline |
| OrchestratorScreen | `/robot/:rrn/orchestrators` | Firestore | — | inline |
| HarnessViewerPage | `/robot/:rrn/harness` | Firestore (via robotDetailProvider) | — | inline |
| HarnessEditorScreen | `/robot/:rrn/harness/edit` | Firestore **direct write** | — | inline |
| FleetLeaderboardScreen | `/fleet/leaderboard` | Firestore **direct** | — | inline `Center(Text)` |
| FleetContributeScreen | `/fleet/contribute` | Firestore **direct** | — | inline `Center(Text)` |
| ConsentScreen (top-level) | `/consent` | Firestore + CF (ConsentRepository) | — | inline |
| PendingConsentScreen | `/consent/pending` | Firestore (via ConsentRepository) | — | inline |
| AlertsScreen | `/alerts` | Firestore (via robotRepositoryProvider) | — | — |
| SettingsScreen | `/settings` | SharedPreferences (themeModeProvider) | — | — |
| AccountScreen | `/account` | FirebaseAuth | — | — |
| ProScreen | `/pro` | Firestore **direct** | — | inline |
| MissionListScreen | `/missions` | Firestore **direct** | — | inline |
| MissionScreen | `/missions/:id` | Firestore **direct** + CF | — | inline |
| SetupScreen | `/setup` | Firebase Auth (Google provider) | — | inline |

**Totals:**
- Screens: **33** screen files (+ 3 in-file screens: `_SplashScreen`, `_LoginScreen`, `_HarnessViewerPage` in `app.dart`)
- GoRoutes: **40** `GoRoute` entries + **1** `ShellRoute`
- Top-level (outside ShellRoute): 4 routes (`/`, `/splash`, `/login`, `/setup`)
- Under ShellRoute: 36 routes

---

### Data Flow Diagram (ASCII)

```
┌─────────────────────────────────────────────────────────────────┐
│                        Flutter UI Layer                          │
│                                                                  │
│  Screen ─► ViewModel/Provider ─► Repository ─► Firebase SDK     │
│                                                                  │
│  ✅ CLEAN (Fleet, RobotDetail, PhysicalControl, Explore,        │
│            Alerts, Consent, PendingConsent, Settings):           │
│                                                                  │
│  FleetScreen ──► fleetProvider ──► robotRepositoryProvider       │
│                                      └──► FirestoreRobotService  │
│                                             └──► Firestore SDK   │
│                                                                  │
│  ⚠️  BYPASSED (20 UI files, 62 call sites):                     │
│                                                                  │
│  MissionScreen ──► FirebaseFirestore.instance.collection()       │
│  HarnessEditor ──► FirebaseFirestore.instance.collection()       │
│  ContributeSettings ──► Firestore.collection('commands').add()   │
│  FleetLeaderboard ──► FirebaseFirestore.instance directly        │
│  ComponentsScreen ──► FirebaseFirestore.instance directly        │
│  HardwareProvider ──► FirebaseFirestore.instance directly        │
│  (+ 14 more files)                                               │
│                                                                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
    Cloud Firestore   Cloud Functions   GCS HTTP API
    (robot state,     (sendCommand,     (explore configs,
     telemetry,        consent,          CDN-cached,
     alerts)           searchConfigs)    fallback to CF)
          │
          ▼
    WebSocket (ws://<robot-local-ip>:8001/ws/telemetry)
    — wsTelemetryProvider — properly abstracted in service layer
```

---

### State Management Audit

**Total Riverpod providers: ~34** (across all files)

| Provider | Location | Type | Scope |
|----------|----------|------|-------|
| `robotRepositoryProvider` | `fleet_view_model.dart` | `Provider<RobotRepository>` | Global |
| `authStateProvider` | `fleet_view_model.dart` | `StreamProvider<User?>` | Global |
| `fleetProvider` | `fleet_view_model.dart` | `StreamProvider<List<Robot>>` | Global |
| `estopCommandProvider` | `fleet_view_model.dart` | `AutoDisposeNotifierProvider` | AutoDispose |
| `robotDetailProvider` | `robot_detail_view_model.dart` | `StreamProvider.family` | family |
| `commandsProvider` | `robot_detail_view_model.dart` | `StreamProvider.family` | family |
| `sendChatProvider` | `robot_detail_view_model.dart` | `AsyncNotifierProvider.autoDispose` | AutoDispose |
| `controlRobotProvider` | `control_view_model.dart` | `StreamProvider.family` | family (no autoDispose ⚠️) |
| `controlProvider` | `control_view_model.dart` | — (in-file) | — |
| `_myFleetProvider` | `consent_screen.dart` | `StreamProvider<List<Robot>>` | Screen-local ⚠️ DUPLICATE |
| `consentRepositoryProvider` | `consent_repository_provider.dart` | `Provider<ConsentRepository>` | Global |
| `themeModeProvider` | `theme_mode_provider.dart` | `NotifierProvider` | Global |
| `exploreFilterProvider` | `explore_view_model.dart` | `StateProvider` | Global |
| `exploreSearchProvider` | `explore_view_model.dart` | `StateProvider` | Global |
| `exploreConfigsProvider` | `explore_view_model.dart` | `FutureProvider.family` | family |
| `hubConfigDetailProvider` | `explore_view_model.dart` | `FutureProvider.family` | family |
| `starredConfigsProvider` | `explore_view_model.dart` | `StateProvider` | Global |
| `commentsProvider` | `social_view_model.dart` | `FutureProvider.family` | family |
| `myStarsProvider` | `social_view_model.dart` | `FutureProvider` | Global |
| `myConfigsProvider` | `social_view_model.dart` | `FutureProvider` | Global |
| `wsTelemetryProvider` | `ws_telemetry_service.dart` | `StreamProvider.family.autoDispose` | AutoDispose |
| `hardwareProfileProvider` | `harness/hardware_provider.dart` | `FutureProvider.family` | family (no autoDispose ⚠️) |
| `slashCommandsProvider` | `robot_detail/slash_command_provider.dart` | `FutureProvider.family` | family |
| `loaEnableCommandProvider` | `capabilities_widgets.dart` | `FutureProvider.family` | family |
| `contributeHistoryProvider` | `contribute_history_view.dart` | `FutureProvider.family` | family |
| `_componentsProvider` | `components_screen.dart` | `StreamProvider.family` | Screen-local ⚠️ |
| `_leaderboardProvider` | `fleet_leaderboard_screen.dart` | `FutureProvider.autoDispose` | Screen-local ⚠️ |
| `_researchStatusProvider` | `fleet_leaderboard_screen.dart` | `FutureProvider.autoDispose` | Screen-local ⚠️ |
| `personalResearchProvider` | `personal_research_card.dart` | `FutureProvider.autoDispose` | Screen-local ⚠️ |
| `personalResearchRrnProvider` | `personal_research_card.dart` | `StreamProvider.family.autoDispose` | family |
| `_userRrnProvider` | `personal_research_card.dart` | `FutureProvider.autoDispose` | Screen-local ⚠️ |
| `_fleetContributeProvider` | `fleet_contribute_screen.dart` | `FutureProvider` | Screen-local ⚠️ |
| `creditsProvider` | `fleet_contribute/credits_card.dart` | `FutureProvider.autoDispose` | — |
| `orchestratorsProvider` | `robot_detail/orchestrator_screen.dart` | `FutureProvider.family` | family |
| `_latestVersionProvider` | `robot_detail_screen.dart` | `FutureProvider` | Screen-local ⚠️ |

---

### Known Issues & Tech Debt

#### 🔴 Critical — Architecture Violations

1. **Direct Firestore calls bypassing repository layer** (20 UI files, 62 call sites)
   - `contribute_settings_view.dart` writes commands **directly** to Firestore `commands` subcollection — bypasses Cloud Functions, R2RAM enforcement, and rate limiting. This is a Protocol 66 compliance risk.
   - `mission_screen.dart` has 15+ raw Firestore/CF calls with no ViewModel or repository
   - `harness_editor.dart` writes harness configs directly to Firestore
   - `fleet_leaderboard_screen.dart`, `fleet_contribute_screen.dart`, `pro_screen.dart` read Firestore directly

2. **`robotRepositoryProvider` mislocated in `fleet_view_model.dart`**  
   It is the global DI binding but lives in a UI file. Imported by 10+ files via `show robotRepositoryProvider`. Should be in `data/repositories/`.

3. **`_myFleetProvider` in `consent_screen.dart` duplicates `fleetProvider`**  
   Creates a separate Firestore listener for the same data already available from `fleetProvider`. Wastes a connection slot.

#### 🟡 Medium — Inconsistency

4. **No MissionRepository**  
   `MissionScreen` and `MissionListScreen` call `FirebaseFirestore.instance` and `FirebaseFunctions.instance` directly with no abstraction, no ViewModel, no error state widget.

5. **Inconsistent error/loading/empty patterns**  
   `ErrorView` and `EmptyView` widgets exist in `ui/shared/` but are barely used. ~15 screens use `Center(child: Text('Error: $e'))` inline, which is inconsistent styling and loses the retry CTA.

6. **robot_capabilities screens lack ViewModels**  
   All 10+ capability sub-screens (`AiScreen`, `SafetyScreen`, `ConformanceScreen`, etc.) use `robotDetailProvider` directly but have no local ViewModel. Any capability-specific business logic lands inline in `build()`.

7. **Screen-local providers hard to test**  
   `_componentsProvider`, `_leaderboardProvider`, `_researchStatusProvider`, `_fleetContributeProvider`, `_latestVersionProvider` are defined inside screen files. Cannot be overridden in tests without importing the private screen file.

8. **Missing `autoDispose` on long-lived family providers**  
   `controlRobotProvider` and `hardwareProfileProvider` use `.family` without `.autoDispose`, meaning Riverpod holds them in memory even after the widget is gone.

#### 🟢 Low — Polish

9. **2 TODO comments** (fleet_leaderboard_screen.dart lines 683, 1117)  
   - `// TODO: navigate to full season standings`  
   - `// TODO: navigate to harness research detail`

10. **`withOpacity()` fully migrated** — 0 instances remaining. ✅

11. **GCS access not abstracted** — `explore_view_model.dart` calls `http.get(Uri.parse('$_kGcsBase/...'))` directly. Should go through an `ExploreRepository` for testability.

---

## Target Architecture (v2.0)

### Repository Pattern

```
lib/data/
├── repositories/
│   ├── robot_repository.dart          (abstract — already exists ✅)
│   ├── robot_repository_provider.dart (NEW — move from fleet_view_model.dart)
│   ├── consent_repository.dart        (abstract — already exists ✅)
│   ├── consent_repository_provider.dart (already exists ✅)
│   ├── mission_repository.dart        (NEW — abstract MissionRepository)
│   └── explore_repository.dart        (NEW — abstract ExploreRepository / GCS)
├── services/
│   ├── firestore_robot_service.dart   (already implements RobotRepository ✅)
│   ├── firestore_consent_service.dart (already implements ConsentRepository ✅)
│   ├── firestore_mission_service.dart (NEW — implements MissionRepository)
│   └── gcs_explore_service.dart       (NEW — implements ExploreRepository)
└── models/
    └── ... (already clean ✅)
```

**MissionRepository interface:**
```dart
abstract class MissionRepository {
  Stream<List<Mission>> watchMissions(String uid);
  Stream<Mission?> watchMission(String missionId);
  Future<String> createMission({required String name, ...});
  Future<void> addParticipant(String missionId, String rrn);
  Future<void> sendMissionCommand({required String missionId, ...});
}
```

**ExploreRepository interface:**
```dart
abstract class ExploreRepository {
  Future<List<HubConfig>> getConfigs({ExploreFilter filter});
  Future<HubConfig> getConfig(String id);
  Future<bool> toggleStar(String configId);
  Future<List<HubComment>> getComments(String configId);
  Future<void> addComment(String configId, String text);
}
```

**Contribution/system command** writes in `contribute_settings_view.dart` must be routed through `RobotRepository.sendCommand()` (Cloud Functions) — never directly to Firestore. Add a `CommandScope.system` path to `sendCommand` if needed.

---

### Provider Consolidation

Move these out of screen files into dedicated provider/viewmodel files:

| Current location | New location |
|------------------|-------------|
| `fleet_view_model.dart::robotRepositoryProvider` | `data/repositories/robot_repository_provider.dart` |
| `consent_screen.dart::_myFleetProvider` | DELETE — use `fleetProvider` from fleet_view_model.dart |
| `components_screen.dart::_componentsProvider` | `robot_capabilities/components_view_model.dart` |
| `fleet_leaderboard_screen.dart::_leaderboardProvider` | `fleet_leaderboard/leaderboard_view_model.dart` |
| `fleet_leaderboard_screen.dart::_researchStatusProvider` | `fleet_leaderboard/leaderboard_view_model.dart` |
| `fleet_contribute_screen.dart::_fleetContributeProvider` | `fleet/fleet_contribute_view_model.dart` |
| `robot_detail_screen.dart::_latestVersionProvider` | `robot_detail/robot_detail_view_model.dart` |
| `personal_research_card.dart::_userRrnProvider` | `fleet_leaderboard/leaderboard_view_model.dart` |

Add `.autoDispose` to:
- `controlRobotProvider`
- `hardwareProfileProvider`

---

### Shell Route for Bottom Nav

The current `_AppShell` manually computes `selectedIndex` via string matching. A proper GoRouter `ShellRoute` with nested child routes is cleaner and removes fragile string checks.

```dart
// Target structure in app.dart
ShellRoute(
  navigatorKey: _shellNavigatorKey,
  builder: (ctx, state, child) => AppShell(child: child),
  routes: [
    // Tab 0: Fleet
    GoRoute(path: '/fleet', builder: ...),
    GoRoute(path: '/robot/:rrn', builder: ...),
    // ... all robot sub-routes

    // Tab 1: Explore
    GoRoute(path: '/explore', builder: ...),

    // Tab 2: Compete / Leaderboard
    GoRoute(path: '/fleet/leaderboard', builder: ...),

    // Tab 3: Alerts
    GoRoute(path: '/alerts', builder: ...),

    // Tab 4: Settings
    GoRoute(path: '/settings', builder: ...),
    GoRoute(path: '/account', builder: ...),
  ],
),
```

The `AppShell` would derive `selectedIndex` from `GoRouterState` without the brittle `startsWith` chain.

---

### Standardised Error / Loading / Empty Widgets

Shared widgets already exist at `lib/ui/shared/`:
- `ErrorView(error, onRetry, title)` ✅
- `EmptyView(icon, title, subtitle, ctaLabel, onCta)` ✅
- `RobotCardSkeleton` / `CommandTileSkeleton` ✅

**Target usage pattern** (currently only `FleetScreen` uses these consistently):

```dart
// Every screen's AsyncValue.when() should follow this template:
asyncValue.when(
  loading: () => const Center(child: CircularProgressIndicator()),
  error: (e, _) => ErrorView(error: e.toString(), onRetry: () => ref.invalidate(provider)),
  data: (value) => value.isEmpty
      ? EmptyView(icon: Icons.inbox_outlined, title: 'No items yet')
      : _buildContent(value),
);
```

The ~15 screens using `Center(child: Text('Error: $e'))` must be updated to use `ErrorView`.

---

### Data Source Summary (v2.0)

| Source | Access pattern | Abstraction |
|--------|----------------|-------------|
| Cloud Firestore | Read-only streams (robot state, telemetry) | `RobotRepository`, `MissionRepository` |
| Cloud Functions | All writes (commands, consent, missions) | `RobotRepository.sendCommand()`, `ConsentRepository`, `MissionRepository` |
| GCS / CDN | Explore config index + JSON blobs | `ExploreRepository` |
| WebSocket | Local-network live telemetry | `wsTelemetryProvider` (already clean ✅) |
| Firebase Auth | Sign-in state | `authStateProvider` (already clean ✅) |

---

## Migration Plan

### Phase 1 — Repository Abstraction (no UI changes)

**Goal:** All Firestore/CF calls go through a repository. Zero UI changes.

1. Create `data/repositories/robot_repository_provider.dart`  
   Move `robotRepositoryProvider` out of `fleet_view_model.dart`.  
   Update all 10 import sites.

2. Create `MissionRepository` (abstract) + `FirestoreMissionService` (impl).  
   Wire `missionRepositoryProvider`.  
   Replace all raw Firestore/CF calls in `mission_screen.dart` and `mission_list_screen.dart`.

3. Create `ExploreRepository` (abstract) + `GcsExploreService` (impl).  
   Move GCS `http.get` calls from `explore_view_model.dart`.

4. Route `contribute_settings_view.dart` command writes through `RobotRepository.sendCommand()`.  
   This is the highest-priority fix — direct `commands.add({})` bypasses R2RAM.

5. Move `hardwareProfileProvider` into `RobotRepository`  
   Add `Future<Map<String, dynamic>> getHardwareProfile(String rrn)` to the interface.  
   Implement in `FirestoreRobotService`.

6. Add `Stream<List<Map<String, dynamic>>> watchComponents(String rrn)` to `RobotRepository`.  
   Remove `_componentsProvider` direct Firestore call.

**Acceptance:** `grep -r "FirebaseFirestore.instance" lib/ui/` returns 0 results.

---

### Phase 2 — Shell Route + Bottom Nav

**Goal:** Clean up navigation, remove brittle string matching.

1. Extract `AppShell` to `lib/ui/shared/app_shell.dart` (already close — just move out of app.dart).
2. Refactor `_AppShell.selectedIndex` to use `GoRouterState` path extension rather than manual `startsWith` chain.
3. (Optional) Add `/missions` as a 5th nav tab if product wants it.
4. Remove dead route `/missions/new` redirect (it's a no-op redirect to `/missions`).

---

### Phase 3 — Provider Consolidation

**Goal:** All providers in dedicated ViewModel files; all screens testable in isolation.

1. Delete `_myFleetProvider` in `consent_screen.dart` — use `fleetProvider`.
2. Create `fleet_leaderboard/leaderboard_view_model.dart` with `leaderboardProvider`, `researchStatusProvider`, `userRrnProvider`.
3. Create `fleet/fleet_contribute_view_model.dart` with `fleetContributeProvider`.
4. Create `robot_capabilities/components_view_model.dart` with `componentsProvider`.
5. Move `_latestVersionProvider` to `robot_detail_view_model.dart`.
6. Add `.autoDispose` to `controlRobotProvider` and `hardwareProfileProvider`.
7. Apply `ErrorView` / `EmptyView` consistently across all 15+ affected screens.
8. Fix 2 TODO comments in `fleet_leaderboard_screen.dart`.

---

### Sub-Issues to File

1. **[refactor] Move robotRepositoryProvider to data layer + add MissionRepository** — Phase 1 items 1–2
2. **[refactor] Route contribute_settings_view.dart writes through RobotRepository (Protocol 66 compliance)** — Phase 1 item 4
3. **[refactor] Shell route cleanup + remove brittle selectedIndex string matching** — Phase 2
4. **[refactor] Standardise ErrorView / EmptyView across all screens** — Phase 3 item 7
5. **[refactor] Consolidate screen-local providers into ViewModel files** — Phase 3 items 2–6
