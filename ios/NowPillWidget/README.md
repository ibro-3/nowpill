# NowPillWidget (iOS home-screen widget)

WidgetKit extension source for the NowPill today-summary widget (Phase 15).
**Building and signing requires macOS + Xcode** — this folder ships the Swift
sources and integration steps; the extension target is not auto-wired into the
Xcode project from Linux.

## Files
- `NowPillWidget.swift` — timeline provider + SwiftUI view. Reads the snapshot
  from the shared App Group `UserDefaults` and renders progress + top streak.
- `CheckHabitIntent.swift` — iOS 17+ AppIntent for one-tap habit check-in from
  the widget (Phase 27), plus the shared-store write contract.

## Integration steps (on a Mac)
1. In Xcode, add a **Widget Extension** target named `NowPillWidget` to the
   Runner project. Replace the generated Swift file with `NowPillWidget.swift`
   and add `CheckHabitIntent.swift` to the same target.
2. Enable the **App Group** capability `group.app.nowpill` on **both** the
   Runner target and the NowPillWidget target.
3. The Flutter side must write the snapshot into that App Group and reload
   timelines. `WidgetBridgeService` (Dart) currently sends a MethodChannel
   message; on iOS, add a handler in `AppDelegate` that:
   - writes the JSON string to
     `UserDefaults(suiteName: "group.app.nowpill")` under
     `nowpill_widget_snapshot`, and
   - calls `WidgetCenter.shared.reloadTimelines(ofKind: "app.nowpill.today")`.
4. Handle the `nowpill://today` deep link in Runner to open the Today tab.
5. **Interactive check-in (Phase 27):** implement `NowPillWidgetStore.checkInToday`
   in `CheckHabitIntent.swift`. The extension runs in its own process, so it
   must write the shared SQLite file directly (link sqlite3):
   - place `nowpill.sqlite` in the App Group container (or point the app's
     `resolveDatabasePath` there on iOS),
   - insert/update today's `habit_checkins` row for the habit id, carrying
     `uuid`, `habit_uuid`, `amount = target_amount` (full goal), and a fresh
     `updated_at` so file sync merges it correctly,
   - update the cached snapshot JSON (done/remaining/habits rows) and reload
     timelines. The Android path (`WidgetActionReceiver` + `widgetActionMain`)
     is fully implemented and emulator-verified; iOS ships as source.

## Snapshot contract
The JSON matches `WidgetSnapshot.toJson()` (Dart): `done`, `total`, `remaining`,
`allDone`, `topStreak`, `topHabitName`, `dateKey`, `updatedAtMillis`, and
`habits` — an array of `{id, name, done, color, amount, target}` rows (v2).
