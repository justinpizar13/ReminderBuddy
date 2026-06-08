import SwiftUI

struct CategoriesView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                if store.categories.isEmpty {
                    ContentUnavailableView(
                        "No Lists",
                        systemImage: "folder",
                        description: Text("Create lists like Groceries, Bills, or Errands to organize your reminders."))
                } else {
                    ForEach(store.categories) { category in
                        HStack {
                            Image(systemName: "circle.fill")
                                .foregroundStyle(Color(hex: category.colorHex))
                            Text(category.name)
                            Spacer()
                            Text("\(store.tasks(in: category).count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("Lists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                CategoryEditorView()
            }
        }
    }

    private func delete(at offsets: IndexSet) {
        let toDelete = offsets.map { store.categories[$0] }
        Task {
            for category in toDelete {
                await store.deleteCategory(category)
            }
        }
    }
}

struct CategoryEditorView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorHex = CategoryPalette.colors.first!

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("List name", text: $name)
                }
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(CategoryPalette.colors, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if hex == colorHex {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.white)
                                            .font(.caption.bold())
                                    }
                                }
                                .onTapGesture { colorHex = hex }
                                .accessibilityLabel(Text("Color \(hex)"))
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        Task { await store.addCategory(name: trimmed, colorHex: colorHex) }
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
