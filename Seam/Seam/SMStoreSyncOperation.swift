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
let SMStoreSyncOperationServerTokenKey = "SMStoreSyncOperationServerTokenKey"

enum SMSyncConflictResolutionPolicy: Int16
{
    case ClientTellsWhichWins = 0
    case ServerRecordWins = 1
    case ClientRecordWins = 2
    case GreaterModifiedDateWins = 3
    case KeepBoth = 4
}

enum SMSyncOperationError: ErrorType
{
    case LocalChangesFetchError
    case ConflictsDetected
}

class SMStoreSyncOperation: NSOperation {
    
    private var operationQueue: NSOperationQueue?
    private var localStoreMOC: NSManagedObjectContext?
    private var persistentStoreCoordinator: NSPersistentStoreCoordinator?
    private var entities: Array<NSEntityDescription>?
    var syncConflictPolicy: SMSyncConflictResolutionPolicy?
    var syncCompletionBlock:((syncError:NSError?) -> ())?
    var syncConflictResolutionBlock:((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    
    init(persistentStoreCoordinator:NSPersistentStoreCoordinator?,entitiesToSync entities:[NSEntityDescription], conflictPolicy:SMSyncConflictResolutionPolicy?) {
        
        self.persistentStoreCoordinator = persistentStoreCoordinator
        self.entities = entities
        self.syncConflictPolicy = conflictPolicy
        super.init()
    }
    
    // MARK: Sync
    override func main() {
        
        self.operationQueue = NSOperationQueue()
        self.operationQueue?.maxConcurrentOperationCount = 1
        
        self.localStoreMOC = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        self.localStoreMOC?.persistentStoreCoordinator = self.persistentStoreCoordinator
        
        if self.syncCompletionBlock != nil
        {
            do
            {
                try self.performSync()
                self.syncCompletionBlock!(syncError: nil)
            }
            catch let error as NSError?
            {
                self.syncCompletionBlock!(syncError: error)
            }
        }
    }
    
    func performSync() throws
    {
        let localChangesInServerRepresentation = try self.localChangesInServerRepresentation()
        var insertedOrUpdatedCKRecords:Array<CKRecord>? = localChangesInServerRepresentation.insertedOrUpdatedCKRecords
        let deletedCKRecordIDs:Array<CKRecordID>? = localChangesInServerRepresentation.deletedCKRecordIDs
        
        do
        {
            try self.applyLocalChangesToServer(insertedOrUpdatedCKRecords: insertedOrUpdatedCKRecords, deletedCKRecordIDs: deletedCKRecordIDs)
            do
            {
                try self.fetchAndApplyServerChangesToLocalDatabase()
            }
            catch let error as NSError?
            {
                throw error!
            }
        }
        catch let error as NSError?
        {
            let conflictedRecords = error!.userInfo[SMSyncConflictsResolvedRecordsKey] as! Array<CKRecord>
            self.resolveConflicts(conflictedRecords: conflictedRecords)
            var insertedOrUpdatedCKRecordsWithRecordIDStrings:Dictionary<String,CKRecord> = Dictionary<String,CKRecord>()
            
            for record in insertedOrUpdatedCKRecords!
            {
                let ckRecord:CKRecord = record as CKRecord
                insertedOrUpdatedCKRecordsWithRecordIDStrings[ckRecord.recordID.recordName] = ckRecord
            }
            
            for record in conflictedRecords
            {
                insertedOrUpdatedCKRecordsWithRecordIDStrings[record.recordID.recordName] = record
            }
            
            insertedOrUpdatedCKRecords = insertedOrUpdatedCKRecordsWithRecordIDStrings.values.array
    
            try self.applyLocalChangesToServer(insertedOrUpdatedCKRecords: insertedOrUpdatedCKRecords, deletedCKRecordIDs: deletedCKRecordIDs)
            
            do
            {
                try self.fetchAndApplyServerChangesToLocalDatabase()
            }
            catch let error as NSError?
            {
                throw error!
            }
        }
    }
    
    func fetchAndApplyServerChangesToLocalDatabase() throws
    {
        var moreComing = true
        var insertedOrUpdatedCKRecordsFromServer = Array<CKRecord>()
        var deletedCKRecordIDsFromServer = Array<CKRecordID>()
        while moreComing
        {
            let returnValue = self.fetchRecordChangesFromServer()
            insertedOrUpdatedCKRecordsFromServer += returnValue.insertedOrUpdatedCKRecords
            deletedCKRecordIDsFromServer += returnValue.deletedRecordIDs
            moreComing = returnValue.moreComing
        }
        
        try self.applyServerChangesToLocalDatabase(insertedOrUpdatedCKRecordsFromServer, deletedCKRecordIDs: deletedCKRecordIDsFromServer)
    }
    
    // MARK: Local Changes
    func applyServerChangesToLocalDatabase(insertedOrUpdatedCKRecords:Array<CKRecord>,deletedCKRecordIDs:Array<CKRecordID>) throws
    {
        try self.deleteManagedObjects(fromCKRecordIDs: deletedCKRecordIDs)
        try self.insertOrUpdateManagedObjects(fromCKRecords: insertedOrUpdatedCKRecords)
    }
    
    func applyLocalChangesToServer(insertedOrUpdatedCKRecords insertedOrUpdatedCKRecords: Array<CKRecord>? , deletedCKRecordIDs: Array<CKRecordID>?) throws
    {
        let ckModifyRecordsOperation = CKModifyRecordsOperation(recordsToSave: insertedOrUpdatedCKRecords, recordIDsToDelete: deletedCKRecordIDs)
        
        let savedRecords:[CKRecord] = [CKRecord]()
        var conflictedRecords:[CKRecord] = [CKRecord]()
        ckModifyRecordsOperation.modifyRecordsCompletionBlock = ({(savedRecords,deletedRecordIDs,operationError)->Void in
        })
        ckModifyRecordsOperation.perRecordCompletionBlock = ({(ckRecord,operationError)->Void in
            
            let error:NSError? = operationError
            if error != nil && error!.code == CKErrorCode.ServerRecordChanged.rawValue
            {
                conflictedRecords.append(ckRecord!)
            }
        })
        
        self.operationQueue?.addOperation(ckModifyRecordsOperation)
        self.operationQueue?.waitUntilAllOperationsAreFinished()
        
        if conflictedRecords.count > 0
        {
            throw NSError(domain: SMStoreSyncOperationErrorDomain, code: SMSyncOperationError.ConflictsDetected._code, userInfo: [SMSyncConflictsResolvedRecordsKey:conflictedRecords])
        }
        
        if savedRecords.count > 0
        {
            var savedRecordsWithType:Dictionary<String,Dictionary<String,CKRecord>> = Dictionary<String,Dictionary<String,CKRecord>>()
            
            for record in savedRecords
            {
                if savedRecordsWithType[record.recordType] != nil
                {
                    savedRecordsWithType[record.recordType]![record.recordID.recordName] = record
                    continue
                }
                let recordWithRecordIDString:Dictionary<String,CKRecord> = Dictionary<String,CKRecord>()
                savedRecordsWithType[record.recordType] = recordWithRecordIDString
            }
            
            let predicate = NSPredicate(format: "%K IN $recordIDStrings",SMLocalStoreRecordIDAttributeName)
            
            let types = savedRecordsWithType.keys.array
            
            for type in types
            {
                let fetchRequest = NSFetchRequest(entityName: type)
                let ckRecordsForType = savedRecordsWithType[type]
                let ckRecordIDStrings = ckRecordsForType!.keys.array
                
                fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["recordIDStrings":ckRecordIDStrings])
                var results = try self.localStoreMOC!.executeFetchRequest(fetchRequest)
                if results.count > 0
                {
                    for managedObject in results as! [NSManagedObject]
                    {
                        let ckRecord = ckRecordsForType![managedObject.valueForKey(SMLocalStoreRecordIDAttributeName) as! String]
                        let encodedSystemFields = ckRecord?.encodedSystemFields()
                        managedObject.setValue(encodedSystemFields, forKey: SMLocalStoreRecordEncodedValuesAttributeName)
                    }
                }
            }
            
            try self.localStoreMOC!.save()
        }
    }
    
    func resolveConflicts(conflictedRecords conflictedRecords: Array<CKRecord>)
    {
        if conflictedRecords.count > 0
        {
            var conflictedRecordsWithStringRecordIDs: Dictionary<String,(clientRecord:CKRecord?,serverRecord:CKRecord?)> = Dictionary<String,(clientRecord:CKRecord?,serverRecord:CKRecord?)>()
            
            for record in conflictedRecords
            {
                conflictedRecordsWithStringRecordIDs[record.recordID.recordName] = (record,nil)
            }
            
            let ckFetchRecordsOperation:CKFetchRecordsOperation = CKFetchRecordsOperation(recordIDs: conflictedRecords.map({(object)-> CKRecordID in
                
                let ckRecord:CKRecord = object as CKRecord
                return ckRecord.recordID
            }))
            
            ckFetchRecordsOperation.perRecordCompletionBlock = ({(record,recordID,error)->Void in
                
                if error == nil
                {
                    let ckRecord: CKRecord? = record
                    let ckRecordID: CKRecordID? = recordID
                    if conflictedRecordsWithStringRecordIDs[ckRecordID!.recordName] != nil
                    {
                        conflictedRecordsWithStringRecordIDs[ckRecordID!.recordName] = (conflictedRecordsWithStringRecordIDs[ckRecordID!.recordName]!.clientRecord,ckRecord)
                    }
                }
            })
            self.operationQueue?.addOperation(ckFetchRecordsOperation)
            self.operationQueue?.waitUntilAllOperationsAreFinished()
            
            var finalCKRecords:[CKRecord] = [CKRecord]()
            
            for key in conflictedRecordsWithStringRecordIDs.keys.array
            {
                let value = conflictedRecordsWithStringRecordIDs[key]!
                var clientServerCKRecord = value as (clientRecord:CKRecord?,serverRecord:CKRecord?)
                
                if self.syncConflictPolicy == SMSyncConflictResolutionPolicy.ClientTellsWhichWins
                {
                    if self.syncConflictResolutionBlock != nil
                    {
                        clientServerCKRecord.serverRecord = self.syncConflictResolutionBlock!(clientRecord: clientServerCKRecord.clientRecord!,serverRecord: clientServerCKRecord.serverRecord!)
                    }
                }
                else if (self.syncConflictPolicy == SMSyncConflictResolutionPolicy.ClientRecordWins || (self.syncConflictPolicy == SMSyncConflictResolutionPolicy.GreaterModifiedDateWins && clientServerCKRecord.clientRecord!.modificationDate!.compare(clientServerCKRecord.serverRecord!.modificationDate!) == NSComparisonResult.OrderedDescending))
                {
                    let keys = clientServerCKRecord.serverRecord!.allKeys()
                    let values = clientServerCKRecord.clientRecord!.dictionaryWithValuesForKeys(keys)
                    clientServerCKRecord.serverRecord!.setValuesForKeysWithDictionary(values)
                }
                
                finalCKRecords.append(clientServerCKRecord.serverRecord!)
            }
            
//            let userInfo:Dictionary<String,Array<CKRecord>> = [CKSSyncConflictedResolvedRecordsKey:finalCKRecords]
//            throw NSError(domain: CKSIncrementalStoreSyncOperationErrorDomain, code: CKSStoresSyncError.ConflictsDetected._code, userInfo: userInfo)
        }
    }
    
    func localChangesInServerRepresentation() throws -> (insertedOrUpdatedCKRecords:Array<CKRecord>?,deletedCKRecordIDs:Array<CKRecordID>?)
    {
        let changeSetHandler = SMStoreChangeSetHandler.defaultHandler
        let insertedOrUpdatedCKRecords = try changeSetHandler.recordsForUpdatedObjects(backingContext: self.localStoreMOC!)
        let deletedCKRecordIDs = try changeSetHandler.recordIDsForDeletedObjects(self.localStoreMOC!)
        
        return (insertedOrUpdatedCKRecords,deletedCKRecordIDs)
    }
    
    func fetchRecordChangesFromServer() -> (insertedOrUpdatedCKRecords:Array<CKRecord>,deletedRecordIDs:Array<CKRecordID>,moreComing:Bool)
    {
        let token = SMServerTokenHandler.defaultHandler.token()
        let recordZoneID = CKRecordZoneID(zoneName: SMStoreCloudStoreCustomZoneName, ownerName: CKOwnerDefaultName)
        let fetchRecordChangesOperation = CKFetchRecordChangesOperation(recordZoneID: recordZoneID, previousServerChangeToken: token)
        
        var insertedOrUpdatedCKRecords: Array<CKRecord> = Array<CKRecord>()
        var deletedCKRecordIDs: Array<CKRecordID> = Array<CKRecordID>()
        
        fetchRecordChangesOperation.fetchRecordChangesCompletionBlock = ({(serverChangeToken,clientChangeToken,operationError)->Void in
            
            if operationError == nil
            {
                SMServerTokenHandler.defaultHandler.save(serverChangeToken: serverChangeToken!)
                SMServerTokenHandler.defaultHandler.commit()
            }
        })
        
        fetchRecordChangesOperation.recordChangedBlock = ({(record)->Void in
            
            let ckRecord:CKRecord = record as CKRecord
            insertedOrUpdatedCKRecords.append(ckRecord)
        })
        
        fetchRecordChangesOperation.recordWithIDWasDeletedBlock = ({(recordID)->Void in
            
            deletedCKRecordIDs.append(recordID as CKRecordID)
        })
        
        self.operationQueue?.addOperation(fetchRecordChangesOperation)
        self.operationQueue?.waitUntilAllOperationsAreFinished()
        return (insertedOrUpdatedCKRecords,deletedCKRecordIDs,fetchRecordChangesOperation.moreComing)
    }
    
    func insertOrUpdateManagedObjects(fromCKRecords ckRecords:Array<CKRecord>) throws
    {
        let predicate = NSPredicate(format: "%K == $ckRecordIDString",SMLocalStoreRecordIDAttributeName)
        
        for object in ckRecords
        {
            let ckRecord:CKRecord = object
            let fetchRequest = NSFetchRequest(entityName: ckRecord.recordType)
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["ckRecordIDString":ckRecord.recordID.recordName])
            fetchRequest.fetchLimit = 1
            var results = try self.localStoreMOC!.executeFetchRequest(fetchRequest)
            if results.count > 0
            {
                let managedObject = results.first as! NSManagedObject
                let keys = ckRecord.allKeys().filter({(obj)->Bool in
                    
                    if ckRecord.objectForKey(obj as String) is CKReference
                    {
                        return false
                    }
                    return true
                })
                
                let values = ckRecord.dictionaryWithValuesForKeys(keys)
                managedObject.setValuesForKeysWithDictionary(values)
                managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue), forKey: SMLocalStoreChangeTypeAttributeName)
                managedObject.setValue(ckRecord.encodedSystemFields(), forKey: SMLocalStoreRecordEncodedValuesAttributeName)
                
                let changedCKReferenceRecordIDStringsWithKeys = ckRecord.allKeys().filter({(obj)->Bool in
                    
                    if ckRecord.objectForKey(obj as String) is CKReference
                    {
                        return true
                    }
                    return false
                    
                }).map({(obj)->(key:String,recordIDString:String) in
                    
                    let key:String = obj as String
                    return (key,(ckRecord.objectForKey(key) as! CKReference).recordID.recordName)
                })
                
                for object in changedCKReferenceRecordIDStringsWithKeys
                {
                    let key = object.key
                    let relationship: NSRelationshipDescription? = managedObject.entity.relationshipsByName[key]
                    let attributeEntityName = relationship!.destinationEntity!.name
                    let fetchRequest = NSFetchRequest(entityName: attributeEntityName!)
                    fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,object.recordIDString)
                    var results = try self.localStoreMOC!.executeFetchRequest(fetchRequest)
                    if  results.count > 0
                    {
                        managedObject.setValue(results.first, forKey: object.key)
                        break
                    }
                    
                }
            }
            else
            {
                let managedObject:NSManagedObject = NSEntityDescription.insertNewObjectForEntityForName(ckRecord.recordType, inManagedObjectContext: self.localStoreMOC!) as NSManagedObject
                let keys = ckRecord.allKeys().filter({(object)->Bool in
                    
                    let key:String = object as String
                    if ckRecord.objectForKey(key) is CKReference
                    {
                        return false
                    }
                    
                    return true
                })
                
                
                managedObject.setValue(ckRecord.encodedSystemFields(), forKey: SMLocalStoreRecordEncodedValuesAttributeName)
                let changedCKReferencesRecordIDsWithKeys = ckRecord.allKeys().filter({(object)->Bool in
                    
                    let key:String = object as String
                    if ckRecord.objectForKey(key) is CKReference
                    {
                        return true
                    }
                    return false
                    
                }).map({(object)->(key:String,recordIDString:String) in
                    
                    let key:String = object as String
                    
                    return (key,(ckRecord.objectForKey(key) as! CKReference).recordID.recordName)
                })
                
                let values = ckRecord.dictionaryWithValuesForKeys(keys)
                managedObject.setValuesForKeysWithDictionary(values)
                managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue), forKey: SMLocalStoreChangeTypeAttributeName)
                managedObject.setValue(ckRecord.recordID.recordName, forKey: SMLocalStoreRecordIDAttributeName)
                
                
                for object in changedCKReferencesRecordIDsWithKeys
                {
                    let ckReferenceRecordIDString:String = object.recordIDString
                    let referenceManagedObject = Array(self.localStoreMOC!.registeredObjects).filter({(object)->Bool in
                        
                        let managedObject:NSManagedObject = object as NSManagedObject
                        if (managedObject.valueForKey(SMLocalStoreRecordIDAttributeName) as! String) == ckReferenceRecordIDString
                        {
                            return true
                        }
                        return false
                    }).first
                    
                    if referenceManagedObject != nil
                    {
                        managedObject.setValue(referenceManagedObject, forKey: object.key)
                    }
                    else
                    {
                        let relationshipDescription: NSRelationshipDescription? = managedObject.entity.relationshipsByName[object.key]
                        let destinationRelationshipDescription: NSEntityDescription? = relationshipDescription?.destinationEntity
                        let entityName: String? = destinationRelationshipDescription!.name
                        let fetchRequest = NSFetchRequest(entityName: entityName!)
                        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,ckReferenceRecordIDString)
                        fetchRequest.fetchLimit = 1
                        var results = try self.localStoreMOC!.executeFetchRequest(fetchRequest)
                        if results.count > 0
                        {
                            managedObject.setValue(results.first as! NSManagedObject, forKey: object.key)
                            break
                        }
                    }
                }
            }
        }
        
        try self.localStoreMOC?.saveIfHasChanges()
    }
    
    func deleteManagedObjects(fromCKRecordIDs ckRecordIDs:Array<CKRecordID>) throws
    {
        let predicate = NSPredicate(format: "%K IN $ckRecordIDs",SMLocalStoreRecordIDAttributeName)
        let ckRecordIDStrings = ckRecordIDs.map({(object)->String in
            
            let ckRecordID:CKRecordID = object
            return ckRecordID.recordName
        })
        
        let entityNames = self.entities!.map { (entity) -> String in
            
            return entity.name!
        }
        
        for name in entityNames
        {
            let fetchRequest = NSFetchRequest(entityName: name as String)
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["ckRecordIDs":ckRecordIDStrings])
            var results = try self.localStoreMOC!.executeFetchRequest(fetchRequest)
            if results.count > 0
            {
                for object in results as! [NSManagedObject]
                {
                    self.localStoreMOC?.deleteObject(object)
                }
                
            }
        }
        try self.localStoreMOC?.saveIfHasChanges()
    }
}