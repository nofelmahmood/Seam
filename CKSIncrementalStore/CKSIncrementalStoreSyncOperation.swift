//
//  CKSIncrementalStoreSyncOperation.swift
//  
//
//  Created by Nofel Mahmood on 20/07/2015.
//
//

import UIKit
import CloudKit
import CoreData

let CKSIncrementalStoreSyncOperationErrorDomain = "CKSIncrementalStoreSyncOperationErrorDomain"
let CKSSyncConflictedResolvedRecordsKey = "CKSSyncConflictedResolvedRecordsKey"
let CKSIncrementalStoreSyncOperationFetchChangeTokenKey = "CKSIncrementalStoreSyncOperationFetchChangeTokenKey"

class CKSIncrementalStoreSyncOperation: NSOperation {
    
    private var operationQueue:NSOperationQueue?
    private var localStoreMOC:NSManagedObjectContext?
    private var persistentStoreCoordinator:NSPersistentStoreCoordinator?
    var syncConflictPolicy:CKSStoresSyncConflictPolicy?
    var syncCompletionBlock:((syncError:NSError?) -> ())?
    var syncConflictResolutionBlock:((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    
    init(persistentStoreCoordinator:NSPersistentStoreCoordinator?,conflictPolicy:CKSStoresSyncConflictPolicy?) {
        
        self.persistentStoreCoordinator = persistentStoreCoordinator
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
            var error:NSError?
            
            if self.performSync() == false
            {
                error = NSError()
            }
            self.syncCompletionBlock!(syncError: error)
        }
        
    }
    
    func performSync()->Bool
    {
        var localChanges = self.localChanges()
        var localChangesInServerRepresentation = self.localChangesInServerRepresentation(localChanges: localChanges)
        var insertedOrUpdatedCKRecords:Array<CKRecord> = localChangesInServerRepresentation.insertedOrUpdatedCKRecords
        var deletedCKRecordIDs:Array<CKRecordID> = localChangesInServerRepresentation.deletedCKRecordIDs
        
        
        var error:NSError?
        var wasSuccessful = self.applyLocalChangesToServer(insertedOrUpdatedCKRecords, deletedCKRecordIDs: deletedCKRecordIDs, error: &error)
        
        if !wasSuccessful && error != nil
        {
            var insertedOrUpdatedCKRecordsWithRecordIDStrings:Dictionary<String,CKRecord> = Dictionary<String,CKRecord>()
            for record in insertedOrUpdatedCKRecords
            {
                var ckRecord:CKRecord = record as CKRecord
                insertedOrUpdatedCKRecordsWithRecordIDStrings[ckRecord.recordID.recordName] = ckRecord
            }
            var conflictedRecords = error!.userInfo![CKSSyncConflictedResolvedRecordsKey] as! Array<CKRecord>
            
            for record in conflictedRecords
            {
                insertedOrUpdatedCKRecordsWithRecordIDStrings[record.recordID.recordName] = record
            }
            
            insertedOrUpdatedCKRecords = insertedOrUpdatedCKRecordsWithRecordIDStrings.values.array
            error = nil
            wasSuccessful = self.applyLocalChangesToServer(insertedOrUpdatedCKRecords, deletedCKRecordIDs: deletedCKRecordIDs, error: &error)
            
            if !wasSuccessful && error != nil
            {
                return false
            }
        }
        
        var moreComing = true
        var insertedOrUpdatedCKRecordsFromServer = Array<CKRecord>()
        var deletedCKRecordIDsFromServer = Array<CKRecordID>()
        while moreComing
        {
            var returnValue = self.fetchRecordChangesFromServer()
            insertedOrUpdatedCKRecordsFromServer += returnValue.insertedOrUpdatedCKRecords
            deletedCKRecordIDsFromServer += returnValue.deletedRecordIDs
            moreComing = returnValue.moreComing
        }
        
        return self.applyServerChangesToLocalDatabase(insertedOrUpdatedCKRecordsFromServer, deletedCKRecordIDs: deletedCKRecordIDsFromServer)
        
    }
    
    // MARK: Server Change Token
    func savedCKServerChangeToken()->CKServerChangeToken?
    {
        if NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreSyncOperationFetchChangeTokenKey) != nil
        {
            var fetchTokenKeyArchived = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreSyncOperationFetchChangeTokenKey) as! NSData
            return NSKeyedUnarchiver.unarchiveObjectWithData(fetchTokenKeyArchived) as? CKServerChangeToken
        }
        
