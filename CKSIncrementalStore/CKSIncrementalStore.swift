//    CKSIncrementalStore.swift
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


import CoreData
import CloudKit
import ObjectiveC

let CKSIncrementalStoreCloudDatabaseCustomZoneName="CKSIncrementalStoreZone"
let CKSIncrementalStoreCloudDatabaseSyncSubcriptionName="CKSIncrementalStore_Sync_Subcription"

let CKSIncrementalStoreLocalStoreEntityNameAttributeName = "cks_LocalStore_Attribute_EntityName"
let CKSIncrementalStoreLocalStoreChangeTypeAttributeName="cks_LocalStore_Attribute_ChangeType"
let CKSIncrementalStoreLocalStoreRecordIDAttributeName="cks_LocalStore_Attribute_RecordID"
let CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName = "cks_LocalStore_Attribute_EncodedValues"
let CKSIncrementalStoreLocalStoreRecordChangedPropertiesAttributeName = "cks_LocalStore_Attribute_ChangedProperties"
let CKSIncrementalStoreLocalStoreChangeQueuedAttributeName = "cks_LocalStore_Attribute_Queued"

let CKSIncrementalStoreDidStartSyncOperationNotification = "CKSIncrementalStoreDidStartSyncOperationNotification"
let CKSIncrementalStoreDidFinishSyncOperationNotification = "CKSIncrementalStoreDidFinishSyncOperationNotification"

let CKSIncrementalStoreSyncConflictPolicyOption = "CKSIncrementalStoreSyncConflictPolicyOption"

let CKSIncrementalStoreErrorDomain = "CKSIncrementalStoreErrorDomain"

let CKSChangeSetEntityName = "CKS_ChangeSetEntity"

enum CKSLocalStoreRecordChangeType: Int16
{
    case RecordNoChange = 0
    case RecordUpdated  = 1
    case RecordDeleted  = 2
    case RecordInserted = 3
}

enum CKSIncrementalStoreError: ErrorType
{
    case BackingStoreFetchRequestError
    case InvalidRequest
    case BackingStoreCreationFailed
}


class CKSIncrementalStore: NSIncrementalStore {
    
    private var syncOperation:CKSIncrementalStoreSyncOperation?
    private var cloudStoreSetupOperation:CKSIncrementalStoreCloudStoreSetupOperation?
    private var cksStoresSyncConflictPolicy:CKSStoresSyncConflictPolicy = CKSStoresSyncConflictPolicy.GreaterModifiedDateWins
    private var database:CKDatabase?
    private var operationQueue:NSOperationQueue?
    private var backingPersistentStoreCoordinator:NSPersistentStoreCoordinator?
    private var backingPersistentStore:NSPersistentStore?
    var syncAutomatically: Bool = true
    private lazy var backingMOC:NSManagedObjectContext={
        
        var moc = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        moc.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
        moc.retainsRegisteredObjects = true
        return moc
        
        }()
    
    var recordConflictResolutionBlock:((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    
    override class func initialize()
    {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    
    override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator?, configurationName name: String?, URL url: NSURL, options: [NSObject : AnyObject]?) {
        
        self.database = CKContainer.defaultContainer().privateCloudDatabase
        if options != nil
        {
            if options![CKSIncrementalStoreSyncConflictPolicyOption] != nil
            {
                let syncConflictPolicy = options![CKSIncrementalStoreSyncConflictPolicyOption] as! NSNumber
                self.cksStoresSyncConflictPolicy = CKSStoresSyncConflictPolicy(rawValue: syncConflictPolicy.shortValue)!
            }
        }
        
        super.init(persistentStoreCoordinator: root, configurationName: name, URL: url, options: options)
        
    }
    
    class var type:String{
        return NSStringFromClass(self)
    }
    
    override func loadMetadata() throws {
        
        self.metadata=[
            NSStoreUUIDKey:NSProcessInfo().globallyUniqueString,
            NSStoreTypeKey:self.dynamicType.type
        ]
        
        let storeURL=self.URL
        let backingMOM: NSManagedObjectModel? = self.backingModel()
        
        if backingMOM != nil
        {
            self.backingPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: backingMOM!)
            
            do
            {
                self.backingPersistentStore = try self.backingPersistentStoreCoordinator?.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: nil)
                self.operationQueue = NSOperationQueue()
                self.operationQueue?.maxConcurrentOperationCount = 1
                self.triggerSync()
            }
            catch
            {
                throw CKSIncrementalStoreError.BackingStoreCreationFailed
            }
            
            return
        }
        
        throw CKSIncrementalStoreError.BackingStoreCreationFailed
    }
    
