# Motion polish audit (Phase 10)

A sweep of every animation in the app for spring-token consistency,
reduce-motion compliance, and interrupt/retarget safety.

## Spring-token consistency

**Result: clean.** No ad-hoc `AnimationController`, `CurvedAnimation`, `Tween`,
or `Curves.*` anywhere in `lib/` (verified by grep). Every animated widget reads
its spring from the central `MotionTokens` via `MotionScope.of(context)`:

| Widget | Token | Reduced-motion behavior |
| --- | --- | --- |
| `CheckPill` | `spatialFast` | standard spring (0.9 damping) → minimal bounce |
| `StreakOdometer` | `spatialDefault` | standard spring → near-critical settle |
| `HabitHeatmap` entrance | `spatialSlow` | standard spring → gentle, no overshoot |
| `TokenWallet` pop | `spatialFast` | standard spring |
| `TodayProgressRing` | `spatialSlow` | explicit `reduced` branch: static arc, no burst |
| `ConfettiOverlay` | `celebration` | explicit `reduced` branch: skipped entirely |
| `FloatingPills` bob | `spatialSlow` | explicit `reduced` branch: static illustration |
| Stats `_Entrance` | `spatialDefault` | explicit `reduced` branch: static card |

The `celebration` token is a dedicated critically-damped spring (stiffness 12,
~2.5s, never overshoots) so the confetti runs its full course; spatial springs
would cut it short at their overshoot.

## Reduce-motion compliance

Two layers, OR'd together in `MotionScope`:

1. **User preference** — Settings → Motion → Standard (`motionTokensProvider`).
2. **OS accessibility** — `MediaQuery.disableAnimations` (read in `MotionScope`).

When either is set, `MotionScope` publishes `MotionTokens.standard` *and*
re-publishes `MediaQuery.disableAnimations: true` so M3E components (sheets,
carousel, etc.) reduce motion too. Looping/particle effects (bob, confetti,
ring burst, stats entrance) additionally short-circuit on `tokens.reduced` so
they render statically rather than relying on spring damping alone.

The e2e suite boots with `motionMode: standard`, exercising this path end to end.

## Interrupt / retarget safety

Every controller retargets its spring in `build` (`_x.motion = tokens.…`), so a
scheme switch mid-animation redirects the running simulation (motor's
`_redirectSimulation`) rather than restarting it. Rapid taps on `CheckPill` /
task cards call `animateTo` on the same controller, which cancels and re-targets
the in-flight spring — no stacked animations or leaks. All controllers are
disposed in `State.dispose`; the `FloatingPills` loop guards on `mounted` before
re-arming, and `ReminderCoordinator`/`NotificationService` cancel timers on
dispose.

## Interrupt / retarget sanity (automated)

`test/features/motion_interrupt_test.dart` covers:

- **Rapid taps** — 7 consecutive `CheckPill` taps at 40ms intervals (each lands
  mid-morph); the spring retargets and settles on the correct state with no
  exceptions or stacked tickers.
- **Scheme switch mid-flight** — OS reduce-motion flips on and back off while
  a morph is animating; `MotionScope` republishes and the running controller
  retargets safely.
- **Rapid habit toggles** — 6 check-in/undo taps at 80ms intervals against the
  real database; the unique(habitId, date) constraint and idempotent check-in
  keep the DB consistent (ends unchecked, zero rows).

## 60fps check (automated frame budgets)

`integration_test/perf_test.dart` uses
`IntegrationTestWidgetsFlutterBinding.watchPerformance` to collect real engine
frame timings while the heaviest animations run with the **expressive** scheme:

1. **All-done celebration** — ring overshoot + banner + ~2.5s confetti spring.
2. **Heatmap entrance** — detail route transition + 31-cell staggered pop-in.

Both assert the 90th-percentile build and rasterizer frame times stay under a
32ms budget (generous for debug builds / software rendering; the goal is
catching per-frame *work* regressions, not release pixel throughput). Summaries
are printed as `NOWPILL_PERF <key> <json>` and stored in `binding.reportData`.

