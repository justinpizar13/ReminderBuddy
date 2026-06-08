import SwiftUI

/// A month calendar. Each day shows a dot/count when it has incomplete tasks due.
/// Tapping a day reveals that day's tasks below the grid.
struct CalendarView: View {
    @EnvironmentObject private var store: TaskStore

    @State private var visibleMonth: Date = Date()
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: Date())
    @State private var showingAdd = false

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var grid: MonthGrid { MonthGrid(month: visibleMonth, calendar: calendar) }
    private var countsByDay: [Date: Int] { store.incompleteCountsByDay(calendar: calendar) }
    private var selectedTasks: [ReminderTask] { store.tasks(on: selectedDay, calendar: calendar) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                monthHeader
                weekdayHeader
                monthGrid
                Divider().padding(.top, 4)
                selectedDayList
            }
            .navigationTitle("Calendar")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { goToToday() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
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

    // MARK: Header

    private var monthHeader: some View {
        HStack {
            Button { changeMonth(by: -1) } label: {
                Image(systemName: "chevron.left").font(.headline)
            }
            Spacer()
            Text(grid.monthTitle).font(.headline)
            Spacer()
            Button { changeMonth(by: 1) } label: {
                Image(systemName: "chevron.right").font(.headline)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(grid.weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: Grid

    private var monthGrid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(grid.days) { day in
                dayCell(day)
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .contentShape(Rectangle())
        .gesture(monthSwipe)
        // Re-identify on month change so the swipe transition animates cleanly.
        .id(calendar.dateComponents([.year, .month], from: visibleMonth))
        .transition(.opacity)
    }

    /// Horizontal swipe to move between months (left = next, right = previous).
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                // Only treat predominantly-horizontal swipes as month changes.
                guard abs(horizontal) > abs(vertical) else { return }
                if horizontal < 0 {
                    changeMonth(by: 1)
                } else if horizontal > 0 {
                    changeMonth(by: -1)
                }
            }
    }

    private func dayCell(_ day: CalendarDay) -> some View {
        let startOfDay = calendar.startOfDay(for: day.date)
        let count = countsByDay[startOfDay] ?? 0
        let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDay)
        let isToday = calendar.isDateInToday(day.date)

        return Button {
            selectedDay = startOfDay
        } label: {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: day.date))")
                    .font(.callout)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(cellTextColor(day: day, isSelected: isSelected, isToday: isToday))
                // Dot indicator for days with incomplete tasks.
                Circle()
                    .fill(count > 0 ? Color.accentColor : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.18))
                } else if isToday {
                    RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(day.isInMonth ? 1 : 0.3)
        .accessibilityLabel(accessibilityText(day: day.date, count: count))
    }

    private func cellTextColor(day: CalendarDay, isSelected: Bool, isToday: Bool) -> Color {
        if isToday { return .accentColor }
        return day.isInMonth ? .primary : .secondary
    }

    // MARK: Selected-day list

    private var selectedDayList: some View {
        Group {
            if selectedTasks.isEmpty {
                ContentUnavailableView {
                    Label(selectedDayTitle, systemImage: "calendar")
                } description: {
                    Text("No reminders due this day.")
                } actions: {
                    Button("Add Reminder") { showingAdd = true }
                        .buttonStyle(.bordered)
                }
                .frame(maxHeight: .infinity)
            } else {
                List {
                    Section(selectedDayTitle) {
                        ForEach(selectedTasks) { task in
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
                }
                .listStyle(.plain)
            }
        }
    }

    private var selectedDayTitle: String {
        if calendar.isDateInToday(selectedDay) { return "Today" }
        if calendar.isDateInTomorrow(selectedDay) { return "Tomorrow" }
        return selectedDay.formatted(.dateTime.weekday(.wide).month().day())
    }

    // MARK: Actions

    private func changeMonth(by delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: visibleMonth) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { visibleMonth = newMonth }
    }

    private func goToToday() {
        let today = calendar.startOfDay(for: Date())
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleMonth = today
            selectedDay = today
        }
    }

    private func accessibilityText(day: Date, count: Int) -> Text {
        let dateText = day.formatted(.dateTime.month().day())
        if count == 0 { return Text(dateText) }
        return Text("\(dateText), \(count) reminder\(count == 1 ? "" : "s") due")
    }
}
