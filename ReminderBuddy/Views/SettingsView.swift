import SwiftUI
import CloudKit
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var summaryPrefs: SummaryPreferences
    @EnvironmentObject private var store: TaskStore

    @State private var editingName = false
    @State private var nameDraft = ""
    @State private var shareItem: ShareWrapper?
    @State private var preparingShare = false
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("You") {
                    if let user = auth.currentUser {
                        LabeledContent("Name", value: user.displayName)
                        Button("Change Name") {
                            nameDraft = user.displayName
                            editingName = true
                        }
                    }
                }

                Section {
                    Button {
                        prepareShare()
                    } label: {
                        if preparingShare {
                            HStack { ProgressView(); Text("Preparing invite…") }
                        } else {
                            Label("Invite Your Partner", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    .disabled(preparingShare)
                } header: {
                    Text("Sharing")
                } footer: {
                    Text("Send an invite to share this list. Once they accept, you'll both see and edit the same reminders.")
                }

                Section {
                    HStack {
                        Label("Notifications", systemImage: "bell.badge")
                        Spacer()
                        Text(notifications.isAuthorized ? "On" : "Off")
                            .foregroundStyle(notifications.isAuthorized ? .green : .secondary)
                    }
                    if !notifications.isAuthorized {
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Get alerted when your partner adds a task, updates one, completes it, or adds a note — plus reminders for due dates.")
                }

                Section {
                    Toggle("Daily Summary", isOn: $summaryPrefs.isEnabled)
                    if summaryPrefs.isEnabled {
                        DatePicker(
                            "Time",
                            selection: Binding(
                                get: { summaryPrefs.timeOfDay },
                                set: { summaryPrefs.timeOfDay = $0 }),
                            displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Daily Summary")
                } footer: {
                    Text("A morning rundown of everything due that day. Delivered each day that has reminders due.")
                }

                Section {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        Text("Sign Out")
                    }
                }

                if let shareError {
                    Section {
                        Text(shareError).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Settings")
            .alert("Change Name", isPresented: $editingName) {
                TextField("Name", text: $nameDraft)
                Button("Save") { auth.updateDisplayName(nameDraft) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This is how your partner will see your activity.")
            }
            .sheet(item: $shareItem) { wrapper in
                CloudSharingView(share: wrapper.share, container: wrapper.container)
                    .ignoresSafeArea()
            }
            .task { await notifications.refreshAuthorizationStatus() }
            .onChange(of: summaryPrefs.isEnabled) { _, _ in store.rescheduleDailySummaries() }
            .onChange(of: summaryPrefs.hour) { _, _ in store.rescheduleDailySummaries() }
            .onChange(of: summaryPrefs.minute) { _, _ in store.rescheduleDailySummaries() }
        }
    }

    private func prepareShare() {
        preparingShare = true
        shareError = nil
        Task {
            do {
                let (share, container) = try await CloudKitService.shared.fetchOrCreateShare()
                shareItem = ShareWrapper(share: share, container: container)
            } catch {
                shareError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            preparingShare = false
        }
    }
}

private struct ShareWrapper: Identifiable {
    let id = UUID()
    let share: CKShare
    let container: CKContainer
}

/// Wraps UICloudSharingController so we can present the system "invite people" sheet.
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func itemTitle(for csc: UICloudSharingController) -> String? { "Reminder Buddy" }
        func cloudSharingController(_ csc: UICloudSharingController,
                                    failedToSaveShareWithError error: Error) {
            // Surfaced via the controller's own UI.
        }
    }
}