        return nil
    }
    
    func saveServerChangeToken(#serverChangeToken:CKServerChangeToken)
    {
        NSUserDefaults.standardUserDefaults().setObject(NSKeyedArchiver.archivedDataWithRootObject(serverChangeToken), forKey: CKSIncrementalStoreSyncOperationFetchChangeTokenKey)
    }
    
    func deleteSavedServerChangeToken()
    {
        if self.savedCKServerChangeToken() != nil
        {
            NSUserDefaults.standardUserDefaults().setObject(nil, forKey: CKSIncrementalStoreSyncOperationFetchChangeTokenKey)
        }
    }
    
    // MARK: Local Changes
    func localChanges()->(insertedOrUpdatedManagedObjects:Array<AnyObject>,deletedManagedObjects:Array<AnyObject>)
    {
        var entityNames = self.localStoreMOC?.persistentStoreCoordinator?.managedObjectModel.entities.map({(entity)->String in
            
            return (entity as! NSEntityDescription).name!
        })
        
        var deletedManagedObjects:Array<AnyObject> = Array<AnyObject>()
        var insertedOrUpdatedManagedObjects:Array<AnyObject> = Array<AnyObject>()
        
        var predicate = NSPredicate(format: "%K != %@", CKSIncrementalStoreLocalStoreChangeTypeAttributeName, NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue))
        
        for name in entityNames!
        {
            var fetchRequest=NSFetchRequest(entityName: name)
            fetchRequest.predicate = predicate
            
            var error:NSErrorPointer=nil
            var results = self.localStoreMOC?.executeFetchRequest(fetchRequest, error: error)
            if error == nil && results?.count > 0
            {
                insertedOrUpdatedManagedObjects += (results!.filter({(object)->Bool in
                    
                    var managedObject:NSManagedObject = object as! NSManagedObject
                    if (managedObject.valueForKey(CKSIncrementalStoreLocalStoreChangeTypeAttributeName)) as! NSNumber == NSNumber(short: CKSLocalStoreRecordChangeType.RecordUpdated.rawValue)
                    {
                        return true
                    }
                    return false
                }))
                
                deletedManagedObjects += (results!.filter({(object)->Bool in
                    
                    var managedObject:NSManagedObject = object as! NSManagedObject
                    if (managedObject.valueForKey(CKSIncrementalStoreLocalStoreChangeTypeAttributeName)) as! NSNumber == NSNumber(short: CKSLocalStoreRecordChangeType.RecordDeleted.rawValue)
                    {
                        return true
                    }
                    return false
                }))
                
            }
        }
        
        return (insertedOrUpdatedManagedObjects,deletedManagedObjects)
    }
    
    func localChangesInServerRepresentation(#localChanges:(insertedOrUpdatedManagedObjects:Array<AnyObject>,deletedManagedObjects:Array<AnyObject>))->(insertedOrUpdatedCKRecords:Array<CKRecord>,deletedCKRecordIDs:Array<CKRecordID>)
    {
        return (self.insertedOrUpdatedCKRecords(fromManagedObjects: localChanges.insertedOrUpdatedManagedObjects),self.deletedCKRecordIDs(fromManagedObjects: localChanges.deletedManagedObjects))
    }
    
    func ckRecord(fromEncodedSystemFields encodedFields: NSData) -> CKRecord
    {
        var coder = NSKeyedUnarchiver(forReadingWithData: encodedFields)
        var ckRecord = CKRecord(coder: coder)
        coder.finishDecoding()
        return ckRecord
    }
    
    func encodedSystemFields(fromCkRecord ckRecord: CKRecord) -> NSData
    {
        var data = NSMutableData()
        var coder = NSKeyedArchiver(forWritingWithMutableData: data)
        ckRecord.encodeSystemFieldsWithCoder(coder)
        coder.finishEncoding()
        
        return data
    }
    
    func insertedOrUpdatedCKRecords(fromManagedObjects managedObjects:Array<AnyObject>)->Array<CKRecord>
    {
        return managedObjects.map({(object)->CKRecord in
            
            var managedObject:NSManagedObject = object as! NSManagedObject
            var ckRecordID = CKRecordID(recordName: (managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String), zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName))
            
            var ckRecord:CKRecord
            if managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName) != nil
            {
                var encodedSystemFields = managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName) as! NSData
                ckRecord = self.ckRecord(fromEncodedSystemFields: encodedSystemFields)
            }
                
            else
            {
                ckRecord = CKRecord(recordType: (managedObject.entity.name)!, recordID: ckRecordID)
            }
            
            var entityProperties = managedObject.entity.properties.filter({(object)->Bool in
                
                if object is NSAttributeDescription
                {
                    var attributeDescription:NSAttributeDescription = object as! NSAttributeDescription
                    
                    if attributeDescription.name == CKSIncrementalStoreLocalStoreChangeTypeAttributeName || attributeDescription.name == CKSIncrementalStoreLocalStoreRecordIDAttributeName || attributeDescription.name == CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName
                    {
                        return false
                    }
                }
                return true
            })
            
            var entityAttributes = managedObject.entity.attributesByName.values.array.filter({(object) -> Bool in
                
                var attribute: NSAttributeDescription = object as! NSAttributeDescription
                if attribute.name == CKSIncrementalStoreLocalStoreRecordIDAttributeName || attribute.name == CKSIncrementalStoreLocalStoreChangeTypeAttributeName || attribute.name == CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName
                {
                    return false
                }
                
                return true
            })
            
            var entityRelationships = managedObject.entity.relationshipsByName.values.array.filter({(object) -> Bool in
                
                var relationship: NSRelationshipDescription = object as! NSRelationshipDescription
                return relationship.toMany == false
            })
            
            for attributeDescription in entityAttributes as! [NSAttributeDescription]
            {
                if managedObject.valueForKey(attributeDescription.name) != nil
                {
                    switch attributeDescription.attributeType
                    {
                    case .StringAttributeType:
                        ckRecord.setObject(managedObject.valueForKey(attributeDescription.name) as! String, forKey: attributeDescription.name)
                        
                    case .DateAttributeType:
                        ckRecord.setObject(managedObject.valueForKey(attributeDescription.name) as! NSDate, forKey: attributeDescription.name)
                        
                    case .BinaryDataAttributeType:
                        ckRecord.setObject(managedObject.valueForKey(attributeDescription.name) as! NSData, forKey: attributeDescription.name)
                        
                    case .BooleanAttributeType, .DecimalAttributeType, .DoubleAttributeType, .FloatAttributeType, .Integer16AttributeType, .Integer32AttributeType, .Integer32AttributeType, .Integer64AttributeType:
                        ckRecord.setObject(managedObject.valueForKey(attributeDescription.name) as! NSNumber, forKey: attributeDescription.name)
                        
                    default:
                        break
                    }
                }
            }
            
            for relationshipDescription in entityRelationships as! [NSRelationshipDescription]
            {
                if managedObject.valueForKey(relationshipDescription.name) == nil
                {
                    continue
                }
                
                var relationshipManagedObject: NSManagedObject = managedObject.valueForKey(relationshipDescription.name) as! NSManagedObject
                var ckRecordZoneID = CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName)
                var relationshipCKRecordID = CKRecordID(recordName: relationshipManagedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String, zoneID: ckRecordZoneID)
                var ckReference = CKReference(recordID: relationshipCKRecordID, action: CKReferenceAction.DeleteSelf)
                ckRecord.setObject(ckReference, forKey: relationshipDescription.name)
            }
            
            return ckRecord
        })
    }
    
    func deletedCKRecordIDs(fromManagedObjects managedObjects:Array<AnyObject>)->Array<CKRecordID>
    {
        return managedObjects.map({(object)->CKRecordID in
            
            var managedObject:NSManagedObject = object as! NSManagedObject
            var ckRecordID = CKRecordID(recordName: managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String, zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName))
            
            return ckRecordID
        })
    }
    
    func fetchRecordChangesFromServer()->(insertedOrUpdatedCKRecords:Array<CKRecord>,deletedRecordIDs:Array<CKRecordID>,moreComing:Bool)
    {
        var fetchRecordChangesOperation = CKFetchRecordChangesOperation(recordZoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName), previousServerChangeToken:self.savedCKServerChangeToken())
        
        var insertedOrUpdatedCKRecords:Array<CKRecord> = Array<CKRecord>()
        var deletedCKRecordIDs:Array<CKRecordID> = Array<CKRecordID>()
        
        fetchRecordChangesOperation.fetchRecordChangesCompletionBlock = ({(serverChangeToken,clientChangeToken,operationError)->Void in
            
            if operationError == nil
            {
                self.saveServerChangeToken(serverChangeToken: serverChangeToken)
            }
        })
        
        fetchRecordChangesOperation.recordChangedBlock = ({(record)->Void in
            
            var ckRecord:CKRecord = record as CKRecord
            insertedOrUpdatedCKRecords.append(ckRecord)
        })
        
        fetchRecordChangesOperation.recordWithIDWasDeletedBlock = ({(recordID)->Void in
            
            deletedCKRecordIDs.append(recordID as CKRecordID)
        })
        
        self.operationQueue?.addOperation(fetchRecordChangesOperation)
        self.operationQueue?.waitUntilAllOperationsAreFinished()
        return (insertedOrUpdatedCKRecords,deletedCKRecordIDs,fetchRecordChangesOperation.moreComing)
    }
    
    func applyServerChangesToLocalDatabase(insertedOrUpdatedCKRecords:Array<AnyObject>,deletedCKRecordIDs:Array<AnyObject>)->Bool
    {
        return self.deleteManagedObjects(fromCKRecordIDs: deletedCKRecordIDs) && self.insertOrUpdateManagedObjects(fromCKRecords: insertedOrUpdatedCKRecords)
    }
    
    func applyLocalChangesToServer(insertedOrUpdatedCKRecords:Array<AnyObject>,deletedCKRecordIDs:Array<AnyObject>,error:NSErrorPointer)->Bool
    {
        var wasSuccessful = false
        var ckModifyRecordsOperation = CKModifyRecordsOperation(recordsToSave: insertedOrUpdatedCKRecords, recordIDsToDelete: deletedCKRecordIDs)
        ckModifyRecordsOperation.atomic = true
        var savedRecords:[CKRecord]?
        var conflictedRecords:[CKRecord] = [CKRecord]()
        ckModifyRecordsOperation.modifyRecordsCompletionBlock = ({(savedRecords,deletedRecordIDs,operationError)->Void in
            
            var error:NSError? = operationError
            if error == nil
            {
                wasSuccessful = true
            }
            else
            {
                wasSuccessful = false
            }
        })
        ckModifyRecordsOperation.perRecordCompletionBlock = ({(ckRecord,operationError)->Void in
            
            var error:NSError? = operationError
            
            if error == nil
            {
            }
            else
            {
                if error!.code == CKErrorCode.ServerRecordChanged.rawValue
                {
                    conflictedRecords.append(ckRecord)
                }
            }
            
        })
        
        self.operationQueue?.addOperation(ckModifyRecordsOperation)
        self.operationQueue?.waitUntilAllOperationsAreFinished()
        
        if conflictedRecords.count > 0
        {
            var conflictedRecordsWithStringRecordIDs:Dictionary<String,(clientRecord:CKRecord?,serverRecord:CKRecord?)> = Dictionary<String,(clientRecord:CKRecord?,serverRecord:CKRecord?)>()
            
            for record in conflictedRecords
            {
                conflictedRecordsWithStringRecordIDs[record.recordID.recordName] = (record,nil)
            }
            
            var ckFetchRecordsOperation:CKFetchRecordsOperation = CKFetchRecordsOperation(recordIDs: conflictedRecords.map({(object)-> CKRecordID in
                
                var ckRecord:CKRecord = object as CKRecord
                return ckRecord.recordID
            }))
            
            ckFetchRecordsOperation.perRecordCompletionBlock = ({(record,recordID,error)->Void in
                
                if error == nil
                {
                    var ckRecord:CKRecord = record as CKRecord
                    var ckRecordID:CKRecordID = recordID as CKRecordID
                    if conflictedRecordsWithStringRecordIDs[ckRecordID.recordName] != nil
                    {
                        conflictedRecordsWithStringRecordIDs[ckRecordID.recordName] = (conflictedRecordsWithStringRecordIDs[ckRecordID.recordName]!.clientRecord,ckRecord)
                    }
                    wasSuccessful = true
                }
                else
                {
                    wasSuccessful = false
                }
            })
            self.operationQueue?.addOperation(ckFetchRecordsOperation)
            self.operationQueue?.waitUntilAllOperationsAreFinished()
            
            var finalCKRecords:[CKRecord] = [CKRecord]()
            
            for key in conflictedRecordsWithStringRecordIDs.keys.array
            {
                var value = conflictedRecordsWithStringRecordIDs[key]!
                var clientServerCKRecord = value as (clientRecord:CKRecord?,serverRecord:CKRecord?)
                
                if self.syncConflictPolicy == CKSStoresSyncConflictPolicy.ClientTellsWhichWins
                {
                    if self.syncConflictResolutionBlock != nil
                    {
                        clientServerCKRecord.serverRecord = self.syncConflictResolutionBlock!(clientRecord: clientServerCKRecord.clientRecord!,serverRecord: clientServerCKRecord.serverRecord!)
                    }
                }
                else if (self.syncConflictPolicy == CKSStoresSyncConflictPolicy.ClientRecordWins || (self.syncConflictPolicy == CKSStoresSyncConflictPolicy.GreaterModifiedDateWins && clientServerCKRecord.clientRecord!.modificationDate.compare(clientServerCKRecord.serverRecord!.modificationDate) == NSComparisonResult.OrderedDescending))
                {
                    var keys = clientServerCKRecord.serverRecord!.allKeys()
                    var values = clientServerCKRecord.clientRecord!.dictionaryWithValuesForKeys(keys)
                    clientServerCKRecord.serverRecord!.setValuesForKeysWithDictionary(values)
                }
                
                finalCKRecords.append(clientServerCKRecord.serverRecord!)
            }
            
            var userInfo:Dictionary<String,Array<CKRecord>> = [CKSSyncConflictedResolvedRecordsKey:finalCKRecords]
            
            error.memory = NSError(domain: CKSIncrementalStoreSyncOperationErrorDomain, code: 1, userInfo: userInfo)
            wasSuccessful = false
            return false
        }
        
        if savedRecords != nil
        {
            var savedRecordsWithIDStrings = savedRecords!.map({(object)->String in
                
                var ckRecord:CKRecord = object as CKRecord
                return ckRecord.recordID.recordName
            })
            
            var savedRecordsWithType:Dictionary<String,Dictionary<String,CKRecord>> = Dictionary<String,Dictionary<String,CKRecord>>()
            
            for record in savedRecords!
            {
                if savedRecordsWithType[record.recordType] != nil
                {
                    savedRecordsWithType[record.recordType]![record.recordID.recordName] = record
                    continue
                }
                var recordWithRecordIDString:Dictionary<String,CKRecord> = Dictionary<String,CKRecord>()
                savedRecordsWithType[record.recordType] = recordWithRecordIDString
            }
            
            var predicate = NSPredicate(format: "%K IN $recordIDStrings",CKSIncrementalStoreLocalStoreRecordIDAttributeName)
            
            var types = savedRecordsWithType.keys.array
            
            var ckRecordsManagedObjects:Array<(ckRecord:CKRecord,managedObject:NSManagedObject)> = Array<(ckRecord:CKRecord,managedObject:NSManagedObject)>()
            
            for type in types
            {
                var fetchRequest = NSFetchRequest(entityName: type)
                var ckRecordsForType = savedRecordsWithType[type]
                var ckRecordIDStrings = ckRecordsForType!.keys.array
                
                fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["recordIDStrings":ckRecordIDStrings])
                var error:NSErrorPointer = nil
                var results = self.localStoreMOC?.executeFetchRequest(fetchRequest, error: error)
                if error == nil && results?.count > 0
                {
                    for managedObject in results as! [NSManagedObject]
                    {
                        var ckRecord = ckRecordsForType![managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String]
                       managedObject.setValue(self.encodedSystemFields(fromCkRecord: ckRecord!), forKey: CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName)
                    }
                }
            }
            
            var error:NSErrorPointer = nil
            self.localStoreMOC!.save(error)
            
            if error == nil
            {
                return true
            }
            else
            {
                return false
            }
        }
        return wasSuccessful
    }
    
    func insertOrUpdateManagedObjects(fromCKRecords ckRecords:Array<AnyObject>)->Bool
    {
        var predicate = NSPredicate(format: "%K == $ckRecordIDString",CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        
        for object in ckRecords
        {
            var ckRecord:CKRecord = object as! CKRecord
            var fetchRequest = NSFetchRequest(entityName: ckRecord.recordType)
            var error:NSErrorPointer = nil
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["ckRecordIDString":ckRecord.recordID.recordName])
            fetchRequest.fetchLimit = 1
            var results = self.localStoreMOC?.executeFetchRequest(fetchRequest, error: error)
            
            if error == nil && results?.count > 0
            {
                var managedObject = results?.first as! NSManagedObject
                var recordIDString = managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                
                var keys = ckRecord.allKeys().filter({(obj)->Bool in
                    
                    if ckRecord.objectForKey(obj as! String) is CKReference
                    {
                        return false
                    }
                    return true
                })
                
                var values = ckRecord.dictionaryWithValuesForKeys(keys)
                managedObject.setValuesForKeysWithDictionary(values)
                managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
                
                var data = NSMutableData()
                var coder = NSKeyedArchiver(forWritingWithMutableData: data)
                ckRecord.encodeSystemFieldsWithCoder(coder)
                coder.finishEncoding()
                managedObject.setValue(data, forKey: CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName)
                
                var changedCKReferenceRecordIDStringsWithKeys = ckRecord.allKeys().filter({(obj)->Bool in
                    
                    if ckRecord.objectForKey(obj as! String) is CKReference
                    {
                        return true
                    }
                    return false
                    
                }).map({(obj)->(key:String,recordIDString:String) in
                    
                    var key:String = obj as! String
                    return (key,(ckRecord.objectForKey(key) as! CKReference).recordID.recordName)
                })
                
                for object in changedCKReferenceRecordIDStringsWithKeys
                {
                    var attributeEntityName = (managedObject.entity.relationshipsByName[object.key] as! NSRelationshipDescription).destinationEntity?.name
                    var fetchRequest = NSFetchRequest(entityName: attributeEntityName!)
                    fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,object.recordIDString)
                    var error:NSErrorPointer = nil
                    var results = self.localStoreMOC?.executeFetchRequest(fetchRequest, error: error)
                    if error == nil && results!.count > 0
                    {
                        managedObject.setValue(results?.first, forKey: object.key)
                        break
                    }
                    
                }
            }
            else
            {
                var managedObject:NSManagedObject = NSEntityDescription.insertNewObjectForEntityForName(ckRecord.recordType, inManagedObjectContext: self.localStoreMOC!) as! NSManagedObject
                var keys = ckRecord.allKeys().filter({(object)->Bool in
                    
                    var key:String = object as! String
                    if ckRecord.objectForKey(key) is CKReference
                    {
                        return false
                    }
                    
                    return true
                })

                managedObject.setValue(self.encodedSystemFields(fromCkRecord: ckRecord), forKey: CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName)
                var changedCKReferencesRecordIDsWithKeys = ckRecord.allKeys().filter({(object)->Bool in
                    
                    var key:String = object as! String
                    if ckRecord.objectForKey(key) is CKReference
                    {
                        return true
                    }
                    return false
                    
                }).map({(object)->(key:String,recordIDString:String) in
                    
                    var key:String = object as! String
                    
                    return (key,(ckRecord.objectForKey(key) as! CKReference).recordID.recordName)
                })
                
                var values = ckRecord.dictionaryWithValuesForKeys(keys)
                managedObject.setValuesForKeysWithDictionary(values)
                managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
                managedObject.setValue(ckRecord.recordID.recordName, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
                
                
                for object in changedCKReferencesRecordIDsWithKeys
                {
                    var ckReferenceRecordIDString:String = object.recordIDString
                    var referenceManagedObject = Array(self.localStoreMOC!.registeredObjects).filter({(object)->Bool in
                        
                        var managedObject:NSManagedObject = object as! NSManagedObject
                        if (managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String) == ckReferenceRecordIDString
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
                        var attributeEntityName = (managedObject.entity.relationshipsByName[object.key] as! NSRelationshipDescription).destinationEntity?.name
                        var fetchRequest = NSFetchRequest(entityName: attributeEntityName!)
                        fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,ckReferenceRecordIDString)
                        fetchRequest.fetchLimit = 1
                        var error:NSErrorPointer = nil
                        var results = self.localStoreMOC?.executeFetchRequest(fetchRequest, error: error)
                        if error == nil && results?.count > 0
                        {
                            managedObject.setValue(results?.first as! NSManagedObject, forKey: object.key)
                            break
                        }
                    }
                }
            }
        }
        
        if self.localStoreMOC!.hasChanges
        {
            var error:NSErrorPointer = nil
            self.localStoreMOC!.save(error)
            if error == nil
            {
                return true
            }
        }
        else
        {
            return true
        }
        return false
    }
    
    func deleteManagedObjects(fromCKRecordIDs ckRecordIDs:Array<AnyObject>)->Bool
    {
        var predicate = NSPredicate(format: "%K IN $ckRecordIDs",CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        
        var ckRecordIDStrings = ckRecordIDs.map({(object)->String in
            
            var ckRecordID:CKRecordID = object as! CKRecordID
            return ckRecordID.recordName
        })
        
        var entityNames = self.localStoreMOC?.persistentStoreCoordinator?.managedObjectModel.entitiesByName.keys.array
        
        for name in entityNames!
        {
            var fetchRequest = NSFetchRequest(entityName: name as! String)
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["ckRecordIDs":ckRecordIDStrings])
            var error:NSErrorPointer = nil
            var results = self.localStoreMOC?.executeFetchRequest(fetchRequest, error: error)
            if error == nil && results?.count > 0
            {
                for object in results as! [NSManagedObject]
                {
                    self.localStoreMOC?.deleteObject(object)
                }
                
            }
        }
        
        var error:NSErrorPointer = nil
        self.localStoreMOC?.save(error)
        
        
        if error == nil
        {
            return true
        }
        
        return false
    }
}

