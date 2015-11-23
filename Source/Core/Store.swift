//    Store.swift
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

public class Store: NSIncrementalStore {
  static let errorDomain = "com.seam.error.store.errorDomain"
  enum Error: ErrorType {
    case CreationFailed
    case ModelCreationFailed
    case PersistentStoreInitializationFailed
    case InvalidRequest
    case BackingObjectFetchFailed
  }
  private var backingPSC: NSPersistentStoreCoordinator?
  private lazy var backingMOC: NSManagedObjectContext = {
    var backingMOC = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    backingMOC.persistentStoreCoordinator = self.backingPSC
    backingMOC.retainsRegisteredObjects = true
    backingMOC.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
    return backingMOC
  }()
  private lazy var operationQueue: NSOperationQueue = {
    let operationQueue = NSOperationQueue()
    operationQueue.maxConcurrentOperationCount = 1
    return operationQueue
  }()
  var changeManager: Change.Manager!
  
  override public class func initialize() {
    NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: type)
    registerTransformers()
  }
  
  class internal var type: String {
    return NSStringFromClass(self)
  }
  
  class func registerTransformers() {
    let valueTransformer = AssetURLTransformer()
    NSValueTransformer.setValueTransformer(valueTransformer, forName: SpecialAttribute.Asset.valueTransformerName)
  }
  
  override public func loadMetadata() throws {
    metadata = [
      NSStoreUUIDKey: NSProcessInfo().globallyUniqueString,
      NSStoreTypeKey: self.dynamicType.type
    ]
    guard let backingMOM = Change.modifiedModel(fromModel: persistentStoreCoordinator!.managedObjectModel) else {
      throw Error.ModelCreationFailed
    }
    backingPSC = NSPersistentStoreCoordinator(managedObjectModel: backingMOM)
    guard let backingPSC = backingPSC else {
      throw Error.PersistentStoreInitializationFailed
    }
    guard let _ = try? backingPSC.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: URL, options: nil) else {
      throw Error.CreationFailed
    }
    changeManager = Change.Manager(managedObjectContext: backingMOC)
  }
  
  public func performContextBasedSync(completionBlock: ((insertedOrUpdatedObjectIDs: [NSManagedObjectID]?, deletedObjectIDs: [NSManagedObjectID]?) -> ())?) {
    guard operationQueue.operationCount == 0 else {
      print("Already Syncing")
      completionBlock?(insertedOrUpdatedObjectIDs: nil, deletedObjectIDs: nil)
      return
    }
    let sync = Sync(backingPersistentStoreCoordinator: backingPSC!, persistentStoreCoordinator: persistentStoreCoordinator!)
    sync.syncCompletionBlock = { (notifications, changesFromServerInfo, error) in
      if error == nil {
          self.backingMOC.performBlock {
          notifications.forEach { notification in
            self.backingMOC.mergeChangesFromContextDidSaveNotification(notification)
          }
          let _ = try? self.backingMOC.save()
          var insertedOrUpdatedObjectIDs = [NSManagedObjectID]()
          var deletedObjectIDs = [NSManagedObjectID]()
          changesFromServerInfo?.insertedOrUpdatedObjectsInfo.forEach { (uniqueID, entityName) in
            let entity = self.persistentStoreCoordinator!.managedObjectModel.entitiesByName[entityName]!
            let objectID = self.newObjectIDForEntity(entity, referenceObject: uniqueID)
            insertedOrUpdatedObjectIDs.append(objectID)
          }
          changesFromServerInfo?.deletedObjectsInfo.forEach { (uniqueID, entityName) in
            let entity = self.persistentStoreCoordinator!.managedObjectModel.entitiesByName[entityName]!
            let objectID = self.newObjectIDForEntity(entity, referenceObject: uniqueID)
            deletedObjectIDs.append(objectID)
          }
          completionBlock?(insertedOrUpdatedObjectIDs: insertedOrUpdatedObjectIDs, deletedObjectIDs: deletedObjectIDs)
        }
      } else {
        completionBlock?(insertedOrUpdatedObjectIDs: nil, deletedObjectIDs: nil)
      }
    }
    operationQueue.addOperation(sync)
  }
  
  // MARK: - Translation
  
  func uniqueIDForObjectID(objectID: NSManagedObjectID) -> String {
    return referenceObjectForObjectID(objectID) as! String
  }
  
  func objectIDForBackingObjectForEntity(entityName: String, withReferenceObject referenceObject: String) throws -> NSManagedObjectID? {
    let fetchRequest = NSFetchRequest(entityName: entityName)
    fetchRequest.resultType = .ManagedObjectIDResultType
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: referenceObject)
    return try backingMOC.executeFetchRequest(fetchRequest).last as? NSManagedObjectID
  }
  
  // MARK: Attribute and Relationship Setters
  
  func setAttributeValuesForBackingObject(backingObject: NSManagedObject, sourceObject: NSManagedObject) {
    if backingObject.valueForKey(UniqueID.name) == nil {
      let uniqueID = uniqueIDForObjectID(sourceObject.objectID)
      backingObject.setValue(uniqueID, forKey: UniqueID.name)
    }
    let keys = sourceObject.entity.attributeNames + sourceObject.entity.assetAttributeNames
    let valuesForKeys = sourceObject.dictionaryWithValuesForKeys(keys)
    backingObject.setValuesForKeysWithDictionary(valuesForKeys)
  }
  
  func setRelationshipValuesForBackingObject(backingObject: NSManagedObject,fromSourceObject sourceObject: NSManagedObject) throws {
    try sourceObject.entity.relationships.forEach { relationship in
      guard !sourceObject.hasFaultForRelationshipNamed(relationship.name) else {
        return
      }
      guard sourceObject.valueForKey(relationship.name) != nil else {
        return
      }
      if let relationshipManagedObjects = sourceObject.valueForKey(relationship.name) as? Set<NSManagedObject> {
        var backingRelationshipManagedObjects = Set<NSManagedObject>()
        try relationshipManagedObjects.forEach { relationshipManagedObject in
          guard !relationshipManagedObject.objectID.temporaryID else {
            return
          }
          let referenceObject = uniqueIDForObjectID(relationshipManagedObject.objectID)
          if let backingRelationshipObjectID = try objectIDForBackingObjectForEntity(relationshipManagedObject.entity.name!, withReferenceObject: referenceObject) {
            let backingRelationshipObject = try backingMOC.existingObjectWithID(backingRelationshipObjectID)
            backingRelationshipManagedObjects.insert(backingRelationshipObject)
          }
        }
        backingObject.setValue(backingRelationshipManagedObjects, forKey: relationship.name)
      } else if let relationshipManagedObject = sourceObject.valueForKey(relationship.name) as? NSManagedObject {
        guard !relationshipManagedObject.objectID.temporaryID else {
          return
        }
        let referenceObject = uniqueIDForObjectID(relationshipManagedObject.objectID)
        if let backingRelationshipObjectID = try objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject) {
          if let backingRelationshipObject = try? backingMOC.existingObjectWithID(backingRelationshipObjectID) {
            backingObject.setValue(backingRelationshipObject, forKey: relationship.name)
          }
        }
      }
    }
  }
  
  // MARK: - Faulting
  
  override public func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
    let recordID = uniqueIDForObjectID(objectID)
    let fetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: recordID)
    guard let managedObject = try backingMOC.executeFetchRequest(fetchRequest).last as? NSManagedObject else {
      throw Error.BackingObjectFetchFailed
    }
    let propertiesToReturn = objectID.entity.propertyNamesToFetch
    var valuesDictionary = managedObject.dictionaryWithValuesForKeys(propertiesToReturn)
    valuesDictionary.forEach { (key, value) in
      if let managedObject = value as? NSManagedObject {
        let recordID  = managedObject.uniqueID
        let entities = persistentStoreCoordinator!.managedObjectModel.entitiesByName
        let entityName = managedObject.entity.name!
        let entity = entities[entityName]! as NSEntityDescription
        let objectID = newObjectIDForEntity(entity, referenceObject: recordID)
        valuesDictionary[key] = objectID
      }
    }
    let incrementalStoreNode = NSIncrementalStoreNode(objectID: objectID, withValues: valuesDictionary, version: 1)
    return incrementalStoreNode
  }
  
  override public func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
    let referenceObject = uniqueIDForObjectID(objectID)
    guard let backingObjectID = try objectIDForBackingObjectForEntity(objectID.entity.name!, withReferenceObject: referenceObject) else {
      if relationship.toMany {
        return []
      } else {
        return NSNull()
      }
    }
    let backingObject = try backingMOC.existingObjectWithID(backingObjectID)
    if let relationshipManagedObjects = backingObject.valueForKey(relationship.name) as? Set<NSManagedObject> {
      var relationshipManagedObjectIDs = Set<NSManagedObjectID>()
      relationshipManagedObjects.forEach { object in
        let uniqueID = object.uniqueID
        let objectID = newObjectIDForEntity(relationship.destinationEntity!, referenceObject: uniqueID)
        relationshipManagedObjectIDs.insert(objectID)
      }
      return relationshipManagedObjectIDs
    } else if let relationshipManagedObject = backingObject.valueForKey(relationship.name) as? NSManagedObject {
      let uniqueID = relationshipManagedObject.uniqueID
      return newObjectIDForEntity(relationship.destinationEntity!, referenceObject: uniqueID)
    }
    return NSNull()
  }
  
  override public func obtainPermanentIDsForObjects(array: [NSManagedObject]) throws -> [NSManagedObjectID] {
    return array.map { newObjectIDForEntity($0.entity, referenceObject: NSUUID().UUIDString) }
  }
  
  // MARK: - Requests
  
  override public func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
    if let context = context {
      if let fetchRequest = request as? NSFetchRequest {
        return try executeFetchRequest(fetchRequest, context: context)
      } else if let saveChangesRequest = request as? NSSaveChangesRequest {
        return try executeSaveChangesRequest(saveChangesRequest, context: context)
      } else if let batchUpdateRequest = request as? NSBatchUpdateRequest {
        return try executeBatchUpdateRequest(batchUpdateRequest, context: context)
      } else if let batchDeleteRequest = request as? NSBatchDeleteRequest {
        return try executeBatchDeleteRequest(batchDeleteRequest, context: context)
      } else {
        throw Error.InvalidRequest
      }
    }
    return []
  }
  
  // MARK: FetchRequest
  
  func executeFetchRequest(fetchRequest: NSFetchRequest, context: NSManagedObjectContext) throws -> [NSManagedObject] {
    if let result = try? backingMOC.executeFetchRequest(fetchRequest) {
      if let fetchedObjects = result as? [NSManagedObject] {
        return fetchedObjects.map { object in
          let recordID = object.uniqueID
          let entity = persistentStoreCoordinator!.managedObjectModel.entitiesByName[fetchRequest.entityName!]
          let objectID = newObjectIDForEntity(entity!, referenceObject: recordID)
          let object = context.objectWithID(objectID)
          return object
        }
      }
    }
    return []
  }
  
  // MARK: SaveChangesRequest
  
  private func executeSaveChangesRequest(request: NSSaveChangesRequest, context: NSManagedObjectContext) throws -> [AnyObject] {
    if let deletedObjects = request.deletedObjects {
      try deleteObjectsFromBackingStore(objectsToDelete: deletedObjects, mainContext: context)
    }
    if let insertedObjects = request.insertedObjects {
      try insertObjectsInBackingStore(objectsToInsert: insertedObjects, mainContext: context)
    }
    if let updatedObjects = request.updatedObjects {
      try updateObjectsInBackingStore(objectsToUpdate: updatedObjects)
    }
    return []
  }
  
  func insertObjectsInBackingStore(objectsToInsert objects:Set<NSManagedObject>, mainContext: NSManagedObjectContext) throws {
    try backingMOC.performBlockAndWait {
      try objects.forEach { sourceObject in
        let backingObject = NSEntityDescription.insertNewObjectForEntityForName((sourceObject.entity.name)!, inManagedObjectContext: self.backingMOC) as NSManagedObject
        let referenceObject = self.uniqueIDForObjectID(sourceObject.objectID)
        backingObject.setValue(referenceObject, forKey: UniqueID.name)
        try self.backingMOC.obtainPermanentIDsForObjects([backingObject])
        self.setAttributeValuesForBackingObject(backingObject, sourceObject: sourceObject)
        try self.setRelationshipValuesForBackingObject(backingObject, fromSourceObject: sourceObject)
        mainContext.willChangeValueForKey("objectID")
        try mainContext.obtainPermanentIDsForObjects([sourceObject])
        mainContext.didChangeValueForKey("objectID")
        try self.changeManager.new(referenceObject, changedObject: sourceObject)
        try self.backingMOC.save()
      }
    }
  }
  
  private func updateObjectsInBackingStore(objectsToUpdate objects: Set<NSManagedObject>) throws {
    try backingMOC.performBlockAndWait {
      try objects.forEach { sourceObject in
        let referenceObject = self.uniqueIDForObjectID(sourceObject.objectID)
        if let backingObjectID = try self.objectIDForBackingObjectForEntity(sourceObject.entity.name!, withReferenceObject: referenceObject) {
          if let backingObject = try? self.backingMOC.existingObjectWithID(backingObjectID) {
            self.setAttributeValuesForBackingObject(backingObject, sourceObject: sourceObject)
            try self.setRelationshipValuesForBackingObject(backingObject, fromSourceObject: sourceObject)
            let changedValueKeys = sourceObject.changedValueKeys
            if changedValueKeys.count > 0 {
              try self.changeManager.new(referenceObject, changedObject: sourceObject)
            }
            try self.backingMOC.save()
          }
        }
      }
    }
  }
  
  private func deleteObjectsFromBackingStore(objectsToDelete objects: Set<NSManagedObject>, mainContext: NSManagedObjectContext) throws {
    try backingMOC.performBlockAndWait {
      try objects.forEach { sourceObject in
        let fetchRequest = NSFetchRequest(entityName: sourceObject.entity.name!)
        let referenceObject = self.uniqueIDForObjectID(sourceObject.objectID)
        fetchRequest.predicate = NSPredicate(equalsToUniqueID: referenceObject)
        fetchRequest.includesPropertyValues = false
        let results = try self.backingMOC.executeFetchRequest(fetchRequest)
        if let backingObject = results.last as? NSManagedObject {
          self.backingMOC.deleteObject(backingObject)
          try self.changeManager.new(referenceObject, changedObject: sourceObject)
          try self.backingMOC.save()
        }
      }
    }
  }
  
  // MARK: BatchUpdateRequest
  
  func executeBatchUpdateRequest(batchUpdateRequest: NSBatchUpdateRequest, context: NSManagedObjectContext) throws -> AnyObject {
    try backingMOC.performBlockAndWait {
      let request = NSBatchUpdateRequest(entityName: batchUpdateRequest.entityName)
      request.predicate = batchUpdateRequest.predicate
      request.propertiesToUpdate = batchUpdateRequest.propertiesToUpdate
      try self.backingMOC.executeRequest(request)
    }
    return []
  }
  
  // MARK: BatchDeleteRequest
  
  func executeBatchDeleteRequest(batchDeleteRequest: NSBatchDeleteRequest, context: NSManagedObjectContext) throws -> AnyObject {
    try backingMOC.performBlockAndWait {
      try self.backingMOC.executeRequest(batchDeleteRequest)
    }
    return []
  }
}