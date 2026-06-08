import Foundation

// This file is shared between the app target and the widget extension target.
// It defines the small, Codable snapshot the app writes to the App Group container
// and the widget reads to render "today's reminders".

/// Identifiers shared by the app and the widget.
enum WidgetSharedConstants {
    static let appGroup = "group.com.reminderbuddyjp.app"
    static let snapshotFilename = "widget-snapshot.json"
    static let widgetKind = "ReminderBuddyWidget"
}

/// A single reminder as shown on the widget (minimal fields only — no PII beyond a title).
struct WidgetReminder: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let dueDate: Date?
    let isOverdue: Bool
    let assigneeName: String?
}

/// The full snapshot the app publishes for the widget.
struct WidgetSnapshot: Codable, Hashable {
    var generatedAt: Date
    var todayCount: Int
    var overdueCount: Int
    /// The items to display (already trimmed/sorted by the app).
    var items: [WidgetReminder]

    static let empty = WidgetSnapshot(generatedAt: .distantPast, todayCount: 0, overdueCount: 0, items: [])
}

/// Reads/writes the widget snapshot in the shared App Group container.
/// Used by the app (write) and the widget (read).
enum WidgetSharedStore {

    private static var containerURL: URL? {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: WidgetSharedConstants.appGroup)
    }

    private static var fileURL: URL? {
        containerURL?.appendingPathComponent(WidgetSharedConstants.snapshotFilename)
    }

    static func write(_ snapshot: WidgetSnapshot) {
        guard let fileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Non-fatal: the widget just shows its last known (or empty) state.
        }
    }

    static func read() -> WidgetSnapshot {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return .empty
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }
}
