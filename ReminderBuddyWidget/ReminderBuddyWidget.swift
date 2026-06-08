import WidgetKit
import SwiftUI

// MARK: - Timeline entry

struct ReminderEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

// MARK: - Provider

struct ReminderProvider: TimelineProvider {
    func placeholder(in context: Context) -> ReminderEntry {
        ReminderEntry(date: Date(), snapshot: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReminderEntry) -> Void) {
        let snapshot = context.isPreview ? Self.sample : WidgetSharedStore.read()
        completion(ReminderEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReminderEntry>) -> Void) {
        let snapshot = WidgetSharedStore.read()
        let now = Date()
        let entry = ReminderEntry(date: now, snapshot: snapshot)

        // Refresh after the next hour boundary so "overdue/today" stays roughly accurate
        // even if the app doesn't push an update; the app also reloads us on changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    static let sample = WidgetSnapshot(
        generatedAt: Date(),
        todayCount: 3,
        overdueCount: 1,
        items: [
            WidgetReminder(id: "1", title: "Pay electric bill", dueDate: Date(), isOverdue: true, assigneeName: "Alex"),
            WidgetReminder(id: "2", title: "Buy groceries", dueDate: Date().addingTimeInterval(7200), isOverdue: false, assigneeName: nil),
            WidgetReminder(id: "3", title: "Call the plumber", dueDate: Date().addingTimeInterval(14400), isOverdue: false, assigneeName: "Sam")
        ])
}

// MARK: - Widget definition

struct ReminderBuddyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSharedConstants.widgetKind, provider: ReminderProvider()) { entry in
            ReminderBuddyWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Reminders")
        .description("See what's due today and what's overdue at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
