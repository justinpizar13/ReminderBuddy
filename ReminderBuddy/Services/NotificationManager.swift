import Foundation
import UserNotifications

/// Handles all user-facing notifications:
///  1. Due-date reminders (scheduled locally when a task has a due date).
///  2. "Activity" alerts raised after a CloudKit push tells us the partner changed something.
@MainActor
final class NotificationManager: NSObject, ObservableObject {

    static let shared = NotificationManager()

    @Published private(set) var isAuthorized = false

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    // MARK: Authorization

    func requestAuthorization() async {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    // MARK: Due-date reminders

    /// Schedules (or reschedules) a local reminder for a task's due date.
    func scheduleDueReminder(for task: ReminderTask) {
        cancelDueReminder(for: task.id)
        guard let dueDate = task.dueDate, dueDate > Date(), !task.isComplete else { return }

        let content = UNMutableNotificationContent()
        content.title = "Reminder: \(task.title)"
        content.body = task.details.isEmpty ? "This task is due." : task.details
        content.sound = .default
        content.threadIdentifier = "due-reminders"

        let triggerComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: dueDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        let request = UNNotificationRequest(identifier: dueID(task.id), content: content, trigger: trigger)
        center.add(request)
    }

    func cancelDueReminder(for taskID: String) {
        center.removePendingNotificationRequests(withIdentifiers: [dueID(taskID)])
    }

    private func dueID(_ taskID: String) -> String { "due-\(taskID)" }

    // MARK: Daily summary ("due today" each morning)

    private static let summaryPrefix = "daily-summary-"
    /// How many days ahead to pre-schedule morning summaries for.
    private static let summaryHorizonDays = 14

    /// Rebuilds the morning "due today" summaries for the next two weeks based on the
    /// current tasks. Each day's notification is computed individually so the count and
    /// titles are accurate. Call whenever tasks change, when settings change, or on launch.
    ///
    /// - Parameters:
    ///   - tasks: the full task list (completed tasks are ignored).
    ///   - enabled: whether the user has the daily summary turned on.
    ///   - hour/minute: local time of day to deliver the summary.
    func rescheduleDailySummaries(tasks: [ReminderTask],
                                  enabled: Bool,
                                  hour: Int,
                                  minute: Int,
                                  calendar: Calendar = .current) {
        // Clear any previously scheduled summaries first.
        cancelDailySummaries()
        guard enabled else { return }

        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)

        for offset in 0..<Self.summaryHorizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday),
                  var fireComponents = dayComponents(day, hour: hour, minute: minute, calendar: calendar),
                  let fireDate = calendar.date(from: fireComponents) else { continue }

            // Don't schedule a time that has already passed today.
            if fireDate <= now { continue }

            let dueThatDay = tasks.filter { task in
                guard !task.isComplete, let due = task.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: day)
            }
            // Only schedule a summary on days that actually have tasks.
            guard !dueThatDay.isEmpty else { continue }

            let content = UNMutableNotificationContent()
            content.title = offset == 0 ? "Due Today" : "Reminders for \(Self.weekdayName(day, calendar: calendar))"
            content.body = summaryBody(for: dueThatDay)
            content.sound = .default
            content.threadIdentifier = "daily-summary"
            content.badge = NSNumber(value: dueThatDay.count)

            fireComponents.second = 0
            let trigger = UNCalendarNotificationTrigger(dateMatching: fireComponents, repeats: false)
            let request = UNNotificationRequest(
                identifier: "\(Self.summaryPrefix)\(offset)", content: content, trigger: trigger)
            center.add(request)
        }
    }

    func cancelDailySummaries() {
        let ids = (0..<Self.summaryHorizonDays).map { "\(Self.summaryPrefix)\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    private func dayComponents(_ day: Date, hour: Int, minute: Int, calendar: Calendar) -> DateComponents? {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        comps.hour = hour
        comps.minute = minute
        return comps
    }

    private func summaryBody(for tasks: [ReminderTask]) -> String {
        if tasks.count == 1 {
            return tasks[0].title
        }
        // List up to three titles, then summarize the rest.
        let titles = tasks.prefix(3).map(\.title)
        let listed = titles.joined(separator: ", ")
        let remaining = tasks.count - titles.count
        if remaining > 0 {
            return "\(tasks.count) reminders: \(listed) +\(remaining) more"
        }
        return "\(tasks.count) reminders: \(listed)"
    }

    private static func weekdayName(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter.string(from: date)
    }

    // MARK: Activity alerts (partner made a change)

    /// Raises an immediate local notification summarizing a change made by the partner.
    /// We compare a freshly-fetched snapshot against the previous one to decide the message.
    func notifyActivity(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = "activity"

        // Fire (almost) immediately.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "activity-\(UUID().uuidString)", content: content, trigger: trigger)
        center.add(request)
    }
}

// MARK: - Foreground presentation

extension NotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banners + play sound even when the app is in the foreground.
        [.banner, .sound, .list]
    }
}
