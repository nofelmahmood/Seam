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
//        self.deleteSavedServerChangeToken()
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
        print("Changes \(insertedOrUpdatedCKRecords) Deleted \(deletedCKRecordIDs)")
        return (insertedOrUpdatedCKRecords,deletedCKRecordIDs,fetchRecordChangesOperation.moreComing)
    }
    
    func applyServerChangesToLocalDatabase(insertedOrUpdatedCKRecords:Array<AnyObject>,deletedCKRecordIDs:Array<AnyObject>)->Bool
    {
        print("Applying Server Changes To Local Database")
        return self.insertOrUpdateManagedObjects(fromCKRecords: insertedOrUpdatedCKRecords) && self.deleteManagedObjects(fromCKRecordIDs: deletedCKRecordIDs)
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
        
        var predicate = NSPredicate(format: "%K == %@ || %K == %@", CKSIncrementalStoreLocalStoreChangeTypeAttributeName, NSNumber(short: CKSLocalStoreRecordChangeType.RecordUpdated.rawValue) ,CKSIncrementalStoreLocalStoreChangeTypeAttributeName,NSNumber(short: CKSLocalStoreRecordChangeType.RecordDeleted.rawValue))
        
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
        print("Local Changes \(insertedOrUpdatedManagedObjects) Deleted \(deletedManagedObjects)")
        return (insertedOrUpdatedManagedObjects,deletedManagedObjects)
    }
    
    func insertOrUpdateManagedObjects(fromCKRecords ckRecords:Array<AnyObject>)->Bool
    {
        var predicate = NSPredicate(format: "%K IN $ckRecordIDs",CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        var ckRecordsWithTypeNames:Dictionary<String,Dictionary<String,CKRecord>> = Dictionary<String,Dictionary<String,CKRecord>>()
        
        for object in ckRecords
        {
            var ckRecord:CKRecord = object as! CKRecord
            if ckRecordsWithTypeNames[ckRecord.recordType] == nil
            {
                ckRecordsWithTypeNames[ckRecord.recordType] = [ckRecord.recordID.recordName:ckRecord]
            }
            else
            {
                ckRecordsWithTypeNames[ckRecord.recordType]![ckRecord.recordID.recordName] = ckRecord
            }
        }
        
        var types = ckRecordsWithTypeNames.keys.array
        
        for type in types
        {
            var fetchRequest = NSFetchRequest(entityName: type)
            var error:NSErrorPointer = nil
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["ckRecordIDs":ckRecordsWithTypeNames[type]!])
            var results = self.localStoreMOC?.executeFetchRequest(fetchRequest, error: error)
            
            var ckRecordsWithTypeName:Dictionary<String,CKRecord> = ckRecordsWithTypeNames[type]!
            
            if error == nil && results?.count > 0
            {
                print("Got Matching Results")
                for object in results!
                {
                    var managedObject = object as! NSManagedObject
                    var recordIDString = managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                    
                    if ckRecordsWithTypeName[recordIDString] != nil
                    {
                        var ckRecord = ckRecordsWithTypeName[recordIDString]!
                        var keys = ckRecord.allKeys()
                        var values = ckRecord.dictionaryWithValuesForKeys(keys)
                        managedObject.setValuesForKeysWithDictionary(values)
                        ckRecordsWithTypeName[recordIDString] = nil
                        managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
                    }
                }
            }
            
            for record in ckRecordsWithTypeName.values.array
            {
                print("Got Results to be inserted")
                var managedObject:NSManagedObject = NSEntityDescription.insertNewObjectForEntityForName(type, inManagedObjectContext: self.localStoreMOC!) as! NSManagedObject
                var keys = record.allKeys().filter({(object)->Bool in
                    var key:String = object as! String
                    if record.objectForKey(key) is CKReference
                    {
                        return false
                    }
                    return true
                })
                var values = record.dictionaryWithValuesForKeys(keys)
                print("Values \(values)")
                managedObject.setValuesForKeysWithDictionary(values)
                managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordNoChange.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
                managedObject.setValue(record.recordID.recordName, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
            }
        }
        
        var error:NSError?
        self.localStoreMOC?.save(&error)
        if (error == nil)
        {
            return true
        }
        print("Saving Error \(error!)")
        
        return false
    }
    
    func deleteManagedObjects(fromCKRecordIDs ckRecordIDs:Array<AnyObject>)->Bool
    {
        var predicate = NSPredicate(format: "%K IN $ckRecordIDs",CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        var entityNames = self.localStoreMOC?.persistentStoreCoordinator?.managedObjectModel.entities.map({(object)->String in
            
            var entity:NSEntityDescription = object as! NSEntityDescription
            return entity.name!
        })
        
        for name in entityNames!
        {
            var fetchRequest = NSFetchRequest(entityName: name)
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables(["ckRecordIDs":ckRecordIDs])
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

    // MARK : Mapping Methods
    func cloudKitModifyRecordsOperationFromSaveChangesRequest(saveChangesRequest:NSSaveChangesRequest,context:NSManagedObjectContext)->CKModifyRecordsOperation
    {
        var allObjects:NSArray=NSArray()
        if((saveChangesRequest.insertedObjects) != nil)
        {
            allObjects=allObjects.arrayByAddingObjectsFromArray((saveChangesRequest.insertedObjects! as NSSet).allObjects)
        }
        if((saveChangesRequest.updatedObjects) != nil)
        {
            allObjects=allObjects.arrayByAddingObjectsFromArray((saveChangesRequest.updatedObjects! as NSSet).allObjects)
        }
        
        var ckRecordsToModify:NSMutableArray=NSMutableArray()
        
        for managedObject in allObjects
        {
            ckRecordsToModify.addObject(self.ckRecordFromManagedObject(managedObject as! NSManagedObject))
        }
        
        var deletedObjects:NSArray=NSArray()
        if((saveChangesRequest.deletedObjects) != nil)
        {
            deletedObjects=deletedObjects.arrayByAddingObjectsFromArray((saveChangesRequest.deletedObjects! as NSSet).allObjects)
        }
        var ckRecordsToDelete:NSMutableArray=NSMutableArray()
        for managedObject in deletedObjects
        {
            ckRecordsToDelete.addObject(self.ckRecordFromManagedObject(managedObject as! NSManagedObject).recordID)
        }
        
        var ckModifyRecordsOperation:CKModifyRecordsOperation=CKModifyRecordsOperation(recordsToSave: ckRecordsToModify as [AnyObject], recordIDsToDelete: ckRecordsToDelete as [AnyObject])
        
        ckModifyRecordsOperation.database=self.database
        return ckModifyRecordsOperation
    }
    
    func cloudKitRequestOperationFromFetchRequest(fetchRequest:NSFetchRequest,context:NSManagedObjectContext)->NSOperation
    {
        var requestPredicate:NSPredicate=NSPredicate(value: true)
        if (fetchRequest.predicate != nil)
        {
            requestPredicate=fetchRequest.predicate!
        }
        
        var query:CKQuery=CKQuery(recordType: fetchRequest.entityName, predicate: requestPredicate)
        if (fetchRequest.sortDescriptors != nil)
        {
            query.sortDescriptors=fetchRequest.sortDescriptors!
        }
        
        var queryOperation:CKQueryOperation=CKQueryOperation(query: query)
        queryOperation.resultsLimit=fetchRequest.fetchLimit
        if (fetchRequest.propertiesToFetch != nil)
        {
            queryOperation.desiredKeys=fetchRequest.propertiesToFetch
        }
        queryOperation.database=self.database
        return queryOperation
    }
    
    func ckRecordFromManagedObject(managedObject:NSManagedObject)->CKRecord
    {
        var identifier:NSString=self.identifier(managedObject.objectID) as! NSString
        var recordID:CKRecordID=CKRecordID(recordName: identifier as String)
        var record:CKRecord=CKRecord(recordType: managedObject.entity.name, recordID: recordID)

        var attributes:NSDictionary=managedObject.entity.attributesByName as NSDictionary
        var relationships:NSDictionary=managedObject.entity.relationshipsByName as NSDictionary
        
        for var i=0;i<attributes.allKeys.count;i++
        {
            var key:String=attributes.allKeys[i] as! String
            var valueForKey:AnyObject?=managedObject.valueForKey(key)
            
            if valueForKey is NSString
            {
                record.setObject(valueForKey as! NSString, forKey: key)
            }
            else if valueForKey is NSDate
            {
                record.setObject(valueForKey as! NSDate, forKey: key)
            }
            else if valueForKey is NSNumber
            {
                record.setObject(valueForKey as! NSNumber, forKey: key)
            }
        }
       for var i=0;i<relationships.allKeys.count;i++
        {
            var key:String=relationships.allKeys[i] as! String
            var relationship:NSRelationshipDescription=relationships.objectForKey(i) as! NSRelationshipDescription
            
            if relationship.toMany==false
            {
                var valueForKey:AnyObject?=managedObject.valueForKey(key)
                var id: AnyObject=self.identifier(valueForKey!.objectID)
                var ckRecordID:CKRecordID=CKRecordID(recordName: id as! String)
                var ckReference:CKReference=CKReference(recordID: ckRecordID, action: CKReferenceAction.DeleteSelf)
                record.setObject(ckReference, forKey: key)
            }

        }
        
        return record
        
    }
    func identifier(objectID:NSManagedObjectID)->AnyObject
    {
        return self.referenceObjectForObjectID(objectID)
    }
    func objectID(identifier:String,entity:NSEntityDescription)->NSManagedObjectID
    {
        var objectID:NSManagedObjectID=self.newObjectIDForEntity(entity, referenceObject: identifier)
        return objectID
    }
    

}
