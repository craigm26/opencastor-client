# opencastor-client Compliance UI Design

**Date:** 2026-04-12
**Repo:** craigm26/opencastor-client
**Status:** Approved — pending implementation plan

---

## Goal

Add RCAN v3.0 compliance UI to the Flutter web app: a new `ui/compliance/` feature with six screens (hub + five sub-screens), a `ComplianceRepository` backed by the rcan.dev API, and targeted updates to the existing `ComplianceReportScreen`, `ConformanceScreen`, and version strings.

---

## Architecture

Option B: new `ComplianceRepository` + isolated feature folder. Follows the existing MVVM pattern (Views → ViewModels → Repositories → Services). The rcan.dev API is isolated in a single `RcanComplianceService`; Firestore-based data (conformance scores, robot telemetry) is untouched.

Data sources:
- **rcan.dev API** → `RcanComplianceService` → `ComplianceRepository` → Riverpod providers → new compliance screens + updated existing screens
- **Firestore** → existing providers (unchanged — still powers conformance scores and robot fields)

---

## Section 1: Data Layer

### `lib/data/models/compliance.dart`

Plain immutable Dart classes. No codegen. Field names use camelCase (Dart convention); JSON parsing maps from snake_case wire format.

```dart
class ComplianceStatus {
  final String rrn;
  final String complianceStatus; // "compliant"|"provisional"|"non_compliant"|"no_fria"
  final String? friaSubmittedAt; // ISO-8601 or null
  final bool sigVerified;
  final bool overallPass;
  final bool prerequisiteWaived;
}

class FriaConformance {
  final double score;      // 0.0–1.0
  final int passCount;
  final int warnCount;
  final int failCount;
}

class FriaDocument {
  final String schema;        // "rcan-fria-v1"
  final String generatedAt;   // ISO-8601
  final Map<String, dynamic> system;      // { rrn, robot_name, rcan_version }
  final Map<String, dynamic> deployment;  // { annex_iii_basis, prerequisite_waived }
  final Map<String, dynamic> signingKey;  // { alg, kid, public_key }
  final Map<String, dynamic> sig;         // { alg, kid, value }
  final FriaConformance? conformance;     // null if not yet computed
}

class SafetyBenchmark {
  final String protocol;  // e.g. "rcan-sbp-v1"
  final double score;
  final int passCount;
  final int failCount;
  final String runAt;  // ISO-8601
  final String rrn;
}

class InstructionsForUse {
  final String rrn;
  final String robotName;
  final String intendedUse;
  final String operatingEnvironment;
  final List<String> contraindications;
  final String version;
  final String issuedAt;  // ISO-8601
}

class PostMarketIncident {
  final String rrn;
  final String incidentId;
  final String severity;    // "low"|"medium"|"high"|"critical"
  final String description;
  final String occurredAt;  // ISO-8601
  final String reportedAt;  // ISO-8601
  final String status;      // "open"|"under_review"|"resolved"
}

class EuRegisterEntry {
  final String rrn;
  final String robotName;
  final String manufacturer;
  final String annexIiiBasis;
  final String? friaSubmittedAt;
  final String complianceStatus;
  final String registeredAt;
}
```

### `lib/data/repositories/compliance_repository.dart`

Abstract interface. ViewModels depend on this, not on `RcanComplianceService`.

```dart
abstract class ComplianceRepository {
  Future<ComplianceStatus> getComplianceStatus(String rrn);
  Future<FriaDocument?> getFriaDocument(String rrn);
}
```

`getFriaDocument` returns `null` when rcan.dev returns 404 (no FRIA submitted yet).

### `lib/data/services/rcan_compliance_service.dart`

Implements `ComplianceRepository`. Uses the `http` package (already a dependency). Base URL: `https://rcan.dev/api/v1`.

Endpoints called:
- `GET /robots/:rrn/compliance` → `ComplianceStatus`
- `GET /robots/:rrn/fria` → `FriaDocument?` (null on 404)

Throws `Exception` on non-200/404 responses. No caching — Riverpod's `FutureProvider` handles re-fetch on invalidation.

---

## Section 2: UI Layer — New Screens

### `lib/data/repositories/compliance_repository_provider.dart`

Riverpod DI binding (separate file to avoid circular imports):

```dart
final complianceRepositoryProvider = Provider<ComplianceRepository>(
  (ref) => RcanComplianceService(),
);
```

### `lib/ui/compliance/compliance_view_model.dart`

