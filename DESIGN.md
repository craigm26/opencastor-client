# DESIGN.md — OpenCastor Client

> **Design system reference for AI coding agents.**
> Read this before making any UI changes. Never use magic numbers — always reference `AppTheme`, `Spacing`, and `AppRadius`.
>
> Follows the [Google Stitch DESIGN.md spec](https://stitch.withgoogle.com/docs/design-md/overview).
> To regenerate from live screenshots: `npx skills add google-labs-code/stitch-skills --skill design-md`

---

## Vibe & Mood

**Airy, Technical, Dark-first.** Like a mission control panel designed by engineers who care about aesthetics — utilitarian but polished. Think aerospace HUD meets developer tooling. Clean geometry, purposeful color, no decoration for its own sake.

Key adjectives: *Precise. Focused. Trustworthy. Clinical. Alive.*

The app controls physical robots in the real world. Every UI decision should reinforce confidence and clarity. When a user taps "Pause" they need to feel certain it happened. When ESTOP fires the color must be unmistakable.

---

## Color Palette

Source of truth: `lib/ui/core/theme/app_theme.dart`

### Brand Colors

| Name | Hex | Usage |
|---|---|---|
| **Sky Blue** (primary seed) | `#0ea5e9` | Interactive elements, links, active states, brand identity |
| **Teal Accent** (secondary) | `#2dd4bf` | Highlights, secondary CTAs, complementary accents |
| **Midnight** (dark bg) | `#0a0b1e` | Dark scaffold background — deepest surface layer |

### Semantic / Status Colors

These carry meaning. Never repurpose them for decoration.

| Name | Hex | Constant | Meaning |
|---|---|---|---|
| **Success Green** | `#146C2E` | `AppTheme.online` | Robot online, operation succeeded |
| **Amber Warning** | `#7D5700` | `AppTheme.warning` | Degraded, needs attention, non-critical |
| **Error Red** | `#B3261E` | `AppTheme.danger` | Error, blocked, failed |
| **ESTOP Red** | `#B3261E` | `AppTheme.estop` | Protocol 66 emergency stop — **reserved, never reuse** |
| **Offline Grey** | `#49454F` | `AppTheme.offline` | Robot offline, inactive, disabled |

> ⛔ **ESTOP Red (`#B3261E`) is sacred.** It is the only color for Protocol 66 emergency stop. Using it anywhere else trains users to ignore it. Don't.

### Material 3 Dynamic Colors

The full color scheme is generated via `ColorScheme.fromSeed(seedColor: Color(0xFF0ea5e9))` in both light and dark modes. Use `Theme.of(context).colorScheme` tokens — never hardcode surface/background/onSurface values.

Key M3 roles to use:
- `colorScheme.surface` — card backgrounds
- `colorScheme.surfaceContainerHighest` — elevated surfaces
- `colorScheme.onSurface` — primary text
- `colorScheme.onSurfaceVariant` — secondary/metadata text
- `colorScheme.primary` — interactive elements (derives from #0ea5e9)
- `colorScheme.outline` — borders, dividers
- `colorScheme.error` — error states (aligns with #B3261E)

---

## Typography

Source of truth: `lib/ui/core/theme/app_theme.dart`

### Font Families

| Family | Constant | Use |
|---|---|---|
| **Inter** | `AppTheme._fontFamily` | All UI text — headings, body, labels, buttons |
| **JetBrains Mono** | `AppTheme.mono` | Telemetry data, RRNs, version strings, status values, terminal/log output, code |

Always use `AppTheme.mono` for: robot identifiers (`RRN-000000000001`), IP addresses, version strings (`2026.3.17.13`), sensor readings, coordinate values, JSON/YAML snippets.

### Material 3 Type Scale

Follow M3 type roles — don't invent custom sizes:

| Role | Use |
|---|---|
| `displayLarge / displayMedium` | Hero screens, empty states |
| `headlineLarge / headlineMedium` | Screen titles, section headers |
| `titleLarge / titleMedium / titleSmall` | Card titles, list item primaries, dialog titles |
| `bodyLarge / bodyMedium / bodySmall` | Content text, descriptions, helper text |
| `labelLarge / labelMedium / labelSmall` | Buttons, chips, metadata badges, status labels |

---

## Spacing Scale

Source of truth: `lib/ui/core/theme/app_theme.dart` → `class Spacing`

**Always use these. No magic numbers.**

| Token | Value | Use |
|---|---|---|
| `Spacing.xs` | 4dp | Icon gaps, tight inline spacing |
| `Spacing.sm` | 8dp | Between related elements, chip padding |
| `Spacing.md` | 16dp | Default content padding, section gaps |
| `Spacing.lg` | 24dp | Between sections, card internal padding |
| `Spacing.xl` | 32dp | Screen horizontal margins, hero spacing |
| `Spacing.xxl` | 48dp | Large section separators, empty state padding |

```dart
// ✅ correct
Padding(padding: const EdgeInsets.all(Spacing.md))

// ❌ wrong
Padding(padding: const EdgeInsets.all(16))
```

---

## Border Radius Scale

Source of truth: `lib/ui/core/theme/app_theme.dart` → `class AppRadius`

| Token | Value | Use |
|---|---|---|
| `AppRadius.sm` | `Radius.circular(8)` | Chips, small tags, input fields |
| `AppRadius.md` | `Radius.circular(12)` | Cards, standard buttons (default) |
| `AppRadius.lg` | `Radius.circular(16)` | Modals, bottom sheets, large containers |
| `AppRadius.xl` | `Radius.circular(28)` | FABs, large pill buttons |
| `AppRadius.full` | `Radius.circular(999)` | Fully rounded — badges, avatars, status dots |

---

## Components

### Cards

```dart
// Defined in AppTheme — don't override unless necessary
CardThemeData(
  elevation: 0,                                    // flat, no shadow
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.all(AppRadius.md),  // 12dp
  ),
)
```

- Use `colorScheme.surface` as background (auto via theme)
- Elevation 0 by default — use `surfaceContainerHighest` for emphasis instead of shadow
- Add a thin `colorScheme.outlineVariant` border for separation in dense layouts

### Buttons

```dart
// FilledButton (primary CTA)
FilledButton.styleFrom(
  minimumSize: const Size(0, 48),                 // always 48dp tall
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.all(AppRadius.md),
  ),
)

// OutlinedButton (secondary)
OutlinedButton.styleFrom(
  minimumSize: const Size(0, 48),
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.all(AppRadius.md),
  ),
)
```

- Minimum height: **48dp** (touch target, non-negotiable)
- Text buttons for inline/tertiary actions only (never as primary CTA)
- Destructive actions: use `FilledButton` with `style: FilledButton.styleFrom(backgroundColor: AppTheme.danger)`

### Text Inputs

```dart
InputDecorationTheme(
  border: OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),  // slightly tighter than cards
  ),
)
```

### AppBar

```dart
AppBarTheme(
  centerTitle: false,   // left-aligned titles
  elevation: 0,
  scrolledUnderElevation: 3,
)
```

Left-align titles always. Use subtitle/leading for context breadcrumbs. On robot detail screens, title = robot name, subtitle = RRN.

### Chips

```dart
ChipThemeData(
  shape: RoundedRectangleBorder(
    borderRadius: BorderRadius.all(AppRadius.sm),  // 8dp
  ),
)
```

Use chips for: capability tags, scope badges, status labels. Pair with `AppTheme.online/warning/danger/offline` for status chips.

### Status Indicators

```dart
// Online dot
Container(
  width: 8, height: 8,
  decoration: BoxDecoration(
    color: AppTheme.online,            // #146C2E
    shape: BoxShape.circle,
  ),
)

// Offline
color: AppTheme.offline               // #49454F

// Warning
color: AppTheme.warning               // #7D5700

// ESTOP / Danger
color: AppTheme.estop                 // #B3261E
```

### Bottom Sheets

```dart
showModalBottomSheet(
  context: context,
  useSafeArea: true,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: AppRadius.lg),  // 16dp top
  ),
  builder: (context) => DraggableScrollableSheet(...),  // for tall content
)
```

### Icons

Material Icons — outlined variants for nav/secondary, filled for active/selected states.

| Purpose | Icon |
|---|---|
| Robot hardware | `Icons.memory_outlined` |
| Layers / harness | `Icons.layers_outlined` |
| Pause | `Icons.pause_circle_outline` |
| Resume | `Icons.play_circle_outline` |
| Shutdown | `Icons.power_settings_new_outlined` |
| Camera | `Icons.camera_alt_outlined` |
| ESTOP / Safety | `Icons.emergency`, `Icons.shield_outlined` |
| Settings | `Icons.settings_outlined` |
| Commands | `Icons.terminal_outlined` |
| Snapshot | `Icons.photo_camera_outlined` |

**Icon sizes:**
- `16dp` — inline, inside chips, next to text
- `24dp` — standard (default)
- `32dp` — card header, section lead

---

## Dark Mode

Dark mode is the **default** for robot operators (low-light environments, industrial settings).

- Dark scaffold: `#0a0b1e` (Midnight) — set in `AppTheme.dark`
- All semantic colors (online/warning/danger/offline) are tested for WCAG AA on `#0a0b1e`
- Every new component must be verified in both light and dark before merging
- Use `Theme.of(context).brightness == Brightness.dark` to branch only when absolutely necessary — prefer M3 role tokens that adapt automatically

---

## Architecture Rules for AI Agents

Read before generating any code.

### Pattern: MVVM

```
lib/
  ui/
    screen_name/
      screen_name_screen.dart     ← View (ConsumerWidget / ConsumerStatefulWidget)
      screen_name_view_model.dart ← ViewModel (StateNotifier / AsyncNotifier)
  data/
    repositories/
      robot_repository.dart       ← Abstract interface
    services/
      firestore_robot_service.dart ← Concrete implementation
    models/
      robot.dart                  ← Data models
```

- **No business logic in `build()`** — views observe state and dispatch events
- **`ref.watch()`** for reactive state, **`ref.read()`** for one-shot reads in callbacks
- **State management**: Riverpod (`flutter_riverpod` + `hooks_riverpod`)
- **Navigation**: `go_router` — never `Navigator.push` directly
- **No direct Firestore calls from UI** — always through repository → service layer

### Firestore Access

```dart
// ✅ correct — through repository
final robots = ref.watch(robotFleetProvider(uid));

// ❌ wrong — direct Firestore from widget
FirebaseFirestore.instance.collection('robots').get();
```

### Null Safety

- All models must handle missing/null fields gracefully
- Use `??` fallbacks for optional fields
- Never assume Firestore documents have all fields present (robots may be on older bridge versions)

### Platform

Target: **Flutter Web** (primary), Flutter Android (secondary).
- Test layout at 360dp, 768dp, 1280dp widths
- Use `LayoutBuilder` / `AdaptiveLayout` for responsive breakpoints
- No platform-specific (dart:io) code in UI layer

---

## Stitch Compatibility

This file follows the [Google Stitch DESIGN.md spec](https://stitch.withgoogle.com/docs/design-md/overview).

When using Stitch MCP to generate screens:
1. Pass this file as design context
2. Reference the color tokens by descriptive name (e.g. "Sky Blue primary", "Midnight background")
3. Specify dark-mode-first unless the screen is explicitly light-only

Stitch skill for this repo:
```bash
npx skills add google-labs-code/stitch-skills --skill design-md
npx skills add google-labs-code/stitch-skills --skill stitch-design
```
