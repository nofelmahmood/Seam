//
//  CloudKitIncrementalStore.swift
//  
//
//  Created by Nofel Mahmood on 26/03/2015.
//
//

import CoreData
import CloudKit
import ObjectiveC


let CKSIncrementalStoreSyncOperationErrorDomain = "CKSIncrementalStoreSyncOperationErrorDomain"
let CKSSyncConflictedResolvedRecordsKey = "CKSSyncConflictedResolvedRecordsKey"
let CKSIncrementalStoreSyncOperationFetchChangeTokenKey = "CKSIncrementalStoreSyncOperationFetchChangeTokenKey"
class CKSIncrementalStoreSyncOperation: NSOperation {
    
    private var operationQueue:NSOperationQueue?
    private var localStoreMOC:NSManagedObjectContext?
    private var persistentStoreCoordinator:NSPersistentStoreCoordinator?
    private var syncConflictPolicy:CKSStoresSyncConflictPolicy?
    private var syncCompletionBlock:((syncError:NSError?) -> ())?
    private var syncConflictResolutionBlock:((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    
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
    
    func insertedOrUpdatedCKRecords(fromManagedObjects managedObjects:Array<AnyObject>)->Array<CKRecord>
    {
        return managedObjects.map({(object)->CKRecord in
            
            var managedObject:NSManagedObject = object as! NSManagedObject
            var ckRecordID = CKRecordID(recordName: (managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String), zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName))
            
            var ckRecord:CKRecord
            if managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName) != nil
            {
                var encodedSystemFields = managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName) as! NSData
                var coder = NSKeyedUnarchiver(forReadingWithData: encodedSystemFields)
                ckRecord = CKRecord(coder: coder)
                coder.finishDecoding()
            }
            else
            {
                ckRecord = CKRecord(recordType: (managedObject.entity.name)!, recordID: ckRecordID)
            }
            
            var entityProperties = managedObject.entity.properties.filter({(object)->Bool in
                
                if object is NSAttributeDescription
                {
                    var attributeDescription:NSAttributeDescription = object as! NSAttributeDescription
                    switch attributeDescription.name
                    {
                    case CKSIncrementalStoreLocalStoreRecordIDAttributeName,CKSIncrementalStoreLocalStoreChangeTypeAttributeName,CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName:
                        return false
                    default:
                        break
                    }
                }
                return true
            })
            
            for property in entityProperties
            {
                var propertyDescription: NSPropertyDescription = property as! NSPropertyDescription
                
                if managedObject.valueForKey(propertyDescription.name) != nil
                {
                    if property is NSAttributeDescription
                    {
                        var attributeDescription:NSAttributeDescription = property as! NSAttributeDescription
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
                    else if property is NSRelationshipDescription
                    {
                        var relationshipDescription:NSRelationshipDescription = property as! NSRelationshipDescription
                        if managedObject.valueForKey(relationshipDescription.name) != nil
                        {
                            if relationshipDescription.toMany == false
                            {
                                var relationshipManagedObject:NSManagedObject = managedObject.valueForKey(relationshipDescription.name) as! NSManagedObject
                                var relationshipCKRecordID = CKRecordID(recordName: relationshipManagedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String, zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName))
                                
                                var ckReference = CKReference(recordID: relationshipCKRecordID, action: CKReferenceAction.DeleteSelf)
                                ckRecord.setObject(ckReference, forKey: relationshipDescription.name)
                            }
                        }
                        
                        //                    else
                        //                    {
                        //                        var relationshipManagedObjects:Array<AnyObject> = managedObject.valueForKey(relationshipDescription.name) as! Array<AnyObject>
                        //                        var ckReferences = relationshipManagedObjects.map({(object)->CKReference in
                        //
                        //                            var managedObject:NSManagedObject = object as! NSManagedObject
                        //                            var ckRecordID = CKRecordID(recordName: managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String, zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName))
                        //                            var ckReference = CKReference(recordID: ckRecordID, action: CKReferenceAction.DeleteSelf)
                        //                            return ckReference
                        //                        })
                        //                        ckRecord.setObject(ckReferences, forKey: relationshipDescription.name)
                        //                    }
                    }
                }
                
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
                
                if self.syncConflictPolicy == CKSStoresSyncConflictPolicy.UserTellsWhichWins
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
                        var data = NSMutableData()
                        var coder = NSKeyedArchiver(forWritingWithMutableData: data)
                        ckRecord!.encodeSystemFieldsWithCoder(coder)
                        managedObject.setValue(data, forKey: CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName)
                        coder.finishEncoding()
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
                var data = NSMutableData()
                var coder = NSKeyedArchiver(forWritingWithMutableData: data)
                ckRecord.encodeSystemFieldsWithCoder(coder)
                coder.finishEncoding()
                managedObject.setValue(data, forKey: CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName)
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


let CKSIncrementalStoreCloudStoreCustomZoneKey = "CKSIncrementalStoreCloudStoreCustomZoneKey"
let CKSIncrementalStoreCloudStoreZoneSubcriptionKey = "CKSIncrementalStoreCloudStoreZoneSubcriptionKey"


class CKSIncrementalStoreCloudStoreSetupOperation:NSOperation {
    
    var database:CKDatabase?
    var setupOperationCompletionBlock:((customZoneCreated:Bool,customZoneSubscriptionCreated:Bool,error:NSError?)->Void)?
    
    
    init(cloudDatabase:CKDatabase?) {
        
        self.database = cloudDatabase
        super.init()
    }
    
    override func main() {
        
        var error:NSError?
        
        var operationQueue = NSOperationQueue()
        var zone = CKRecordZone(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName)
        
        var modifyRecordZonesOperation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        modifyRecordZonesOperation.database = self.database
        modifyRecordZonesOperation.modifyRecordZonesCompletionBlock = ({(savedRecordZones,deletedRecordZonesIDs , operationError) -> Void in
            
            error = operationError
            var customZoneWasCreated:AnyObject? = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreCustomZoneKey)
            var customZoneSubscriptionWasCreated:AnyObject? = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreZoneSubcriptionKey)
            
            if ((operationError == nil || customZoneWasCreated != nil) && customZoneSubscriptionWasCreated == nil)
            {
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: CKSIncrementalStoreCloudStoreCustomZoneKey)
                var subcription:CKSubscription = CKSubscription(zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName), subscriptionID: CKSIncrementalStoreCloudDatabaseSyncSubcriptionName, options: nil)
                
                var subcriptionNotificationInfo = CKNotificationInfo()
                subcriptionNotificationInfo.alertBody = ""
                subcriptionNotificationInfo.shouldSendContentAvailable = true
                subcription.notificationInfo = subcriptionNotificationInfo
                subcriptionNotificationInfo.shouldBadge = false
                
                var subcriptionsOperation = CKModifySubscriptionsOperation(subscriptionsToSave: [subcription], subscriptionIDsToDelete: nil)
                subcriptionsOperation.database=self.database
                subcriptionsOperation.modifySubscriptionsCompletionBlock=({ (modified,created,operationError) -> Void in
                    
                    error = operationError
                    if operationError == nil
                    {
                        NSUserDefaults.standardUserDefaults().setBool(true, forKey: CKSIncrementalStoreCloudStoreZoneSubcriptionKey)
                    }
                })
                
                operationQueue.addOperation(subcriptionsOperation)
            }
        })
        
        operationQueue.addOperation(modifyRecordZonesOperation)
        operationQueue.waitUntilAllOperationsAreFinished()
        
        if self.setupOperationCompletionBlock != nil
        {
            if error == nil
            {
                self.setupOperationCompletionBlock!(customZoneCreated: true,customZoneSubscriptionCreated: true,error: error)
            }
            else
            {
                if NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreCustomZoneKey) == nil
                {
                    self.setupOperationCompletionBlock!(customZoneCreated: false, customZoneSubscriptionCreated: false, error: error)
                }
                else
                {
                    self.setupOperationCompletionBlock!(customZoneCreated: true, customZoneSubscriptionCreated: false, error: error)
                }
            }
        }
    }
}