    func backingModel() -> NSManagedObjectModel?
    {
        if self.persistentStoreCoordinator?.managedObjectModel != nil
        {
            let backingModel: NSManagedObjectModel = self.persistentStoreCoordinator!.managedObjectModel.copy() as! NSManagedObjectModel
            
            for entity in backingModel.entities
            {
                self.addExtraBackingStoreAttributes(toEntity: entity)
            }
            
            backingModel.entities.append(self.changeSetEntity())
            
            return backingModel
        }
        
        return nil
    }
    
    func addExtraBackingStoreAttributes(toEntity entity: NSEntityDescription)
    {
        let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
        recordIDAttribute.name = CKSIncrementalStoreLocalStoreRecordIDAttributeName
        recordIDAttribute.optional = false
        recordIDAttribute.indexed = true
        entity.properties.append(recordIDAttribute)
        
        let recordEncodedValuesAttribute: NSAttributeDescription = NSAttributeDescription()
        recordEncodedValuesAttribute.name = CKSIncrementalStoreLocalStoreRecordEncodedValuesAttributeName
        recordEncodedValuesAttribute.attributeType = NSAttributeType.BinaryDataAttributeType
        recordEncodedValuesAttribute.optional = true
        entity.properties.append(recordEncodedValuesAttribute)
    }
    
    func changeSetEntity() -> NSEntityDescription
    {
        let changeSetEntity: NSEntityDescription = NSEntityDescription()
        changeSetEntity.name = CKSChangeSetEntityName
        
        let entityNameAttribute: NSAttributeDescription = NSAttributeDescription()
        entityNameAttribute.name = CKSIncrementalStoreLocalStoreEntityNameAttributeName
        entityNameAttribute.attributeType = NSAttributeType.StringAttributeType
        entityNameAttribute.optional = true
        changeSetEntity.properties.append(entityNameAttribute)
        
        let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
        recordIDAttribute.name = CKSIncrementalStoreLocalStoreRecordIDAttributeName
        recordIDAttribute.attributeType = NSAttributeType.StringAttributeType
        recordIDAttribute.optional = false
        recordIDAttribute.indexed = true
        changeSetEntity.properties.append(recordIDAttribute)
        
        let recordChangedPropertiesAttribute: NSAttributeDescription = NSAttributeDescription()
        recordChangedPropertiesAttribute.name = CKSIncrementalStoreLocalStoreRecordChangedPropertiesAttributeName
        recordChangedPropertiesAttribute.attributeType = NSAttributeType.StringAttributeType
        recordChangedPropertiesAttribute.optional = true
        changeSetEntity.properties.append(recordChangedPropertiesAttribute)
        
        let recordChangeTypeAttribute: NSAttributeDescription = NSAttributeDescription()
        recordChangeTypeAttribute.name = CKSIncrementalStoreLocalStoreChangeTypeAttributeName
        recordChangeTypeAttribute.attributeType = NSAttributeType.Integer16AttributeType
        recordChangeTypeAttribute.optional = false
        recordChangeTypeAttribute.defaultValue = NSNumber(short: CKSLocalStoreRecordChangeType.RecordInserted.rawValue)
        changeSetEntity.properties.append(recordChangeTypeAttribute)
        
        let changeTypeQueuedAttribute: NSAttributeDescription = NSAttributeDescription()
        changeTypeQueuedAttribute.name = CKSIncrementalStoreLocalStoreChangeQueuedAttributeName
        changeTypeQueuedAttribute.optional = false
        changeTypeQueuedAttribute.attributeType = NSAttributeType.BooleanAttributeType
        changeTypeQueuedAttribute.defaultValue = NSNumber(bool: false)
        changeSetEntity.properties.append(changeTypeQueuedAttribute)
        
        return changeSetEntity
    }
    
