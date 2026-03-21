# Changelog

All notable changes to opencastor-client are documented here.

---

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
