# Setup Guide — OpenCastor Client

## New Firebase + Google Cloud project (one-time, done by Craig)

### 1. Create the projects

```bash
# Install gcloud if not already
brew install google-cloud-sdk   # or apt

# Create GCP project
gcloud projects create opencastor-fleet --name="OpenCastor Fleet"

# Set billing account (required for Cloud Functions)
gcloud billing projects link opencastor-fleet \
  --billing-account=$(gcloud billing accounts list --format='value(name)' | head -1)
```

Then in [Firebase Console](https://console.firebase.google.com):
- Add project → select existing GCP project `opencastor-fleet`
- Enable: **Firestore**, **Authentication** (Google provider), **Functions**, **Messaging**

### 2. Configure the Flutter app

```bash
# Install FlutterFire CLI (once)
dart pub global activate flutterfire_cli

# In opencastor-client/ directory:
flutterfire configure --project=opencastor-fleet

# This generates lib/firebase_options.dart — gitignored, DO NOT COMMIT
# For CI: copy the file contents into GitHub secret FIREBASE_OPTIONS_DART
```

### 3. Deploy Cloud Functions

```bash
cd functions
npm install

# Deploy functions + Firestore rules + indexes
firebase use opencastor-fleet
firebase deploy --only functions,firestore
```

### 4. Set up app.opencastor.com

In [Cloudflare Dashboard](https://dash.cloudflare.com):
1. Pages → Create project → `opencastor-client`
2. Connect to GitHub repo `craigm26/opencastor-client`
3. Build settings:
   - Framework: Flutter
   - Build command: `flutter build web --release --base-href /`
   - Output: `build/web`
4. Custom domain: `app.opencastor.com`
5. Add CNAME in DNS: `app → opencastor-client.pages.dev`

Or use the GitHub Actions workflow (`.github/workflows/deploy-web.yml`) which handles this automatically on push to master.

**Required GitHub Secrets:**
```
FIREBASE_OPTIONS_DART     — contents of lib/firebase_options.dart
CLOUDFLARE_API_TOKEN      — Cloudflare API token with Pages:Edit
CLOUDFLARE_ACCOUNT_ID     — your Cloudflare account ID
```

### 5. Robot side — start the bridge

```bash
# Install with cloud extras
pip install opencastor[cloud]

# One-time: authenticate with Google
gcloud auth application-default login

# Start bridge (alongside castor gateway)
castor bridge \
  --config bob.rcan.yaml \
  --firebase-project opencastor-fleet \
  --gateway-url http://127.0.0.1:8000

# Or with systemd (recommended for production):
sudo cp deploy/systemd/castor-gateway.service /etc/systemd/system/
sudo cp deploy/systemd/castor-bridge.service /etc/systemd/system/
# Edit /etc/systemd/system/castor-bridge.service → set FIREBASE_PROJECT=opencastor-fleet
sudo systemctl enable --now castor-gateway castor-bridge
```

### 6. Add firebase_uid to robot RCAN config

After creating the Firebase project, get your UID:
```bash
# Sign in at app.opencastor.com, then in Firebase Console:
# Authentication → Users → copy your UID
```

Add to `bob.rcan.yaml`:
```yaml
firebase_uid: "YOUR_FIREBASE_UID_HERE"
```

---

## App Store submissions

### Google Play
- Account: existing personal developer account (already have LiveCaptionsXR)
- Package: `com.opencastor.app`
- Build: `flutter build appbundle --release`
- Switch to organization account when charging subscriptions or signing enterprise contracts

### Apple App Store
- Account: existing personal developer account (\$99/year)
- Bundle ID: `com.opencastor.app`
- Build: `flutter build ipa --release` (requires macOS + Xcode)
- Personal account shows your name on the App Store listing
- Switch to organization (needs D-U-N-S number) when you want "OpenCastor" as the publisher name

### CA Sole Proprietor / DBA (when needed)
- File "Fictitious Business Name" with your county (~\$25-75)
- Name: "OpenCastor" or "OpenCastor Labs"
- Required before: opening a business bank account, signing contracts as OpenCastor
- Full LLC: when revenue is real and you want liability protection

---

## Self-hosting (for third-party developers)

Anyone can self-host the full stack at zero cost to Craig:

```bash
# 1. Fork this repo
# 2. Create their own Firebase project (free tier is enough for small fleets)
# 3. Run: flutterfire configure --project=<their-project>
# 4. Deploy functions: firebase deploy --only functions,firestore
# 5. Build web: flutter build web
# 6. Deploy anywhere: Cloudflare Pages, Firebase Hosting, Netlify
```

Their Firebase project, their costs. Craig's Firebase is never hit.
