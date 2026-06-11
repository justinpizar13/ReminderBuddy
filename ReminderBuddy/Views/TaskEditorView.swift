import SwiftUI

/// Create or edit a task. Used both as a "new task" sheet and an "edit" sheet.
struct TaskEditorView: View {
    enum Mode {
        case create(defaultCategoryID: String?)
        case edit(ReminderTask)
    }

    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var auth: AuthManager
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var kind: ItemKind = .reminder
    @State private var title = ""
    @State private var details = ""
    @State private var hasDueDate = false
    @State private var dueDate = Date().addingTimeInterval(3600)
    @State private var categoryID: String?
    @State private var assignedTo: String?
    @State private var recurrence: Recurrence = .none

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var isEvent: Bool { kind == .event }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $kind.animation()) {
                        ForEach(ItemKind.allCases) { itemKind in
                            Text(itemKind.label).tag(itemKind)
                        }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text(isEvent
                         ? "An event is something you're reminded of — there's nothing to check off."
                         : "A reminder is a to-do you check off when it's done.")
                }

                Section {
                    TextField("Title", text: $title, axis: .vertical)
                    TextField("Notes (optional)", text: $details, axis: .vertical)
                        .lineLimit(1...5)
                }

                Section {
                    Toggle(isEvent ? "Set date" : "Due date", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("Date", selection: $dueDate)
                            .datePickerStyle(.compact)
                        // Recurrence only applies to reminders (they recur when completed).
                        if !isEvent {
                            Picker("Repeat", selection: $recurrence) {
                                ForEach(Recurrence.allCases) { rule in
                                    Text(rule.label).tag(rule)
                                }
                            }
                        }
                    }
                } header: {
                    Text("When")
                } footer: {
                    if hasDueDate && !isEvent && recurrence.isRepeating {
                        Text("When you mark this complete, the next \(recurrence.label.lowercased()) occurrence is created automatically.")
                    }
                }

                Section("List") {
                    Picker("List", selection: $categoryID) {
                        Text("None").tag(String?.none)
                        ForEach(store.categories) { category in
                            Text(category.name).tag(String?.some(category.id))
                        }
                    }
                }

                Section("Assigned to") {
                    Picker("Assignee", selection: $assignedTo) {
                        Text("Anyone").tag(String?.none)
                        if let me = auth.currentUser {
                            Text("\(me.displayName) (me)").tag(String?.some(me.userID))
                        }
                        // The partner's id appears once they've created/edited a shared task.
                        ForEach(partnerOptions, id: \.0) { id, name in
                            Text(name).tag(String?.some(id))
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
            .onAppear(perform: populate)
            .onChange(of: hasDueDate) { _, hasDue in
                // Recurrence is meaningless without a due date.
                if !hasDue { recurrence = .none }
            }
            .onChange(of: kind) { _, newKind in
                // Events don't recur on completion.
                if newKind == .event { recurrence = .none }
            }
        }
    }

    private var navigationTitle: String {
        switch (isEditing, isEvent) {
        case (true, true):   return "Edit Event"
        case (true, false):  return "Edit Reminder"
        case (false, true):  return "New Event"
        case (false, false): return "New Reminder"
        }
    }

    /// Distinct people seen in the shared data, excluding me — used to offer an assignee.
    private var partnerOptions: [(String, String)] {
        let myID = auth.currentUser?.userID
        var seen: [String: String] = [:]
        for task in store.tasks where task.createdByID != myID && !task.createdByID.isEmpty {
            seen[task.createdByID] = task.createdByName
        }
        return seen.map { ($0.key, $0.value) }.sorted { $0.1 < $1.1 }
    }

    private func populate() {
        switch mode {
        case .create(let defaultCategoryID):
            categoryID = defaultCategoryID
        case .edit(let task):
            kind = task.kind
            title = task.title
            details = task.details
            if let due = task.dueDate {
                hasDueDate = true
                dueDate = due
            }
            categoryID = task.categoryID
            assignedTo = task.assignedTo
            recurrence = task.recurrence
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = hasDueDate ? dueDate : nil
        // Events never recur on completion, so force recurrence off for them.
        let rule = (hasDueDate && !isEvent) ? recurrence : .none

        Task {
            switch mode {
            case .create:
                await store.addTask(title: trimmedTitle,
                                    details: trimmedDetails,
                                    kind: kind,
                                    dueDate: due,
                                    categoryID: categoryID,
                                    assignedTo: assignedTo,
                                    recurrence: rule)
            case .edit(let original):
                var updated = original
                updated.kind = kind
                updated.title = trimmedTitle
                updated.details = trimmedDetails
                updated.dueDate = due
                updated.categoryID = categoryID
                updated.assignedTo = assignedTo
                updated.recurrence = rule
                // An event that has been switched from a reminder shouldn't stay "complete".
                if kind == .event { updated.isComplete = false; updated.completedByName = nil }
                await store.updateTask(updated)
            }
            dismiss()
        }
    }
}
