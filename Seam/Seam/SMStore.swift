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
    case recordNoChange = 0
    case recordUpdated  = 1
    case recordDeleted  = 2
    case recordInserted = 3
}

enum SMStoreError: Error {
    case backingStoreFetchRequestError
    case invalidRequest
    case backingStoreCreationFailed
}

open class SMStore: NSIncrementalStore {
    fileprivate var syncOperation: SMStoreSyncOperation?
    fileprivate var cloudStoreSetupOperation: SMServerStoreSetupOperation?
    fileprivate var cksStoresSyncConflictPolicy: SMSyncConflictResolutionPolicy = SMSyncConflictResolutionPolicy.serverRecordWins
    fileprivate var database: CKDatabase?
    fileprivate var operationQueue: OperationQueue?
    fileprivate var backingPersistentStoreCoordinator: NSPersistentStoreCoordinator?
    fileprivate var backingPersistentStore: NSPersistentStore?
    var syncAutomatically: Bool = true
    var recordConflictResolutionBlock:((_ clientRecord:CKRecord,_ serverRecord:CKRecord)->CKRecord)?
    fileprivate lazy var backingMOC: NSManagedObjectContext = {
        var moc = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.privateQueueConcurrencyType)
        moc.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
        moc.retainsRegisteredObjects = true
        return moc
        }()
    
    override open class func initialize() {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    
    override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator?, configurationName name: String?, at url: URL, options: [AnyHashable : Any]?) {
        self.database = CKContainer.default().privateCloudDatabase
        if options != nil {
            if options![SMStoreSyncConflictResolutionPolicyOption] != nil {
                let syncConflictPolicy = options![SMStoreSyncConflictResolutionPolicyOption] as! NSNumber
                self.cksStoresSyncConflictPolicy = SMSyncConflictResolutionPolicy(rawValue: syncConflictPolicy.int16Value)!
            }
        }
        super.init(persistentStoreCoordinator: root, configurationName: name, at: url, options: options)
    }
    
    class open var type:String {
        return NSStringFromClass(self)
    }
    
    override open func loadMetadata() throws {
        self.metadata=[
            NSStoreUUIDKey: ProcessInfo().globallyUniqueString,
            NSStoreTypeKey: type(of: self).type
        ]
        let storeURL=self.url
        let backingMOM: NSManagedObjectModel? = self.backingModel()
        if backingMOM != nil {
            self.backingPersistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: backingMOM!)
            do {
                self.backingPersistentStore = try self.backingPersistentStoreCoordinator?.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
                self.operationQueue = OperationQueue()
                self.operationQueue!.maxConcurrentOperationCount = 1
            } catch {
                throw SMStoreError.backingStoreCreationFailed
            }
            return
        }
        throw SMStoreError.backingStoreCreationFailed
    }
    
    func backingModel() -> NSManagedObjectModel? {
        if self.persistentStoreCoordinator?.managedObjectModel != nil {
            let backingModel: NSManagedObjectModel = SMStoreChangeSetHandler.defaultHandler.modelForLocalStore(usingModel: self.persistentStoreCoordinator!.managedObjectModel)
            return backingModel
        }
        return nil
    }
    
    open func handlePush(userInfo:[NSObject : AnyObject]) {
        let u = userInfo as! [String : NSObject]
        let ckNotification = CKNotification(fromRemoteNotificationDictionary: u)
        if ckNotification.notificationType == CKNotificationType.recordZone {
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
    
    open func triggerSync() {
        if self.operationQueue != nil && self.operationQueue!.operationCount > 0 {
            return
        }
        let syncOperationBlock = {
            self.syncOperation = SMStoreSyncOperation(persistentStoreCoordinator: self.backingPersistentStoreCoordinator, entitiesToSync: self.entitiesToParticipateInSync()!, conflictPolicy: self.cksStoresSyncConflictPolicy)
            self.syncOperation?.syncConflictResolutionBlock = self.recordConflictResolutionBlock
            self.syncOperation?.syncCompletionBlock =  { error in
                if error == nil {
                    print("Sync Performed Successfully")
                    OperationQueue.main.addOperation {
                        NotificationCenter.default.post(name: Notification.Name(rawValue: SMStoreDidFinishSyncOperationNotification), object: self)
                    }
                } else {
                    print("Sync unSuccessful")
                    OperationQueue.main.addOperation {
                        NotificationCenter.default.post(name: Notification.Name(rawValue: SMStoreDidFinishSyncOperationNotification), object: self, userInfo: error!.userInfo)
                    }
                }
            }
            self.operationQueue?.addOperation(self.syncOperation!)
        }
        if UserDefaults.standard.object(forKey: SMStoreCloudStoreCustomZoneName) == nil || UserDefaults.standard.object(forKey: SMStoreCloudStoreSubscriptionName) == nil {
            self.cloudStoreSetupOperation = SMServerStoreSetupOperation(cloudDatabase: self.database)
            self.cloudStoreSetupOperation?.setupOperationCompletionBlock = { customZoneWasCreated, customZoneSubscriptionWasCreated in
                syncOperationBlock()
            }
            self.operationQueue?.addOperation(self.cloudStoreSetupOperation!)
        } else {
            syncOperationBlock()
        }
        NotificationCenter.default.post(name: Notification.Name(rawValue: SMStoreDidStartSyncOperationNotification), object: self)
    }
    
    override open func execute(_ request: NSPersistentStoreRequest, with context: NSManagedObjectContext?) throws -> Any {
        if request.requestType == NSPersistentStoreRequestType.fetchRequestType {
            let fetchRequest = request as! NSFetchRequest<NSManagedObject>
            return try self.executeInResponseToFetchRequest(fetchRequest, context: context!)
        } else if request.requestType == NSPersistentStoreRequestType.saveRequestType {
            let saveChangesRequest: NSSaveChangesRequest = request as! NSSaveChangesRequest
            return try self.executeInResponseToSaveChangesRequest(saveChangesRequest, context: context!)
        } else {
            throw NSError(domain: SMStoreErrorDomain, code: SMStoreError.invalidRequest._code, userInfo: nil)
        }
    }
    
    override open func newValuesForObject(with objectID: NSManagedObjectID, with context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        let recordID:String = self.referenceObject(for: objectID) as! String
        let propertiesToFetch = Array(objectID.entity.propertiesByName.values).filter { object  in
            if object is NSRelationshipDescription {
                let relationshipDescription: NSRelationshipDescription = object as! NSRelationshipDescription
                return relationshipDescription.isToMany == false
            }
            return true
            }.map {
                return $0.name
        }
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: objectID.entity.name!)
        let predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,recordID)
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = predicate
        fetchRequest.resultType = NSFetchRequestResultType.dictionaryResultType
        fetchRequest.propertiesToFetch = propertiesToFetch
        let results = try self.backingMOC.fetch(fetchRequest)
        var backingObjectValues = results.last as! Dictionary<String,NSObject>
        for (key,value) in backingObjectValues {
            if value is NSManagedObject {
                let managedObject: NSManagedObject = value as! NSManagedObject
                let recordID: String = managedObject.value(forKey: SMLocalStoreRecordIDAttributeName) as! String
                let entities = self.persistentStoreCoordinator!.managedObjectModel.entitiesByName
                let entityName = managedObject.entity.name!
                let entity: NSEntityDescription = entities[entityName]! as NSEntityDescription
                let objectID = self.newObjectID(for: entity, referenceObject: recordID)
                backingObjectValues[key] = objectID
            }
        }
        let incrementalStoreNode = NSIncrementalStoreNode(objectID: objectID, withValues: backingObjectValues, version: 1)
        return incrementalStoreNode
        
    }
    
    override open func newValue(forRelationship relationship: NSRelationshipDescription, forObjectWith objectID: NSManagedObjectID, with context: NSManagedObjectContext?) throws -> Any {
        let recordID: String = self.referenceObject(for: objectID) as! String
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: objectID.entity.name!)
        let predicate: NSPredicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,recordID)
        fetchRequest.predicate = predicate
        let results = try self.backingMOC.fetch(fetchRequest)
        if results.count > 0 {
            let managedObject = results.first!
            let relationshipValues: Set<NSObject> = managedObject.value(forKey: relationship.name) as! Set<NSObject>
            return Array(relationshipValues).map({(object) -> NSManagedObjectID in
                let value: NSManagedObject = object as! NSManagedObject
                let recordID: String = value.value(forKey: SMLocalStoreRecordIDAttributeName) as! String
                let objectID: NSManagedObjectID = self.newObjectID(for: value.entity, referenceObject: recordID)
                return objectID
            })
        }
        return []
    }
    
    override open func obtainPermanentIDs(for array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        return array.map { object in
            let insertedObject:NSManagedObject = object as NSManagedObject
            let newRecordID: String = UUID().uuidString
            return self.newObjectID(for: insertedObject.entity, referenceObject: newRecordID)
        }
    }
    
    // MARK : Fetch Request
    func executeInResponseToFetchRequest(_ fetchRequest:NSFetchRequest<NSManagedObject>,context:NSManagedObjectContext) throws ->NSArray {
        let resultsFromLocalStore = try self.backingMOC.fetch(fetchRequest)
        if resultsFromLocalStore.count > 0 {
            return NSArray(array: resultsFromLocalStore.map({(result)->NSManagedObject in
                let result = result
                let recordID: String = result.value(forKey: SMLocalStoreRecordIDAttributeName) as! String
                let entity = self.persistentStoreCoordinator?.managedObjectModel.entitiesByName[fetchRequest.entityName!]
                let objectID = self.newObjectID(for: entity!, referenceObject: recordID)
                let object = context.object(with: objectID)
                return object
            }))
        }
        return []
    }
    
    // MARK : SaveChanges Request
    fileprivate func executeInResponseToSaveChangesRequest(_ saveRequest:NSSaveChangesRequest,context:NSManagedObjectContext) throws -> Array<AnyObject> {
        try self.insertObjectsInBackingStore(objectsToInsert: context.insertedObjects, mainContext: context)
        try self.updateObjectsInBackingStore(objectsToUpdate: context.updatedObjects)
        try self.deleteObjectsFromBackingStore(objectsToDelete: context.deletedObjects, mainContext: context)
        try self.backingMOC.saveIfHasChanges()
        self.triggerSync()
        return []
    }
    
    func objectIDForBackingObjectForEntity(_ entityName: String, withReferenceObject referenceObject: String?) throws -> NSManagedObjectID? {
        if referenceObject == nil {
            return nil
        }
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        fetchRequest.resultType = NSFetchRequestResultType.managedObjectIDResultType
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,referenceObject!)
        do {
            let results = try self.backingMOC.fetch(fetchRequest)
            if results.count > 0 {
                return results.last?.objectID
            }
        } catch {
            print("")
        }
        return nil
    }
    
    fileprivate func setRelationshipValuesForBackingObject(_ backingObject:NSManagedObject,sourceObject:NSManagedObject) throws {
        for relationship in Array(sourceObject.entity.relationshipsByName.values) as [NSRelationshipDescription] {
            if sourceObject.hasFault(forRelationshipNamed: relationship.name) || sourceObject.value(forKey: relationship.name) == nil {
                continue
            }
            if relationship.isToMany == true {
                let relationshipValue: Set<NSObject> = sourceObject.value(forKey: relationship.name) as! Set<NSObject>
                var backingRelationshipValue: Set<NSObject> = Set<NSObject>()
                for relationshipObject in relationshipValue {
                    let relationshipManagedObject: NSManagedObject = relationshipObject as! NSManagedObject
                    if relationshipManagedObject.objectID.isTemporaryID == false {
                        let referenceObject: String = self.referenceObject(for: relationshipManagedObject.objectID) as! String
                        let backingRelationshipObjectID = try self.objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject)
                        if backingRelationshipObjectID != nil {
                            let backingRelationshipObject = try backingObject.managedObjectContext?.existingObject(with: backingRelationshipObjectID!)
                            backingRelationshipValue.insert(backingRelationshipObject!)
                        }
                    }
                }
                backingObject.setValue(backingRelationshipValue, forKey: relationship.name)
            } else {
                let relationshipValue: NSManagedObject = sourceObject.value(forKey: relationship.name) as! NSManagedObject
                if relationshipValue.objectID.isTemporaryID == false {
                    let referenceObject: String = self.referenceObject(for: relationshipValue.objectID) as! String
                    let backingRelationshipObjectID = try self.objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject)
                    if backingRelationshipObjectID != nil {
                        let backingRelationshipObject = try self.backingMOC.existingObject(with: backingRelationshipObjectID!)
                        backingObject.setValue(backingRelationshipObject, forKey: relationship.name)
                    }
                }
            }
        }
    }
    
    func insertObjectsInBackingStore(objectsToInsert objects:Set<NSObject>, mainContext: NSManagedObjectContext) throws {
        for object in objects {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let managedObject:NSManagedObject = NSEntityDescription.insertNewObject(forEntityName: (sourceObject.entity.name)!, into: self.backingMOC) as NSManagedObject
            let keys = Array(sourceObject.entity.attributesByName.keys)
            let dictionary = sourceObject.dictionaryWithValues(forKeys: keys)
            managedObject.setValuesForKeys(dictionary)
            let referenceObject: String = self.referenceObject(for: sourceObject.objectID) as! String
            managedObject.setValue(referenceObject, forKey: SMLocalStoreRecordIDAttributeName)
            mainContext.willChangeValue(forKey: "objectID")
            try mainContext.obtainPermanentIDs(for: [sourceObject])
            mainContext.didChangeValue(forKey: "objectID")
            SMStoreChangeSetHandler.defaultHandler.createChangeSet(ForInsertedObjectRecordID: referenceObject, entityName: sourceObject.entity.name!, backingContext: self.backingMOC)
            try self.setRelationshipValuesForBackingObject(managedObject, sourceObject: sourceObject)
            try self.backingMOC.saveIfHasChanges()
        }
    }
    
    fileprivate func deleteObjectsFromBackingStore(objectsToDelete objects: Set<NSObject>, mainContext: NSManagedObjectContext) throws {
        let predicateObjectRecordIDKey = "objectRecordID"
        let predicate: NSPredicate = NSPredicate(format: "%K == $objectRecordID", SMLocalStoreRecordIDAttributeName)
        for object in objects {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: sourceObject.entity.name!)
            let recordID: String = self.referenceObject(for: sourceObject.objectID) as! String
            fetchRequest.predicate = predicate.withSubstitutionVariables([predicateObjectRecordIDKey: recordID])
            fetchRequest.fetchLimit = 1
            let results = try self.backingMOC.fetch(fetchRequest)
            let backingObject = results.last!
            SMStoreChangeSetHandler.defaultHandler.createChangeSet(ForDeletedObjectRecordID: recordID, backingContext: self.backingMOC)
            self.backingMOC.delete(backingObject)
            try self.backingMOC.saveIfHasChanges()
        }
    }
    
    fileprivate func updateObjectsInBackingStore(objectsToUpdate objects: Set<NSObject>) throws {
        let predicateObjectRecordIDKey = "objectRecordID"
        let predicate: NSPredicate = NSPredicate(format: "%K == $objectRecordID", SMLocalStoreRecordIDAttributeName)
        for object in objects {
            let sourceObject: NSManagedObject = object as! NSManagedObject
            let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: sourceObject.entity.name!)
            let recordID: String = self.referenceObject(for: sourceObject.objectID) as! String
            fetchRequest.predicate = predicate.withSubstitutionVariables([predicateObjectRecordIDKey:recordID])
            fetchRequest.fetchLimit = 1
            let results = try self.backingMOC.fetch(fetchRequest)
            let backingObject = results.last!
            let keys = Array(self.persistentStoreCoordinator!.managedObjectModel.entitiesByName[sourceObject.entity.name!]!.attributesByName.keys)
            let sourceObjectValues = sourceObject.dictionaryWithValues(forKeys: keys)
            backingObject.setValuesForKeys(sourceObjectValues)
            SMStoreChangeSetHandler.defaultHandler.createChangeSet(ForUpdatedObject: backingObject, usingContext: self.backingMOC)
            try self.setRelationshipValuesForBackingObject(backingObject, sourceObject: sourceObject)
            try self.backingMOC.saveIfHasChanges()
        }
    }
}