**Measured (Linux debug, dev machine, 2026-11-23):**

| Scenario | Frames | Avg build | p90 build | p99 build | Steady-state frames |
| --- | --- | --- | --- | --- | --- |
| Celebration (ring + confetti, 2.6s) | 184 | 3.4ms | 5.6ms | 58.1ms | 0.3–2ms |
| Heatmap entrance (route + 31 cells) | 102 | 4.9ms | 17.9ms | 42.3ms | 0.3–0.8ms |

The p99/worst outliers are one-time costs (first confetti frame, route
transition + first heatmap build), not animation-loop work; rasterizer time is
~0 throughout. Both pass the 32ms p90 budget with headroom.

**Measured (Android debug, API 37 x86_64 emulator, `flutter drive --no-dds`,
2026-11-23):**

| Scenario | Avg build | p90 build | p99 build | Worst |
| --- | --- | --- | --- | --- |
| Celebration (ring + confetti, 2.6s) | 2.3ms | 3.8ms | 8.0ms | 44.9ms |
| Heatmap entrance (route + 31 cells) | 5.4ms | 17.1ms | 57.1ms | 200.4ms |

Both pass the same budget. The three journey e2e flows also pass on the
emulator. Runner notes: on Android emulators the perf suite needs `--no-dds`
(DDS blocks the VM-service connection `watchPerformance` uses). With
`flutter test --no-dds` every test passes but a flutter_tools golden-stream
subscription bug marks the *loading* step failed; `flutter drive --no-dds`
avoids that harness path:

```bash
flutter drive --no-dds --driver=test_driver/integration_test.dart \
  --target=integration_test/perf_test.dart -d emulator-5554
```

Architecture keeps per-frame work bounded: the confetti is a single
`CustomPaint` driven by one spring (26 pieces, no per-piece widgets); the
heatmap uses one entrance controller with per-cell phase offsets. Release-mode
numbers on physical hardware come from `flutter drive --profile` (follow-up).

## v0.2.0 re-audit (Phases 12–16)

Re-ran the spring-token sweep after manual freeze, i18n, widgets, and store
prep: **still clean** — no ad-hoc `AnimationController`/`CurvedAnimation`/
`Tween`/`Curves.*` in `lib/`. The new surfaces introduce no custom animation:

- **Manual-freeze choice dialog** (Phase 12) — standard `M3EDialog`, which
  honors `MediaQuery.disableAnimations` republished by `MotionScope`.
- **Language picker** (Phase 14) — standard `M3ESegmentedButton`; locale
  switches rebuild labels without animation.
- **Home-screen widget** (Phase 15) — native RemoteViews / WidgetKit, outside
  the Flutter motion system; the snapshot controller only pushes data.

The `computeTodayViewModel` extraction (Phase 15) is pure and adds no per-frame
work. All existing animated widgets still read `MotionScope.of(context)` and
retarget on scheme change; the interrupt/retarget tests continue to pass.

## v0.9.2 re-audit (shape morphism + spring polish)

**Result: still token-clean.** No `Curves.*`, ad-hoc `AnimationController`, or
fixed-duration implicit animations remain in feature code. The heatmap's last
`AnimatedContainer(200ms)` was replaced with an `effectsFast` spring.

New/updated surfaces:

| Widget | Token(s) | Reduced-motion behavior |
| --- | --- | --- |
| `CheckPill` | `spatialFast` (shape), `effectsFast` (fill/border) | standard springs; icon crossfade settles |
| `SpringPress` | `spatialFast` | standard spring squish |
| `MorphingShape` | `spatialDefault` + `effectsDefault` | standard springs, no idle morph |
| `TodayProgressRing` | `spatialSlow` | static arc + no burst (unchanged) |
| `HabitHeatmap` cell | `effectsFast` | standard spring fill/border + pop |
| `FloatingPills` | `spatialSlow` (ping-pong sequence) | static illustration |
| Stats `_Entrance` | `spatialDefault` | static card (unchanged) |
| Onboarding step/hero | `spatialDefault` | standard springs |

