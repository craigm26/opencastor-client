# Changelog

All notable changes to opencastor-client are documented here.

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
