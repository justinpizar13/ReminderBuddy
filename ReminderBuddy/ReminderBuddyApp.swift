import SwiftUI
import CloudKit
import UIKit

extension Notification.Name {
    /// Posted after a CloudKit share invitation is accepted, so the UI can reload.
    static let didAcceptCloudKitShare = Notification.Name("ReminderBuddy.didAcceptCloudKitShare")
}

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
                .onReceive(NotificationCenter.default.publisher(for: .didAcceptCloudKitShare)) { _ in
                    // The partner just accepted an invite (handled by the scene delegate);
                    // reload so the shared zone's data appears.
                    Task { await store.start() }
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

    // MARK: Scene configuration
    //
    // SwiftUI-lifecycle apps route CloudKit share acceptance to the *scene* delegate,
    // not the app delegate. We supply a UISceneConfiguration whose delegate is our
    // SceneDelegate so `windowScene(_:userDidAcceptCloudKitShareWith:)` actually fires.

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
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
}

// MARK: - Scene delegate (CloudKit share acceptance)

/// Handles the partner tapping an invite link. iOS delivers share metadata here — to the
/// active scene's delegate — for SwiftUI-lifecycle apps. We accept the share via CloudKit
/// and post a notification so the app reloads the now-shared data.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    /// Cold launch: the app wasn't running when the user tapped the invite, so the
    /// metadata arrives in the connection options.
    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            accept(metadata)
        }
    }

    /// Warm path: the app was already running when the user tapped the invite.
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        accept(cloudKitShareMetadata)
    }

    private func accept(_ metadata: CKShare.Metadata) {
        Task { @MainActor in
            do {
                try await CloudKitService.shared.accept(metadata)
                NotificationCenter.default.post(name: .didAcceptCloudKitShare, object: nil)
            } catch {
                // Surface acceptance failures the next time the app fetches; the user can retry.
                NSLog("CloudKit share acceptance failed: \(error.localizedDescription)")
            }
        }
    }
}
