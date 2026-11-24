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
  `on surface variant` text — never accent-colored body text.
- App bar containers stay square; only the flexible variants are used.
- FABs use medium size on compact/medium windows and a medium extended FAB on
  expanded windows (≥840dp), matching M3 breakpoint guidance.

No new dependencies; the M3E pin remains 1.2.3.
