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

// MARK: - ReminderTask

/// A shared task/reminder.
struct ReminderTask: Identifiable, Hashable {
    var id: String              // recordName of the CKRecord
    var title: String
    var details: String
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

// MARK: - AppUser

/// The locally-known identity of the signed-in person (from Sign in with Apple).
struct AppUser: Codable, Equatable {
    var userID: String          // stable Apple user identifier
    var displayName: String
}
