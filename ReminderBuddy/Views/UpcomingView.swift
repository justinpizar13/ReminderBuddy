import SwiftUI

/// Shows incomplete tasks grouped by due date: Overdue, Today, Tomorrow, This Week,
/// Later, and (optionally) No Due Date. Reuses TaskRow and the shared detail screen.
struct UpcomingView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var showingAdd = false
    @State private var includeNoDate = true

    private var sections: [DueSection] {
        store.upcomingSections(includeNoDate: includeNoDate)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.isLoading && store.tasks.isEmpty {
                    ProgressView("Syncing…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sections.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Upcoming")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Toggle("Show Undated", isOn: $includeNoDate)
                    } label: {
                        Label("Options", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await store.refresh(announceChanges: false) }
            .sheet(isPresented: $showingAdd) {
                TaskEditorView(mode: .create(defaultCategoryID: nil))
            }
            .navigationDestination(for: ReminderTask.self) { task in
                if let live = store.tasks.first(where: { $0.id == task.id }) {
                    TaskDetailView(task: live)
                } else {
                    TaskDetailView(task: task)
                }
            }
            .overlay(alignment: .bottom) {
                if let error = store.errorMessage {
                    ErrorBanner(message: error) { store.errorMessage = nil }
                }
            }
        }
    }

    private var list: some View {
        List {
            ForEach(sections) { section in
                Section {
                    ForEach(section.tasks) { task in
                        NavigationLink(value: task) {
                            TaskRow(task: task)
                        }
                        .swipeActions(edge: .leading) {
                            if task.kind != .event {
                                Button {
                                    Task { await store.toggleComplete(task) }
                                } label: {
                                    Label("Done", systemImage: "checkmark")
                                }
                                .tint(.green)
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                Task { await store.deleteTask(task) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Label(section.group.title, systemImage: section.group.systemImage)
                        .foregroundStyle(section.group == .overdue ? .red : .secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing Upcoming", systemImage: "calendar.badge.checkmark")
        } description: {
            Text("You're all caught up. Tap + to add a reminder or event with a date.")
        } actions: {
            Button("Add Item") { showingAdd = true }
                .buttonStyle(.borderedProminent)
        }
    }
}
