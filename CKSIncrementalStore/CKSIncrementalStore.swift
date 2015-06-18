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

let CKSIncrementalStoreSyncOperationFetchChangeTokenKey = "CKSIncrementalStoreSyncOperationFetchChangeTokenKey"
class CKSIncrementalStoreSyncOperation: NSOperation {
    
    private var operationQueue:NSOperationQueue?
    private var localStoreMOC:NSManagedObjectContext?
    private var persistentStoreCoordinator:NSPersistentStoreCoordinator?
    private var syncCompletionBlock:((syncError:NSError?) -> ())?
    private var syncConflictResolutionBlock:((attemptedRecord:CKRecord,originalRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    
    init(persistentStoreCoordinator:NSPersistentStoreCoordinator?) {
        
        self.persistentStoreCoordinator = persistentStoreCoordinator
        super.init()
    }
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
        var insertedOrUpdatedCKRecords = localChangesInServerRepresentation.insertedOrUpdatedCKRecords
        var deletedCKRecordIDs = localChangesInServerRepresentation.deletedCKRecordIDs
        
        if self.applyLocalChangesToServer(insertedOrUpdatedCKRecords, deletedCKRecordIDs: deletedCKRecordIDs)
        {
            var moreComing = true
            var insertedOrUpdatedCKRecords = Array<CKRecord>()
            var deletedCKRecordIDs = Array<CKRecordID>()
            while moreComing
            {
                var returnValue = self.fetchRecordChangesFromServer()
                insertedOrUpdatedCKRecords += returnValue.insertedOrUpdatedCKRecords
                deletedCKRecordIDs += returnValue.deletedRecordIDs
                moreComing = returnValue.moreComing
            }
            
            return self.applyServerChangesToLocalDatabase(insertedOrUpdatedCKRecords, deletedCKRecordIDs: deletedCKRecordIDs)
        }
        
        return false
    }
    
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
    
    func applyLocalChangesToServer(insertedOrUpdatedCKRecords:Array<AnyObject>,deletedCKRecordIDs:Array<AnyObject>)->Bool
    {
        var wasSuccessful = false
        var ckModifyRecordsOperation = CKModifyRecordsOperation(recordsToSave: insertedOrUpdatedCKRecords, recordIDsToDelete: deletedCKRecordIDs)
        ckModifyRecordsOperation.atomic = true
        ckModifyRecordsOperation.savePolicy = CKRecordSavePolicy.IfServerRecordUnchanged
        var savedRecords:[CKRecord]?
        ckModifyRecordsOperation.modifyRecordsCompletionBlock = ({(savedRecords,deletedRecordIDs,operationError)->Void in
            
            var error:NSError? = operationError
            if error == nil
            {
                wasSuccessful = true
            }
            else
            {
                var userInfo = error!.userInfo
                if self.syncConflictResolutionBlock != nil
                {
                    if error!.code == CKErrorCode.ServerRecordChanged.rawValue
                    {
                        print("Conflict occurred \(userInfo!)")
                    }
                }
            }
        })
        ckModifyRecordsOperation.perRecordCompletionBlock = ({(ckRecord,operationError)->Void in
            
            var error:NSError? = operationError
            
            if error == nil
            {
            }
            else
            {
                if self.syncConflictResolutionBlock != nil
                {
                    if error!.code == CKErrorCode.ServerRecordChanged.rawValue
                    {
                        print("Conflict Occurred in per record Block \(error!.userInfo!)")
                    }
                }
            }
            
        })
        ckModifyRecordsOperation.description
        
        self.operationQueue?.addOperation(ckModifyRecordsOperation)
        self.operationQueue?.waitUntilAllOperationsAreFinished()
        
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
    
    func localChangesInServerRepresentation(#localChanges:(insertedOrUpdatedManagedObjects:Array<AnyObject>,deletedManagedObjects:Array<AnyObject>))->(insertedOrUpdatedCKRecords:Array<AnyObject>,deletedCKRecordIDs:Array<AnyObject>)
    {
        return (self.insertedOrUpdatedCKRecords(fromManagedObjects: localChanges.insertedOrUpdatedManagedObjects),self.deletedCKRecordIDs(fromManagedObjects: localChanges.deletedManagedObjects))
    }
    
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
                managedObject.setValue(data, forKey: CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName)
                coder.finishEncoding()
                
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
    
    func insertedOrUpdatedCKRecords(fromManagedObjects managedObjects:Array<AnyObject>)->Array<AnyObject>
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
                        case CKSIncrementalStoreLocalStoreRecordIDAttributeName,CKSIncrementalStoreLocalStoreChangeTypeAttributeName:
                            return false
                        default:
                            break
                    }
                }
                return true
            })
            
            for property in entityProperties
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
                    if relationshipDescription.toMany == false
                    {
                        var relationshipManagedObject:NSManagedObject = managedObject.valueForKey(relationshipDescription.name) as! NSManagedObject
                        var relationshipCKRecordID = CKRecordID(recordName: relationshipManagedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String, zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName))
                        
                        var ckReference = CKReference(recordID: relationshipCKRecordID, action: CKReferenceAction.DeleteSelf)
                        ckRecord.setObject(ckReference, forKey: relationshipDescription.name)
                    }
                    else
                    {
                        var relationshipManagedObjects:Array<AnyObject> = managedObject.valueForKey(relationshipDescription.name) as! Array<AnyObject>
                        var ckReferences = relationshipManagedObjects.map({(object)->CKReference in
                            
                            var managedObject:NSManagedObject = object as! NSManagedObject
                            var ckRecordID = CKRecordID(recordName: managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String, zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName))
                            var ckReference = CKReference(recordID: ckRecordID, action: CKReferenceAction.DeleteSelf)
                            return ckReference
                        })
                        ckRecord.setObject(ckReferences, forKey: relationshipDescription.name)
                    }
                }
            }
            
            return ckRecord
        })
    }
    
    func deletedCKRecordIDs(fromManagedObjects managedObjects:Array<AnyObject>)->Array<AnyObject>
    {
        return managedObjects.map({(object)->CKRecordID in
            
            var managedObject:NSManagedObject = object as! NSManagedObject
            var ckRecordID = CKRecordID(recordName: managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String, zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName))
            
            return ckRecordID
        })
    }
}


