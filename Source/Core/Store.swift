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

public typealias ConflictResolutionInfo = (serverValues: [String: AnyObject], localValues: [String: AnyObject], pendingLocallyChangedProperties: [String])
public typealias ConflictResolutionReturnedInfo = (newValues: [String: AnyObject], pendingLocallyChangedProperties: [String])
public typealias ConflictResolutionBlock = ((conflictResolutionInfo: ConflictResolutionInfo) -> ConflictResolutionReturnedInfo)

public class Store: NSIncrementalStore {
  
  var zone: Zone!
//    if let zoneName = self.zoneName {
//      return Zone(zoneName: zoneName)
//    } else if let zoneName = try? self.preferenceManager.zoneName() where zoneName != nil {
//      return Zone(zoneName: zoneName!)
//    }
//    return Zone()
//  }()
  
  lazy var changeManager: Change.Manager = {
    return Change.Manager(changeContext: self.backingMOC)
  }()
  
  lazy var preferenceManager: Preference.Manager = {
    let managedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    managedObjectContext.persistentStoreCoordinator = self.backingPSC
    return Preference.Manager(context: managedObjectContext)
  }()

  lazy var backingPSC: NSPersistentStoreCoordinator = {
    let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: self.backingStoreModel)
    return persistentStoreCoordinator
  }()
  
  lazy var backingStoreModel: NSManagedObjectModel = {
    let model = self.persistentStoreCoordinator!.managedObjectModel.copy() as! NSManagedObjectModel
    model.entities.forEach { entity in
      entity.properties.append(UniqueID.attributeDescription)
    }
    model.entities.append(Change.Entity.entityDescription)
    model.entities.append(Metadata.Entity.entityDescription)
    model.entities.append(Preference.Entity.entityDescription)
    return model
  }()
  
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
  
  var syncConflictResolutionBlock: ConflictResolutionBlock?
  
  // MARK: Computed Properties for Options
  lazy var optionValues: (conflictResolutionPolicy: String?, zoneName: String?) = {
    let optionValues: (conflictResolutionPolicy: String?, zoneName: String?)
    optionValues.conflictResolutionPolicy = self.options?[SMSyncConflictResolutionPolicyOption] as? String
    optionValues.zoneName = self.options?[SMCloudKitZoneNameOption] as? String
    return optionValues
  }()
  
  // MARK: Error

  static let errorDomain = "com.seam.error.store.errorDomain"
  enum Error: ErrorType {
    case CreationFailed
    case InvalidRequest
    case BackingObjectFetchFailed
  }
  
  override public class func initialize() {
    NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: type)
    Transformers.registerAll()
  }
  
  class internal var type: String {
    return NSStringFromClass(self)
  }
  
  override public func loadMetadata() throws {
    metadata = [
      NSStoreUUIDKey: NSProcessInfo().globallyUniqueString,
      NSStoreTypeKey: self.dynamicType.type
    ]
    let isNewStore = URL != nil && NSFileManager.defaultManager().fileExistsAtPath(URL!.path!) == false
    guard let _ = try? backingPSC.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: URL, options: nil) else {
      throw Error.CreationFailed
    }
    changeManager = Change.Manager(changeContext: backingMOC)
    
    guard isNewStore else {
      if let zoneName = try preferenceManager.zoneName() {
        zone = Zone(zoneName: zoneName)
      }
      return
    }
    if let zoneName = optionValues.zoneName {
      preferenceManager.saveZoneName(zoneName)
      zone = Zone(zoneName: zoneName)
    } else {
      zone = Zone()
      preferenceManager.saveZoneName(zone.zone.zoneID.zoneName)
    }
  }

  public func sync(conflictResolutionBlock: ConflictResolutionBlock?) {
    guard operationQueue.operationCount == 0 else {
      return
    }
    self.syncConflictResolutionBlock = conflictResolutionBlock
    let sync = Sync(store: self)
    sync.onCompletion = { (saveNotification, error) in
      guard let notification = saveNotification where error == nil else {
        return
      }
      self.backingMOC.performBlock {
        NSNotificationCenter.defaultCenter().postNotificationName(SMStoreDidFinishSyncingNotification, object: nil, userInfo: notification.userInfo)
      }
    }
    operationQueue.addOperation(sync)
  }
  
  public func subscribeToPushNotifications(completionBlock: ((successful: Bool) -> ())?) {
    zone.createSubscription({ successful in
      guard successful else {
        completionBlock?(successful: false)
        return
      }
      completionBlock?(successful: true)
    })
  }
  
  func setUniqueIDForInsertedObject(uniqueID: String, insertedObject: NSManagedObject) {
    backingMOC.setUniqueIDForInsertedObject(uniqueID, object: insertedObject)
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
    return array.map { sourceObject in
      if let uniqueID = self.backingMOC.uniqueIDForInsertedObject(sourceObject) {
        return newObjectIDForEntity(sourceObject.entity, referenceObject: uniqueID)
      } else {
        return newObjectIDForEntity(sourceObject.entity, referenceObject: NSUUID().UUIDString)
      }
    }
  }
  
  // MARK: - Requests

  override public func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
    var result: AnyObject = []
    try backingMOC.performBlockAndWait {
      if let context = context {
        if let fetchRequest = request as? NSFetchRequest {
          result = try self.executeFetchRequest(fetchRequest, context: context)
        } else if let saveChangesRequest = request as? NSSaveChangesRequest {
          result = try self.executeSaveChangesRequest(saveChangesRequest, context: context)
        } else {
          throw Error.InvalidRequest
        }
      }
    }
    return result
  }
  
  // MARK: FetchRequest
  
  func executeFetchRequest(fetchRequest: NSFetchRequest, context: NSManagedObjectContext) throws -> [NSManagedObject] {
    let result = try backingMOC.executeFetchRequest(fetchRequest) as! [NSManagedObject]
    return result.map { object in
      let recordID = object.uniqueID
      let entity = persistentStoreCoordinator!.managedObjectModel.entitiesByName[fetchRequest.entityName!]
      let objectID = newObjectIDForEntity(entity!, referenceObject: recordID)
      let object = context.objectWithID(objectID)
      return object
    }
  }
  
  // MARK: SaveChangesRequest
  
  private func executeSaveChangesRequest(request: NSSaveChangesRequest, context: NSManagedObjectContext) throws -> [AnyObject] {
    if let deletedObjects = request.deletedObjects {
      try deleteObjectsFromBackingStore(objectsToDelete: deletedObjects, context: context)
    }
    if let insertedObjects = request.insertedObjects {
      try insertObjectsInBackingStore(objectsToInsert: insertedObjects, context: context)
    }
    if let updatedObjects = request.updatedObjects {
      try updateObjectsInBackingStore(objectsToUpdate: updatedObjects, context: context)
    }
    try backingMOC.performBlockAndWait {
      try self.backingMOC.saveIfHasChanges()
    }
    return []
  }
  
  func insertObjectsInBackingStore(objectsToInsert objects:Set<NSManagedObject>, context: NSManagedObjectContext) throws {
    try backingMOC.performBlockAndWait {
      try objects.forEach { sourceObject in
        let backingObject = NSEntityDescription.insertNewObjectForEntityForName((sourceObject.entity.name)!, inManagedObjectContext: self.backingMOC) as NSManagedObject
        if let uniqueID = self.backingMOC.uniqueIDForInsertedObject(sourceObject) {
          backingObject.uniqueID = uniqueID
        } else {
          let uniqueID = self.uniqueIDForObjectID(sourceObject.objectID)
          backingObject.uniqueID = uniqueID
        }
        self.setAttributeValuesForBackingObject(backingObject, sourceObject: sourceObject)
        try self.setRelationshipValuesForBackingObject(backingObject, fromSourceObject: sourceObject)
        if context.doesNotAllowChangeRecording == false {
          self.changeManager.new(backingObject.uniqueID, changedObject: sourceObject)
        }
      }
    }
  }
  
  private func updateObjectsInBackingStore(objectsToUpdate objects: Set<NSManagedObject>, context: NSManagedObjectContext) throws {
    try backingMOC.performBlockAndWait {
      try objects.forEach { sourceObject in
        let referenceObject = self.uniqueIDForObjectID(sourceObject.objectID)
        guard let backingObjectID = try self.objectIDForBackingObjectForEntity(sourceObject.entity.name!, withReferenceObject: referenceObject) else {
          return
        }
        guard let backingObject = try? self.backingMOC.existingObjectWithID(backingObjectID) else {
          return
        }
        self.setAttributeValuesForBackingObject(backingObject, sourceObject: sourceObject)
        try self.setRelationshipValuesForBackingObject(backingObject, fromSourceObject: sourceObject)
        let changedValueKeys = sourceObject.changedValueKeys
        guard context.doesNotAllowChangeRecording == false && changedValueKeys.count > 0 else {
          return
        }
        self.changeManager.new(referenceObject, changedObject: sourceObject)
      }
    }
  }
  
  private func deleteObjectsFromBackingStore(objectsToDelete objects: Set<NSManagedObject>, context: NSManagedObjectContext) throws {
    try backingMOC.performBlockAndWait {
      try objects.forEach { sourceObject in
        let fetchRequest = NSFetchRequest(entityName: sourceObject.entity.name!)
        let referenceObject = self.uniqueIDForObjectID(sourceObject.objectID)
        fetchRequest.predicate = NSPredicate(equalsToUniqueID: referenceObject)
        fetchRequest.includesPropertyValues = false
        let results = try self.backingMOC.executeFetchRequest(fetchRequest)
        guard let backingObject = results.last as? NSManagedObject else {
          return
        }
        self.backingMOC.deleteObject(backingObject)
        guard context.doesNotAllowChangeRecording == false else {
          return
        }
        self.changeManager.new(referenceObject, changedObject: sourceObject)
      }
    }
  }
}