`Morph` objects are cached per ordered shape pair in `core/motion/shape_morph.dart`
so a list of habit badges does not re-run polygon matching per row. Overshoot is
always rendered as a small transform scale, never by feeding `progress > 1`
into a morph path (which would extrapolate its geometry). `MotionScope` now
notifies on any token change rather than only the `reduced` flag.

No new dependencies; the M3E pin remains 1.2.3 and all APIs used are public and
already present in the pinned package.

## v0.9.4 re-audit (expressive design pass)

**Result: still token-clean.** No `Curves.*`, ad-hoc `AnimationController`, or
fixed-duration implicit animations in feature code. New motion is centralized
in two shared primitives:

| Widget | Token(s) | Reduced-motion behavior |
| --- | --- | --- |
| `SpringEntrance` (Today sections, Stats cards, all-done banner) | `spatialDefault` | child rendered directly, no fade/rise |
| `SpringSwitcher` (tab branches, Stats range, Tasks/Habits filters) | `spatialFast` | child rendered directly |
| `QuickAddBar` preview chips | `spatialFast` (bounded) | chips shown/hidden instantly |

Design decisions (M3 publishes no values for these): a 60ms stagger per
section capped at 180ms, an 18dp card rise / 8dp switch rise, and a 16dp CTA
gap. M3's spring tokens themselves are unchanged.

Accessibility notes:
- Both primitives use `alwaysIncludeSemantics: true`, so an entrance never
  hides controls from screen readers or from bounded widget-test pumps.
- Today's large flexible app bar falls back to a small variant above 1.3×
  system text scale, and the date moves into the header. This avoids the
  M3E collapsed title block overflow that occurs at 2×.

M3-spec guardrails checked during this pass:
- Card corner radius stays at M3's 12dp step (large corners clip text-heavy
  containers); filled cards keep `surface container highest`.
- Accent washes are low-alpha *fills* over that surface, with `on surface` /
  `on surface variant` text — never accent-colored body text. Per-entity colors
  used as full fills pair with a luminance-selected role via
  `AppSurfaces.onAccent` (see the full design audit below).
- App bar containers stay square; only the flexible variants are used.
- FABs use medium size on compact/medium windows and a medium extended FAB on
  expanded windows (≥840dp), matching M3 breakpoint guidance.

No new dependencies; the M3E pin remains 1.2.3.

## Full M3 Expressive design audit (follow-up pass)

A source-checked sweep against the M3E references (tokens, color, typography,
motion, shape, foundations, layout, and per-component guidance). Each change
below is stated as **From M3** vs. **My design decision (not in M3)**.

### Fixed

| Finding | Resolution |
| --- | --- |
| Accent colors used as text/icons on tinted surfaces | Foregrounds now use `on surface` / `on surface variant`. Where a per-entity color is the *fill* (heatmap "done" cells), `AppSurfaces.onAccent` pairs it with `on surface` or `surface` by luminance. **From M3:** container roles are fills only; 4.5:1 small / 3:1 large text and graphics. **My design decision:** the 0.18 luminance threshold. Measured contrast of the raw brand palette is 1.2–3.5:1 on light surfaces, so the old foregrounds could not pass. |
| Steppers below 48×48dp | `SizedBox(48 × 48)` + `Center` around both amount icons; widget test added. **From M3:** 48×48dp minimum touch target. |
| 24dp banner corners | Snapped to `AppShape.hero` (28dp). **From M3:** the 10-step scale has no 24dp step. **My design decision:** assigning `hero` to banners. |
| Nested 12dp InkWell inside a 12dp card | Uses `AppShape.inner(AppShape.card, 4)` = 8dp. **From M3:** `inner = outer − padding`. |
| 10 deprecated segmented buttons | Replaced by `ConnectedChoiceGroup`, a thin wrapper over `M3EButtonGroup(type: connected, selectionRequired: true)`. **From M3:** segmented buttons are no longer recommended; connected button groups replace them. **My design decision:** tonal style. |
| Expanded rail at 600dp | Rail is `collapsed` for 600–839dp and `expanded` at ≥840dp. **From M3:** medium windows use the 96dp collapsed rail; 220–360dp expanded rails belong to expanded windows. |
| `fontSize: 9` override / non-M3E dialog text | Type size left at `labelSmall`; relapse dialog uses `M3ETheme.typography.baseline.bodyMedium`. **From M3:** avoid changing type size when customizing. |

