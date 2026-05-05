# OpenCastor Fleet UI

Web dashboard for managing your OpenCastor robot fleet — real-time monitoring, control, ESTOP, and consent management from any browser.

[![Live](https://img.shields.io/badge/live-app.opencastor.com-orange)](https://app.opencastor.com)
[![RCAN](https://img.shields.io/badge/RCAN-protocol-blue)](https://rcan.dev/compatibility)
[![License](https://img.shields.io/badge/license-Apache%202.0-green)](LICENSE)

**Live at [app.opencastor.com](https://app.opencastor.com)**

## What It Does

- **Fleet overview** — real-time status cards for all your robots; one-tap ESTOP on every screen
- **Robot detail** — telemetry, command history, [RCAN protocol](https://rcan.dev/compatibility) capability badges (transport, LoA, federation)
- **Chat control** — send instructions in natural language via the chat interface
- **Control panel** — arm teleop with confirmation modal + persistent ESTOP button
- **Consent management** — approve/deny R2RAM access requests; view and revoke established peer consent
- **Revocation display** — badges show when a robot's RCAN identity is revoked
- **LoA display** — shows operator Level of Assurance on each control command
- **Multi-modal stub** — media attachment UI for [RCAN protocol](https://rcan.dev/compatibility) multi-modal payloads

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Flutter Web |
| Auth | Firebase Auth (Google sign-in) |
| Real-time state | Firestore |
| Push alerts | Firebase Cloud Messaging (FCM) |
| Backend relay | Cloud Functions (TypeScript, `relay.ts`) |
| Hosting | Cloudflare Pages |

## Architecture

```
Flutter Web app (browser)
  │  Firebase Auth — Google sign-in, UID-based access control
  │  Firestore — robot state, command queue, consent records, audit log
  │  FCM — push alerts (ESTOP, faults, consent requests)
  ▼
Cloud Functions (relay.ts)
  │  R2RAM scope enforcement + rate limiting
  │  Commands queued; robots poll via outbound Firestore connection
  ▼
castor bridge (on each robot)
  │  Outbound-only Firestore connection — no open ports on robot
  ▼
castor gateway (local REST API, port 8000)
  │  Protocol 66 safety layer — same gates as local commands
  ▼
Robot hardware
```

Robot API tokens are stored in Cloud Functions environment variables — never in the Flutter app or Firestore. See internal ops docs for credential management.

## Developer Setup

### Prerequisites

- Flutter 3.22+
- Firebase project with Firestore, Auth (Google), Functions, and Messaging enabled
- Node.js 18+ (for Cloud Functions)
- OpenCastor ≥ 2026.3.17.1 on each robot

### 1. Configure Firebase

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure for your Firebase project (generates lib/firebase_options.dart)
flutterfire configure --project=<your-project-id>
```

`lib/firebase_options.dart` is gitignored — do **not** commit it.

### 2. Deploy Cloud Functions

```bash
cd functions
npm install
firebase deploy --only functions
firebase deploy --only firestore:rules,firestore:indexes
```

### 3. Run the Flutter app

```bash
flutter pub get
flutter run -d chrome     # web
flutter run               # or any connected device
```

### 4. Connect a robot

On each robot:

```bash
pip install opencastor[cloud]==2026.3.17.1
castor bridge --config bob.rcan.yaml
```

The bridge connects outbound to Firestore. Your robot appears in the fleet dashboard within 30 seconds.

## RCAN Protocol Features

| Feature | UI Location |
|---|---|
| Consent screens | Access tab — approve/deny per-scope R2RAM requests |
| Revocation badges | Robot detail — red badge if RRN is revoked |
| LoA display | Command history — operator LoA shown per command |
| Transport badges | Robot detail — HTTP / Compact / Minimal transport indicators |
| Multi-modal stub | Chat — attach media for [RCAN protocol](https://rcan.dev/compatibility) multi-modal payloads |

## Deployment

Deployed via Cloudflare Pages CI on push to `master`. Build command: `flutter build web`. Output: `build/web/`.

For self-hosting, point any static host at the `build/web/` directory after `flutter build web --release`.

## Security Notes

- Robot API tokens: stored in Cloud Functions env vars, never in the app
- Firestore rules: owner-only access; cross-owner writes go through Cloud Function relay
- Control-scope commands: require explicit confirmation dialog in UI
- Rate limiting: 60/min for chat/status, 10/min for control, unlimited for ESTOP
- All commands: audited in Firestore with Firebase UID + timestamp

## Ecosystem

| Project | Version | Purpose |
|---|---|---|
| **Fleet UI** (this) | live | Web fleet dashboard |
| [OpenCastor](https://github.com/craigm26/OpenCastor) | v2026.3.17.1 | Robot runtime |
| [RCAN Protocol](https://rcan.dev/spec/) | v1.6.0 | Open robot communication standard |
| [rcan-py](https://github.com/continuonai/rcan-py) | v0.6.0 | Python RCAN SDK |
| [rcan-ts](https://github.com/continuonai/rcan-ts) | v0.6.0 | TypeScript RCAN SDK |
| [RRF](https://robotregistryfoundation.org) | v1.6.0 | Robot identity registry |

## Contributing

PRs welcome. See [SETUP.md](SETUP.md) for the full developer environment guide.

## License

Apache 2.0
