//    SMStore.swift
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

struct SMStoreNotification {
    static let SyncDidStart = "SMStoreDidStartSyncOperationNotification"
    static let SyncDidFinish = "SMStoreDidFinishSyncOperationNotification"
}
struct SMStoreRecordChangeType {
    static let RecordNoChange = 0
    static let RecordUpdated = 1
    static let RecordDeleted = 2
    static let RecordInserted = 3
}
public let SMStoreDidStartSyncOperationNotification = "SMStoreDidStartSyncOperationNotification"
public let SMStoreDidFinishSyncOperationNotification = "SMStoreDidFinishSyncOperationNotification"

let SMStoreSyncConflictResolutionPolicyOption = "SMStoreSyncConflictResolutionPolicyOption"

let SMStoreErrorDomain = "SMStoreErrorDomain"

public let SeamStoreType = SMStore.type

enum SMLocalStoreRecordChangeType: Int16 {
    case RecordNoChange = 0
    case RecordUpdated  = 1
    case RecordDeleted  = 2
    case RecordInserted = 3
}

enum SMStoreError: ErrorType {
    case BackingStoreFetchRequestError
    case InvalidRequest
    case BackingStoreCreationFailed
}

public class SMStore: NSIncrementalStore {
    private var syncOperation: SMStoreSyncOperation?
    private var cloudStoreSetupOperation: SMServerStoreSetupOperation?
    private var cksStoresSyncConflictPolicy: SMSyncConflictResolutionPolicy = SMSyncConflictResolutionPolicy.ServerRecordWins
    private var database: CKDatabase?
    private var operationQueue: NSOperationQueue?
    private var backingPersistentStoreCoordinator: NSPersistentStoreCoordinator?
    private var backingPersistentStore: NSPersistentStore?
    var syncAutomatically: Bool = true
    var recordConflictResolutionBlock:((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
    private lazy var backingMOC: NSManagedObjectContext = {
        var moc = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        moc.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
        moc.retainsRegisteredObjects = true
        return moc
        }()
    
    override public class func initialize() {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    
    override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator?, configurationName name: String?, URL url: NSURL, options: [NSObject : AnyObject]?) {
        self.database = CKContainer.defaultContainer().privateCloudDatabase
        if options != nil {
            if options![SMStoreSyncConflictResolutionPolicyOption] != nil {
                let syncConflictPolicy = options![SMStoreSyncConflictResolutionPolicyOption] as! NSNumber
                self.cksStoresSyncConflictPolicy = SMSyncConflictResolutionPolicy(rawValue: syncConflictPolicy.shortValue)!
            }
        }
        super.init(persistentStoreCoordinator: root, configurationName: name, URL: url, options: options)
    }
    
    class public var type:String {
        return NSStringFromClass(self)
    }
    
    override public func loadMetadata() throws {
        self.metadata=[
            NSStoreUUIDKey: NSProcessInfo().globallyUniqueString,
            NSStoreTypeKey: self.dynamicType.type
        ]
        let storeURL=self.URL
        let backingMOM: NSManagedObjectModel? = self.backingModel()
        if backingMOM != nil {
            self.backingPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: backingMOM!)
            do {
                self.backingPersistentStore = try self.backingPersistentStoreCoordinator?.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: nil)
                self.operationQueue = NSOperationQueue()
                self.operationQueue!.maxConcurrentOperationCount = 1
            } catch {
                throw SMStoreError.BackingStoreCreationFailed
            }
            return
        }
        throw SMStoreError.BackingStoreCreationFailed
    }
    
    func backingModel() -> NSManagedObjectModel? {
        if self.persistentStoreCoordinator?.managedObjectModel != nil {
            let backingModel: NSManagedObjectModel = SMStoreChangeSetHandler.defaultHandler.modelForLocalStore(usingModel: self.persistentStoreCoordinator!.managedObjectModel)
            return backingModel
        }
        return nil
    }
    
    public func handlePush(userInfo userInfo:[NSObject : AnyObject]) {
        let u = userInfo as! [String : NSObject]
        let ckNotification = CKNotification(fromRemoteNotificationDictionary: u)
        if ckNotification.notificationType == CKNotificationType.RecordZone {
            let recordZoneNotification = CKRecordZoneNotification(fromRemoteNotificationDictionary: u)
            if recordZoneNotification.recordZoneID!.zoneName == SMStoreCloudStoreCustomZoneName {
                self.triggerSync()
            }
        }
    }
    