let CKSIncrementalStoreCloudDatabaseCustomZoneName="CKSIncrementalStoreZone"
let CKSIncrementalStoreCloudDatabaseSyncSubcriptionName="CKSIncrementalStore_Sync_Subcription"

let CKSIncrementalStoreLocalStoreChangeTypeAttributeName="cks_LocalStore_Attribute_ChangeType"
let CKSIncrementalStoreLocalStoreRecordIDAttributeName="cks_LocalStore_Attribute_RecordID"
let CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName = "cks_LocalStore_Attribute_EncodedValues"

let CKSIncrementalStoreDidStartSyncOperationNotification = "CKSIncrementalStoreDidStartSyncOperationNotification"
let CKSIncrementalStoreDidFinishSyncOperationNotification = "CKSIncrementalStoreDidFinishSyncOperationNotification"

let CKSIncrementalStoreSyncConflictPolicyOption = "CKSIncrementalStoreSyncConflictPolicyOption"

enum CKSLocalStoreRecordChangeType:Int16
{
    case RecordNoChange = 0
    case RecordUpdated  = 1
    case RecordDeleted  = 2
}

enum CKSStoresSyncConflictPolicy:Int16
{
    case UserTellsWhichWins = 0
    case ServerRecordWins = 1
    case ClientRecordWins = 2
    case GreaterModifiedDateWins = 3
    case KeepBoth = 4
}

