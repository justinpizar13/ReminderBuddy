import SwiftUI

struct MainTabView: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        TabView {
            UpcomingView()
                .tabItem { Label("Upcoming", systemImage: "calendar") }
                .badge(store.dueSoonCount())

            SharedInfoView()
                .tabItem { Label("Info", systemImage: "info.circle") }

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar.day.timeline.left") }

            CategoriesView()
                .tabItem { Label("Lists", systemImage: "folder") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
