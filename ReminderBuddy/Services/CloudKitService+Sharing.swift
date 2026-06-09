import Foundation
import CloudKit

// MARK: - Share status

/// A friendly summary of the current sharing state, for display in Settings.
struct ShareStatus: Equatable {
    enum Role: Equatable {
        case notShared          // No share exists yet.
        case owner              // You created the share.
        case participant        // You accepted someone else's share.
    }

    struct Member: Equatable, Identifiable {
        let id: String
        let name: String
        let isYou: Bool
        let isOwner: Bool
        /// True once the person has accepted the invite (vs. still pending).
        let hasAccepted: Bool
    }

    var role: Role
    var members: [Member]

    /// People other than yourself who have accepted — i.e. you're actively sharing.
    var acceptedPartners: [Member] {
        members.filter { !$0.isYou && $0.hasAccepted }
    }

    /// People invited but who haven't accepted yet.
    var pendingPartners: [Member] {
        members.filter { !$0.isYou && !$0.hasAccepted }
    }

    static let notShared = ShareStatus(role: .notShared, members: [])
}

// MARK: - Sharing & subscriptions

extension CloudKitService {

    /// Returns the current sharing state: whether a share exists, your role, and the
    /// list of participants with their acceptance status. Safe to call for both the
    /// owner (reads the private DB) and an invited participant (reads the shared DB).
    func shareStatus() async -> ShareStatus {
        // Are we a participant? If the zone shows up in the shared DB, someone shared
        // it with us.
        if let sharedShare = await fetchSharedZoneShare() {
            return makeStatus(from: sharedShare, role: .participant)
        }

        // Otherwise, do we own a share?
        if let ownedShare = try? await existingZoneShare() {
            return makeStatus(from: ownedShare, role: .owner)
        }

        return .notShared
    }

    /// On the participant side, locate the accepted share living in the shared database.
    private func fetchSharedZoneShare() async -> CKShare? {
        do {
            let zones = try await sharedDB.allRecordZones()
            guard let zone = zones.first(where: { $0.zoneID.zoneName == Self.zoneName }) else {
                return nil
            }
            let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zone.zoneID)
            return try await sharedDB.record(for: shareID) as? CKShare
        } catch {
            return nil
        }
    }

    private func makeStatus(from share: CKShare, role: ShareStatus.Role) -> ShareStatus {
        let members: [ShareStatus.Member] = share.participants.map { participant in
            let nameComponents = participant.userIdentity.nameComponents
            let formatted = nameComponents.map {
                PersonNameComponentsFormatter().string(from: $0)
            } ?? ""
            let displayName = formatted.isEmpty
                ? (participant.role == .owner ? "Owner" : "Partner")
                : formatted
            return ShareStatus.Member(
                id: participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                name: displayName,
                isYou: participant.userIdentity.userRecordID == share.currentUserParticipant?.userIdentity.userRecordID,
                isOwner: participant.role == .owner,
                hasAccepted: participant.acceptanceStatus == .accepted)
        }
        return ShareStatus(role: role, members: members)
    }

    /// Creates (or returns the existing) zone-wide CKShare for the reminders zone, which
    /// shares EVERY record in the zone (categories, tasks, notes) with the partner — not
    /// just a single root record. Only the zone owner should call this.
    ///
    /// A zone share's record always lives at the well-known record name
    /// `cloudkit.zoneshare` inside the shared zone, so we can look it up directly to
    /// decide whether to reuse an existing invite or mint a new one.
    func fetchOrCreateShare() async throws -> (CKShare, CKContainer) {
        try await ensureAccountAvailable()
        try await createZoneIfNeeded()

        // Reuse an existing zone share if one already exists.
        if let existing = try await existingZoneShare() {
            return (existing, container)
        }

        let share = CKShare(recordZoneID: zoneID)
        share[CKShare.SystemFieldKey.title] = "Reminder Buddy" as CKRecordValue
        share.publicPermission = .none   // invitation only — never public

        do {
            _ = try await privateDB.modifyRecords(saving: [share], deleting: [])
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            // A share was created concurrently; fetch and return it.
            if let existing = try await existingZoneShare() {
                return (existing, container)
            }
            throw CloudKitError.shareCreationFailed
        } catch {
            throw CloudKitError.shareCreationFailed
        }
        return (share, container)
    }

    /// Looks up the zone's existing share record, if any.
    private func existingZoneShare() async throws -> CKShare? {
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
        do {
            return try await privateDB.record(for: shareID) as? CKShare
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
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
