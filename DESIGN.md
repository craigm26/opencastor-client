# DESIGN.md — opencastor-client

> Google Stitch-compatible design system reference.
> Source of truth: `lib/ui/core/theme/app_theme.dart`

---

## 1. Vibe & Mood

Airy, Technical, Dark-first robotic dashboard. Clean and clinical with a sense of precision and control. Like a mission control panel — utilitarian but polished. Inspired by developer tooling and aerospace UI aesthetics.

---

## 2. Color Palette

| Name                  | Hex       | Usage                                                                 |
|-----------------------|-----------|-----------------------------------------------------------------------|
| Primary (Sky Blue)    | `#0ea5e9` | Brand seed, interactive elements, links, active states                |
| Secondary (Teal)      | `#2dd4bf` | Highlights, secondary actions, online indicators                      |
| Midnight Background   | `#0a0b1e` | Dark scaffold background, deepest surface                             |
| Status / Online       | `#146C2E` | M3 Success Green — online indicators, healthy state                   |
| Status / Warning      | `#7D5700` | M3 Amber — degraded state, caution                                    |
| Status / Danger+ESTOP | `#B3261E` | M3 Error Red — Protocol 66 emergency stop. **Never repurpose this.**  |
| Status / Offline      | `#49454F` | M3 Outline — disconnected, inactive                                   |

**Theme generation:** `ColorScheme.fromSeed(seedColor: #0ea5e9)` — light and dark variants auto-generated via Material 3.

---

## 3. Typography

| Role      | Font           | Usage                                                    |
|-----------|----------------|----------------------------------------------------------|
| Primary   | Inter          | All UI text                                              |
| Monospace | JetBrains Mono | Telemetry data, code, RRNs, status values, terminal output |

- Follow Material 3 type scale: `displayLarge` → `bodySmall`
- Labels: use `labelLarge` / `labelMedium` for metadata chips and status badges
- Monospace style: `AppTheme.mono`

---

## 4. Spacing Scale

Always use these tokens — no magic numbers.

| Token        | Value | Usage              |
|--------------|-------|--------------------|
| `Spacing.xs` | 4 dp  | Tight gaps         |
| `Spacing.sm` | 8 dp  | Small gaps         |
| `Spacing.md` | 16 dp | Default padding    |
| `Spacing.lg` | 24 dp | Section spacing    |
| `Spacing.xl` | 32 dp | Large gaps         |
| `Spacing.xxl`| 48 dp | Page-level margins |

Reference: `Spacing.xs` / `Spacing.sm` / `Spacing.md` / `Spacing.lg` / `Spacing.xl` / `Spacing.xxl`

---

## 5. Border Radius Scale

| Token           | Value  | Usage                            |
|-----------------|--------|----------------------------------|
| `AppRadius.sm`  | 8 dp   | Chips, small buttons, inputs     |
| `AppRadius.md`  | 12 dp  | Cards, standard buttons (default)|
| `AppRadius.lg`  | 16 dp  | Modals, bottom sheets            |
| `AppRadius.xl`  | 28 dp  | FABs, large pill buttons         |
| `AppRadius.full`| 999 dp | Fully rounded (badges, avatars)  |

Reference: `AppRadius.sm` / `AppRadius.md` / `AppRadius.lg` / `AppRadius.xl` / `AppRadius.full`

---

## 6. Component Conventions

| Component       | Spec                                                                      |
|-----------------|---------------------------------------------------------------------------|
| Cards           | `elevation=0`, `radius=md(12)`, use `ColorScheme` surface colors — never hardcode backgrounds |
| FilledButton    | `min-height=48dp`, `radius=md(12)`                                        |
| OutlinedButton  | `min-height=48dp`, `radius=md(12)`                                        |
| Text inputs     | `OutlineInputBorder`, `radius=10dp` (slightly tighter than cards)         |
| AppBar          | `centerTitle=false`, `elevation=0`, `scrolledUnderElevation=3`            |
| Chips           | `radius=sm(8)`                                                            |
| Bottom sheets   | `useSafeArea=true`, top `radius=lg(20)`, `DraggableScrollableSheet` for tall content |

---

## 7. Architecture Rules (for AI agents)

- **Pattern:** MVVM — Views → ViewModels (Riverpod providers) → Repositories → Services
- Never put business logic in `Widget.build()` methods
- Use `ref.watch()` in `ConsumerWidget` / `ConsumerStatefulWidget`
- **State:** Riverpod (`flutter_riverpod` + `hooks_riverpod`)
- **Navigation:** `go_router`
- No direct Firestore calls from UI — always through repository layer
- **ESTOP color (`#B3261E`) is reserved for Protocol 66 safety — never use for decorative purposes**

---

## 8. Icons

- Use **Material Icons** (outlined variants preferred for nav/secondary, filled for active states)
- Robot / status icons: `Icons.memory_outlined`, `Icons.layers_outlined`, `Icons.pause_circle_outline`, `Icons.play_circle_outline`, `Icons.power_settings_new_outlined`, `Icons.camera_alt_outlined`
- Safety: `Icons.emergency`, `Icons.shield_outlined`
- Consistent sizes: **16 dp** (inline/chip), **24 dp** (standard), **32 dp** (card header)

---

## 9. Dark Mode

- **Default to dark mode** for robot operators (low-light environments)
- Dark scaffold: `#0a0b1e` (Midnight)
- All colors must pass **WCAG AA** contrast on both light and dark backgrounds
- Test new components in both modes

---

## 10. Stitch Compatibility Note

This DESIGN.md follows the [Google Stitch DESIGN.md spec](https://stitch.withgoogle.com/docs/design-md).
When generating screens with Stitch MCP, pass this file as context.
To regenerate from live screenshots: `npx skills add google-labs-code/stitch-skills --skill design-md`
