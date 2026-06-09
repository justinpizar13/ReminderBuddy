import Foundation
import CloudKit

// MARK: - Fetch + write operations
//
// All reads/writes go through the "active" database + zone so the code works whether
// the current user owns the shared zone (private DB) or was invited to it (shared DB).

extension CloudKitService {

    // MARK: Fetch

    /// Loads the full current contents of the synced zone.
    ///
    /// Uses `recordZoneChanges(inZoneWith:since:)` (the zone-change API) rather than
    /// `CKQuery`. Passing `since: nil` returns every live record in the zone, and unlike
    /// queries this path requires **no Queryable indexes** in the CloudKit schema — which
    /// is why it avoids the "field 'recordName' is not marked queryable" failure in the
    /// locked Production environment.
    func fetchAll() async throws -> (categories: [TaskCategory], tasks: [ReminderTask], notes: [TaskNote]) {
        let db = await activeDatabase()
        let zone = await activeZoneID()
        let records = try await fetchAllRecords(in: db, zone: zone)

        let categories = records
            .compactMap { TaskCategory(record: $0) }
            .sorted { $0.sortIndex < $1.sortIndex }
        let tasks = records.compactMap { ReminderTask(record: $0) }
        let notes = records
            .compactMap { TaskNote(record: $0) }
            .sorted { $0.createdAt < $1.createdAt }

        return (categories, tasks, notes)
    }

    /// Fetches every record currently in the zone via the change-tracking API, following
    /// `moreComing` pages. Starts from a nil token, so it returns the complete set.
    private func fetchAllRecords(in db: CKDatabase, zone: CKRecordZone.ID) async throws -> [CKRecord] {
        var collected: [CKRecord] = []
        var token: CKServerChangeToken?

        repeat {
            let result = try await db.recordZoneChanges(inZoneWith: zone, since: token)
            for (_, modificationResult) in result.modificationResultsByID {
                if case .success(let modification) = modificationResult {
                    collected.append(modification.record)
                }
            }
            token = result.changeToken
            if !result.moreComing { break }
        } while true

        return collected
    }

    // MARK: Save

    @discardableResult
    func save(task: ReminderTask) async throws -> ReminderTask {
        let db = await activeDatabase()
        let zone = await activeZoneID()
        let record = try await mergedRecord(for: task.toRecord(in: zone), in: db)
        let saved = try await db.save(record)
        return ReminderTask(record: saved) ?? task
    }

    @discardableResult
    func save(category: TaskCategory) async throws -> TaskCategory {
        let db = await activeDatabase()
        let zone = await activeZoneID()
        let record = try await mergedRecord(for: category.toRecord(in: zone), in: db)
        let saved = try await db.save(record)
        return TaskCategory(record: saved) ?? category
    }

    @discardableResult
    func save(note: TaskNote) async throws -> TaskNote {
        let db = await activeDatabase()
        let zone = await activeZoneID()
        // Notes are append-only, so no merge needed.
        let saved = try await db.save(note.toRecord(in: zone))
        return TaskNote(record: saved) ?? note
    }

    // MARK: Delete

    func deleteTask(id: String) async throws {
        let db = await activeDatabase()
        let zone = await activeZoneID()
        let recordID = CKRecord.ID(recordName: id, zoneID: zone)
        _ = try await db.modifyRecords(saving: [], deleting: [recordID])
    }

    func deleteCategory(id: String) async throws {
        let db = await activeDatabase()
        let zone = await activeZoneID()
        let recordID = CKRecord.ID(recordName: id, zoneID: zone)
        _ = try await db.modifyRecords(saving: [], deleting: [recordID])
    }

    // MARK: Conflict handling

    /// Fetches the server record (if any) and copies our fields onto it so we don't
    /// clobber the server's change tag. Prevents `serverRecordChanged` write failures.
    private func mergedRecord(for localRecord: CKRecord, in db: CKDatabase) async throws -> CKRecord {
        do {
            let serverRecord = try await db.record(for: localRecord.recordID)
            for key in localRecord.allKeys() {
                serverRecord[key] = localRecord[key]
            }
            return serverRecord
        } catch let error as CKError where error.code == .unknownItem {
            // Record doesn't exist yet — first write wins.
            return localRecord
        }
    }
}