### Test note

`M3EButtonGroup` always builds an offstage measurement copy of each labeled
action. Widget tests therefore see two `Text` nodes per label and target the
visible copy with `.first`. This is a package behavior, not an app bug.

### Verification

`flutter analyze` clean; `flutter test` passes (525 tests), including the new
`test/core/app_surfaces_test.dart` contrast assertions and the 48dp stepper
target check in `test/features/today_measurable_test.dart`.

### Reviewed and intentionally left as design decisions

- Hand-built tag chips (`task_card.dart`) and count badges (`today_screen.dart`)
  use custom geometry rather than M3 chip/badge tokens. They are informational,
  not primary actions; remapping them would change visual identity without a
  usability gain.
- Low-alpha accent card borders (`AppSurfaces.accentBorder`) and accent progress
  fills remain accents-as-*fills*. The card fill already provides the boundary,
  so the border is decorative rather than a target outline.
- Per-entity colors in confetti, quick-add tags, and progress bars.

Still explicit design decisions (M3 publishes no values): the celebration
spring, 18dp/8dp entrance rises, 60ms stagger, 16dp CTA gap, per-entity color
palettes, and the reduce-motion scheme swap.

## M3E audit remediation (2026-11-25)

A second, independent sweep checked the implementation against the published
spring-role rules (spatial for geometry, effects for opacity/color), touch
target sizes, and per-entity contrast. Earlier audits above were correct that
no ad-hoc curves or controllers exist, but **token selection** was wrong in
several places.

### Fixed — From M3

| Finding | Resolution |
| --- | --- |
| Opacity driven by spatial springs in `SpringEntrance`, `SpringSwitcher`, `MorphingShape`, `CheckPill`, `HabitHeatmap`, `YearHeatmap`, `StreakOdometer`, `TodayProgressRing` | Each now has a separate critically damped effects controller for opacity/color; spatial controllers keep geometry. `SpringEntrance`'s doc comment now matches its implementation. |
| Ring burst alpha derived from the overshooting burst spring, and the ring color snapping between primary/tertiary | Burst scale/rotation stay spatial; alpha uses `effectsSlow` and the color lerp uses `effectsFast`. |
| `CheckPill` 32dp tap target in tasks, habits and Today | 32dp visual retained, gesture box is now 48×48dp (new `hitSize`, default 48). |
| Year heatmap's ~4dp tappable cells | Cells are visual semantics nodes; one grid-level gesture maps the tap position to a day, so the grid — not a 4dp square — is the target. Month grid keeps per-day taps and its whole tile is now the hit area. |
| White check icon over mint/amber/green habit fills (1.8–2.5:1) | Uses `AppSurfaces.onAccent` instead of `onPrimary`; ≥3:1 for all brand accents. |
| Quit-habit relapse icon used raw habit color on surface | Uses `colorScheme.error`. |
| Non-token corner radii (6, 5, 4, 3, 2dp) | Added `AppShape.xsmall` (4) and `AppShape.small` (8) tokens; all accent bars, chart bars, heatmap cells and tiny progress tracks now use the scale. |
| Onboarding `Column` + `Spacers` overflowed at 2× text / 320dp | `LayoutBuilder` + `SingleChildScrollView` + `ConstrainedBox(minHeight)`, `Wrap` button row, and M3E card rows instead of `ListTile`. |
| Three stats tiles cramped at large text | Stacked below 360dp or above 1.3× text scale. |

### My design decision (not in M3)

