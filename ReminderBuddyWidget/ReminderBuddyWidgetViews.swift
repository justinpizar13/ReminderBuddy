import WidgetKit
import SwiftUI

struct ReminderBuddyWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ReminderEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(snapshot: entry.snapshot)
        case .systemLarge:
            ListWidgetView(snapshot: entry.snapshot, maxRows: 8)
        default: // .systemMedium and any future families
            ListWidgetView(snapshot: entry.snapshot, maxRows: 3)
        }
    }
}

// MARK: - Small: counts only

private struct SmallWidgetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                Text("Reminder Buddy").font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("\(snapshot.todayCount)")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text(snapshot.todayCount == 1 ? "due today" : "due today")
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshot.overdueCount > 0 {
                Text("\(snapshot.overdueCount) overdue")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Medium / Large: header + list

private struct ListWidgetView: View {
    let snapshot: WidgetSnapshot
    let maxRows: Int

    private var rows: [WidgetReminder] { Array(snapshot.items.prefix(maxRows)) }
    private var remaining: Int { max(0, (snapshot.todayCount + snapshot.overdueCount) - rows.count) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if rows.isEmpty {
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                            .foregroundStyle(.green)
                        Text("All caught up").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { item in
                    ReminderRowView(item: item)
                }
                if remaining > 0 {
                    Text("+\(remaining) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack {
            Label("Today", systemImage: "checklist")
                .font(.subheadline.weight(.semibold))
            Spacer()
            if snapshot.overdueCount > 0 {
                Text("\(snapshot.overdueCount) overdue")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct ReminderRowView: View {
    let item: WidgetReminder

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(item.isOverdue ? .red : .secondary)
            Text(item.title)
                .font(.caption)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let due = item.dueDate {
                Text(due, style: .time)
                    .font(.caption2)
                    .foregroundStyle(item.isOverdue ? .red : .secondary)
            }
        }
    }
}
