# OpenCastor Client

Remote fleet management for [OpenCastor](https://github.com/craigm26/OpenCastor) robots.
Manage, command, and monitor your robots from anywhere — no port forwarding, no exposed endpoints.

## Architecture

```
Your Phone (Flutter app)
  │  Firebase Auth (Google sign-in)
  │  Firestore — robot state, command queue, consent records
  │  FCM — push alerts (ESTOP, faults, consent requests)
  ▼
Cloud Functions — relay + R2RAM enforcement + rate limiting
  │
  │  (outbound only from robot)
  ▼
castor bridge — runs on each robot alongside castor gateway
  │
castor gateway — existing local REST API (port 8000)
  │  RCAN
Bob ←──────────→ Alex (local mesh unchanged)
```

Robots initiate outbound connections only. Protocol 66 safety enforcement runs locally on each robot — cloud commands pass through the same confidence gates and bounds checks as local commands.

## Screens

- **Fleet** — real-time status cards for all robots; one-tap ESTOP
- **Robot detail** — telemetry, command history, chat-scope instruction input
- **Control** — arm TELEOP with confirmation modal + persistent ESTOP button
- **Access** — R2RAM consent: approve/deny incoming requests, view/revoke established peers
- **Alerts** — ESTOP events and faults across all robots

## Setup

### 1. Robot side — start the bridge

```bash
pip install opencastor[cloud]

castor bridge \
  --config ~/opencastor/bob.rcan.yaml \
  --firebase-project live-captions-xr \
  --gateway-url http://127.0.0.1:8000 \
  --gateway-token <your-api-token>
```

Or with explicit service account credentials:

```bash
castor bridge \
  --config ~/opencastor/bob.rcan.yaml \
  --firebase-project live-captions-xr \
  --credentials /path/to/serviceAccount.json
```

Using Google ADC (recommended):
```bash
gcloud auth application-default login
castor bridge --config bob.rcan.yaml --firebase-project live-captions-xr
```

### 2. Cloud Functions — deploy

```bash
cd functions
npm install
firebase deploy --only functions
firebase deploy --only firestore:rules,firestore:indexes
```

### 3. Flutter app — configure Firebase

```bash
# Install FlutterFire CLI
dart pub global activate flutterfire_cli

# Configure for your Firebase project
flutterfire configure --project=live-captions-xr

# This generates lib/firebase_options.dart — do NOT commit it
```

Then build and run:

```bash
flutter pub get
flutter run
```

## R2RAM Authorization

Robot-to-robot communication follows the RCAN v1.5 R2RAM spec ([rcan-spec #160](https://github.com/continuonai/rcan-spec/issues/160)):

| Tier | Default |
|---|---|
| Same-owner robots | All scopes allowed (implicit consent) |
| Trusted cross-owner peers | Scopes explicitly granted, time-bounded |
| Unknown robots | Blocked — DISCOVER only until consent handshake |

ESTOP from any robot with a valid RURI is always honored. Only authorized sources can issue RESUME.

## Security

- Robot API tokens are **never** stored in the Flutter app — they live in Cloud Functions environment variables
- Firestore security rules enforce owner-only access; cross-owner writes require Cloud Function relay
- All control-scope commands require explicit confirmation in the UI
- Rate limiting: 60 calls/min for chat/status, 10/min for control, unlimited for safety
- All commands are audited in Firestore with Firebase UID + timestamp

## Requirements

- Flutter 3.22+
- Firebase project with Firestore, Auth (Google), Functions, Messaging enabled
- OpenCastor ≥ 2026.3.14.6 on each robot
- Python `opencastor[cloud]` extra (`firebase-admin ≥ 6.0`)