- The year heatmap's tap-position → day mapping (rather than removing editing
  from the overview entirely).
- `AppShape.xsmall` / `AppShape.small` naming for the 4dp/8dp scale steps.
- The 1.3× text-scale / 360dp breakpoint for stacking the summary tiles.
- `M3ECard`'s own expand/on-press animation still uses the package default
  (`M3EMotion.short4` + `M3EMotion.standard`, lines 561-562 of M3E 1.2.3). The
  widget exposes only `animationDuration`/`animationCurve` — no spring override —
  so matching the app's spring system would require replacing the component.
  It already honors `MediaQuery.disableAnimations`, so this remains a package
  default rather than an app-level regression.

### Verification

`flutter analyze` clean; `flutter test` passes (528 tests), including the new
`test/features/m3e_compliance_test.dart` (48dp check target and ≥3:1 accent
icon contrast) and a 2× text / 320dp onboarding overflow regression.

## Liveliness pass (2026-11-25)

A second user-facing pass added ambient motion and two UX changes. The existing
spring rules still apply to *state changes*; continuous idle motion is a
separate category.

### From M3

- `M3EProgressIndicator.linearWavy` replaces the flat linear indicators in
  habit insights and stats. M3 explicitly offers wavy progress indicators for
  a more expressive tone, with the waveform scaling to the indicator size.
  Under reduced motion `waveSpeed` is 0, so the shape stays but does not travel.
- The Today FAB uses `M3EFabMenu` (2–6 related actions), and the empty state no
  longer duplicates its "New task" action as a second button.
- Nav icons keep M3E's own 1.08 scale pop; the added tilt is a small, one-shot
  spring on selection, skipped under reduced motion.
- Headings/titles/labels use heavier steps of Nunito's variable `wght` axis;
  body text stays at 500 so large text remains legible.

### My design decision (not in M3)

- **Ambient motion is time-based, not spring-based.** A spring settles, which
  makes a looping drift read as stiff. `AmbientClock` supplies monotonic
  seconds, so background shapes drift on two sine frequencies, the empty-state
  center rotates while satellites orbit and breathe, and the progress ring's
  wiggle travels at a steady tempo. Different frequencies never jump at a loop
  boundary because the clock never wraps. All of it freezes under reduced
  motion and pauses off-tab via go_router's `TickerMode`.
- The backdrop is decoration only: low-alpha fills, `IgnorePointer`,
  `ExcludeSemantics`, and no text layered on top.
- The FAB is Today's only creation affordance: the bottom quick-add text field
  was removed so it cannot compete with the FAB for the same corner. The
  `QuickAddBar` widget and its natural-language parser remain in the codebase
  for reuse, but are no longer mounted on the dashboard.
- Task notes collapse behind "Add notes" and expand automatically when editing
  a task that already has one; empty notes still save as `null`.

### Verification

`flutter analyze` clean; full suite green, with new regressions for the FAB
menu, optional notes, and the ambient clock's start/stop behavior.

## Fresh full M3E audit (2026-11-25, third pass)

An independent, source-checked sweep of all 50 Dart files in `lib/` (~13.7k
LOC), run as three parallel audits: Today/Tasks/shell, Habits/Onboarding, and
Stats/Settings/Search plus shared theme/motion utilities. Earlier audits were
treated as prior evidence only. **38 findings were confirmed and resolved.**
Every number below comes from the M3E references in the `m3-expressive` skill;
items not published by M3 are labelled explicitly.

### Fixed — From M3

