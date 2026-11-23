import WidgetKit
import SwiftUI

// NowPill home-screen widget (Phase 15). Reads the today-summary snapshot the
// Flutter app writes into the shared App Group container and renders progress
// plus the top habit streak. Tapping deep-links into the app.
//
// NOTE: Building/signing this extension requires macOS + Xcode. Add the
// NowPillWidget extension target in Xcode (see README.md in this folder),
// enable the App Group "group.app.nowpill" on both Runner and this target.

/// Shared container identifiers. Must match the App Group entitlement on the
/// Runner target and the value WidgetBridgeService writes on the Flutter side.
enum NowPillWidgetConfig {
    static let appGroup = "group.app.nowpill"
    static let snapshotKey = "nowpill_widget_snapshot"
    static let kind = "app.nowpill.today"
}

/// Decoded today-summary snapshot (mirrors WidgetSnapshot.toJson in Dart).
struct TodaySnapshot {
    var done: Int = 0
    var total: Int = 0
    var remaining: Int = 0
    var allDone: Bool = false
    var topStreak: Int = 0
    var topHabitName: String = ""
    var dateKey: String = ""

    static func load() -> TodaySnapshot {
        guard
            let defaults = UserDefaults(suiteName: NowPillWidgetConfig.appGroup),
            let json = defaults.string(forKey: NowPillWidgetConfig.snapshotKey),
            let data = json.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return TodaySnapshot()
        }
        var s = TodaySnapshot()
        s.done = obj["done"] as? Int ?? 0
        s.total = obj["total"] as? Int ?? 0
        s.remaining = obj["remaining"] as? Int ?? 0
        s.allDone = obj["allDone"] as? Bool ?? false
        s.topStreak = obj["topStreak"] as? Int ?? 0
        s.topHabitName = obj["topHabitName"] as? String ?? ""
        s.dateKey = obj["dateKey"] as? String ?? ""
        return s
    }

    var percent: Double {
        total <= 0 ? 0 : Double(done) / Double(total)
    }
}

struct NowPillEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot
}

struct NowPillTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowPillEntry {
        NowPillEntry(date: Date(), snapshot: TodaySnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPillEntry) -> Void) {
        completion(NowPillEntry(date: Date(), snapshot: TodaySnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPillEntry>) -> Void) {
        let entry = NowPillEntry(date: Date(), snapshot: TodaySnapshot.load())
        // Reload periodically; the app also reloads timelines on each push.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct NowPillWidgetEntryView: View {
    var entry: NowPillEntry
    @Environment(\.widgetFamily) var family

    private var subtitle: String {
        let s = entry.snapshot
        if s.total == 0 { return "A clear day ahead" }
        if s.allDone { return "All done — enjoy your day!" }
        return "\(s.remaining) to go"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("NowPill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Color(red: 0.18, green: 0.83, blue: 0.66))
                Spacer()
                Text("\(entry.snapshot.done)/\(entry.snapshot.total)")
                    .font(.system(size: 20, weight: .bold))
            }
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            ProgressView(value: entry.snapshot.percent)
                .tint(Color(red: 0.18, green: 0.83, blue: 0.66))
            if entry.snapshot.topStreak > 0 {
                Text("🔥 \(entry.snapshot.topStreak) · \(entry.snapshot.topHabitName)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(red: 1.0, green: 0.42, blue: 0.37))
            } else {
                Text("Build your first streak")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .widgetURL(URL(string: "nowpill://today"))
    }
}

@main
struct NowPillWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: NowPillWidgetConfig.kind,
            provider: NowPillTimelineProvider()
        ) { entry in
            NowPillWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("NowPill Today")
        .description("Today's habit and task progress at a glance.")
        .supportedFamilies([.systemMedium])
    }
}
