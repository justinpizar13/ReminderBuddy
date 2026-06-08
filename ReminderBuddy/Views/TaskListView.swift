import SwiftUI

struct TaskListView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var selectedCategoryID: String? = nil   // nil == All
    @State private var showingAdd = false
    @State private var showingCompleted = false

    private var filteredTasks: [ReminderTask] {
        let base: [ReminderTask]
        if let id = selectedCategoryID {
            base = store.tasks.filter { $0.categoryID == id }
        } else {
            base = store.tasks
        }
        return showingCompleted ? base : base.filter { !$0.isComplete }
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.tasks.isEmpty {
                    ProgressView("Syncing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredTasks.isEmpty {
                    emptyState
                } else {
                    taskList
                }
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $selectedCategoryID) {
                            Text("All Lists").tag(String?.none)
                            ForEach(store.categories) { category in
                                Text(category.name).tag(String?.some(category.id))
                            }
                        }
                        Toggle("Show Completed", isOn: $showingCompleted)
                    } label: {
                        Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await store.refresh(announceChanges: false) }
            .sheet(isPresented: $showingAdd) {
                TaskEditorView(mode: .create(defaultCategoryID: selectedCategoryID))
            }
            .overlay(alignment: .bottom) {
                if let error = store.errorMessage {
                    ErrorBanner(message: error) { store.errorMessage = nil }
                }
            }
        }
    }

    private var taskList: some View {
        List {
            ForEach(filteredTasks) { task in
                NavigationLink(value: task) {
                    TaskRow(task: task)
                }
                .swipeActions(edge: .leading) {
                    Button {
                        Task { await store.toggleComplete(task) }
                    } label: {
                        Label(task.isComplete ? "Reopen" : "Done",
                              systemImage: task.isComplete ? "arrow.uturn.backward" : "checkmark")
                    }
                    .tint(task.isComplete ? .gray : .green)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await store.deleteTask(task) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationDestination(for: ReminderTask.self) { task in
            // Bind to the latest version from the store.
            if let live = store.tasks.first(where: { $0.id == task.id }) {
                TaskDetailView(task: live)
            } else {
                TaskDetailView(task: task)
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Reminders", systemImage: "checkmark.circle")
        } description: {
            Text(showingCompleted
                 ? "Nothing here yet."
                 : "You're all caught up. Tap + to add a reminder.")
        } actions: {
            Button("Add Reminder") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Row

struct TaskRow: View {
    @EnvironmentObject private var store: TaskStore
    let task: ReminderTask

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                Task { await store.toggleComplete(task) }
            } label: {
                Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isComplete ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.isComplete, color: .secondary)
                    .foregroundStyle(task.isComplete ? .secondary : .primary)

                HStack(spacing: 8) {
                    if let category = store.category(for: task) {
                        Label(category.name, systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption2)
                            .foregroundStyle(Color(hex: category.colorHex))
                    }
                    if let due = task.dueDate {
                        Label(due.formatted(date: .abbreviated, time: .shortened),
                              systemImage: "calendar")
                            .font(.caption2)
                            .foregroundStyle(isOverdue(due, completed: task.isComplete) ? .red : .secondary)
                    }
                    if task.recurrence.isRepeating {
                        Label(task.recurrence.shortLabel, systemImage: "repeat")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    let count = store.notes(for: task).count
                    if count > 0 {
                        Label("\(count)", systemImage: "text.bubble")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func isOverdue(_ date: Date, completed: Bool) -> Bool {
        !completed && date < Date()
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).font(.footnote)
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(.primary)
        .padding(.horizontal)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
