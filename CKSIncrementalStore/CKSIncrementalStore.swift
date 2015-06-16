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

let CKSIncrementalStoreSyncEngineFetchChangeTokenKey = "CKSIncrementalStoreSyncEngineFetchChangeTokenKey"
class CKSIncrementalStoreSyncEngine: NSObject {
    
    static let defaultEngine=CKSIncrementalStoreSyncEngine()
    var operationQueue:NSOperationQueue?
    var localStoreMOC:NSManagedObjectContext?
    
    func performSync()->Bool
    {
        self.operationQueue = NSOperationQueue()
        self.operationQueue?.maxConcurrentOperationCount = 1

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
        if NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreSyncEngineFetchChangeTokenKey) != nil
        {
            var fetchTokenKeyArchived = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreSyncEngineFetchChangeTokenKey) as! NSData
            return NSKeyedUnarchiver.unarchiveObjectWithData(fetchTokenKeyArchived) as? CKServerChangeToken
        }
        
        return nil
    }
    
    func saveServerChangeToken(#serverChangeToken:CKServerChangeToken)
    {
        NSUserDefaults.standardUserDefaults().setObject(NSKeyedArchiver.archivedDataWithRootObject(serverChangeToken), forKey: CKSIncrementalStoreSyncEngineFetchChangeTokenKey)
    }
    
    func deleteSavedServerChangeToken()
    {
        if self.savedCKServerChangeToken() != nil
        {
            NSUserDefaults.standardUserDefaults().setObject(nil, forKey: CKSIncrementalStoreSyncEngineFetchChangeTokenKey)
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
        ckModifyRecordsOperation.modifyRecordsCompletionBlock = ({(savedRecords,deletedRecordIDs,operationError)->Void in
            
            if operationError == nil
            {
                wasSuccessful = true
                
            }
        })
        
        self.operationQueue?.addOperation(ckModifyRecordsOperation)
        self.operationQueue?.waitUntilAllOperationsAreFinished()
        
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
            var ckRecord = CKRecord(recordType: (managedObject.entity.name)!, recordID: ckRecordID)
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
class CKSIncrementalStoreSyncPushNotificationHandler
{
    static let defaultHandler=CKSIncrementalStoreSyncPushNotificationHandler()
    
    func handlePush(#userInfo:[NSObject : AnyObject])
    {
        var ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        
        if ckNotification.notificationType == CKNotificationType.RecordZone
        {
            var recordZoneNotification = CKRecordZoneNotification(fromRemoteNotificationDictionary: userInfo)
            if recordZoneNotification.recordZoneID.zoneName == CKSIncrementalStoreCloudDatabaseCustomZoneName
            {
                if CKSIncrementalStoreSyncEngine.defaultEngine.performSync()
                {
                    print("Performed Sync")
                }
                else
                {
                    print("Not able to complete sync because of some error")
                }
            }
            
        }
    }
}

let CKSIncrementalStoreDatabaseType="CKSIncrementalStoreDatabaseType"
let CKSIncrementalStorePrivateDatabaseType="CKSIncrementalStorePrivateDatabaseType"
let CKSIncrementalStorePublicDatabaseType="CKSIncrementalStorePublicDatabaseType"

let CKSIncrementalStoreCloudDatabaseCustomZoneName="CKSIncrementalStore_OnlineStoreZone"

let CKSIncrementalStoreCloudDatabaseCustomZoneIDKey = "CKSIncrementalStoreCloudDatabaseCustomZoneIDKey"

let CKSIncrementalStoreCloudDatabaseSyncSubcriptionName="CKSIncrementalStore_Sync_Subcription"


let CKSIncrementalStoreLocalStoreChangeTypeAttributeName="changeType"
let CKSIncrementalStoreLocalStoreRecordIDAttributeName="recordID"

enum CKSLocalStoreRecordChangeType:Int16
{
    case RecordNoChange = 0
    case RecordUpdated  = 1
    case RecordDeleted  = 2
}

class CKSIncrementalStore: NSIncrementalStore {
    
    lazy var cachedValues:NSMutableDictionary={
        return NSMutableDictionary()
    }()
    
    var database:CKDatabase?
    var cloudDatabaseCustomZoneID:CKRecordZoneID?
    
    var backingPersistentStoreCoordinator:NSPersistentStoreCoordinator?
    lazy var backingMOC:NSManagedObjectContext={
        
        var moc=NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        moc.persistentStoreCoordinator=self.backingPersistentStoreCoordinator
        moc.retainsRegisteredObjects=true
        return moc
    }()
    
    override class func initialize()
    {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator, configurationName name: String?, URL url: NSURL, options: [NSObject : AnyObject]?) {
        
        self.database=CKContainer.defaultContainer().privateCloudDatabase
        
        if options != nil && options![CKSIncrementalStoreDatabaseType] != nil
        {
            var optionValue: AnyObject?=options![CKSIncrementalStoreDatabaseType]
            
            if optionValue! as! String == CKSIncrementalStorePublicDatabaseType
            {
                self.database=CKContainer.defaultContainer().publicCloudDatabase
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
//        self.createCKSCloudDatabaseCustomZone()
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
            
            var recordChangeTypeAttributeDescription = NSAttributeDescription()
            recordChangeTypeAttributeDescription.name = CKSIncrementalStoreLocalStoreChangeTypeAttributeName
            recordChangeTypeAttributeDescription.attributeType = NSAttributeType.Integer16AttributeType
            recordChangeTypeAttributeDescription.indexed = true
            recordChangeTypeAttributeDescription.defaultValue = NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue)
            
            entity.properties.append(recordIDAttributeDescription)
            entity.properties.append(recordChangeTypeAttributeDescription)
            
        }
        self.backingPersistentStoreCoordinator=NSPersistentStoreCoordinator(managedObjectModel: model as! NSManagedObjectModel)
        
        var error: NSError? = nil
        if self.backingPersistentStoreCoordinator?.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: nil, error: &error)! == nil
        {
            print("Backing Store Error \(error)")
            return false
        }
        
        var syncLocalContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        syncLocalContext.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
        CKSIncrementalStoreSyncEngine.defaultEngine.localStoreMOC = syncLocalContext
        return true

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
                self.cloudDatabaseCustomZoneID=zone.zoneID
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
