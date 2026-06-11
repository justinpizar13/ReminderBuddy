import Foundation
import CloudKit

// MARK: - Category

/// A list/category that tasks can be grouped into (e.g. Groceries, Bills, Errands).
struct TaskCategory: Identifiable, Hashable {
    var id: String              // recordName of the CKRecord
    var name: String
    var colorHex: String        // stored as a hex string so we can render a swatch
    var sortIndex: Int

    static let recordType = "Category"

    init(id: String = UUID().uuidString,
         name: String,
         colorHex: String = "#4F8EF7",
         sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.sortIndex = sortIndex
    }
}

// MARK: - Recurrence

/// How often a task repeats. A recurring task spawns its next occurrence when completed.
enum Recurrence: String, CaseIterable, Identifiable, Hashable {
    case none
    case daily
    case weekly
    case monthly
    case yearly

    var id: String { rawValue }

    /// Human-friendly label for pickers and badges.
    var label: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    /// Short label used in compact UI (rows/badges).
    var shortLabel: String {
        switch self {
        case .none: return ""
        case .daily: return "Daily"
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        }
    }

    var isRepeating: Bool { self != .none }

    /// Advances a date by one interval of this recurrence. Returns nil for `.none`.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let component: Calendar.Component
        switch self {
        case .none:    return nil
        case .daily:   component = .day
        case .weekly:  component = .weekOfYear
        case .monthly: component = .month
        case .yearly:  component = .year
        }
        return calendar.date(byAdding: component, value: 1, to: date)
    }
}

// MARK: - ItemKind

/// Whether an item is a to-do you complete, or an event you're simply reminded of.
/// Events still appear in Upcoming/Calendar by date, but have no completion checkbox
/// and never recur-on-complete.
enum ItemKind: String, CaseIterable, Identifiable, Hashable {
    case reminder
    case event

    var id: String { rawValue }

    /// Title used for pickers and segmented controls.
    var label: String {
        switch self {
        case .reminder: return "Reminder"
        case .event:    return "Event"
        }
    }

    var systemImage: String {
        switch self {
        case .reminder: return "checklist"
        case .event:    return "calendar"
        }
    }

    var isEvent: Bool { self == .event }
}

// MARK: - ReminderTask

/// A shared task/reminder.
struct ReminderTask: Identifiable, Hashable {
    var id: String              // recordName of the CKRecord
    var title: String
    var details: String
    var kind: ItemKind          // a completable reminder, or an event you're reminded of
    var isComplete: Bool
    var dueDate: Date?
    var categoryID: String?     // recordName of the owning Category, if any
    var assignedTo: String?     // stable user id (Sign in with Apple) of the assignee
    var recurrence: Recurrence  // how often this task repeats

    // Audit fields so each person can see who did what.
    var createdByName: String
    var createdByID: String
    var lastModifiedByName: String
    var completedByName: String?
    var createdAt: Date
    var updatedAt: Date

    static let recordType = "ReminderTask"

    init(id: String = UUID().uuidString,
         title: String,
         details: String = "",
         kind: ItemKind = .reminder,
         isComplete: Bool = false,
         dueDate: Date? = nil,
         categoryID: String? = nil,
         assignedTo: String? = nil,
         recurrence: Recurrence = .none,
         createdByName: String = "",
         createdByID: String = "",
         lastModifiedByName: String = "",
         completedByName: String? = nil,
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.details = details
        self.kind = kind
        self.isComplete = isComplete
        self.dueDate = dueDate
        self.categoryID = categoryID
        self.assignedTo = assignedTo
        self.recurrence = recurrence
        self.createdByName = createdByName
        self.createdByID = createdByID
        self.lastModifiedByName = lastModifiedByName
        self.completedByName = completedByName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - TaskNote

/// A note/comment attached to a task. Either partner can add notes.
struct TaskNote: Identifiable, Hashable {
    var id: String              // recordName of the CKRecord
    var taskID: String          // recordName of the parent ReminderTask
    var body: String
    var authorName: String
    var authorID: String
    var createdAt: Date

    static let recordType = "TaskNote"

    init(id: String = UUID().uuidString,
         taskID: String,
         body: String,
         authorName: String = "",
         authorID: String = "",
         createdAt: Date = Date()) {
        self.id = id
        self.taskID = taskID
        self.body = body
        self.authorName = authorName
        self.authorID = authorID
        self.createdAt = createdAt
    }
}

// MARK: - SharedInfoItem

/// A piece of shared reference information the household needs month to month —
/// e.g. a utility (internet, gas, water) with its dashboard link, account number,
/// and monthly price. This is reference data, not a task: nothing to complete.
struct SharedInfoItem: Identifiable, Hashable {
    var id: String              // recordName of the CKRecord
    var title: String           // e.g. "Internet — Xfinity"
    var detail: String          // free-form notes (login email, plan, etc.)
    var link: String            // dashboard / account URL
    var accountNumber: String   // account or customer number
    var monthlyPrice: Double?   // recurring cost per month, if any
    var sortIndex: Int

    // Audit fields, mirroring tasks so each person can see who added what.
    var createdByName: String
    var createdByID: String
    var lastModifiedByName: String
    var createdAt: Date
    var updatedAt: Date

    static let recordType = "SharedInfoItem"

    init(id: String = UUID().uuidString,
         title: String,
         detail: String = "",
         link: String = "",
         accountNumber: String = "",
         monthlyPrice: Double? = nil,
         sortIndex: Int = 0,
         createdByName: String = "",
         createdByID: String = "",
         lastModifiedByName: String = "",
         createdAt: Date = Date(),
         updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.link = link
        self.accountNumber = accountNumber
        self.monthlyPrice = monthlyPrice
        self.sortIndex = sortIndex
        self.createdByName = createdByName
        self.createdByID = createdByID
        self.lastModifiedByName = lastModifiedByName
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// A normalized URL for the link, if it can be made into one.
    /// Falls back to prepending https:// when the user typed a bare domain.
    var url: URL? {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let u = URL(string: trimmed), u.scheme != nil { return u }
        return URL(string: "https://\(trimmed)")
    }
}

// MARK: - AppUser

/// The locally-known identity of the signed-in person (from Sign in with Apple).
struct AppUser: Codable, Equatable {
    var userID: String          // stable Apple user identifier
    var displayName: String
}