| Finding | Resolution / published rule |
| --- | --- |
| Today's FAB menu was paired with a navigation rail at ≥600dp | Today now uses a single plain `M3EFab` for "New task" at every width, prefilled with today's date; the FAB menu was dropped. **From M3:** use a FAB menu only when many kinds of action belong to the button (`components/fabs.md`). "New habit" remains on the Habits destination's own FAB. |
| Paused-habit icon used the raw habit color as a foreground (~1.7–2.4:1 on light surface) | Switched to `onSurfaceVariant`. **From M3:** container roles are fills, never text/icons; graphics need 3:1 (`color.md`, `tokens.md`). |
| `_AmountBar` was a hand-built static 5dp bar with no stop indicator or semantics | Replaced with `M3EProgressIndicator.linearWavy`. **From M3:** wavy is an M3 Expressive configuration; default track thickness 4dp; waveform scales with size; active indicator = primary; track = secondary container (package default); 4dp stop indicator when track contrast is under 3:1; descriptor label for the process; reduced motion stops the wave. |
| Ring grew to 264dp at 2× text scale | Clamped to 240dp. **From M3:** circular indicators range 24–240dp (`components/feedback.md`). |
| Per-entity colors used as icon/dot/swatch foregrounds across archived habits, onboarding, editor, leaderboard, routine dots, search results, vacation scope tiles (1.3–2.7:1) | Added `AppSurfaces.graphic`, which keeps the hue only when it clears 3:1 on its own wash and falls back to `onSurfaceVariant`. **From M3:** 3:1 for graphics; `on *` roles are the guaranteed pairs. |
| Raw tag colors used as chart slices/legend swatches could fall below 3:1 | Added `AppSurfaces.fill`, blending toward `onSurface` until 3:1 is met. **From M3:** data-viz graphics still follow the 3:1 minimum. |
| Active progress fills used raw per-entity colors (~1.4–2.7:1) | Progress indicators now use `primary` for the active fill; per-entity colors remain in icon washes. **From M3:** active indicator = primary (`components/feedback.md` §6). |
| Sub-48dp targets: completion rows (36dp), search result cards (44dp), routine color swatch (28dp), editor icon/color choices (44/36dp), M3E chips (32dp), month-grid cells (~35dp) | Added a 48dp minimum to the completion row, 12dp vertical card padding, 48dp hit boxes around the swatch/icon/color choices, a `ChipHitArea` transparent extension behind chips, and a horizontally scrollable month grid with 48dp tiles. **From M3:** touch targets at least 48 × 48dp (`foundations.md`). |
| Weekday chip row overflowed at 320dp | `Row` → `Wrap` with 6dp spacing. **From M3:** layouts reflow when space changes; chips that don't fit must show all options (`layout.md`, `components/input.md`). |
| Missed-day dialog had three actions; confirmations used default filled buttons | Dialog now has two text-button actions (cancel + apply) with freeze/backfill as selections in the content; all dialog confirmations use `M3EButtonStyle.text`. **From M3:** basic dialogs have at most two actions, shown as text buttons (`components/containment.md`). |
| Settings/vacation switches and routine reorder buttons had no descriptive accessibility label; color swatches were unlabelled | Wrapped switches in `Semantics(label: …)`, added `routineMoveUp`/`routineMoveDown`/`routineColorOption` strings in en+es, and labelled the swatches. **From M3:** icon-only actions and controls need descriptive labels (`components/buttons.md`, `components/input.md`). |
| Search used a plain outlined text field | Replaced with `M3ESearchBar`. **From M3:** search uses the contained style and expands on focus (`components/input.md`). |
| Non-token radii: literal 999 chip corners, a 2dp confetti radius, a continuously computed 1–3dp heatmap radius, a 20dp chip | Swapped to `AppShape.pill`/`xsmall`/`small`, and to scale steps only (0 or 4dp) in the heatmap. **From M3:** the 10-step scale is 0/4/8/12/16/20/28/32/48/full; use tokens, not literal dp (`tokens.md`, `foundations.md`). |
| Filter row used physical `Alignment.centerLeft` | Changed to `AlignmentDirectional.centerStart`. **From M3:** spacing and alignment use leading/trailing so they mirror in RTL (`layout.md`, `foundations.md`). |
| Informational labels used emphasized type (routine count, weekly goal) | Moved to the baseline scale. **From M3:** emphasized styles are for selection, actions, headlines and editorial (`typography.md`). |
| Insights progress announced only a percentage; routine comparison round-tripped a role color through ARGB int | Descriptive `a11yInsightProgress` label; `CompletionRow` now takes a `Color` role directly. **From M3:** progress labels describe the process; apply color roles rather than static values. |

