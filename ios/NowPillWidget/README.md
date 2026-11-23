# NowPillWidget (iOS home-screen widget)

WidgetKit extension source for the NowPill today-summary widget (Phase 15).
**Building and signing requires macOS + Xcode** — this folder ships the Swift
sources and integration steps; the extension target is not auto-wired into the
Xcode project from Linux.

## Files
- `NowPillWidget.swift` — timeline provider + SwiftUI view. Reads the snapshot
  from the shared App Group `UserDefaults` and renders progress + top streak.

## Integration steps (on a Mac)
1. In Xcode, add a **Widget Extension** target named `NowPillWidget` to the
   Runner project. Replace the generated Swift file with `NowPillWidget.swift`.
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

## Snapshot contract
The JSON matches `WidgetSnapshot.toJson()` (Dart): `done`, `total`, `remaining`,
`allDone`, `topStreak`, `topHabitName`, `dateKey`, `updatedAtMillis`.
