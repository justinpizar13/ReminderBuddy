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
    func toRecord(in zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: zoneID)
        let record = CKRecord(recordType: ReminderTask.recordType, recordID: recordID)
        record["title"] = title as CKRecordValue
        record["details"] = details as CKRecordValue
        record["isComplete"] = (isComplete ? 1 : 0) as CKRecordValue
        if let dueDate { record["dueDate"] = dueDate as CKRecordValue }
        if let categoryID { record["categoryID"] = categoryID as CKRecordValue }
        if let assignedTo { record["assignedTo"] = assignedTo as CKRecordValue }
        record["recurrence"] = recurrence.rawValue as CKRecordValue
        record["createdByName"] = createdByName as CKRecordValue
        record["createdByID"] = createdByID as CKRecordValue
        record["lastModifiedByName"] = lastModifiedByName as CKRecordValue
        if let completedByName { record["completedByName"] = completedByName as CKRecordValue }
        record["createdAt"] = createdAt as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        return record
    }

    init?(record: CKRecord) {
        guard record.recordType == ReminderTask.recordType else { return nil }
        self.id = record.recordID.recordName
        self.title = record["title"] as? String ?? ""
        self.details = record["details"] as? String ?? ""
        self.isComplete = (record["isComplete"] as? Int ?? 0) == 1
        self.dueDate = record["dueDate"] as? Date
        self.categoryID = record["categoryID"] as? String
        self.assignedTo = record["assignedTo"] as? String
        self.recurrence = Recurrence(rawValue: record["recurrence"] as? String ?? "") ?? .none
        self.createdByName = record["createdByName"] as? String ?? ""
        self.createdByID = record["createdByID"] as? String ?? ""
        self.lastModifiedByName = record["lastModifiedByName"] as? String ?? ""
        self.completedByName = record["completedByName"] as? String
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