    internal func handlePush(userInfo userInfo:[NSObject : AnyObject])
    {
        let u = userInfo as! [String : NSObject]
        let ckNotification = CKNotification(fromRemoteNotificationDictionary: u)
        if ckNotification.notificationType == CKNotificationType.RecordZone
        {
            let recordZoneNotification = CKRecordZoneNotification(fromRemoteNotificationDictionary: u)
            
            if recordZoneNotification.recordZoneID!.zoneName == CKSIncrementalStoreCloudDatabaseCustomZoneName
            {
                self.triggerSync()
            }
        }
    }
    
    func entitiesToParticipateInSync() -> [NSEntityDescription]?
    {
        return self.backingMOC.persistentStoreCoordinator?.managedObjectModel.entities.filter({ (object) -> Bool in
            
            let entity: NSEntityDescription = object
            return (entity.name)! != CKSChangeSetEntityName
        })
    }
    
    internal func triggerSync()
    {
        if self.operationQueue != nil && self.operationQueue!.operationCount > 0
        {
            return
        }
        
        let syncOperationBlock = ({()->Void in
            
            self.syncOperation = CKSIncrementalStoreSyncOperation(persistentStoreCoordinator: self.backingPersistentStoreCoordinator, entitiesToSync: self.entitiesToParticipateInSync()!, conflictPolicy: self.cksStoresSyncConflictPolicy)
            
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
            self.cloudStoreSetupOperation?.setupOperationCompletionBlock = ({(customZoneWasCreated, customZoneSubscriptionWasCreated) -> Void in
                
                syncOperationBlock()
            })
            self.operationQueue?.addOperation(self.cloudStoreSetupOperation!)
        }
        else
        {
            syncOperationBlock()
        }
        
        
        NSNotificationCenter.defaultCenter().postNotificationName(CKSIncrementalStoreDidStartSyncOperationNotification, object: self)
    }
    
    override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        if request.requestType == NSPersistentStoreRequestType.FetchRequestType
        {
            let fetchRequest: NSFetchRequest = request as! NSFetchRequest
            return try self.executeInResponseToFetchRequest(fetchRequest, context: context!)
        }
            
        else if request.requestType == NSPersistentStoreRequestType.SaveRequestType
        {
            let saveChangesRequest: NSSaveChangesRequest = request as! NSSaveChangesRequest
            return try self.executeInResponseToSaveChangesRequest(saveChangesRequest, context: context!)
        }
            
        else
        {
            throw NSError(domain: CKSIncrementalStoreErrorDomain, code: CKSIncrementalStoreError.InvalidRequest._code, userInfo: nil)
        }
    }
    
    override func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        
        let recordID:String = self.referenceObjectForObjectID(objectID) as! String
        let propertiesToFetch = objectID.entity.propertiesByName.values.array.filter({(object) -> Bool in
            
            if object is NSRelationshipDescription
            {
                let relationshipDescription: NSRelationshipDescription = object as! NSRelationshipDescription
                return relationshipDescription.toMany == false
            }
            return true
            
        }).map({(object) -> String in
            
            let propertyDescription: NSPropertyDescription = object as NSPropertyDescription
            return propertyDescription.name
        })
        