    func entitiesToParticipateInSync() -> [NSEntityDescription]? {
        return self.backingMOC.persistentStoreCoordinator?.managedObjectModel.entities.filter { object in
            let entity: NSEntityDescription = object
            return (entity.name)! != SMLocalStoreChangeSetEntityName
        }
    }
    
    public func triggerSync() {
        if self.operationQueue != nil && self.operationQueue!.operationCount > 0 {
            return
        }
        let syncOperationBlock = {
            self.syncOperation = SMStoreSyncOperation(persistentStoreCoordinator: self.backingPersistentStoreCoordinator, entitiesToSync: self.entitiesToParticipateInSync()!, conflictPolicy: self.cksStoresSyncConflictPolicy)
            self.syncOperation?.syncConflictResolutionBlock = self.recordConflictResolutionBlock
            self.syncOperation?.syncCompletionBlock =  { error in
                if error == nil {
                    print("Sync Performed Successfully")
                    NSOperationQueue.mainQueue().addOperationWithBlock {
                        NSNotificationCenter.defaultCenter().postNotificationName(SMStoreDidFinishSyncOperationNotification, object: self)
                    }
                } else {
                    print("Sync unSuccessful")
                    NSOperationQueue.mainQueue().addOperationWithBlock {
                        NSNotificationCenter.defaultCenter().postNotificationName(SMStoreDidFinishSyncOperationNotification, object: self, userInfo: error!.userInfo)
                    }
                }
            }
            self.operationQueue?.addOperation(self.syncOperation!)
        }
        if NSUserDefaults.standardUserDefaults().objectForKey(SMStoreCloudStoreCustomZoneName) == nil || NSUserDefaults.standardUserDefaults().objectForKey(SMStoreCloudStoreSubscriptionName) == nil {
            self.cloudStoreSetupOperation = SMServerStoreSetupOperation(cloudDatabase: self.database)
            self.cloudStoreSetupOperation?.setupOperationCompletionBlock = { customZoneWasCreated, customZoneSubscriptionWasCreated in
                syncOperationBlock()
            }
            self.operationQueue?.addOperation(self.cloudStoreSetupOperation!)
        } else {
            syncOperationBlock()
        }
        NSNotificationCenter.defaultCenter().postNotificationName(SMStoreDidStartSyncOperationNotification, object: self)
    }
    
