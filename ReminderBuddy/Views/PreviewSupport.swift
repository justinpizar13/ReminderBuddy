import SwiftUI

#if DEBUG
/// Lightweight environment objects so SwiftUI previews can render without iCloud.
enum PreviewSupport {
    @MainActor static func auth() -> AuthManager {
        let a = AuthManager()
        return a
    }

    @MainActor static func summaryPrefs() -> SummaryPreferences {
        // Use an isolated defaults suite so previews don't touch real settings.
        SummaryPreferences(defaults: UserDefaults(suiteName: "preview.reminderbuddy") ?? .standard)
    }

    @MainActor static func store() -> TaskStore {
        TaskStore(auth: auth(), summaryPrefs: summaryPrefs())
    }
}

#Preview("Sign In") {
    SignInView()
        .environmentObject(PreviewSupport.auth())
}
#endif
