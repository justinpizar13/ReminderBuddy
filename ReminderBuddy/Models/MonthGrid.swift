import Foundation

/// A single cell in the month calendar grid.
struct CalendarDay: Identifiable, Hashable {
    let date: Date
    /// False for leading/trailing days that belong to the adjacent month.
    let isInMonth: Bool
    var id: Date { date }
}

/// Computes the weeks/days needed to render a month in a 7-column grid, including the
/// leading days from the previous month and trailing days from the next month so each
/// week row is full.
struct MonthGrid {
    let month: Date            // any date within the target month
    let calendar: Calendar
    let days: [CalendarDay]

    init(month: Date, calendar: Calendar = .current) {
        self.month = month
        self.calendar = calendar
        self.days = MonthGrid.makeDays(for: month, calendar: calendar)
    }

    /// Localized weekday symbols starting on the calendar's first weekday (e.g. Sun or Mon).
    var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1   // firstWeekday is 1-based
        return Array(symbols[first...] + symbols[..<first])
    }

    var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: month)
    }

    private static func makeDays(for month: Date, calendar: Calendar) -> [CalendarDay] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else { return [] }

        var days: [CalendarDay] = []
        var cursor = firstWeek.start

        // Render 6 weeks (42 cells) to keep the grid height stable across months.
        for _ in 0..<42 {
            let inMonth = calendar.isDate(cursor, equalTo: month, toGranularity: .month)
            days.append(CalendarDay(date: cursor, isInMonth: inMonth))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }
}