class CKSIncrementalStore: NSIncrementalStore {
    
    private var syncOperation:CKSIncrementalStoreSyncOperation?
    private var cloudStoreSetupOperation:CKSIncrementalStoreCloudStoreSetupOperation?
    private var cksStoresSyncConflictPolicy:CKSStoresSyncConflictPolicy = CKSStoresSyncConflictPolicy.GreaterModifiedDateWins
    private var database:CKDatabase?
    private var operationQueue:NSOperationQueue?
    private var backingPersistentStoreCoordinator:NSPersistentStoreCoordinator?
    private var backingPersistentStore:NSPersistentStore?
    private lazy var backingMOC:NSManagedObjectContext={
        
        var moc=NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        moc.persistentStoreCoordinator=self.backingPersistentStoreCoordinator
        moc.retainsRegisteredObjects=true
        return moc
    }()
    var recordConflictResolutionBlock:((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    
    override class func initialize()
    {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    
    override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator, configurationName name: String?, URL url: NSURL, options: [NSObject : AnyObject]?) {
        
        self.database=CKContainer.defaultContainer().privateCloudDatabase
        if options != nil
        {
            if options![CKSIncrementalStoreSyncConflictPolicyOption] != nil
            {
                var syncConflictPolicy = options![CKSIncrementalStoreSyncConflictPolicyOption] as! NSNumber
                
                switch(syncConflictPolicy.shortValue)
                {
                case CKSStoresSyncConflictPolicy.ClientRecordWins.rawValue:
                    self.cksStoresSyncConflictPolicy = CKSStoresSyncConflictPolicy.ClientRecordWins
                case CKSStoresSyncConflictPolicy.ServerRecordWins.rawValue:
                    self.cksStoresSyncConflictPolicy = CKSStoresSyncConflictPolicy.ServerRecordWins
                case CKSStoresSyncConflictPolicy.UserTellsWhichWins.rawValue:
                    self.cksStoresSyncConflictPolicy = CKSStoresSyncConflictPolicy.UserTellsWhichWins
                case CKSStoresSyncConflictPolicy.GreaterModifiedDateWins.rawValue:
                    self.cksStoresSyncConflictPolicy = CKSStoresSyncConflictPolicy.GreaterModifiedDateWins
                default:
                    break
                }

            }
        }

        super.init(persistentStoreCoordinator: root, configurationName: name, URL: url, options: options)
        
    }
    
    class var type:String{
        return NSStringFromClass(self)
    }
    
    override func loadMetadata(error: NSErrorPointer) -> Bool {
        
        self.metadata=[
            NSStoreUUIDKey:NSProcessInfo().globallyUniqueString,
            NSStoreTypeKey:self.dynamicType.type
        ]
        var storeURL=self.URL
        var model:AnyObject=(self.persistentStoreCoordinator?.managedObjectModel.copy())!
        for e in model.entities
        {
            var entity=e as! NSEntityDescription
            
            if entity.superentity != nil
            {
                continue
            }
            
            var recordIDAttributeDescription = NSAttributeDescription()
            recordIDAttributeDescription.name=CKSIncrementalStoreLocalStoreRecordIDAttributeName
            recordIDAttributeDescription.attributeType=NSAttributeType.StringAttributeType
            recordIDAttributeDescription.indexed=true
            
            var recordEncodedValuesAttributeDescription = NSAttributeDescription()
            recordEncodedValuesAttributeDescription.name = CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName
            recordEncodedValuesAttributeDescription.attributeType = NSAttributeType.BinaryDataAttributeType
            recordEncodedValuesAttributeDescription.indexed = true
            recordEncodedValuesAttributeDescription.optional = true
            
            var recordChangeTypeAttributeDescription = NSAttributeDescription()
            recordChangeTypeAttributeDescription.name = CKSIncrementalStoreLocalStoreChangeTypeAttributeName
            recordChangeTypeAttributeDescription.attributeType = NSAttributeType.Integer16AttributeType
            recordChangeTypeAttributeDescription.indexed = true
            recordChangeTypeAttributeDescription.defaultValue = NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue)
            
            entity.properties.append(recordIDAttributeDescription)
            entity.properties.append(recordEncodedValuesAttributeDescription)
            entity.properties.append(recordChangeTypeAttributeDescription)
            
        }
        
        
        self.backingPersistentStoreCoordinator=NSPersistentStoreCoordinator(managedObjectModel: model as! NSManagedObjectModel)
        
        var error: NSError? = nil
        self.backingPersistentStore = self.backingPersistentStoreCoordinator?.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: nil, error: &error)
        
        if self.backingPersistentStore == nil
        {
            print("Backing Store Error \(error)")
            return false
        }
        
        self.operationQueue = NSOperationQueue()
        self.operationQueue?.maxConcurrentOperationCount = 1

        self.triggerSync()
        
        return true

    }
    