let CKSIncrementalStoreCloudDatabaseCustomZoneName="CKSIncrementalStore_OnlineStoreZone"
let CKSIncrementalStoreCloudDatabaseSyncSubcriptionName="CKSIncrementalStore_Sync_Subcription"


let CKSIncrementalStoreLocalStoreChangeTypeAttributeName="changeType"
let CKSIncrementalStoreLocalStoreRecordIDAttributeName="recordID"
let CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName = "encodedValues"

let CKSIncrementalStoreDidStartSyncOperationNotification = "CKSIncrementalStoreDidStartSyncOperationNotification"
let CKSIncrementalStoreDidFinishSyncOperationNotification = "CKSIncrementalStoreDidFinishSyncOperationNotification"

enum CKSLocalStoreRecordChangeType:Int16
{
    case RecordNoChange = 0
    case RecordUpdated  = 1
    case RecordDeleted  = 2
}

class CKSIncrementalStore: NSIncrementalStore {
    
    var syncOperation:CKSIncrementalStoreSyncOperation?
    private var database:CKDatabase?
    private var operationQueue:NSOperationQueue?
    private var backingPersistentStoreCoordinator:NSPersistentStoreCoordinator?
    private lazy var backingMOC:NSManagedObjectContext={
        
        var moc=NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        moc.persistentStoreCoordinator=self.backingPersistentStoreCoordinator
        moc.retainsRegisteredObjects=true
        return moc
    }()
    var recordConflictResolutionBlock:((attemptedRecord:CKRecord,originalRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    
    override class func initialize()
    {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    
    override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator, configurationName name: String?, URL url: NSURL, options: [NSObject : AnyObject]?) {
        
        self.database=CKContainer.defaultContainer().privateCloudDatabase
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
        self.createCKSCloudDatabaseCustomZone()
        self.createCKSCloudDatabaseCustomZoneSubcription()

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
        if self.backingPersistentStoreCoordinator?.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: nil, error: &error)! == nil
        {
            print("Backing Store Error \(error)")
            return false
        }
        
        self.operationQueue = NSOperationQueue()
        self.operationQueue?.maxConcurrentOperationCount = 1
        self.triggerSync()
        
        return true

    }
    
    func handlePush(#userInfo:[NSObject : AnyObject])
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
    func triggerSync()
    {
        if self.operationQueue != nil && self.operationQueue!.operationCount > 0
        {
            return
        }
        
        if self.syncOperation == nil
        {
            self.syncOperation = CKSIncrementalStoreSyncOperation(persistentStoreCoordinator: self.backingPersistentStoreCoordinator)
            self.syncOperation?.syncConflictResolutionBlock = self.recordConflictResolutionBlock
            self.syncOperation?.syncCompletionBlock =  ({(error) -> Void in
                
                if error == nil
                {
                    print("Sync Performed Successfully")
                    dispatch_async(dispatch_get_main_queue(), {
                        
                        NSNotificationCenter.defaultCenter().postNotificationName(CKSIncrementalStoreDidFinishSyncOperationNotification, object: self, userInfo: error!.userInfo)
                    })
                }
                else
                {
                    print("Sync unSuccessful")
                    dispatch_async(dispatch_get_main_queue(), {
                        
                        NSNotificationCenter.defaultCenter().postNotificationName(CKSIncrementalStoreDidFinishSyncOperationNotification, object: self)
                    })
                }

            })
        }
        self.operationQueue?.addOperation(syncOperation!)
        NSNotificationCenter.defaultCenter().postNotificationName(CKSIncrementalStoreDidStartSyncOperationNotification, object: self)
        
        
    }
    func createCKSCloudDatabaseCustomZone()
    {
        var zone = CKRecordZone(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName)
        
        self.database?.saveRecordZone(zone, completionHandler: { (zoneFromServer, error) -> Void in
            
            if error != nil
            {
                println("CKSIncrementalStore Custom Zone creation failed")
            }
            else
            {
                self.createCKSCloudDatabaseCustomZoneSubcription()
            }
            
        })
    }
    
    func createCKSCloudDatabaseCustomZoneSubcription()
    {
        var subcription:CKSubscription = CKSubscription(zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName), subscriptionID: CKSIncrementalStoreCloudDatabaseSyncSubcriptionName, options: nil)
        
        var subcriptionNotificationInfo = CKNotificationInfo()
        subcriptionNotificationInfo.alertBody=""
        subcriptionNotificationInfo.shouldSendContentAvailable = true
        subcription.notificationInfo=subcriptionNotificationInfo
        subcriptionNotificationInfo.shouldBadge=false
        
        var subcriptionsOperation=CKModifySubscriptionsOperation(subscriptionsToSave: [subcription], subscriptionIDsToDelete: nil)
        subcriptionsOperation.database=self.database
        subcriptionsOperation.modifySubscriptionsCompletionBlock=({ (modified,created,error) -> Void in
            
            if error != nil
            {
                println("Error \(error.localizedDescription)")
            }
            else
            {
                println("Successfull")
            }
            
        })
        
        var operationQueue = NSOperationQueue()
        operationQueue.addOperation(subcriptionsOperation)
    }
    
    override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext, error: NSErrorPointer) -> AnyObject? {
        
        
        if request.requestType==NSPersistentStoreRequestType.FetchRequestType
        {
            var fetchRequest:NSFetchRequest=request as! NSFetchRequest
            return self.executeInResponseToFetchRequest(fetchRequest, context: context, error: error)
        }
        else if request.requestType==NSPersistentStoreRequestType.SaveRequestType
        {
            var saveChangesRequest:NSSaveChangesRequest=request as! NSSaveChangesRequest
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
            var keys = managedObject.entity.attributesByName.keys.array.filter({(key)->Bool in
                
                if (key as! String) == CKSIncrementalStoreLocalStoreRecordIDAttributeName || (key as! String) == CKSIncrementalStoreLocalStoreChangeTypeAttributeName
                {
                    return false
                }
                return true
            })
            var values = managedObject.dictionaryWithValuesForKeys(keys)
            var incrementalStoreNode = NSIncrementalStoreNode(objectID: objectID, withValues: values, version: 1)
            
            return incrementalStoreNode
        }
        
        return nil
    }
    