```dart
final complianceStatusProvider = FutureProvider.family<ComplianceStatus, String>(
  (ref, rrn) => ref.read(complianceRepositoryProvider).getComplianceStatus(rrn),
);

final friaProvider = FutureProvider.family<FriaDocument?, String>(
  (ref, rrn) => ref.read(complianceRepositoryProvider).getFriaDocument(rrn),
);
```

### New Screens

All screens are read-only viewers. They watch their provider, show a `CircularProgressIndicator` while loading, and an error card on failure.

| File | Route | Data |
|------|-------|------|
| `compliance_hub_screen.dart` | `/robot/:rrn/compliance` | `complianceStatusProvider` |
| `fria_screen.dart` | `/robot/:rrn/compliance/fria` | `friaProvider` |
| `safety_benchmark_screen.dart` | `/robot/:rrn/compliance/benchmark` | `friaProvider` (conformance sub-object) |
| `ifu_screen.dart` | `/robot/:rrn/compliance/ifu` | placeholder — "Not yet available" card |
| `incidents_screen.dart` | `/robot/:rrn/compliance/incidents` | placeholder — "Not yet available" card |
| `eu_register_screen.dart` | `/robot/:rrn/compliance/eu-register` | placeholder — "Not yet available" card |

**ComplianceHubScreen** — shows:
- Compliance status chip (`compliant` → green, `provisional` → amber, `non_compliant` → red, `no_fria` → grey)
- FRIA submitted date (or "Not submitted")
- Six `ListTile` cards navigating to each sub-screen

**FriaScreen** — shows:
- Schema, generated_at, system fields (rrn, rcan_version)
- Deployment fields (annex_iii_basis, prerequisite_waived)
- Signing key alg + kid
- Conformance score bar + pass/warn/fail counts (or "Not computed" if null)

**SafetyBenchmarkScreen** — uses `friaProvider`'s `conformance` field:
- Protocol identifier
- Score progress bar
- Pass / Warn / Fail count chips
- Run timestamp

**IFU, Incidents, EuRegister screens** — styled "Not yet available" card with explanatory text. Routes exist so navigation works; content fills in when API endpoints are added.

---

## Section 3: Existing Screen Updates

### `lib/core/constants.dart`

```dart
// Before
static const String rcanVersion = 'v2.2.1';

// After
static const String rcanVersion = 'v3.0';
```

### `lib/data/models/robot.dart`

Add version predicate alongside existing ones:

```dart
bool get isRcanV30 {
  final parts = (rcanVersion ?? '').split('.');
  final major = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  return major >= 3;
}
```

### `lib/ui/robot_detail/compliance_report_screen.dart`

- Watch `complianceStatusProvider(rrn)` in addition to existing Firestore data
- Replace the hardcoded `isRcanV21` RCAN conformance check with live `complianceStatus.complianceStatus` from the API
- Add a "View Full Compliance →" `ListTile` at the bottom linking to `/robot/:rrn/compliance`
- Show `complianceStatus.friaSubmittedAt` in the FRIA row (was previously absent)

### `lib/ui/robot_capabilities/conformance_screen.dart`

- Watch `friaProvider(rrn)` 
- Insert a "FRIA Conformance" card above the existing L4/L5 supply chain section showing `conformance.score`, `passCount`, `warnCount`, `failCount`
- Show loading shimmer while `friaProvider` is loading
- Show "No FRIA submitted" empty state if `friaProvider` returns null

### `lib/routes.dart`

Add 6 new routes as children of the existing `/robot/:rrn` `ShellRoute`:

```dart
GoRoute(path: 'compliance', builder: (_, state) => ComplianceHubScreen(rrn: state.pathParameters['rrn']!),
  routes: [
    GoRoute(path: 'fria',       builder: (_, state) => FriaScreen(rrn: ...)),
    GoRoute(path: 'benchmark',  builder: (_, state) => SafetyBenchmarkScreen(rrn: ...)),
    GoRoute(path: 'ifu',        builder: (_, state) => IfuScreen(rrn: ...)),
    GoRoute(path: 'incidents',  builder: (_, state) => IncidentsScreen(rrn: ...)),
    GoRoute(path: 'eu-register',builder: (_, state) => EuRegisterScreen(rrn: ...)),
  ],
),
```

---

## Out of Scope

- POST /fria submission UI (no form to upload FRIA documents)
- SafetyBenchmark, IFU, PostMarketIncident, EuRegister API endpoints (not yet built on rcan.dev)
- Native Android/iOS — web only (existing app constraint)
- Authentication for rcan.dev API calls (public read endpoints, no auth required)