    internal func handlePush(#userInfo:[NSObject : AnyObject])
    {
        var ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        
        if ckNotification.notificationType == CKNotificationType.RecordZone
        {
            var recordZoneNotification = CKRecordZoneNotification(fromRemoteNotificationDictionary: userInfo)
            if recordZoneNotification.recordZoneID.zoneName == CKSIncrementalStoreCloudDatabaseCustomZoneName
            {
                self.triggerSync()
            }
            
        }
    }
    
    internal func triggerSync()
    {
        if self.operationQueue != nil && self.operationQueue!.operationCount > 0
        {
            return
        }
        
        var syncOperationBlock = ({()->Void in
            
            self.syncOperation = CKSIncrementalStoreSyncOperation(persistentStoreCoordinator: self.backingPersistentStoreCoordinator, conflictPolicy: self.cksStoresSyncConflictPolicy)
            self.syncOperation?.syncConflictResolutionBlock = self.recordConflictResolutionBlock
            self.syncOperation?.syncCompletionBlock =  ({(error) -> Void in
                
                if error == nil
                {
                    print("Sync Performed Successfully")
                    NSOperationQueue.mainQueue().addOperationWithBlock({ () -> Void in
                        
                        NSNotificationCenter.defaultCenter().postNotificationName(CKSIncrementalStoreDidFinishSyncOperationNotification, object: self)
                        
                    })
                    
                }
                else
                {
                    print("Sync unSuccessful")
                    NSOperationQueue.mainQueue().addOperationWithBlock({ () -> Void in
                        
                        NSNotificationCenter.defaultCenter().postNotificationName(CKSIncrementalStoreDidFinishSyncOperationNotification, object: self, userInfo: error!.userInfo)
                    })
                }
                
            })
            self.operationQueue?.addOperation(self.syncOperation!)
        })

        
        if NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreCustomZoneKey) == nil || NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreZoneSubcriptionKey) == nil
        {
            self.cloudStoreSetupOperation = CKSIncrementalStoreCloudStoreSetupOperation(cloudDatabase: self.database)
            self.cloudStoreSetupOperation?.setupOperationCompletionBlock = ({(customZoneWasCreated,customZoneSubscriptionWasCreated,error)->Void in
                
                if error == nil
                {
                    syncOperationBlock()
                }
            })
            self.operationQueue?.addOperation(self.cloudStoreSetupOperation!)
        }
        else
        {
            syncOperationBlock()
        }
        

