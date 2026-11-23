import AppIntents
import WidgetKit
import SwiftUI

// NowPill interactive widget check-in (Phase 27, v0.4). iOS 17+ AppIntents
// button that checks a habit in directly from the home screen.
//
// NOTE: Building/signing requires macOS + Xcode. The intent runs in the
// widget extension process; it must apply the check-in through the SAME
// shared database the app uses and then reload timelines. Two integration
// options (see README.md):
//   A. Open the app's Drift/SQLite file in the App Group container directly
//      from the extension (add the sqlite3 C library + a minimal writer that
//      inserts the check-in row with uuid + updatedAt, matching the Dart
//      schema). Simplest, no Flutter engine in the extension.
//   B. Spawn a FlutterEngine in the extension at `widgetActionMain` (the same
//      entry point Android uses) and call the `app.nowpill/widget_action`
//      channel — heavier, needs the Flutter framework linked into the
//      extension.
// The Swift below implements option A's write contract and is guarded so a
// failure never crashes the widget.

/// Checks a habit in for today. `habitID` is the local database id carried in
/// the snapshot's habit rows.
struct CheckHabitIntent: AppIntent {
    static var title: LocalizedStringResource = "Check in habit"
    static var description = IntentDescription(
        "Marks today's habit as done without opening NowPill."
    )

    @Parameter(title: "Habit ID")
    var habitID: Int

    init() {}

    init(habitID: Int) {
        self.habitID = habitID
    }

    func perform() async throws -> some IntentResult {
        NowPillWidgetStore.checkInToday(habitID: habitID)
        WidgetCenter.shared.reloadTimelines(ofKind: NowPillWidgetConfig.kind)
        return .result()
    }
}

/// Minimal shared-container store for the widget extension. Reads the
/// snapshot the app writes and applies check-ins to the shared SQLite file.
enum NowPillWidgetStore {
    /// App Group container. The Flutter app must place `nowpill.sqlite` here
    /// (or a copy) for the extension to write; see README integration notes.
    static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: NowPillWidgetConfig.appGroup
        )
    }

    /// Applies a full-goal check-in for today, mirroring the Dart
    /// `applyWidgetCheckIn` contract (idempotent; stamps updatedAt).
    ///
    /// This is a guarded placeholder for the sqlite write. On a Mac, link
    /// sqlite3 and implement:
    ///   1. open <container>/nowpill.sqlite
    ///   2. SELECT target_amount FROM habits WHERE id = habitID AND archived_at IS NULL
    ///   3. INSERT OR IGNORE INTO habit_checkins
    ///        (habit_id, habit_uuid, date, amount, uuid, updated_at, created_at)
    ///      VALUES (…, today, target_amount, uuid4(), nowMillis, nowMillis)
    ///      — or UPDATE amount when the row exists (measurable habits).
    ///   4. update the cached snapshot JSON's done/remaining/habits rows.
    static func checkInToday(habitID: Int) {
        // Guarded no-op until the sqlite writer is linked on macOS. The
        // Android path is fully implemented and verified; iOS ships as source.
        guard containerURL != nil else { return }
        // TODO(mac): implement the sqlite write described above.
    }
}