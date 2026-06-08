import Foundation
import CloudKit

// MARK: - Fetch + write operations
//
// All reads/writes go through the "active" database + zone so the code works whether
// the current user owns the shared zone (private DB) or was invited to it (shared DB).

extension CloudKitService {

    // MARK: Fetch

    func fetchAll() async throws -> (categories: [TaskCategory], tasks: [ReminderTask], notes: [TaskNote]) {
        let db = await activeDatabase()
        let zone = await activeZoneID()

        async let categoriesRecords = fetchRecords(ofType: TaskCategory.recordType, in: db, zone: zone)
        async let taskRecords = fetchRecords(ofType: ReminderTask.recordType, in: db, zone: zone)
        async let noteRecords = fetchRecords(ofType: TaskNote.recordType, in: db, zone: zone)

        let categories = try await categoriesRecords.compactMap { TaskCategory(record: $0) }
            .sorted { $0.sortIndex < $1.sortIndex }
        let tasks = try await taskRecords.compactMap { ReminderTask(record: $0) }
        let notes = try await noteRecords.compactMap { TaskNote(record: $0) }
            .sorted { $0.createdAt < $1.createdAt }

        return (categories, tasks, notes)
    }

    private func fetchRecords(ofType type: String,
                              in db: CKDatabase,
                              zone: CKRecordZone.ID) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        var collected: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            let result: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor {
                result = try await db.records(continuingMatchFrom: cursor)
            } else {
                result = try await db.records(matching: query, inZoneWith: zone)
            }
            for (_, recordResult) in result.matchResults {
                if case .success(let record) = recordResult {
                    collected.append(record)
                }
            }
            cursor = result.queryCursor
        } while cursor != nil

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