        let fetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
        let predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,recordID)
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = predicate
        fetchRequest.resultType = NSFetchRequestResultType.DictionaryResultType
        fetchRequest.propertiesToFetch = propertiesToFetch
        
        var results = try self.backingMOC.executeFetchRequest(fetchRequest)
        var backingObjectValues = results.last as! Dictionary<String,NSObject>
        for (key,value) in backingObjectValues
        {
            if value is NSManagedObject
            {
                let managedObject: NSManagedObject = value as! NSManagedObject
                let recordID: String = managedObject.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                let entities = self.persistentStoreCoordinator!.managedObjectModel.entitiesByName
                let entityName = managedObject.entity.name!
                let entity: NSEntityDescription = entities[entityName]! as NSEntityDescription
                let objectID = self.newObjectIDForEntity(entity, referenceObject: recordID)
                backingObjectValues[key] = objectID
            }
        }
        
        let incrementalStoreNode = NSIncrementalStoreNode(objectID: objectID, withValues: backingObjectValues, version: 1)
        return incrementalStoreNode
        
    }
    
    override func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        
        let recordID: String = self.referenceObjectForObjectID(objectID) as! String
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
        let predicate: NSPredicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,recordID)
        fetchRequest.predicate = predicate
        let results = try self.backingMOC.executeFetchRequest(fetchRequest)
        
        if results.count > 0
        {
            let managedObject: NSManagedObject = results.first as! NSManagedObject
            let relationshipValues: Set<NSObject> = managedObject.valueForKey(relationship.name) as! Set<NSObject>
            return Array(relationshipValues).map({(object) -> NSManagedObjectID in
                
                let value: NSManagedObject = object as! NSManagedObject
                let recordID: String = value.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                let objectID: NSManagedObjectID = self.newObjectIDForEntity(value.entity, referenceObject: recordID)
                return objectID
            })
        }
        
        return []
    }
    
    override func obtainPermanentIDsForObjects(array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        
        return array.map({ (object) -> NSManagedObjectID in
            
            let insertedObject:NSManagedObject = object as NSManagedObject
            let newRecordID: String = NSUUID().UUIDString
            return self.newObjectIDForEntity(insertedObject.entity, referenceObject: newRecordID)
            
        })
    }
    
    // MARK : Fetch Request    
    func executeInResponseToFetchRequest(fetchRequest:NSFetchRequest,context:NSManagedObjectContext) throws ->NSArray
    {
        var resultsFromLocalStore = try self.backingMOC.executeFetchRequest(fetchRequest)
        
        if resultsFromLocalStore.count > 0
        {
            return resultsFromLocalStore.map({(result)->NSManagedObject in
                
                let result = result as! NSManagedObject
                let recordID: String = result.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                let entity = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[fetchRequest.entityName!]
                let objectID = self.newObjectIDForEntity(entity!, referenceObject: recordID)
                let object = context.objectWithID(objectID)
                return object
            })
        }
        return []
    }
    
    // MARK : SaveChanges Request
    private func executeInResponseToSaveChangesRequest(saveRequest:NSSaveChangesRequest,context:NSManagedObjectContext) throws -> Array<AnyObject>
    {
        try self.insertObjectsInBackingStore(objectsToInsert: context.insertedObjects, mainContext: context)
        try self.updateObjectsInBackingStore(objectsToUpdate: context.updatedObjects)
        try self.deleteObjectsFromBackingStore(objectsToDelete: context.deletedObjects, mainContext: context)
        
        if self.backingMOC.hasChanges
        {
            try self.backingMOC.save()
            self.triggerSync()
        }
        
        return []
    }
    
    func objectIDForBackingObjectForEntity(entityName: String, withReferenceObject referenceObject: String?) throws -> NSManagedObjectID?
    {
        if referenceObject == nil
        {
            return nil
        }
        
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: entityName)
        fetchRequest.resultType = NSFetchRequestResultType.ManagedObjectIDResultType
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,referenceObject!)
        
        var results = try self.backingMOC.executeFetchRequest(fetchRequest)
        if results.count > 0
        {
            return results.last as? NSManagedObjectID
        }
        
        return nil
    }
    
    private func setRelationshipValuesForBackingObject(backingObject:NSManagedObject,sourceObject:NSManagedObject) throws
    {
        for relationship in sourceObject.entity.relationshipsByName.values.array as [NSRelationshipDescription]
        {
            if sourceObject.hasFaultForRelationshipNamed(relationship.name) || sourceObject.valueForKey(relationship.name) == nil
            {
                continue
            }
            
            if relationship.toMany == true
            {
                let relationshipValue: Set<NSObject> = sourceObject.valueForKey(relationship.name) as! Set<NSObject>
                var backingRelationshipValue: Set<NSObject> = Set<NSObject>()
                
                for relationshipObject in relationshipValue
                {
                    let relationshipManagedObject: NSManagedObject = relationshipObject as! NSManagedObject
                    if relationshipManagedObject.objectID.temporaryID == false
                    {
                        let referenceObject: String = self.referenceObjectForObjectID(relationshipManagedObject.objectID) as! String
                        let backingRelationshipObjectID = try self.objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject)
                        let backingRelationshipObject = try backingObject.managedObjectContext?.existingObjectWithID(backingRelationshipObjectID!)
                        backingRelationshipValue.insert(backingRelationshipObject!)
                    }
                }
                
                backingObject.setValue(backingRelationshipValue, forKey: relationship.name)
            }
            else
            {
                let relationshipValue: NSManagedObject = sourceObject.valueForKey(relationship.name) as! NSManagedObject
                if relationshipValue.objectID.temporaryID == false
                {
                    let referenceObject: String = self.referenceObjectForObjectID(relationshipValue.objectID) as! String
                    let backingRelationshipObjectID = try self.objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject)
                    let backingRelationshipObject = try self.backingMOC.existingObjectWithID(backingRelationshipObjectID!)
                    backingObject.setValue(backingRelationshipObject, forKey: relationship.name)
                }
            }
        }
    }
    
    func insertObjectsInBackingStore(objectsToInsert objects:Set<NSObject>, mainContext: NSManagedObjectContext) throws
    {
        for object in objects
        {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let managedObject:NSManagedObject = NSEntityDescription.insertNewObjectForEntityForName((sourceObject.entity.name)!, inManagedObjectContext: self.backingMOC) as NSManagedObject
            let keys = sourceObject.entity.attributesByName.keys.array
            let dictionary = sourceObject.dictionaryWithValuesForKeys(keys)
            managedObject.setValuesForKeysWithDictionary(dictionary)
            let referenceObject: String = self.referenceObjectForObjectID(sourceObject.objectID) as! String
            managedObject.setValue(referenceObject, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
            managedObject.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordUpdated.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
            mainContext.willChangeValueForKey("objectID")
            try mainContext.obtainPermanentIDsForObjects([sourceObject])
            mainContext.didChangeValueForKey("objectID")
            CKSIncrementalStoreChangeSetHandler.defaultHandler.createChangeSet(ForInsertedObjectRecordID: referenceObject, entityName: sourceObject.entity.name!, backingContext: self.backingMOC)
            try self.setRelationshipValuesForBackingObject(managedObject, sourceObject: sourceObject)
            try self.backingMOC.save()
        }
    }
    
    private func deleteObjectsFromBackingStore(objectsToDelete objects: Set<NSObject>, mainContext: NSManagedObjectContext) throws
    {
        let predicateObjectRecordIDKey = "objectRecordID"
        let predicate: NSPredicate = NSPredicate(format: "%K == $objectRecordID", CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        
        for object in objects
        {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: sourceObject.entity.name!)
            let recordID: String = self.referenceObjectForObjectID(sourceObject.objectID) as! String
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables([predicateObjectRecordIDKey: recordID])
            fetchRequest.fetchLimit = 1
            var results = try self.backingMOC.executeFetchRequest(fetchRequest)
            let backingObject: NSManagedObject = results.last as! NSManagedObject
            CKSIncrementalStoreChangeSetHandler.defaultHandler.createChangeSet(ForDeletedObjectRecordID: recordID, backingContext: self.backingMOC)
            self.backingMOC.deleteObject(backingObject)
            try self.backingMOC.save()
        }
    }
    
    private func updateObjectsInBackingStore(objectsToUpdate objects: Set<NSObject>) throws
    {
        let predicateObjectRecordIDKey = "objectRecordID"
        let predicate: NSPredicate = NSPredicate(format: "%K == $objectRecordID", CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        
        for object in objects
        {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: sourceObject.entity.name!)
            let recordID: String = self.referenceObjectForObjectID(sourceObject.objectID) as! String
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables([predicateObjectRecordIDKey:recordID])
            fetchRequest.fetchLimit = 1
            var results = try self.backingMOC.executeFetchRequest(fetchRequest)
            let backingObject: NSManagedObject = results.last as! NSManagedObject
            let keys = self.persistentStoreCoordinator!.managedObjectModel.entitiesByName[sourceObject.entity.name!]!.attributesByName.keys.array
            let sourceObjectValues = sourceObject.dictionaryWithValuesForKeys(keys)
            backingObject.setValuesForKeysWithDictionary(sourceObjectValues)
            if sourceObject.changedValues().count != 0
            {
                CKSIncrementalStoreChangeSetHandler.defaultHandler.createChangeSet(ForUpdatedObject: backingObject, usingContext: self.backingMOC)
            }
            try self.setRelationshipValuesForBackingObject(backingObject, sourceObject: sourceObject)
            try self.backingMOC.save()
        }
    }
}