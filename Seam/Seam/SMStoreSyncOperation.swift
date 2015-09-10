//    SMStoreSyncOperation.swift
//
//    The MIT License (MIT)
//
//    Copyright (c) 2015 Nofel Mahmood ( https://twitter.com/NofelMahmood )
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.


import Foundation
import CloudKit
import CoreData

let SMStoreSyncOperationErrorDomain = "SMStoreSyncOperationDomain"
let SMSyncConflictsResolvedRecordsKey = "SMSyncConflictsResolvedRecordsKey"

let SMCloudRecordNilValue = "@!SM_CloudStore_Record_Nil_Value"

enum SMSyncConflictResolutionPolicy: Int16 {
    case ClientTellsWhichWins = 0
    case ServerRecordWins = 1
    case ClientRecordWins = 2
    case KeepBoth = 4
}

enum SMSyncOperationError: ErrorType {
    case LocalChangesFetchError
    case ConflictsDetected(conflictedRecords: [CKRecord])
    case UnknownError
}

class SMStoreSyncOperation: NSOperation {
    
    private var operationQueue: NSOperationQueue?
    private var localStoreMOC: NSManagedObjectContext?
    private var persistentStoreCoordinator: NSPersistentStoreCoordinator?
    private var entities: Array<NSEntityDescription>?
    var syncConflictPolicy: SMSyncConflictResolutionPolicy?
    var syncCompletionBlock: ((syncError:NSError?) -> ())?
    var syncConflictResolutionBlock: ((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    
    init(persistentStoreCoordinator:NSPersistentStoreCoordinator?,entitiesToSync entities:[NSEntityDescription], conflictPolicy:SMSyncConflictResolutionPolicy?) {
        self.persistentStoreCoordinator = persistentStoreCoordinator
        self.entities = entities
        self.syncConflictPolicy = conflictPolicy
        super.init()
    }
    
    // MARK: Sync
    override func main() {
        print("Sync Started", terminator: "\n")
        self.operationQueue = NSOperationQueue()
        self.operationQueue!.maxConcurrentOperationCount = 1
        self.localStoreMOC = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        self.localStoreMOC!.persistentStoreCoordinator = self.persistentStoreCoordinator
        if self.syncCompletionBlock != nil {
            do {
                try self.performSync()
                print("Sync Performed", terminator: "\n")
                self.syncCompletionBlock!(syncError: nil)
            } catch let error as NSError? {
                print("Sync Performed with Error", terminator: "\n")
                self.syncCompletionBlock!(syncError: error)
            }
        }
    }
    
    func performSync() throws {
        var localChangesInServerRepresentation = try self.localChangesInServerRepresentation()
        do {
            try self.applyLocalChangesToServer(insertedOrUpdatedCKRecords: localChangesInServerRepresentation.insertedOrUpdatedCKRecords, deletedCKRecordIDs: localChangesInServerRepresentation.deletedCKRecordIDs)
            try self.fetchAndApplyServerChangesToLocalDatabase()
            SMServerTokenHandler.defaultHandler.commit()
            try SMStoreChangeSetHandler.defaultHandler.removeAllQueuedChangeSets(backingContext: self.localStoreMOC!)
            return
        } catch SMSyncOperationError.ConflictsDetected(let conflictedRecords) {
            self.resolveConflicts(conflictedRecords: conflictedRecords)
            var insertedOrUpdatedCKRecordsWithRecordIDStrings: Dictionary<String,CKRecord> = Dictionary<String,CKRecord>()
            for record in localChangesInServerRepresentation.insertedOrUpdatedCKRecords! {
                let ckRecord: CKRecord = record as CKRecord
                insertedOrUpdatedCKRecordsWithRecordIDStrings[ckRecord.recordID.recordName] = ckRecord
            }
            for record in conflictedRecords {
                insertedOrUpdatedCKRecordsWithRecordIDStrings[record.recordID.recordName] = record
            }
            localChangesInServerRepresentation.insertedOrUpdatedCKRecords = Array(insertedOrUpdatedCKRecordsWithRecordIDStrings.values)
            try self.applyLocalChangesToServer(insertedOrUpdatedCKRecords: localChangesInServerRepresentation.insertedOrUpdatedCKRecords, deletedCKRecordIDs: localChangesInServerRepresentation.deletedCKRecordIDs)
            try self.fetchAndApplyServerChangesToLocalDatabase()
            SMServerTokenHandler.defaultHandler.commit()
            try SMStoreChangeSetHandler.defaultHandler.removeAllQueuedChangeSets(backingContext: self.localStoreMOC!)
        } catch {
            throw SMSyncOperationError.UnknownError
        }
    }
    
    func fetchAndApplyServerChangesToLocalDatabase() throws {
        var moreComing = true
        var insertedOrUpdatedCKRecordsFromServer = [CKRecord]()
        var deletedCKRecordIDsFromServer = [CKRecordID]()
        while moreComing {
            let returnValue = self.fetchRecordChangesFromServer()
            insertedOrUpdatedCKRecordsFromServer.appendContentsOf([] + returnValue.insertedOrUpdatedCKRecords)
            deletedCKRecordIDsFromServer.appendContentsOf([] + returnValue.deletedRecordIDs)
            moreComing = returnValue.moreComing
        }
        try self.applyServerChangesToLocalDatabase(insertedOrUpdatedCKRecordsFromServer, deletedCKRecordIDs: deletedCKRecordIDsFromServer)
    }
    
    // MARK: Local Changes
    func applyServerChangesToLocalDatabase(insertedOrUpdatedCKRecords: [CKRecord], deletedCKRecordIDs:[CKRecordID]) throws {
        try self.insertOrUpdateManagedObjects(fromCKRecords: insertedOrUpdatedCKRecords)
        try self.deleteManagedObjects(fromCKRecordIDs: deletedCKRecordIDs)
    }
    
    func applyLocalChangesToServer(insertedOrUpdatedCKRecords insertedOrUpdatedCKRecords: Array<CKRecord>? , deletedCKRecordIDs: Array<CKRecordID>?) throws {
        if insertedOrUpdatedCKRecords == nil && deletedCKRecordIDs == nil {
            return
        }
        let ckModifyRecordsOperation = CKModifyRecordsOperation(recordsToSave: insertedOrUpdatedCKRecords, recordIDsToDelete: deletedCKRecordIDs)
        let savedRecords: [CKRecord] = [CKRecord]()
        var conflictedRecords: [CKRecord] = [CKRecord]()
        ckModifyRecordsOperation.modifyRecordsCompletionBlock = ({(savedRecords,deletedRecordIDs,operationError)->Void in
 
        })
        ckModifyRecordsOperation.perRecordCompletionBlock = ({(ckRecord,operationError)->Void in
            
            let error:NSError? = operationError
            if error != nil && error!.code == CKErrorCode.ServerRecordChanged.rawValue
            {
                print("Conflicted Record \(error!)", terminator: "\n")
                conflictedRecords.append(ckRecord!)
            }
        })
        self.operationQueue!.addOperation(ckModifyRecordsOperation)
        self.operationQueue!.waitUntilAllOperationsAreFinished()
        if conflictedRecords.count > 0 {
            throw SMSyncOperationError.ConflictsDetected(conflictedRecords: conflictedRecords)
        }
        if savedRecords.count > 0 {
            let recordIDSubstitution = "recordIDSubstitution"
            let fetchPredicate: NSPredicate = NSPredicate(format: "%K == $recordIDSubstitution", SMLocalStoreRecordIDAttributeName)
            for record in savedRecords {
                let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: record.recordType)
                let recordIDString: String = record.valueForKey(SMLocalStoreRecordIDAttributeName) as! String
                fetchRequest.predicate = fetchPredicate.predicateWithSubstitutionVariables([recordIDSubstitution:recordIDString])
                fetchRequest.fetchLimit = 1
                let results = try self.localStoreMOC!.executeFetchRequest(fetchRequest)
                if results.count > 0 {
                    let managedObject = results.last as? NSManagedObject
                    let encodedFields = record.encodedSystemFields()
                    managedObject?.setValue(encodedFields, forKey: SMLocalStoreRecordEncodedValuesAttributeName)
                }
            }
            try self.localStoreMOC!.saveIfHasChanges()
        }
    }
    
    func resolveConflicts(conflictedRecords conflictedRecords: [CKRecord])
    {
        if conflictedRecords.count > 0 {
            var conflictedRecordsWithStringRecordIDs: Dictionary<String,(clientRecord:CKRecord?,serverRecord:CKRecord?)> = Dictionary<String,(clientRecord:CKRecord?,serverRecord:CKRecord?)>()
            for record in conflictedRecords {
                conflictedRecordsWithStringRecordIDs[record.recordID.recordName] = (record,nil)
            }
            let ckFetchRecordsOperation:CKFetchRecordsOperation = CKFetchRecordsOperation(recordIDs: conflictedRecords.map({(object)-> CKRecordID in
                let ckRecord:CKRecord = object as CKRecord
                return ckRecord.recordID
            }))
            
            ckFetchRecordsOperation.perRecordCompletionBlock = ({(record,recordID,error)->Void in
                if error == nil {
                    let ckRecord: CKRecord? = record
                    let ckRecordID: CKRecordID? = recordID
                    if conflictedRecordsWithStringRecordIDs[ckRecordID!.recordName] != nil {
                        conflictedRecordsWithStringRecordIDs[ckRecordID!.recordName] = (conflictedRecordsWithStringRecordIDs[ckRecordID!.recordName]!.clientRecord,ckRecord)
                    }
                }
            })
            self.operationQueue?.addOperation(ckFetchRecordsOperation)
            self.operationQueue?.waitUntilAllOperationsAreFinished()
            var finalCKRecords: [CKRecord] = [CKRecord]()
            for key in Array(conflictedRecordsWithStringRecordIDs.keys) {
                let value = conflictedRecordsWithStringRecordIDs[key]!
                var clientServerCKRecord = value as (clientRecord:CKRecord?,serverRecord:CKRecord?)
                if self.syncConflictPolicy == SMSyncConflictResolutionPolicy.ClientTellsWhichWins {
                    if self.syncConflictResolutionBlock != nil {
                        clientServerCKRecord.serverRecord = self.syncConflictResolutionBlock!(clientRecord: clientServerCKRecord.clientRecord!,serverRecord: clientServerCKRecord.serverRecord!)
                    } else {
                        print("ClientTellsWhichWins conflict resolution policy requires to set syncConflictResolutionBlock on the instance of SMStore")
                    }
                } else if self.syncConflictPolicy == SMSyncConflictResolutionPolicy.ClientRecordWins {
                    
                } else if self.syncConflictPolicy == SMSyncConflictResolutionPolicy.ServerRecordWins {
                    
                } else if self.syncConflictPolicy == SMSyncConflictResolutionPolicy.KeepBoth {
                    
                }
//                else if self.syncConflictPolicy == SMSyncConflictResolutionPolicy.KeepBoth
//                {
//                    let keys = clientServerCKRecord.serverRecord!.allKeys()
//                    let values = clientServerCKRecord.clientRecord!.allKeys()
//                    
//                }
//                else if (self.syncConflictPolicy == SMSyncConflictResolutionPolicy.ClientRecordWins || (self.syncConflictPolicy == SMSyncConflictResolutionPolicy.GreaterModifiedDateWins && clientServerCKRecord.clientRecord!.modificationDate!.compare(clientServerCKRecord.serverRecord!.modificationDate!) == NSComparisonResult.OrderedDescending))
//                {
//                    let keys = clientServerCKRecord.serverRecord!.allKeys()
//                    let values = clientServerCKRecord.clientRecord!.dictionaryWithValuesForKeys(keys)
//                    clientServerCKRecord.serverRecord!.setValuesForKeysWithDictionary(values)
//                }
                
                finalCKRecords.append(clientServerCKRecord.serverRecord!)
            }
        }
    }
    
    func localChangesInServerRepresentation() throws -> (insertedOrUpdatedCKRecords:Array<CKRecord>?,deletedCKRecordIDs:Array<CKRecordID>?) {
        let changeSetHandler = SMStoreChangeSetHandler.defaultHandler
        let insertedOrUpdatedCKRecords = try changeSetHandler.recordsForUpdatedObjects(backingContext: self.localStoreMOC!)
        let deletedCKRecordIDs = try changeSetHandler.recordIDsForDeletedObjects(self.localStoreMOC!)
        return (insertedOrUpdatedCKRecords,deletedCKRecordIDs)
    }
    
    func fetchRecordChangesFromServer() -> (insertedOrUpdatedCKRecords:Array<CKRecord>,deletedRecordIDs:Array<CKRecordID>,moreComing:Bool) {
        let token = SMServerTokenHandler.defaultHandler.token()
        let recordZoneID = CKRecordZoneID(zoneName: SMStoreCloudStoreCustomZoneName, ownerName: CKOwnerDefaultName)
        let fetchRecordChangesOperation = CKFetchRecordChangesOperation(recordZoneID: recordZoneID, previousServerChangeToken: token)
        var insertedOrUpdatedCKRecords: [CKRecord] = [CKRecord]()
        var deletedCKRecordIDs: [CKRecordID] = [CKRecordID]()
        fetchRecordChangesOperation.fetchRecordChangesCompletionBlock = { serverChangeToken,clientChangeToken,operationError in
            if operationError == nil {
                SMServerTokenHandler.defaultHandler.save(serverChangeToken: serverChangeToken!)
                SMServerTokenHandler.defaultHandler.commit()
            }
        }
        fetchRecordChangesOperation.recordChangedBlock = { record in
            let ckRecord:CKRecord = record as CKRecord
            insertedOrUpdatedCKRecords.append(ckRecord)
        }
        fetchRecordChangesOperation.recordWithIDWasDeletedBlock = { recordID in
            deletedCKRecordIDs.append(recordID as CKRecordID)
        }
        self.operationQueue!.addOperation(fetchRecordChangesOperation)
        self.operationQueue!.waitUntilAllOperationsAreFinished()
        if insertedOrUpdatedCKRecords.count > 0 {
            let recordIDs: [CKRecordID] = insertedOrUpdatedCKRecords.map { record in
                return record.recordID
            }
            var recordTypes: Set<String> = Set<String>()
            for record in insertedOrUpdatedCKRecords {
                recordTypes.insert(record.recordType)
            }
            var desiredKeys: [String]?
            for recordType in recordTypes {
                if desiredKeys == nil {
                    desiredKeys = [String]()
                }
                let entity = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[recordType]
                if entity != nil {
                    let properties = Array(entity!.propertiesByName.keys).filter {  key in
                        if key == SMLocalStoreRecordIDAttributeName || key == SMLocalStoreRecordEncodedValuesAttributeName {
                            return false
                        }
                        return true
                    }
                    desiredKeys!.appendContentsOf(properties)
                }
            }
            insertedOrUpdatedCKRecords.removeAll()
            let fetchRecordsOperation: CKFetchRecordsOperation = CKFetchRecordsOperation(recordIDs: recordIDs)
            fetchRecordsOperation.desiredKeys = desiredKeys
            fetchRecordsOperation.fetchRecordsCompletionBlock =  { recordsByRecordID,operationError in
                if operationError == nil && recordsByRecordID != nil {
                    insertedOrUpdatedCKRecords = Array(recordsByRecordID!.values)
                }
            }
            self.operationQueue!.addOperation(fetchRecordsOperation)
            self.operationQueue!.waitUntilAllOperationsAreFinished()
            for record in insertedOrUpdatedCKRecords {
                let entity = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[record.recordType]
                if entity != nil {
                    for key in Array(entity!.propertiesByName.keys) {
                        if record[key] == nil && key != SMLocalStoreRecordIDAttributeName && key != SMLocalStoreRecordEncodedValuesAttributeName {
                            record[key] = SMCloudRecordNilValue
                        }
                    }
                }
            }
        }
        if fetchRecordChangesOperation.moreComing {
            print("More Coming", terminator: "\n")
        } else {
            print("Not coming", terminator: "\n")
        }
        return (insertedOrUpdatedCKRecords,deletedCKRecordIDs,fetchRecordChangesOperation.moreComing)
    }
    
    func insertOrUpdateManagedObjects(fromCKRecords ckRecords:Array<CKRecord>) throws {
        for record in ckRecords {
            try record.createOrUpdateManagedObjectFromRecord(usingContext: self.localStoreMOC!)
            try self.localStoreMOC!.saveIfHasChanges()
        }
    }
    
    func deleteManagedObjects(fromCKRecordIDs ckRecordIDs:Array<CKRecordID>) throws {
        if ckRecordIDs.count > 0 {
            let predicate = NSPredicate(format: "%K IN $ckRecordIDs",SMLocalStoreRecordIDAttributeName)
            let ckRecordIDStrings = ckRecordIDs.map({(object)->String in
                let ckRecordID:CKRecordID = object
                return ckRecordID.recordName
            })
            let entityNames = self.entities!.map { (entity) in
                return entity.name!
            }
            for name in entityNames {
                let fetchRequest = NSFetchRequest(entityName: name as String)
                fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["ckRecordIDs":ckRecordIDStrings])
                let results = try self.localStoreMOC!.executeFetchRequest(fetchRequest)
                if results.count > 0 {
                    for object in results as! [NSManagedObject] {
                        self.localStoreMOC?.deleteObject(object)
                    }
                }
            }
        }
        try self.localStoreMOC?.saveIfHasChanges()
    }
}