### My design decision (not in M3)

- `ChipHitArea` keeps the M3E chip's 32dp visual and its own semantics/keyboard
  activation, and puts a transparent `GestureDetector` *behind* it so the
  extended padding forwards taps to the same callback without double-firing.
- `AppSurfaces.graphic` / `AppSurfaces.fill` threshold logic (3:1 against the
  tinted/container background, stepping toward `onSurface` only for fills).
  M3 publishes the contrast floor but no fallback algorithm for user-chosen
  per-entity colors.
- The missed-day dialog's choice-in-content + Apply pattern (M3 fixes the
  action count, not how three mutually exclusive outcomes are offered).
- A 372dp horizontally scrollable month grid (7 × 48dp + 6 × 6dp gaps), so 48dp
  day targets never shrink on a 320dp window.
- The animated bar keeps the existing per-entity identity in the habit icon
  and card wash, while the indicator itself follows M3's role mapping.

### Verification

`flutter analyze` clean; `flutter test` passes **539 tests** (up from 531),
including new regressions for the animated wavy bar and its reduced-motion
freeze, contrast floors for `graphic`/`fill`, the 48dp chip hit area, the
rail-width FAB rule, and the two-action freeze dialog.

## Ambient backdrop + animated progress pass (2026-11-25)

A follow-up pass on the two remaining "flat" areas: the decorative shapes only
existed on Today, and the M3E wavy indicators drew a waveform but jumped
between values.

### From M3

- `M3EProgressIndicator.linearWavy` is the expressive determinate shape; the
  package supplies its token geometry (4dp track, 40dp wavelength, 4dp stop,
  10dp container) and animates the wave phase. **From M3:** determinate
  indicators fill 0%→100%; wavy is the expressive shape option and the waveform
  scales with size (`components/feedback.md` §5).
- Reduced motion renders the **flat** linear variant rather than a wavy bar with
  `waveSpeed: 0`. The visual result is the same, but the package's repeating
  wave ticker is no longer left running with nothing to show.
- The backdrop stays decoration-only: low-alpha fills, `IgnorePointer`,
  `ExcludeSemantics`, never behind text, frozen under reduced motion. **From
  M3:** abstract shapes are for decorative/image elements only and must be used
  sparingly (`shape.md`).

### My design decision (not in M3)

- `AmbientBackdrop` (extracted from `TodayBackdrop`) is mounted once in
  `AppShell` behind the content of all four tabs, so the decorative motion is
  consistent and no screen paints it twice. It stays behind content only — not
  under the navigation bar or rail. The four branch screens therefore use a
  transparent `Scaffold` background so the shell's backdrop is not occluded;
  pushed detail routes keep their own opaque backgrounds.
- Each backdrop shape now also morphs slowly between a pair of M3 shapes on a
  28s cosine cycle, in addition to the drift/rotation/breathe on the 42s
  clock. Drift reach grew from 16dp to 22dp so the motion is perceptible. M3
  publishes no ambient morph period, drift amplitude or choreography values.
- `SpringWavyProgressBar` springs the indicator's `value` with `spatialDefault`
  (fill is a geometry change) and retargets in flight on a scheme switch. Under
  reduced motion the target value is used directly.
- The Today hero keeps the ring on the trailing edge at every width, with the
  ring diameter capped at half the available width (240dp absolute) and its
  label scaled down to fit at 2× text. M3 pins circular indicators to 24–240dp
  but publishes no breakpoint for stacking or label fitting.

### Verification

`flutter analyze` clean; full `flutter test` green (544 tests). New regressions cover the
spring fill, its reduced-motion flat fallback, rapid retargeting, and a 320dp /
2× text-scale Today layout that previously could crowd the header. The perf
suite should be re-run after the ambient morph (three cached `Morph` paths per
frame); if its p90 frame budget regresses, drop the morph and keep the enlarged
drift.
