# CLAUDE.md — opencastor-client

Flutter web app for remote fleet management of OpenCastor robots.
Deployed at **[app.opencastor.com](https://app.opencastor.com)** via Cloudflare Pages.

---

## Ecosystem Repositories

| Repo | Description | Branch |
|------|-------------|--------|
| [craigm26/OpenCastor](https://github.com/craigm26/OpenCastor) | Robot runtime (Python). `castor` CLI, Protocol 66 safety layer, RCAN router, `castor bridge` daemon. | `main` |
| [craigm26/opencastor-client](https://github.com/craigm26/opencastor-client) | **This repo.** Flutter web fleet management app. | `master` |
| [craigm26/opencastor-ops](https://github.com/craigm26/opencastor-ops) | Private. Business, legal, compliance, infrastructure docs. | `main` |
| [continuonai/rcan-spec](https://github.com/continuonai/rcan-spec) | RCAN protocol specification (v1.4). Astro site at rcan.dev. | `master` |
| [continuonai/rcan-py](https://github.com/continuonai/rcan-py) | Python RCAN SDK (v0.4.2). `pip install rcan`. | `main` |
| [continuonai/rcan-ts](https://github.com/continuonai/rcan-ts) | TypeScript RCAN SDK (v0.4.1). `npm install @continuonai/rcan`. | `master` |
| [continuonai/RobotRegistryFoundation](https://github.com/continuonai/RobotRegistryFoundation) | Robot Registry Foundation — canonical RRN records. | `main` |
| [craigm26/personalsite](https://github.com/craigm26/personalsite) | craigmerry.com — Astro + Cloudflare Pages. | `main` |

---

## Architecture

Following [Flutter Architecture Recommendations](https://docs.flutter.dev/app-architecture/recommendations):

```
lib/
├── main.dart                          Entry point — Firebase init, redirect auth
├── app.dart                           Router + MaterialApp (no business logic)
├── firebase_options.dart              Placeholder — real values injected by CI
│
├── data/                              DATA LAYER
│   ├── models/                        Immutable Firestore data models
│   │   ├── robot.dart                 Robot, RobotStatus, RobotCapability
│   │   ├── command.dart               RobotCommand, CommandScope
│   │   └── consent_request.dart       ConsentRequest
│   ├── repositories/                  Abstract contracts (test against these)
│   │   ├── robot_repository.dart      RobotRepository (abstract)
│   │   └── consent_repository.dart    ConsentRepository (abstract)
│   └── services/                      Concrete Firebase implementations
│       ├── auth_service.dart          Google sign-in, sign-out, redirect handling
│       ├── firestore_robot_service.dart   RobotRepository → Firestore + CF
│       ├── firestore_consent_service.dart ConsentRepository → Firestore + CF
│       └── notification_service.dart  FCM push token + foreground routing
│
└── ui/                                UI LAYER
    ├── core/
    │   ├── theme/app_theme.dart       Brand palette, Material 3 theme
    │   └── widgets/                   Shared dumb widgets
    │       ├── capability_badge.dart
    │       ├── confirmation_dialog.dart
    │       └── health_indicator.dart
    ├── fleet/
    │   ├── fleet_view_model.dart      Riverpod providers + robotRepositoryProvider
    │   ├── fleet_screen.dart          View only — no business logic
    │   └── robot_card.dart
    ├── robot_detail/
    │   ├── robot_detail_view_model.dart
    │   └── robot_detail_screen.dart
    ├── control/
    │   ├── control_view_model.dart    ControlViewModel (AutoDisposeNotifier)
    │   └── control_screen.dart
    ├── account/
    │   └── account_screen.dart
    ├── consent/
    │   └── consent_screen.dart
    └── alerts/
        └── alerts_screen.dart
```

### Key Architecture Rules

- **Screens are views only.** No repository calls, no `ref.read(repo)` in build(). Logic goes in ViewModels.
- **Depend on abstract repositories**, never on `FirestoreRobotService` directly. Use `ref.read(robotRepositoryProvider)`.
- **AuthService is the single source of auth.** `AuthService.currentUser`, `AuthService.signInWithGoogle()`, etc.
- **`fleetProvider` watches `authStateProvider`** — auto-rebuilds on sign-in/out. Never capture uid once at build.
- **Unidirectional data flow**: Firestore → ViewModel → Screen. User events → ViewModel method → Firestore.

---

## State Management

Riverpod (`flutter_riverpod ^2.5.1`). Provider hierarchy:

```
ProviderScope (main.dart)
├── authStateProvider          StreamProvider<User?>  — auth state
├── robotRepositoryProvider    Provider<RobotRepository>  — DI binding
├── fleetProvider              StreamProvider<List<Robot>>  — watches auth
├── robotDetailProvider        StreamProvider.family<Robot?, String>
├── commandsProvider           StreamProvider.family<List<RobotCommand>, String>
├── sendChatProvider           AsyncNotifierProvider.autoDispose
└── controlProvider            AutoDisposeNotifierProvider<ControlViewModel, ControlState>
```

---

## Safety Invariants (Protocol 66)

**These must never be removed or weakened:**

1. **ESTOP never rate-limited** — `CommandScope.safety` bypasses all rate limiting in Cloud Functions `relay.ts`
2. **Confirmation modal required** for every `CommandScope.control` command — enforced in `ControlViewModel.execute()` by requiring the screen to show the dialog BEFORE calling execute
3. **Protocol 66 runs locally on the robot** — `castor bridge` enforces safety regardless of what the cloud sends
4. **R2RAM consent required** for cross-robot access (robot-to-robot commands) — enforced in Cloud Functions `consent.ts`

---

## Firebase Architecture

```
GCP Project: opencastor (360358330839)
Firebase Project: opencastor
Region: nam5

Firestore (default):
  /robots/{rrn}                   Robot registration + live telemetry
  /robots/{rrn}/commands/{cmdId}  Command queue + results
  /robots/{rrn}/alerts/{id}       Safety alerts
  /robots/{rrn}/consent_requests  R2RAM inbound requests
  /robots/{rrn}/consent_peers     Approved robot peers

Cloud Functions (TypeScript):
  sendCommand      — validates R2RAM scope, rate-limits, relays to robot
  resolveConsent   — approve/deny R2RAM consent requests
  requestConsent   — initiate R2RAM access request
  revokeConsent    — revoke peer consent
  registerFcmToken — register push notification token

Auth: Google Sign-In (signInWithRedirect on web, GoogleSignIn on native)
```

**Credential handling:**
- Real `firebase_options.dart` and `google-services.json` stored ONLY as GitHub Secrets
- Placeholder values committed to repo (`REPLACE_WITH_*`)
- CI injects real values before build via `FIREBASE_OPTIONS_DART` and `GOOGLE_SERVICES_JSON` secrets

---

## Development

```bash
# Install deps
flutter pub get

# Run web (with Firebase emulator)
flutter run -d chrome --web-renderer html

# Build web
flutter build web --web-renderer html --release

# Analyze
flutter analyze

# Test
flutter test
```

**Web renderer:** `html` (not `canvaskit`). ~1.5MB vs ~6MB — significantly faster TTI.

---

## CI/CD

GitHub Actions → Cloudflare Pages:

- **Build:** `.github/workflows/build.yml` — `flutter analyze`, `flutter test`, build APK + web
- **Deploy:** `.github/workflows/deploy-web.yml` — build web, deploy to CF Pages
- Credentials injected from GitHub Secrets before build
- Cloudflare Pages project: `opencastor-client` (ID: `50996926-8d05-410f-a2a4-9240d8f46e09`)

---

## Robot Connection Architecture

Robots connect **outbound-only** to Firestore — no public ports:

```
Robot (castor bridge) ──outbound──▶ Firestore ◀── Flutter app
                                         │
                                    Cloud Functions
                                    (sendCommand, consent)
```

- Robot API token never reaches the Flutter app (only in Cloud Functions env vars)
- Robot RRN: `RRN-000000000001` (Bob), `RRN-000000000005` (Alex)
- Robot URIs: `rcan://craigm26.opencastor-rpi5-hailo.bob-001` (Bob), `rcan://craigm26.opencastor-rpi5-ackermann.alex-001` (Alex)

---

## RCAN Protocol

This client implements the consumer side of [RCAN v1.4](https://rcan.dev):

- **RRN** (Robot Resource Name): `RRN-000000000001` format — unique robot identifier
- **RURI** (Robot URI): `rcan://[org].[model].[instance]` — routing address
- **R2RAM** (Robot-to-Robot Access Management): consent model for cross-robot commands
  - Scopes: `discover(0) < status(1) < chat(2) < control(3) < safety(99)`
  - Higher scope satisfies lower (control implies chat)
  - ESTOP: any authenticated owner can send regardless of scope
- **Message types**: 20 types including CONSENT_REQUEST (20), CONSENT_GRANT (21), CONSENT_DENY (22)

---

## Android / iOS

- Android package: `com.craigm26.opencastor_client`
- iOS bundle: `com.craigm26.opencastorClient`
- iOS Firebase: placeholder — needs `flutterfire configure --platforms=ios` on macOS

---

## Business Model

Apache 2.0 open source + managed SaaS at `app.opencastor.com`.
Details in [opencastor-ops](https://github.com/craigm26/opencastor-ops) (private).
EU AI Act compliance deadline: August 2, 2026.
