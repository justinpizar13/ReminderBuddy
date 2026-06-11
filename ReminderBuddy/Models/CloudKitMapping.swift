import Foundation
import CloudKit

// MARK: - Record <-> Model mapping
//
// Each model knows how to (a) build a CKRecord for saving and (b) be constructed
// from a fetched CKRecord. We use the model's `id` as the CKRecord.recordName so
// updates target the same record across both partners' devices.

extension TaskCategory {
    func toRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: TaskCategory.recordType, recordID: recordID)
        record["name"] = name as CKRecordValue
        record["colorHex"] = colorHex as CKRecordValue
        record["sortIndex"] = sortIndex as CKRecordValue
        return record
    }

    init?(record: CKRecord) {
        guard record.recordType == TaskCategory.recordType else { return nil }
        self.id = record.recordID.recordName
        self.name = record["name"] as? String ?? "Untitled"
        self.colorHex = record["colorHex"] as? String ?? "#4F8EF7"
        self.sortIndex = record["sortIndex"] as? Int ?? 0
    }
}

extension ReminderTask {
    /// Sentinel for an absent due date. We always write the `dueDate` field (rather than
    /// omitting it for nil) so CloudKit registers the field in the schema on the very first
    /// save — otherwise the field never lands in the locked Production schema and a later
    /// save that *does* set a due date is rejected with "Cannot create or modify field…".
    /// Optional string fields use "" for the same reason.
    fileprivate static let noDueDateSentinel = Date(timeIntervalSince1970: 0)

    func toRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: ReminderTask.recordType, recordID: recordID)
        record["title"] = title as CKRecordValue
        record["details"] = details as CKRecordValue
        record["kind"] = kind.rawValue as CKRecordValue
        record["isComplete"] = (isComplete ? 1 : 0) as CKRecordValue
        // Every field is always written so the full schema registers on first save.
        record["dueDate"] = (dueDate ?? Self.noDueDateSentinel) as CKRecordValue
        record["categoryID"] = (categoryID ?? "") as CKRecordValue
        record["assignedTo"] = (assignedTo ?? "") as CKRecordValue
        record["recurrence"] = recurrence.rawValue as CKRecordValue
        record["createdByName"] = createdByName as CKRecordValue
        record["createdByID"] = createdByID as CKRecordValue
        record["lastModifiedByName"] = lastModifiedByName as CKRecordValue
        record["completedByName"] = (completedByName ?? "") as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        return record
    }

    init?(record: CKRecord) {
        guard record.recordType == ReminderTask.recordType else { return nil }
        self.id = record.recordID.recordName
        self.title = record["title"] as? String ?? ""
        self.details = record["details"] as? String ?? ""
        // Older records (saved before the event/reminder split) have no `kind` field;
        // they default to `.reminder` so they keep their completion behavior.
        self.kind = ItemKind(rawValue: record["kind"] as? String ?? "") ?? .reminder
        self.isComplete = (record["isComplete"] as? Int ?? 0) == 1
        // Map sentinels back to nil. distantPast / epoch-0 means "no due date".
        if let due = record["dueDate"] as? Date, due > Self.noDueDateSentinel {
            self.dueDate = due
        } else {
            self.dueDate = nil
        }
        self.categoryID = (record["categoryID"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.assignedTo = (record["assignedTo"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.recurrence = Recurrence(rawValue: record["recurrence"] as? String ?? "") ?? .none
        self.createdByName = record["createdByName"] as? String ?? ""
        self.createdByID = record["createdByID"] as? String ?? ""
        self.lastModifiedByName = record["lastModifiedByName"] as? String ?? ""
        self.completedByName = (record["completedByName"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        self.createdAt = record["createdAt"] as? Date ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? Date()
    }
}

extension TaskNote {
    func toRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: TaskNote.recordType, recordID: recordID)
        record["taskID"] = taskID as CKRecordValue
        record["body"] = body as CKRecordValue
        record["authorName"] = authorName as CKRecordValue
        record["authorID"] = authorID as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        return record
    }

    init?(record: CKRecord) {
        guard record.recordType == TaskNote.recordType else { return nil }
        self.id = record.recordID.recordName
        self.taskID = record["taskID"] as? String ?? ""
        self.body = record["body"] as? String ?? ""
        self.authorName = record["authorName"] as? String ?? ""
        self.authorID = record["authorID"] as? String ?? ""
        self.createdAt = record["createdAt"] as? Date ?? Date()
    }
}

extension SharedInfoItem {
    /// Sentinel for "no monthly price". We always write the field (using -1 for nil) so
    /// the field registers in the schema on the first save — same reasoning as
    /// `ReminderTask`'s due-date sentinel.
    fileprivate static let noPriceSentinel: Double = -1

    func toRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: SharedInfoItem.recordType, recordID: recordID)
        record["title"] = title as CKRecordValue
        record["detail"] = detail as CKRecordValue
        record["link"] = link as CKRecordValue
        record["accountNumber"] = accountNumber as CKRecordValue
        record["monthlyPrice"] = (monthlyPrice ?? Self.noPriceSentinel) as CKRecordValue
        record["sortIndex"] = sortIndex as CKRecordValue
        record["createdByName"] = createdByName as CKRecordValue
        record["createdByID"] = createdByID as CKRecordValue
        record["lastModifiedByName"] = lastModifiedByName as CKRecordValue
        record["createdAt"] = createdAt as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        return record
    }

    init?(record: CKRecord) {
        guard record.recordType == SharedInfoItem.recordType else { return nil }
        self.id = record.recordID.recordName
        self.title = record["title"] as? String ?? ""
        self.detail = record["detail"] as? String ?? ""
        self.link = record["link"] as? String ?? ""
        self.accountNumber = record["accountNumber"] as? String ?? ""
        if let price = record["monthlyPrice"] as? Double, price >= 0 {
            self.monthlyPrice = price
        } else {
            self.monthlyPrice = nil
        }
        self.sortIndex = record["sortIndex"] as? Int ?? 0
        self.createdByName = record["createdByName"] as? String ?? ""
        self.createdByID = record["createdByID"] as? String ?? ""
        self.lastModifiedByName = record["lastModifiedByName"] as? String ?? ""
        self.createdAt = record["createdAt"] as? Date ?? Date()
        self.updatedAt = record["updatedAt"] as? Date ?? Date()
    }
}