        NSNotificationCenter.defaultCenter().postNotificationName(CKSIncrementalStoreDidStartSyncOperationNotification, object: self)
        
        
    }
    
    override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext, error: NSErrorPointer) -> AnyObject? {
        
        
        if request.requestType == NSPersistentStoreRequestType.FetchRequestType
        {
            var fetchRequest:NSFetchRequest = request as! NSFetchRequest
            return self.executeInResponseToFetchRequest(fetchRequest, context: context, error: error)
        }
        else if request.requestType==NSPersistentStoreRequestType.SaveRequestType
        {
            var saveChangesRequest:NSSaveChangesRequest = request as! NSSaveChangesRequest
            return self.executeInResponseToSaveChangesRequest(saveChangesRequest, context: context, error: error)
        }
        else
        {
            var exception=NSException(name: "Unknown Request Type", reason: "Unknown Request passed to NSManagedObjectContext", userInfo: nil)
            exception.raise()
        }
        
        return []
    }

    override func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext, error: NSErrorPointer) -> NSIncrementalStoreNode? {
        
        var recordID:String = self.referenceObjectForObjectID(objectID) as! String
        var fetchRequest = NSFetchRequest(entityName: (objectID.entity.name)!)
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,recordID)
        var error:NSErrorPointer = nil
        var results = self.backingMOC.executeFetchRequest(fetchRequest, error: error)
        
        if error == nil && results?.count > 0
        {
            var managedObject:NSManagedObject = results?.first as! NSManagedObject
            self.backingMOC.refreshObject(managedObject, mergeChanges: false)
            var keys = managedObject.entity.propertiesByName.values.array.filter({(property)->Bool in
                
                if property is NSAttributeDescription
                {
                    var attributeDescription: NSAttributeDescription = property as! NSAttributeDescription
                    if attributeDescription.name == CKSIncrementalStoreLocalStoreRecordIDAttributeName || attributeDescription.name == CKSIncrementalStoreLocalStoreChangeTypeAttributeName || attributeDescription.name == CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName
                    {
                        return false
                    }
                    else
                    {
                        return true
                    }
                }
                else if property is NSRelationshipDescription
                {
                    var relationshipDescription: NSRelationshipDescription = property as! NSRelationshipDescription
                    
                    return relationshipDescription.toMany == false
                }
                
                return false
            }).map({(object)->String in
                
                var propertyDescription: NSPropertyDescription = object as! NSPropertyDescription
                
                return propertyDescription.name
            })
            
            
            var values = managedObject.dictionaryWithValuesForKeys(keys)
            for (key,value) in values
            {
                if value is NSManagedObject
                {
                    values[key] = (value as! NSManagedObject).objectID
                }
            }
            var incrementalStoreNode = NSIncrementalStoreNode(objectID: objectID, withValues: values, version: 1)
            return incrementalStoreNode
        }
        
        return nil
    }
    
    override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?, error: NSErrorPointer) -> AnyObject? {
        
        var recordID: String = self.referenceObjectForObjectID(objectID) as! String
        var fetchRequest: NSFetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
        var predicate: NSPredicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,recordID)
        fetchRequest.predicate = predicate
        var results = self.backingMOC.executeFetchRequest(fetchRequest, error: error)
        
        if error.memory == nil && results?.count > 0
        {
            var managedObject: NSManagedObject = results?.first as! NSManagedObject
            var relationshipValues: Set<NSObject> = managedObject.valueForKey(relationship.name) as! Set<NSObject>
            return Array(relationshipValues).map({(object)->NSManagedObjectID in
                
                var value: NSManagedObject = object as! NSManagedObject
                var recordID: String = value.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                var objectID: NSManagedObjectID = self.newObjectIDForEntity(value.entity, referenceObject: recordID)
                return objectID
            })
        }
        
        return []
    }
    
    override func obtainPermanentIDsForObjects(array: [AnyObject], error: NSErrorPointer) -> [AnyObject]? {
        
        return array.map({ (object)->NSManagedObjectID in
            
            var insertedObject:NSManagedObject = object as! NSManagedObject
            var newRecordID: String = NSUUID().UUIDString
            return self.newObjectIDForEntity(insertedObject.entity, referenceObject: newRecordID)
            
        })
    }
    
    // MARK : Fetch Request
    func executeInResponseToFetchRequest(fetchRequest:NSFetchRequest,context:NSManagedObjectContext,error:NSErrorPointer)->NSArray
    {
        var predicate = NSPredicate(format: "%K != %@", CKSIncrementalStoreLocalStoreChangeTypeAttributeName,NSNumber(short: CKSLocalStoreRecordChangeType.RecordDeleted.rawValue))
        
        if fetchRequest.predicate != nil
        {
            fetchRequest.predicate = NSCompoundPredicate(type: NSCompoundPredicateType.AndPredicateType, subpredicates: [(fetchRequest.predicate)!,predicate])
        }
        else
        {
            fetchRequest.predicate = predicate
        }
        
        var error:NSErrorPointer = nil
        var resultsFromLocalStore = self.backingMOC.executeFetchRequest(fetchRequest, error: error)
        if error == nil && resultsFromLocalStore?.count > 0
        {
            resultsFromLocalStore = resultsFromLocalStore?.map({(result)->NSManagedObject in
                
                var managedObject:NSManagedObject = result as! NSManagedObject
                var objectID = self.newObjectIDForEntity((fetchRequest.entity)!, referenceObject: managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName)!)
                var object = context.objectWithID(objectID)
                return object
            })
            
            return resultsFromLocalStore!
        }
        return []
    }

    // MARK : SaveChanges Request
    private func executeInResponseToSaveChangesRequest(saveRequest:NSSaveChangesRequest,context:NSManagedObjectContext,error:NSErrorPointer)->NSArray
    {
        self.insertObjectsInBackingStore(context.insertedObjects)
        self.setObjectsInBackingStore(Array(context.updatedObjects), toChangeType: CKSLocalStoreRecordChangeType.RecordUpdated)
        self.setObjectsInBackingStore(Array(context.deletedObjects), toChangeType: CKSLocalStoreRecordChangeType.RecordDeleted)
        
        var error:NSErrorPointer = nil
        self.backingMOC.save(error)
        self.triggerSync()
        
        return NSArray()
    }

    private func setRelationshipValuesForBackingObject(backingObject:NSManagedObject,sourceObject:NSManagedObject)
    {
        for relationship in sourceObject.entity.relationshipsByName.values.array as! [NSRelationshipDescription]
        {
            if sourceObject.valueForKey(relationship.name) == nil
            {
                continue
            }
            
            if relationship.toMany == true
            {
                var relationshipValue: Set<NSObject> = sourceObject.valueForKey(relationship.name) as! Set<NSObject>
                var referenceObjects = Array(relationshipValue).map({(object)-> String in
                    
                    var managedObject: NSManagedObject = object as! NSManagedObject
                    var referenceObject: String = self.referenceObjectForObjectID(managedObject.objectID) as! String
                    return referenceObject
                })
                
                var fetchRequest: NSFetchRequest = NSFetchRequest(entityName: relationship.entity.name!)
                fetchRequest.predicate = NSPredicate(format: "%K IN %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,referenceObjects)
                fetchRequest.resultType = NSFetchRequestResultType.ManagedObjectIDResultType
                var error: NSError?
                var result = self.backingMOC.executeFetchRequest(fetchRequest, error: &error)
                
                if error == nil && result?.count > 0
                {
                    var backingRelationshipValue: Set<NSObject> = Set<NSObject>()
                    
                    for object in result as! [NSManagedObjectID]
                    {
                        var error: NSError?
                        var backingManagedObject = self.backingMOC.existingObjectWithID(object, error: &error)
                        if backingManagedObject != nil
                        {
                            backingRelationshipValue.insert(backingManagedObject!)
                        }
                    }
                    
                    backingObject.setValue(backingRelationshipValue, forKey: relationship.name)
                }
            }
            else
            {
                var relationshipValue: NSManagedObject = sourceObject.valueForKey(relationship.name) as! NSManagedObject
                var referenceObject: String = self.referenceObjectForObjectID(relationshipValue.objectID) as! String

                var error: NSError?
                var fetchRequest: NSFetchRequest = NSFetchRequest(entityName: relationshipValue.entity.name!)
                fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,referenceObject)
                fetchRequest.resultType = NSFetchRequestResultType.ManagedObjectIDResultType
                var result = self.backingMOC.executeFetchRequest(fetchRequest, error: &error)
                var backingRelationshipObjectID: NSManagedObjectID?
                if error == nil && result?.count > 0
                {
                    backingRelationshipObjectID = result?.last as? NSManagedObjectID
                    if backingRelationshipObjectID != nil
                    {
                        var backingRelationshipObject = self.backingMOC.existingObjectWithID(backingRelationshipObjectID!, error: &error)
                        
                        if backingRelationshipObject != nil
                        {
                            backingObject.setValue(backingRelationshipObject!, forKey: relationship.name)
                        }
                    }
                }
            }
        }
    }
    
    func setRelationshipValuesForBackingObjects(sourceObjectsToBackingObjects:Dictionary<NSManagedObject,NSManagedObject>)
    {
        for (object,backingObject) in sourceObjectsToBackingObjects
        {
            self.setRelationshipValuesForBackingObject(backingObject, sourceObject: object)
        }
    }
    
    func insertObjectsInBackingStore(objects:Set<NSObject>)
    {
        var objectsToBackingObjects: Dictionary<NSManagedObject,NSManagedObject> = Dictionary<NSManagedObject,NSManagedObject>()
        
        for object in objects
        {
            var managedObject:NSManagedObject = NSEntityDescription.insertNewObjectForEntityForName(((object as! NSManagedObject).entity.name)!, inManagedObjectContext: self.backingMOC) as! NSManagedObject
            var values = object.dictionaryWithValuesForKeys((object as! NSManagedObject).entity.propertiesByName.keys.array)
            var keys = (object as! NSManagedObject).entity.attributesByName.keys.array
            var dictionary = object.dictionaryWithValuesForKeys(keys)
            managedObject.setValuesForKeysWithDictionary(dictionary)
            managedObject.setValue(self.referenceObjectForObjectID((object as! NSManagedObject).objectID), forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
            managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordUpdated.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
            objectsToBackingObjects[(object as! NSManagedObject)] = managedObject
        }
        
        self.setRelationshipValuesForBackingObjects(objectsToBackingObjects)
    }
    
    func setObjectsInBackingStore(objects:Array<AnyObject>,toChangeType changeType:CKSLocalStoreRecordChangeType)
    {
        var objectsByEntityNames:Dictionary<String,Array<AnyObject>> = Dictionary<String,Array<AnyObject>>()
        
        for object in objects
        {
            var managedObject = object as! NSManagedObject
            if objectsByEntityNames[(managedObject.entity.name)!] == nil
            {
                objectsByEntityNames[(managedObject.entity.name)!] = [managedObject]
            }
            else
            {
                objectsByEntityNames[(managedObject.entity.name)!]?.append(managedObject)
            }
        }
        
        var objectEntityNames = objectsByEntityNames.keys.array
        for key in objectEntityNames
        {
            var objectsInEntity:Array<AnyObject> = objectsByEntityNames[key]!
            var fetchRequestForBackingObjects = NSFetchRequest(entityName: key)
            var cksRecordIDs = Array(objectsInEntity).map({(object)->String in
                
                var managedObject:NSManagedObject = object as! NSManagedObject
                return self.referenceObjectForObjectID(managedObject.objectID) as! String
            })
            fetchRequestForBackingObjects.predicate = NSPredicate(format: "%K IN %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,cksRecordIDs)
            var error:NSErrorPointer = nil
            var results = self.backingMOC.executeFetchRequest(fetchRequestForBackingObjects, error: error)
            
            if error == nil && results?.count > 0
            {
                var objectsToBackingObjects: Dictionary<NSManagedObject,NSManagedObject> = Dictionary<NSManagedObject,NSManagedObject>()
                
                for var i=0; i<results?.count; i++
                {
                    var managedObject:NSManagedObject = results![i] as! NSManagedObject
                    var updatedObject:NSManagedObject = objectsInEntity[i as Int] as! NSManagedObject
                    var keys = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[(managedObject.entity.name)!]?.attributesByName.keys.array
                    var dictionary = updatedObject.dictionaryWithValuesForKeys(keys!)
                    managedObject.setValuesForKeysWithDictionary(dictionary)
                    managedObject.setValue(NSNumber(short: changeType.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
                    objectsToBackingObjects[updatedObject] = managedObject
                }
                
                self.setRelationshipValuesForBackingObjects(objectsToBackingObjects)
            }
        }
    }
}
