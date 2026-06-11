import SwiftUI

struct TaskDetailView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var auth: AuthManager

    let task: ReminderTask

    @State private var newNote = ""
    @State private var showingEdit = false
    @FocusState private var noteFieldFocused: Bool

    private var taskNotes: [TaskNote] { store.notes(for: task) }

    var body: some View {
        List {
            // Header
            Section {
                HStack(alignment: .top, spacing: 12) {
                    if task.kind == .event {
                        Image(systemName: "calendar.circle.fill")
                            .font(.title)
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Button {
                            Task { await store.toggleComplete(task) }
                        } label: {
                            Image(systemName: task.isComplete ? "checkmark.circle.fill" : "circle")
                                .font(.title)
                                .foregroundStyle(task.isComplete ? .green : .secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.title)
                            .font(.title3.weight(.semibold))
                            .strikethrough(task.isComplete, color: .secondary)
                        if !task.details.isEmpty {
                            Text(task.details)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            // Metadata
            Section("Details") {
                if let category = store.category(for: task) {
                    LabeledContent("List") {
                        Label(category.name, systemImage: "circle.fill")
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(Color(hex: category.colorHex))
                    }
                }
                LabeledContent("Type") {
                    Label(task.kind.label, systemImage: task.kind.systemImage)
                }
                if let due = task.dueDate {
                    LabeledContent(task.kind == .event ? "Date" : "Due",
                                   value: due.formatted(date: .abbreviated, time: .shortened))
                }
                if task.recurrence.isRepeating {
                    LabeledContent("Repeats") {
                        Label(task.recurrence.label, systemImage: "repeat")
                    }
                }
                if let assignee = assigneeName {
                    LabeledContent("Assigned to", value: assignee)
                }
                LabeledContent("Created by", value: task.createdByName.isEmpty ? "—" : task.createdByName)
                if task.isComplete, let by = task.completedByName {
                    LabeledContent("Completed by", value: by)
                }
            }

            // Notes / comments
            Section("Notes") {
                if taskNotes.isEmpty {
                    Text("No notes yet. Add one below to keep each other in the loop.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(taskNotes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.body)
                        HStack {
                            Text(note.authorName.isEmpty ? "Unknown" : note.authorName)
                            Text("·")
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    TextField("Add a note…", text: $newNote, axis: .vertical)
                        .focused($noteFieldFocused)
                    Button {
                        submitNote()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                    }
                    .disabled(newNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .navigationTitle(task.kind.label)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            TaskEditorView(mode: .edit(task))
        }
    }

    private var assigneeName: String? {
        guard let assignedTo = task.assignedTo else { return nil }
        if assignedTo == auth.currentUser?.userID {
            return "\(auth.currentUser?.displayName ?? "Me") (me)"
        }
        // Look up the name from any record they authored.
        if let match = store.tasks.first(where: { $0.createdByID == assignedTo }) {
            return match.createdByName
        }
        return "Partner"
    }

    private func submitNote() {
        let body = newNote
        newNote = ""
        noteFieldFocused = false
        Task { await store.addNote(to: task, body: body) }
    }
}
