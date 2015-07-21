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
            var keys = managedObject.entity.propertiesByName.values.array.filter({(property)->Bool in
                
                if property is NSAttributeDescription
                {
                    var attributeDescription: NSAttributeDescription = property as! NSAttributeDescription
                    if attributeDescription.name == CKSIncrementalStoreLocalStoreRecordIDAttributeName || attributeDescription.name == CKSIncrementalStoreLocalStoreChangeTypeAttributeName || attributeDescription.name == CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName
                    {
                        return false
                    }
                    return true
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
                    var managedObject: NSManagedObject = value as! NSManagedObject
                    var recordID: String = managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                    var entity: NSEntityDescription = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[managedObject.entity.name!] as! NSEntityDescription
                    
                    var objectID = self.newObjectIDForEntity(entity, referenceObject: recordID)
                    values[key] = objectID
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
