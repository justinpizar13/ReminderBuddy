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
                    shareStatusRows

                    Button {
                        prepareShare()
                    } label: {
                        if preparingShare {
                            HStack { ProgressView(); Text("Preparing invite…") }
                        } else {
                            Label(inviteButtonTitle, systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    .disabled(preparingShare)
                } header: {
                    Text("Sharing")
                } footer: {
                    Text(shareFooterText)
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
            .sheet(item: $shareItem, onDismiss: {
                // After managing the share, refresh in case invitees changed.
                Task { await store.refreshShareStatus() }
            }) { wrapper in
                CloudSharingView(share: wrapper.share, container: wrapper.container)
                    .ignoresSafeArea()
            }
            .task {
                await notifications.refreshAuthorizationStatus()
                await store.refreshShareStatus()
            }
            .onReceive(NotificationCenter.default.publisher(for: .didAcceptCloudKitShare)) { _ in
                Task { await store.refreshShareStatus() }
            }
            .onChange(of: summaryPrefs.isEnabled) { _, _ in store.rescheduleDailySummaries() }
            .onChange(of: summaryPrefs.hour) { _, _ in store.rescheduleDailySummaries() }
            .onChange(of: summaryPrefs.minute) { _, _ in store.rescheduleDailySummaries() }
        }
    }

    // MARK: Sharing status UI

    @ViewBuilder
    private var shareStatusRows: some View {
        let status = store.shareStatus
        switch status.role {
        case .notShared:
            Label {
                Text("Not shared yet")
            } icon: {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.secondary)

        case .owner, .participant:
            HStack {
                Label {
                    Text(status.role == .owner ? "You're sharing this list" : "Shared with you")
                } icon: {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                }
                Spacer()
            }

            ForEach(status.members) { member in
                HStack {
                    Image(systemName: member.isOwner ? "crown.fill" : "person.fill")
                        .foregroundStyle(member.isOwner ? .yellow : .blue)
                        .frame(width: 22)
                    Text(member.isYou ? "\(member.name) (you)" : member.name)
                    Spacer()
                    if member.hasAccepted {
                        Text(member.isOwner ? "Owner" : "Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Pending")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var inviteButtonTitle: String {
        switch store.shareStatus.role {
        case .notShared: return "Invite Your Partner"
        case .owner: return "Manage Sharing"
        case .participant: return "View Sharing"
        }
    }

    private var shareFooterText: String {
        switch store.shareStatus.role {
        case .notShared:
            return "Send an invite to share this list. Once they accept, you'll both see and edit the same reminders."
        case .owner:
            let pending = store.shareStatus.pendingPartners.count
            if pending > 0 {
                return "Your invite is waiting to be accepted. Tap Manage Sharing to resend or add people."
            }
            return "You're sharing this list. Tap Manage Sharing to add people or change access."
        case .participant:
            return "You're viewing a list shared with you. Changes you make are visible to everyone on the list."
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
