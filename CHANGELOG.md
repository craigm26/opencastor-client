# Changelog

All notable changes to opencastor-client are documented here.

---

## [2.0.0] - 2026-04-12

### Added

**LAN Mode — direct robot connection over local Wi-Fi**
- New `LanRobotService` sends commands directly to the robot's REST API at `http://[local_ip]:8000`, cutting round-trip latency from ~500 ms (Firebase relay) to ~30 ms
- Per-robot LAN toggle + API token stored in SharedPreferences; survives app restarts
- `LanSettingsCard` bottom sheet: token input, ping test, enable/disable toggle
- WiFi indicator badge in app bar when LAN mode is active
- ESTOP tries LAN first then falls back to Firebase (Protocol 66 §4.1 guarantee preserved)
- Slash commands (`/status`, `/pause`, `/resume`, etc.) are fully LAN-aware; responses appear in chat immediately without Firestore polling
- `mergedCommandsProvider` combines in-memory LAN command log with Firestore history for seamless chat display

**EU AI Act Compliance Hub** (deadline: 2026-08-02)
- New `/robot/:rrn/compliance` route with 5 sub-screens:
  - **FRIA** — Fundamental Rights Impact Assessment viewer pulled from rcan.dev
  - **Safety Benchmark** — Protocol 66 / OHB-1 results from rcan.dev
  - **Instructions for Use** — §24 documentation checklist
  - **Post-Market Monitoring** — §72 monitoring obligations
  - **EU Register** — §49 high-risk system submission guide
- **Compliance Report** screen (`/robot/:rrn/compliance-report`) — generates and copies a structured EU AI Act compliance JSON (article mapping, SBOM status, firmware attestation, authority handler, audit retention)
- Article mapping: Art. 12, 16(a), 16(d), 16(j) with pass/warn indicators

**RCAN v3.0 Conformance**
- Conformance level engine updated: L3–L5 path for RCAN v2.1+; v3.0 robots now correctly reach L5
- `isRcanV30` / `isRcanV21` version gates fixed (was incorrectly gating v2.1 as v3.0)
- RCAN v3.0 badge (`_RcanVersionBadge`) — rose-gold color, replaces stale v2.x strings throughout

**Other**
- `rcanComplianceRrn` field on `Robot` model — allows Firestore routing RRN to differ from rcan.dev registration RRN; compliance screens use `effectiveComplianceRrn`
- `castor fria publish` gap noted — FRIA documents can be generated locally but not yet pushed to rcan.dev from within the app

### Fixed
- `ComplianceStatus` / `FriaDocument` JSON deserialization aligned with actual rcan.dev API wire format
- `FilePicker` API migration from deprecated `instance` to `PlatformFilePicker()`
- `LanSettingsCard` — `AsyncValue` has no `.then()`: fixed hydration via `addPostFrameCallback`
- Dependabot alert #109 (riverpod ^3.x major bump) closed — breaking change, not a simple bump

### Security
- rcan-spec: pnpm overrides patched for h3 (`<1.15.9`), smol-toml (`<1.6.1`), yaml (`<2.8.3`), vite (`<6.4.2`)
- Dependabot alerts #14/#15 (picomatch 2.x) dismissed — lockfile only contains picomatch@4.0.4

---

## [1.1.0] - 2026-04-02

### Added
- Real-time telemetry panel in robot detail screen — live CPU, disk, memory, and uptime via Firestore stream (#90/#93)
- FCM push notifications for robot offline status — background alerts when a robot goes offline (#91/#94)

### Fixed
- Safari login loop on web — proxy Firebase auth domain via Cloudflare Pages Function (#85)
- google_sign_in v7 cancellation now handled via exception instead of null check (#86/#88)
- SetupScreen delegates auth to AuthService instead of direct Firebase calls (#87/#92)
- Android build stack overhaul — Gradle 8.11.1 / AGP 8.9.1 / Kotlin 2.2.0 (#82)
- CI branch target fix (#83)

---

## [1.4.0] - 2026-03-28

### Added
- WebSocket real-time telemetry (`ws_telemetry_service.dart`) — merges live WS data over Firestore
- Hardware screen: synthesizes hw profile from `telemetry.system` when CF relay unavailable
- Software screen: displays built-in commands list from bridge skills push
- LoA enforce button (`_LoaEnableSheet`) — sends `loa_enable` command via Firestore
- Components screen (`/robot/:rrn/capabilities/components`) — Firestore stream, grouped by type
- Research screen (`/robot/:rrn/research`) — OHB-1 benchmark, community submit
- Provenance card in hardware screen — full RRF chain (RCN/RMN/RHN)
- Harness editor block ordering UX — numbered badge, drag handle, ↑/↓ buttons
- Harness auto-save draft (2s debounce) + persistence to `robots/{rrn}.user_harness_config`
- Flow graph serialized in harness saves; restored on editor open
- Contribute toggle: direct Firestore write to `robots/{rrn}/commands` (replaces CF relay)
- GCS direct read for Explore configs (public bucket, zero Firestore reads)
- BigQuery telemetry streaming support (bridge-side, confirmed live)

### Changed
- Robot detail: chat-first layout; hardware stats moved to Capabilities → Hardware
- RCAN v2.2 explore configs: PQ badges, v2.2 scope levels
- `_RcanVersionBadge`: v2.2 → emerald, v2.1 → sky, others → grey
- `validateAndSaveHarness` CF rcan_version corrected to `"2.2"`
- `Robot` model: added v2.2 fields (rrfRcns, rrfRmns, rrfRhn, pqKid, manufacturer, hardwareModel)
- `withOpacity()` → `withValues(alpha:)` throughout
- Harness design panels: slider UX overhaul

### Fixed
- Stale service worker causing blank fleet cards + `Failed to fetch`
- `CapStatus.fail` → `missing`, `CapStatus.warn` → `warning`
- `Robot.fromDoc` — handle Firestore Timestamp for `registered_at`
- Firestore security rule for `robots/{rrn}/components/{componentId}`


## [1.2.0] - 2026-03-21
### Added
- Fleet Leaderboard: Kinetic Command design system (Stitch AI) — AeroNexus Technical theme, tonal cards, Space Grotesk typography, badge tier chips (Diamond/Gold/Silver/Bronze), search/filter bar
- Version update notification banner on robot detail screen
- Castor Credits UI — earn/track/redeem section, Pro waitlist screen
### Fixed
- Capabilities screen crash: safe List<dynamic> casting via _asList() helper (#23)
- Harness screen: removed redundant flow-view toggle button (#24)
- Harness editor: applied Kinetic Command design tokens (#24)

---

## [1.1.0+2] — 2026-03-17

### Added
- **Social layer**: robot profiles, version pinning, and CONFIG_SHARE protocol (OpenCastor#701)
- **Community Hub Phase 2**: `/explore` browse page and `/config/:id` detail view for shared configs
- **Firebase Cloud Functions**: backend relay for config publishing and retrieval (`relay.ts`)
- **RCAN v1.6 capability badges**: transport, LoA, and federation status displayed on robot detail cards
- **Multi-modal stub**: media attachment UI for RCAN v1.6 multi-modal payloads
- **LoA display**: operator Level of Assurance shown on each control command

---

## [1.0.0+1] — 2026-03-01

### Added
- Initial release — fleet overview, robot detail, chat control, control panel, consent management
- Real-time ESTOP on every screen
- Revocation display with RCAN identity badges
