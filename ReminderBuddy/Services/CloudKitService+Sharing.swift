import Foundation
import CloudKit

// MARK: - Sharing & subscriptions

extension CloudKitService {

    /// A stable record used as the share's root so the whole zone is effectively shared.
    /// CloudKit shares a record (and its hierarchy); we share a lightweight anchor record
    /// and keep all data in the same zone the anchor lives in.
    static let shareAnchorRecordName = "ReminderBuddyShareAnchor"

    /// Creates (or returns existing) a CKShare you can hand to your partner via the
    /// system share sheet. Only the zone owner should call this.
    func fetchOrCreateShare() async throws -> (CKShare, CKContainer) {
        try await ensureAccountAvailable()
        try await createZoneIfNeeded()

        let anchorID = CKRecord.ID(recordName: Self.shareAnchorRecordName, zoneID: zoneID)

        // If the anchor already has a share, reuse it.
        if let existing = try? await privateDB.record(for: anchorID),
           let shareRef = existing.share {
            if let share = try? await privateDB.record(for: shareRef.recordID) as? CKShare {
                return (share, container)
            }
        }

        let anchor: CKRecord
        if let existing = try? await privateDB.record(for: anchorID) {
            anchor = existing
        } else {
            anchor = CKRecord(recordType: "ShareAnchor", recordID: anchorID)
            anchor["title"] = "Reminder Buddy" as CKRecordValue
        }

        let share = CKShare(rootRecord: anchor)
        share[CKShare.SystemFieldKey.title] = "Reminder Buddy" as CKRecordValue
        share.publicPermission = .none   // invitation only — never public

        do {
            _ = try await privateDB.modifyRecords(saving: [anchor, share], deleting: [])
        } catch {
            throw CloudKitError.shareCreationFailed
        }
        return (share, container)
    }

    /// Accepts a share invitation (called from the AppDelegate when a share URL is opened).
    func accept(_ metadata: CKShare.Metadata) async throws {
        let operation = CKAcceptSharesOperation(shareMetadatas: [metadata])
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.acceptSharesResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
            container.add(operation)
        }
    }

    // MARK: Subscriptions (push notifications)

    /// Registers a database subscription on both the private and shared databases so the
    /// device receives a silent push whenever ANY record changes. The app then refetches
    /// and raises a local notification describing what changed.
    func registerSubscriptions() async throws {
        try await registerDatabaseSubscription(id: "private-changes", in: privateDB)
        try await registerDatabaseSubscription(id: "shared-changes", in: sharedDB)
    }

    private func registerDatabaseSubscription(id: String, in db: CKDatabase) async throws {
        let subscription = CKDatabaseSubscription(subscriptionID: id)
        let notificationInfo = CKSubscription.NotificationInfo()
        // Silent push: wakes the app to refetch without showing a system banner itself.
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await db.modifySubscriptions(saving: [subscription], deleting: [])
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription already exists.
        }
    }
}