    override public func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        if request.requestType == NSPersistentStoreRequestType.FetchRequestType {
            let fetchRequest: NSFetchRequest = request as! NSFetchRequest
            return try self.executeInResponseToFetchRequest(fetchRequest, context: context!)
        } else if request.requestType == NSPersistentStoreRequestType.SaveRequestType {
            let saveChangesRequest: NSSaveChangesRequest = request as! NSSaveChangesRequest
            return try self.executeInResponseToSaveChangesRequest(saveChangesRequest, context: context!)
        } else {
            throw NSError(domain: SMStoreErrorDomain, code: SMStoreError.InvalidRequest._code, userInfo: nil)
        }
    }
    
    override public func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        let recordID:String = self.referenceObjectForObjectID(objectID) as! String
        let propertiesToFetch = Array(objectID.entity.propertiesByName.values).filter { object  in
            if object is NSRelationshipDescription {
                let relationshipDescription: NSRelationshipDescription = object as! NSRelationshipDescription
                return relationshipDescription.toMany == false
            }
            return true
            }.map {
                return $0.name
        }
        let fetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
        let predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,recordID)
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = predicate
        fetchRequest.resultType = NSFetchRequestResultType.DictionaryResultType
        fetchRequest.propertiesToFetch = propertiesToFetch
        let results = try self.backingMOC.executeFetchRequest(fetchRequest)
        var backingObjectValues = results.last as! Dictionary<String,NSObject>
        for (key,value) in backingObjectValues {
            if value is NSManagedObject {
                let managedObject: NSManagedObject = value as! NSManagedObject
                let recordID: String = managedObject.valueForKey(SMLocalStoreRecordIDAttributeName) as! String
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
    
    override public func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        let recordID: String = self.referenceObjectForObjectID(objectID) as! String
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
        let predicate: NSPredicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,recordID)
        fetchRequest.predicate = predicate
        let results = try self.backingMOC.executeFetchRequest(fetchRequest)
        if results.count > 0 {
            let managedObject: NSManagedObject = results.first as! NSManagedObject
            let relationshipValues: Set<NSObject> = managedObject.valueForKey(relationship.name) as! Set<NSObject>
            return Array(relationshipValues).map({(object) -> NSManagedObjectID in
                let value: NSManagedObject = object as! NSManagedObject
                let recordID: String = value.valueForKey(SMLocalStoreRecordIDAttributeName) as! String
                let objectID: NSManagedObjectID = self.newObjectIDForEntity(value.entity, referenceObject: recordID)
                return objectID
            })
        }
        return []
    }
    
    override public func obtainPermanentIDsForObjects(array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        return array.map { object in
            let insertedObject:NSManagedObject = object as NSManagedObject
            let newRecordID: String = NSUUID().UUIDString
            return self.newObjectIDForEntity(insertedObject.entity, referenceObject: newRecordID)
        }
    }
    
    // MARK : Fetch Request
    func executeInResponseToFetchRequest(fetchRequest:NSFetchRequest,context:NSManagedObjectContext) throws ->NSArray {
        let resultsFromLocalStore = try self.backingMOC.executeFetchRequest(fetchRequest)
        if resultsFromLocalStore.count > 0 {
            return resultsFromLocalStore.map({(result)->NSManagedObject in
                let result = result as! NSManagedObject
                let recordID: String = result.valueForKey(SMLocalStoreRecordIDAttributeName) as! String
                let entity = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[fetchRequest.entityName!]
                let objectID = self.newObjectIDForEntity(entity!, referenceObject: recordID)
                let object = context.objectWithID(objectID)
                return object
            })
        }
        return []
    }
    
    // MARK : SaveChanges Request
    private func executeInResponseToSaveChangesRequest(saveRequest:NSSaveChangesRequest,context:NSManagedObjectContext) throws -> Array<AnyObject> {
        try self.insertObjectsInBackingStore(objectsToInsert: context.insertedObjects, mainContext: context)
        try self.updateObjectsInBackingStore(objectsToUpdate: context.updatedObjects)
        try self.deleteObjectsFromBackingStore(objectsToDelete: context.deletedObjects, mainContext: context)
        try self.backingMOC.saveIfHasChanges()
        self.triggerSync()
        return []
    }
    
    func objectIDForBackingObjectForEntity(entityName: String, withReferenceObject referenceObject: String?) throws -> NSManagedObjectID? {
        if referenceObject == nil {
            return nil
        }
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: entityName)
        fetchRequest.resultType = NSFetchRequestResultType.ManagedObjectIDResultType
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,referenceObject!)
        let results = try self.backingMOC.executeFetchRequest(fetchRequest)
        if results.count > 0 {
            return results.last as? NSManagedObjectID
        }
        return nil
    }
    
    private func setRelationshipValuesForBackingObject(backingObject:NSManagedObject,sourceObject:NSManagedObject) throws {
        for relationship in Array(sourceObject.entity.relationshipsByName.values) as [NSRelationshipDescription] {
            if sourceObject.hasFaultForRelationshipNamed(relationship.name) || sourceObject.valueForKey(relationship.name) == nil {
                continue
            }
            if relationship.toMany == true {
                let relationshipValue: Set<NSObject> = sourceObject.valueForKey(relationship.name) as! Set<NSObject>
                var backingRelationshipValue: Set<NSObject> = Set<NSObject>()
                for relationshipObject in relationshipValue {
                    let relationshipManagedObject: NSManagedObject = relationshipObject as! NSManagedObject
                    if relationshipManagedObject.objectID.temporaryID == false {
                        let referenceObject: String = self.referenceObjectForObjectID(relationshipManagedObject.objectID) as! String
                        let backingRelationshipObjectID = try self.objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject)
                        if backingRelationshipObjectID != nil {
                            let backingRelationshipObject = try backingObject.managedObjectContext?.existingObjectWithID(backingRelationshipObjectID!)
                            backingRelationshipValue.insert(backingRelationshipObject!)
                        }
                    }
                }
                backingObject.setValue(backingRelationshipValue, forKey: relationship.name)
            } else {
                let relationshipValue: NSManagedObject = sourceObject.valueForKey(relationship.name) as! NSManagedObject
                if relationshipValue.objectID.temporaryID == false {
                    let referenceObject: String = self.referenceObjectForObjectID(relationshipValue.objectID) as! String
                    let backingRelationshipObjectID = try self.objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject)
                    if backingRelationshipObjectID != nil {
                        let backingRelationshipObject = try self.backingMOC.existingObjectWithID(backingRelationshipObjectID!)
                        backingObject.setValue(backingRelationshipObject, forKey: relationship.name)
                    }
                }
            }
        }
    }
    
    func insertObjectsInBackingStore(objectsToInsert objects:Set<NSObject>, mainContext: NSManagedObjectContext) throws {
        for object in objects {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let managedObject:NSManagedObject = NSEntityDescription.insertNewObjectForEntityForName((sourceObject.entity.name)!, inManagedObjectContext: self.backingMOC) as NSManagedObject
            let keys = Array(sourceObject.entity.attributesByName.keys)
            let dictionary = sourceObject.dictionaryWithValuesForKeys(keys)
            managedObject.setValuesForKeysWithDictionary(dictionary)
            let referenceObject: String = self.referenceObjectForObjectID(sourceObject.objectID) as! String
            managedObject.setValue(referenceObject, forKey: SMLocalStoreRecordIDAttributeName)
            mainContext.willChangeValueForKey("objectID")
            try mainContext.obtainPermanentIDsForObjects([sourceObject])
            mainContext.didChangeValueForKey("objectID")
            SMStoreChangeSetHandler.defaultHandler.createChangeSet(ForInsertedObjectRecordID: referenceObject, entityName: sourceObject.entity.name!, backingContext: self.backingMOC)
            try self.setRelationshipValuesForBackingObject(managedObject, sourceObject: sourceObject)
            try self.backingMOC.saveIfHasChanges()
        }
    }
    
    private func deleteObjectsFromBackingStore(objectsToDelete objects: Set<NSObject>, mainContext: NSManagedObjectContext) throws {
        let predicateObjectRecordIDKey = "objectRecordID"
        let predicate: NSPredicate = NSPredicate(format: "%K == $objectRecordID", SMLocalStoreRecordIDAttributeName)
        for object in objects {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: sourceObject.entity.name!)
            let recordID: String = self.referenceObjectForObjectID(sourceObject.objectID) as! String
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables([predicateObjectRecordIDKey: recordID])
            fetchRequest.fetchLimit = 1
            let results = try self.backingMOC.executeFetchRequest(fetchRequest)
            let backingObject: NSManagedObject = results.last as! NSManagedObject
            SMStoreChangeSetHandler.defaultHandler.createChangeSet(ForDeletedObjectRecordID: recordID, backingContext: self.backingMOC)
            self.backingMOC.deleteObject(backingObject)
            try self.backingMOC.saveIfHasChanges()
        }
    }
    
    private func updateObjectsInBackingStore(objectsToUpdate objects: Set<NSObject>) throws {
        let predicateObjectRecordIDKey = "objectRecordID"
        let predicate: NSPredicate = NSPredicate(format: "%K == $objectRecordID", SMLocalStoreRecordIDAttributeName)
        for object in objects {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: sourceObject.entity.name!)
            let recordID: String = self.referenceObjectForObjectID(sourceObject.objectID) as! String
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables([predicateObjectRecordIDKey:recordID])
            fetchRequest.fetchLimit = 1
            let results = try self.backingMOC.executeFetchRequest(fetchRequest)
            let backingObject: NSManagedObject = results.last as! NSManagedObject
            let keys = Array(self.persistentStoreCoordinator!.managedObjectModel.entitiesByName[sourceObject.entity.name!]!.attributesByName.keys)
            let sourceObjectValues = sourceObject.dictionaryWithValuesForKeys(keys)
            backingObject.setValuesForKeysWithDictionary(sourceObjectValues)
            SMStoreChangeSetHandler.defaultHandler.createChangeSet(ForUpdatedObject: backingObject, usingContext: self.backingMOC)
            try self.setRelationshipValuesForBackingObject(backingObject, sourceObject: sourceObject)
            try self.backingMOC.saveIfHasChanges()
        }
    }
}