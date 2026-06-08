import SwiftUI
import CloudKit
import UIKit

@main
struct ReminderBuddyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var auth = AuthManager()
    @StateObject private var notifications = NotificationManager.shared
    @StateObject private var summaryPrefs = SummaryPreferences()
    @StateObject private var store: TaskStore

    init() {
        let auth = AuthManager()
        let prefs = SummaryPreferences()
        _auth = StateObject(wrappedValue: auth)
        _summaryPrefs = StateObject(wrappedValue: prefs)
        _store = StateObject(wrappedValue: TaskStore(auth: auth, summaryPrefs: prefs))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(store)
                .environmentObject(notifications)
                .environmentObject(summaryPrefs)
                .task {
                    appDelegate.configure(store: store, auth: auth)
                    auth.revalidateCredentialState()
                    await notifications.refreshAuthorizationStatus()
                }
        }
    }
}

/// Handles APNs registration, incoming CloudKit pushes, and share acceptance.
final class AppDelegate: NSObject, UIApplicationDelegate {

    private weak var store: TaskStore?
    private weak var auth: AuthManager?

    @MainActor
    func configure(store: TaskStore, auth: AuthManager) {
        self.store = store
        self.auth = auth
    }

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    // MARK: Remote notifications (CloudKit pushes)

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // A CloudKit change push arrived — refetch and announce the partner's changes.
        // We don't read userInfo contents, so nothing non-Sendable crosses actors.
        Task { @MainActor in
            guard let store = self.store else {
                completionHandler(.noData)
                return
            }
            await store.refresh(announceChanges: true)
            completionHandler(.newData)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Push won't work on the Simulator; this is expected there.
    }

    // MARK: Share acceptance (partner tapped the invite link)

    func application(_ application: UIApplication,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task { @MainActor in
            do {
                try await CloudKitService.shared.accept(cloudKitShareMetadata)
                await store?.start()
            } catch {
                store?.errorMessage = error.localizedDescription
            }
        }
    }
}