    override func obtainPermanentIDsForObjects(array: [AnyObject], error: NSErrorPointer) -> [AnyObject]? {
        
        return array.map({ (object)->NSManagedObjectID in
            
            var insertedObject:NSManagedObject = object as! NSManagedObject
            return self.newObjectIDForEntity(insertedObject.entity, referenceObject: NSUUID().UUIDString)
            
        })
    }
    // MARK : Request Methods
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
                println(object.dictionaryWithValuesForKeys((self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[(object.entity.name)!]?.attributesByName.keys.array)!))
                return object
            })
            
            return resultsFromLocalStore!
        }
        return []
    }

    func executeInResponseToSaveChangesRequest(saveRequest:NSSaveChangesRequest,context:NSManagedObjectContext,error:NSErrorPointer)->NSArray
    {
        self.insertObjectsInBackingStore(Array(context.insertedObjects))
        self.setObjectsInBackingStore(Array(context.updatedObjects), toChangeType: CKSLocalStoreRecordChangeType.RecordUpdated)
        self.setObjectsInBackingStore(Array(context.deletedObjects), toChangeType: CKSLocalStoreRecordChangeType.RecordDeleted)
        
        var error:NSErrorPointer = nil
        self.backingMOC.save(error)
        
        return NSArray()
    }

    func insertObjectsInBackingStore(objects:Array<AnyObject>)
    {
        for object in objects
        {
            var managedObject:NSManagedObject = NSEntityDescription.insertNewObjectForEntityForName(((object as! NSManagedObject).entity.name)!, inManagedObjectContext: self.backingMOC) as! NSManagedObject
            var keys = (object as! NSManagedObject).entity.attributesByName.keys.array
            var dictionary = object.dictionaryWithValuesForKeys(keys)
            managedObject.setValuesForKeysWithDictionary(dictionary)
            managedObject.setValue(self.referenceObjectForObjectID((object as! NSManagedObject).objectID), forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
            managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordUpdated.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
        }
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
                for var i=0; i<results?.count; i++
                {
                    var managedObject:NSManagedObject = results![i] as! NSManagedObject
                    var updatedObject:NSManagedObject = objectsInEntity[i as Int] as! NSManagedObject
                    var keys = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[(managedObject.entity.name)!]?.attributesByName.keys.array
                    var dictionary = updatedObject.dictionaryWithValuesForKeys(keys!)
                    managedObject.setValuesForKeysWithDictionary(dictionary)
                    managedObject.setValue(NSNumber(short: changeType.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
                }
            }
        }
    }
}
