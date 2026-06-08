import SwiftUI

/// Decides whether to show the sign-in screen or the main app.
struct RootView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var notifications: NotificationManager

    var body: some View {
        Group {
            if auth.isSignedIn {
                MainTabView()
                    .task {
                        await notifications.requestAuthorization()
                        if !store.isReady {
                            await store.start()
                        }
                    }
            } else {
                SignInView()
            }
        }
    }
}
