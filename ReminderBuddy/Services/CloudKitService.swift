import Foundation
import CloudKit
import os.log

/// Errors surfaced to the UI from the CloudKit layer.
enum CloudKitError: LocalizedError {
    case accountUnavailable
    case shareCreationFailed
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .accountUnavailable:
            return "iCloud is not available. Make sure you are signed in to iCloud in Settings."
        case .shareCreationFailed:
            return "Could not create the shared list. Please try again."
        case .underlying(let error):
            return error.localizedDescription
        }
    }
}

/// Central CloudKit engine for Reminder Buddy.
///
/// Data model on the server:
/// - A single custom record zone ("ReminderBuddyZone") in the user's PRIVATE database
///   holds all Categories, Tasks and Notes.
/// - That zone is shared with the partner via a CKShare. The partner accesses the same
///   records through their SHARED database. Both sides therefore read/write one dataset.
/// - Subscriptions on both databases trigger silent pushes so each device learns about
///   the other person's changes.
@MainActor
final class CloudKitService {

    static let shared = CloudKitService()

    // Update this if you change the container identifier in the entitlements file.
    static let containerIdentifier = "iCloud.com.reminderbuddy.app"

    let container: CKContainer
    let privateDB: CKDatabase
    let sharedDB: CKDatabase

    static let zoneName = "ReminderBuddyZone"
    let zoneID: CKRecordZone.ID

    private let log = Logger(subsystem: "com.reminderbuddy.app", category: "CloudKit")

    private init() {
        container = CKContainer(identifier: Self.containerIdentifier)
        privateDB = container.privateCloudDatabase
        sharedDB = container.sharedCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    // MARK: - Account & bootstrap

    /// Verifies the iCloud account is usable before doing anything else.
    func ensureAccountAvailable() async throws {
        let status = try await container.accountStatus()
        guard status == .available else {
            log.error("iCloud account status not available: \(String(describing: status), privacy: .public)")
            throw CloudKitError.accountUnavailable
        }
    }

    /// Creates the custom zone (idempotent) and registers change subscriptions.
    func bootstrap() async throws {
        try await ensureAccountAvailable()
        try await createZoneIfNeeded()
        try await registerSubscriptions()
    }

    func createZoneIfNeeded() async throws {
        let zone = CKRecordZone(zoneID: zoneID)
        do {
            _ = try await privateDB.modifyRecordZones(saving: [zone], deleting: [])
            log.info("Custom zone ready.")
        } catch let ckError as CKError where ckError.code == .serverRecordChanged {
            // Zone already exists; safe to ignore.
        }
    }

    /// Determines which database a record lives in for the current user.
    /// The zone owner uses the private DB; the invited partner uses the shared DB.
    func activeDatabase() async -> CKDatabase {
        // If we can see the zone in the shared DB, we are the invited partner.
        do {
            let sharedZones = try await sharedDB.allRecordZones()
            if sharedZones.contains(where: { $0.zoneID.zoneName == Self.zoneName }) {
                return sharedDB
            }
        } catch {
            log.error("Failed to list shared zones: \(error.localizedDescription, privacy: .public)")
        }
        return privateDB
    }

    /// Resolves the zone ID to use for queries/writes for the current user.
    func activeZoneID() async -> CKRecordZone.ID {
        do {
            let sharedZones = try await sharedDB.allRecordZones()
            if let z = sharedZones.first(where: { $0.zoneID.zoneName == Self.zoneName }) {
                return z.zoneID
            }
        } catch {
            log.error("Failed to resolve shared zone: \(error.localizedDescription, privacy: .public)")
        }
        return zoneID
    }
}
