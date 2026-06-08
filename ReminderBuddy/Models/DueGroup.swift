import Foundation

/// A time bucket used by the Upcoming view to group tasks by their due date.
enum DueGroup: Int, CaseIterable, Identifiable, Hashable {
    case overdue
    case today
    case tomorrow
    case thisWeek
    case later
    case noDate

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .overdue:  return "Overdue"
        case .today:    return "Today"
        case .tomorrow: return "Tomorrow"
        case .thisWeek: return "This Week"
        case .later:    return "Later"
        case .noDate:   return "No Due Date"
        }
    }

    var systemImage: String {
        switch self {
        case .overdue:  return "exclamationmark.circle"
        case .today:    return "sun.max"
        case .tomorrow: return "sunrise"
        case .thisWeek: return "calendar"
        case .later:    return "calendar.badge.clock"
        case .noDate:   return "tray"
        }
    }

    /// Classifies a task into a bucket relative to `now`.
    /// Completed tasks are intentionally excluded by the caller, not here.
    static func group(for dueDate: Date?, now: Date = Date(), calendar: Calendar = .current) -> DueGroup {
        guard let dueDate else { return .noDate }

        if dueDate < now && !calendar.isDate(dueDate, inSameDayAs: now) {
            // Earlier calendar day than today => overdue.
            return .overdue
        }
        if calendar.isDateInToday(dueDate) {
            // If the time already passed today, still treat as Today (it reads better than Overdue).
            return .today
        }
        if calendar.isDateInTomorrow(dueDate) {
            return .tomorrow
        }
        // Within the next 7 days (and after tomorrow) => This Week.
        if let weekAhead = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)),
           dueDate < weekAhead {
            return .thisWeek
        }
        return .later
    }
}

/// A section of tasks for the Upcoming view.
struct DueSection: Identifiable {
    let group: DueGroup
    var tasks: [ReminderTask]
    var id: Int { group.rawValue }
}
