# OpenCastor Client — First-Time Setup

## Prerequisites

- Flutter 3.22+ (`flutter --version`)
- Firebase CLI (`npm install -g firebase-tools`)
- FlutterFire CLI (`dart pub global activate flutterfire_cli`)
- Firebase project with these services enabled:
  - Authentication (Google sign-in provider)
  - Firestore
  - Cloud Functions
  - Cloud Messaging

---

## Step 1 — Configure Firebase

```bash
# Login to Firebase
firebase login

# Generate lib/firebase_options.dart for your project
# Run from the opencastor-client/ root
flutterfire configure --project=live-captions-xr

# This creates lib/firebase_options.dart — it's gitignored, keep it local
```

Also download your platform credential files from the Firebase console:

- **Android**: `google-services.json` → `android/app/google-services.json`
- **iOS**: `GoogleService-Info.plist` → `ios/Runner/GoogleService-Info.plist`

---

## Step 2 — Install Flutter dependencies

```bash
flutter pub get
```

---

## Step 3 — Deploy Cloud Functions + Firestore rules

```bash
cd functions
npm install
cd ..

# Deploy everything
firebase deploy --only functions,firestore:rules,firestore:indexes
```

---

## Step 4 — Run the app

```bash
# Android / iOS device
flutter run

# Web (for dev/testing)
flutter run -d chrome
```

---

## Step 5 — Start the bridge on each robot

```bash
# On each robot (Bob, Alex, etc.)
pip install opencastor[cloud]

castor bridge \
  --config ~/opencastor/bob.rcan.yaml \
  --firebase-project live-captions-xr \
  --gateway-url http://127.0.0.1:8000 \
  --gateway-token <api-token>
```

Or use the included systemd service for auto-start on boot:

```bash
# Copy service file to robot
sudo cp deploy/systemd/castor-bridge.service /etc/systemd/system/
sudo cp deploy/systemd/castor-gateway.service /etc/systemd/system/

# Edit to set FIREBASE_PROJECT and RCAN_CONFIG
sudo systemctl edit castor-bridge.service

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable --now castor-gateway castor-bridge

# Check status
sudo systemctl status castor-bridge
journalctl -u castor-bridge -f
```

---

## Using ADC instead of a service account

The bridge works with Google Application Default Credentials:

```bash
# On the robot
gcloud auth application-default login

# Then start bridge without --credentials
castor bridge --config bob.rcan.yaml --firebase-project live-captions-xr
```

---

## Robot RCAN config — adding the cloud block

Add this to your `bob.rcan.yaml` (or whatever config you use):

```yaml
cloud:
  firebase_project: live-captions-xr
  gateway_url: http://127.0.0.1:8000
  telemetry_interval_s: 30
  poll_interval_s: 5
```

Then start the bridge without flags:

```bash
castor bridge --config bob.rcan.yaml
```

---

## R2RAM — consent between robots with different owners

If two robots have different owners and want to communicate:

1. Robot A sends a consent request via the app (Access tab → Request Access)
2. Robot B's owner gets an FCM push notification
3. Robot B's owner approves in the Access tab (scope + duration)
4. Both sides get notified; the channel opens

Same-owner robots (Bob + Alex both owned by you) communicate freely with no consent prompt.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Robot shows offline | Check `castor bridge` is running; check `castor gateway` is running |
| Commands stuck at "pending" | Bridge not polling — check `journalctl -u castor-bridge` |
| FCM notifications not arriving | Re-run `flutterfire configure`; check FCM token is registered |
| Firebase permission denied | Check `firestore.rules` deployed; verify owner UID matches |
| ESTOP not working | ESTOP bypasses rate limiting — if failing, check gateway is alive |
