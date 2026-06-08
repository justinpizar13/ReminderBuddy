import Foundation
import SwiftUI
import CloudKit
import WidgetKit

/// Observable application state. Owns the synced data, performs change detection to
/// raise "your partner did X" notifications, and exposes intent methods to the UI.
@MainActor
final class TaskStore: ObservableObject {

    @Published private(set) var categories: [TaskCategory] = []
    @Published private(set) var tasks: [ReminderTask] = []
    @Published private(set) var notes: [TaskNote] = []

    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var isReady = false

    private let cloud = CloudKitService.shared
    private let notifications = NotificationManager.shared
    private unowned let auth: AuthManager
    private let summaryPrefs: SummaryPreferences

    /// Snapshot used to detect what changed between syncs (for activity notifications).
    private var lastTaskSnapshot: [String: ReminderTask] = [:]
    private var lastNoteIDs: Set<String> = []
    private var hasLoadedOnce = false

    init(auth: AuthManager, summaryPrefs: SummaryPreferences) {
        self.auth = auth
        self.summaryPrefs = summaryPrefs
    }

    private var me: AppUser? { auth.currentUser }

    // MARK: Lifecycle

    func start() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await cloud.bootstrap()
            isReady = true
            await refresh(announceChanges: false)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Refetches everything. When `announceChanges` is true (i.e. triggered by a push),
    /// we diff against the last snapshot and raise notifications for the partner's edits.
    func refresh(announceChanges: Bool) async {
        do {
            let result = try await cloud.fetchAll()
            if announceChanges && hasLoadedOnce {
                detectAndAnnounceChanges(newTasks: result.tasks, newNotes: result.notes)
            }
            categories = result.categories
            tasks = result.tasks.sorted(by: Self.taskSort)
            notes = result.notes
            updateSnapshot()
            reconcileDueReminders()
            hasLoadedOnce = true
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private static func taskSort(_ a: ReminderTask, _ b: ReminderTask) -> Bool {
        if a.isComplete != b.isComplete { return !a.isComplete && b.isComplete }
        switch (a.dueDate, b.dueDate) {
        case let (l?, r?): return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return a.createdAt > b.createdAt
        }
    }

    // MARK: Change detection (notifications when partner edits)

    private func detectAndAnnounceChanges(newTasks: [ReminderTask], newNotes: [TaskNote]) {
        let myID = me?.userID
        let newTaskMap = Dictionary(uniqueKeysWithValues: newTasks.map { ($0.id, $0) })

        // New tasks created by the other person.
        for task in newTasks where lastTaskSnapshot[task.id] == nil {
            guard task.createdByID != myID else { continue }
            notifications.notifyActivity(
                title: "New task added",
                body: "\(task.createdByName) added \"\(task.title)\"")
        }

        // Updated tasks (title/details/due/assignment/completion) by the other person.
        for task in newTasks {
            guard let old = lastTaskSnapshot[task.id] else { continue }
            guard task.lastModifiedByName != (me?.displayName ?? "") else { continue }
            if old.isComplete != task.isComplete && task.isComplete {
                notifications.notifyActivity(
                    title: "Task completed",
                    body: "\(task.completedByName ?? task.lastModifiedByName) completed \"\(task.title)\"")
            } else if hasMeaningfulEdit(old: old, new: task) {
                notifications.notifyActivity(
                    title: "Task updated",
                    body: "\(task.lastModifiedByName) updated \"\(task.title)\"")
            }
        }

        // New notes added by the other person.
        for note in newNotes where !lastNoteIDs.contains(note.id) {
            guard note.authorID != myID else { continue }
            let taskTitle = newTaskMap[note.taskID]?.title ?? "a task"
            notifications.notifyActivity(
                title: "New note",
                body: "\(note.authorName) commented on \"\(taskTitle)\"")
        }
    }

    private func hasMeaningfulEdit(old: ReminderTask, new: ReminderTask) -> Bool {
        old.title != new.title
            || old.details != new.details
            || old.dueDate != new.dueDate
            || old.assignedTo != new.assignedTo
            || old.categoryID != new.categoryID
            || old.recurrence != new.recurrence
    }

    private func updateSnapshot() {
        lastTaskSnapshot = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        lastNoteIDs = Set(notes.map(\.id))
    }

    private func reconcileDueReminders() {
        for task in tasks {
            notifications.scheduleDueReminder(for: task)
        }
        rescheduleDailySummaries()
        publishWidgetSnapshot()
    }

    /// Rebuilds the morning summary notifications from the current task list and prefs.
    /// Safe to call after any change to tasks or to the summary settings.
    func rescheduleDailySummaries() {
        notifications.rescheduleDailySummaries(
            tasks: tasks,
            enabled: summaryPrefs.isEnabled,
            hour: summaryPrefs.hour,
            minute: summaryPrefs.minute)
    }

    // MARK: Widget snapshot

    /// Publishes a small snapshot of overdue + today's incomplete reminders to the shared
    /// App Group container and asks WidgetKit to refresh. Called whenever tasks change.
    func publishWidgetSnapshot(now: Date = Date(), calendar: Calendar = .current) {
        let relevant = tasks.filter { task in
            guard !task.isComplete else { return false }
            let group = DueGroup.group(for: task.dueDate, now: now)
            return group == .overdue || group == .today
        }

        let overdueCount = relevant.filter {
            DueGroup.group(for: $0.dueDate, now: now) == .overdue
        }.count
        let todayCount = relevant.count - overdueCount

        // Overdue first, then by due time; cap the list for the widget.
        let sorted = relevant.sorted { lhs, rhs in
            (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }
        let items = sorted.prefix(8).map { task -> WidgetReminder in
            WidgetReminder(
                id: task.id,
                title: task.title,
                dueDate: task.dueDate,
                isOverdue: DueGroup.group(for: task.dueDate, now: now) == .overdue,
                assigneeName: widgetAssigneeName(for: task))
        }

        let snapshot = WidgetSnapshot(
            generatedAt: now,
            todayCount: todayCount,
            overdueCount: overdueCount,
            items: Array(items))

        WidgetSharedStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSharedConstants.widgetKind)
    }

    /// Best-effort display name for a task's assignee (for the widget).
    private func widgetAssigneeName(for task: ReminderTask) -> String? {
        guard let assignedTo = task.assignedTo else { return nil }
        if assignedTo == me?.userID { return me?.displayName }
        if let match = tasks.first(where: { $0.createdByID == assignedTo }) {
            return match.createdByName
        }
        return nil
    }

    // MARK: Notes helpers

    func notes(for task: ReminderTask) -> [TaskNote] {
        notes.filter { $0.taskID == task.id }.sorted { $0.createdAt < $1.createdAt }
    }

    func category(for task: ReminderTask) -> TaskCategory? {
        guard let id = task.categoryID else { return nil }
        return categories.first { $0.id == id }
    }

    func tasks(in category: TaskCategory?) -> [ReminderTask] {
        guard let category else { return tasks }
        return tasks.filter { $0.categoryID == category.id }
    }

    // MARK: Due-date grouping (Upcoming view)

    /// Groups incomplete tasks into time buckets for the Upcoming view.
    /// Tasks within a bucket are ordered by due date (then creation date for "No Due Date").
    /// Empty buckets are omitted. When `includeNoDate` is false, undated tasks are dropped.
    func upcomingSections(includeNoDate: Bool = true, now: Date = Date()) -> [DueSection] {
        let active = tasks.filter { !$0.isComplete }
        var buckets: [DueGroup: [ReminderTask]] = [:]

        for task in active {
            let group = DueGroup.group(for: task.dueDate, now: now)
            if group == .noDate && !includeNoDate { continue }
            buckets[group, default: []].append(task)
        }

        return DueGroup.allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            let sorted = items.sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (l?, r?): return l < r
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return lhs.createdAt > rhs.createdAt
                }
            }
            return DueSection(group: group, tasks: sorted)
        }
    }

    /// Tasks with a due date that falls on the given calendar day, sorted by time.
    func tasks(on day: Date, calendar: Calendar = .current) -> [ReminderTask] {
        tasks
            .filter { task in
                guard let due = task.dueDate else { return false }
                return calendar.isDate(due, inSameDayAs: day)
            }
            .sorted { lhs, rhs in
                (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
    }

    /// Map of start-of-day -> count of incomplete tasks due that day, for calendar dots.
    func incompleteCountsByDay(calendar: Calendar = .current) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for task in tasks where !task.isComplete {
            guard let due = task.dueDate else { continue }
            let key = calendar.startOfDay(for: due)
            counts[key, default: 0] += 1
        }
        return counts
    }

    /// Count of tasks that are overdue or due today — handy for a tab badge.
    func dueSoonCount(now: Date = Date()) -> Int {
        tasks.filter { task in
            guard !task.isComplete else { return false }
            let group = DueGroup.group(for: task.dueDate, now: now)
            return group == .overdue || group == .today
        }.count
    }

    // MARK: Intents — tasks

    func addTask(title: String,
                 details: String,
                 dueDate: Date?,
                 categoryID: String?,
                 assignedTo: String?,
                 recurrence: Recurrence = .none) async {
        guard let me else { return }
        let task = ReminderTask(
            title: title,
            details: details,
            dueDate: dueDate,
            categoryID: categoryID,
            assignedTo: assignedTo,
            recurrence: recurrence,
            createdByName: me.displayName,
            createdByID: me.userID,
            lastModifiedByName: me.displayName)
        await mutate {
            let saved = try await self.cloud.save(task: task)
            self.applyLocal(task: saved)
            self.notifications.scheduleDueReminder(for: saved)
        }
    }

    func updateTask(_ task: ReminderTask) async {
        guard let me else { return }
        var updated = task
        updated.lastModifiedByName = me.displayName
        updated.updatedAt = Date()
        await mutate {
            let saved = try await self.cloud.save(task: updated)
            self.applyLocal(task: saved)
            self.notifications.scheduleDueReminder(for: saved)
        }
    }

    func toggleComplete(_ task: ReminderTask) async {
        guard let me else { return }
        var updated = task
        updated.isComplete.toggle()
        updated.completedByName = updated.isComplete ? me.displayName : nil
        updated.lastModifiedByName = me.displayName
        updated.updatedAt = Date()
        await mutate {
            let saved = try await self.cloud.save(task: updated)
            self.applyLocal(task: saved)
            if saved.isComplete {
                self.notifications.cancelDueReminder(for: saved.id)
                // Completing a repeating task spawns its next occurrence.
                if let next = self.makeNextOccurrence(from: saved) {
                    let savedNext = try await self.cloud.save(task: next)
                    self.applyLocal(task: savedNext)
                    self.notifications.scheduleDueReminder(for: savedNext)
                }
            } else {
                self.notifications.scheduleDueReminder(for: saved)
            }
        }
    }

    /// Builds the next occurrence of a completed recurring task, advancing the due date
    /// by one interval. Returns nil for non-repeating tasks. The next occurrence is a
    /// brand-new (incomplete) task so the completed one stays as history.
    private func makeNextOccurrence(from completed: ReminderTask) -> ReminderTask? {
        guard completed.recurrence.isRepeating else { return nil }
        // Advance from the original due date when present, otherwise from now.
        let base = completed.dueDate ?? Date()
        guard let nextDue = completed.recurrence.nextDate(after: base) else { return nil }
        return ReminderTask(
            title: completed.title,
            details: completed.details,
            isComplete: false,
            dueDate: nextDue,
            categoryID: completed.categoryID,
            assignedTo: completed.assignedTo,
            recurrence: completed.recurrence,
            createdByName: completed.createdByName,
            createdByID: completed.createdByID,
            lastModifiedByName: me?.displayName ?? completed.lastModifiedByName)
    }

    func deleteTask(_ task: ReminderTask) async {
        await mutate {
            try await self.cloud.deleteTask(id: task.id)
            self.tasks.removeAll { $0.id == task.id }
            self.notes.removeAll { $0.taskID == task.id }
            self.notifications.cancelDueReminder(for: task.id)
            self.updateSnapshot()
            self.rescheduleDailySummaries()
            self.publishWidgetSnapshot()
        }
    }

    // MARK: Intents — notes

    func addNote(to task: ReminderTask, body: String) async {
        guard let me else { return }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = TaskNote(
            taskID: task.id,
            body: trimmed,
            authorName: me.displayName,
            authorID: me.userID)
        await mutate {
            let saved = try await self.cloud.save(note: note)
            self.notes.append(saved)
            self.lastNoteIDs.insert(saved.id)
        }
    }

    // MARK: Intents — categories

    func addCategory(name: String, colorHex: String) async {
        let category = TaskCategory(
            name: name,
            colorHex: colorHex,
            sortIndex: categories.count)
        await mutate {
            let saved = try await self.cloud.save(category: category)
            self.categories.append(saved)
            self.categories.sort { $0.sortIndex < $1.sortIndex }
        }
    }

    func deleteCategory(_ category: TaskCategory) async {
        await mutate {
            try await self.cloud.deleteCategory(id: category.id)
            self.categories.removeAll { $0.id == category.id }
            // Detach tasks from the deleted category locally.
            self.tasks = self.tasks.map { t in
                guard t.categoryID == category.id else { return t }
                var copy = t; copy.categoryID = nil; return copy
            }
        }
    }

    // MARK: Helpers

    private func applyLocal(task: ReminderTask) {
        if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[idx] = task
        } else {
            tasks.append(task)
        }
        tasks.sort(by: Self.taskSort)
        updateSnapshot()
        rescheduleDailySummaries()
        publishWidgetSnapshot()
    }

    private func mutate(_ work: @escaping () async throws -> Void) async {
        do {
            try await work()
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
