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
public typealias ConflictResolutionBlock = ((_ conflictResolutionInfo: ConflictResolutionInfo) -> ConflictResolutionReturnedInfo)

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
    let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
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
    var backingMOC = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    backingMOC.persistentStoreCoordinator = self.backingPSC
    backingMOC.retainsRegisteredObjects = true
    backingMOC.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
    return backingMOC
  }()
  
  private lazy var operationQueue: OperationQueue = {
    let operationQueue = OperationQueue()
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

  static let errorDomain = "com.seam.store.error"
  
  enum StoreError: Error {
    case CreationFailed
    case InvalidRequest
    case BackingObjectFetchFailed
  }
  
  public override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator?, configurationName name: String?, at url: URL, options: [AnyHashable : Any]? = nil) {
    super.init(persistentStoreCoordinator: root, configurationName: name, at: url, options: options)
    NSPersistentStoreCoordinator.registerStoreClass(Store.self, forStoreType: Store.type)
    Transformers.registerAll()
    
  }
  
  class internal var type: String {
    return NSStringFromClass(self)
  }
  
  override public func loadMetadata() throws {
    metadata = [
      NSStoreUUIDKey: ProcessInfo().globallyUniqueString,
      NSStoreTypeKey: Store.type
    ]
    
    let isNewStore = url != nil && FileManager.default.fileExists(atPath: url!.path)
    guard let url = url, let _ = try? backingPSC.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: url, options: nil) else {
      throw StoreError.CreationFailed
    }
    changeManager = Change.Manager(changeContext: backingMOC)
    
    guard isNewStore else {
      if let zoneName = try preferenceManager.zoneName() {
        zone = Zone(zoneName: zoneName)
      }
      return
    }
    if let zoneName = optionValues.zoneName {
      preferenceManager.saveZoneName(name: zoneName)
      zone = Zone(zoneName: zoneName)
    } else {
      zone = Zone()
      preferenceManager.saveZoneName(name: zone.zone.zoneID.zoneName)
    }
  }

  public func sync(conflictResolutionBlock: ConflictResolutionBlock?) {
    guard operationQueue.operationCount == 0 else {
      return
    }
    self.syncConflictResolutionBlock = conflictResolutionBlock
    let sync = Sync(store: self)
    sync.onCompletion = { (saveNotification, error) in
      guard let notification = saveNotification, error == nil else {
        return
      }
      self.backingMOC.perform {
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: SMStoreDidFinishSyncingNotification), object: nil, userInfo: notification.userInfo)
      }
    }
    operationQueue.addOperation(sync)
  }
  
  public func subscribeToPushNotifications(completionBlock: ((_ successful: Bool) -> ())?) {
    
    try? self.zone.createSubscription({ successful in
      guard successful else {
        completionBlock?(successful: false)
        return
      }
      completionBlock?(successful: true)
    })
  }
  
  func setUniqueIDForInsertedObject(uniqueID: String, insertedObject: NSManagedObject) {
    backingMOC.setUniqueIDForInsertedObject(uniqueID: uniqueID, object: insertedObject)
  }
  
  // MARK: - Translation
  
  func uniqueIDForObjectID(objectID: NSManagedObjectID) -> String {
    return referenceObject(for: objectID) as! String
  }
  
  func objectIDForBackingObjectForEntity(entityName: String, withReferenceObject referenceObject: String) throws -> NSManagedObjectID? {
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
    fetchRequest.resultType = .managedObjectIDResultType
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: referenceObject)
    return try backingMOC.fetch(fetchRequest).last as? NSManagedObjectID
  }
  
  // MARK: Attribute and Relationship Setters
  
  func setAttributeValuesForBackingObject(backingObject: NSManagedObject, sourceObject: NSManagedObject) {
    if backingObject.value(forKey: UniqueID.name) == nil {
      let uniqueID = uniqueIDForObjectID(objectID: sourceObject.objectID)
      backingObject.setValue(uniqueID, forKey: UniqueID.name)
    }
    let keys = sourceObject.entity.attributeNames + sourceObject.entity.assetAttributeNames
    let valuesForKeys = sourceObject.dictionaryWithValues(forKeys: keys)
    backingObject.setValuesForKeys(valuesForKeys)
  }
  
  func setRelationshipValuesForBackingObject(backingObject: NSManagedObject,fromSourceObject sourceObject: NSManagedObject) throws {
    try sourceObject.entity.relationships.forEach { relationship in
      guard !sourceObject.hasFault(forRelationshipNamed: relationship.name) else {
        return
      }
      guard sourceObject.value(forKey: relationship.name) != nil else {
        return
      }
      if let relationshipManagedObjects = sourceObject.value(forKey: relationship.name) as? Set<NSManagedObject> {
        var backingRelationshipManagedObjects = Set<NSManagedObject>()
        try relationshipManagedObjects.forEach { relationshipManagedObject in
          guard !relationshipManagedObject.objectID.isTemporaryID else {
            return
          }
          let referenceObject = uniqueIDForObjectID(objectID: relationshipManagedObject.objectID)
          if let backingRelationshipObjectID = try objectIDForBackingObjectForEntity(entityName: relationshipManagedObject.entity.name!, withReferenceObject: referenceObject) {
            let backingRelationshipObject = try backingMOC.existingObject(with: backingRelationshipObjectID)
            backingRelationshipManagedObjects.insert(backingRelationshipObject)
          }
        }
        backingObject.setValue(backingRelationshipManagedObjects, forKey: relationship.name)
      } else if let relationshipManagedObject = sourceObject.value(forKey: relationship.name) as? NSManagedObject {
        guard !relationshipManagedObject.objectID.isTemporaryID else {
          return
        }
        let referenceObject = uniqueIDForObjectID(objectID: relationshipManagedObject.objectID)
        if let backingRelationshipObjectID = try objectIDForBackingObjectForEntity(entityName: relationship.destinationEntity!.name!, withReferenceObject: referenceObject) {
          if let backingRelationshipObject = try? backingMOC.existingObject(with: backingRelationshipObjectID) {
            backingObject.setValue(backingRelationshipObject, forKey: relationship.name)
          }
        }
      }
    }
  }
  
  // MARK: - Faulting
  
  override public func newValuesForObject(with objectID: NSManagedObjectID, with context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
    
    let recordID = uniqueIDForObjectID(objectID: objectID)
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: objectID.entity.name!)
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: recordID)
    guard let managedObject = try backingMOC.fetch(fetchRequest).last as? NSManagedObject else {
      throw StoreError.BackingObjectFetchFailed
    }
    let propertiesToReturn = objectID.entity.propertyNamesToFetch
    var valuesDictionary = managedObject.dictionaryWithValues(forKeys: propertiesToReturn)
    valuesDictionary.forEach { (key, value) in
      if let managedObject = value as? NSManagedObject {
        let recordID  = managedObject.uniqueID
        let entities = persistentStoreCoordinator!.managedObjectModel.entitiesByName
        let entityName = managedObject.entity.name!
        let entity = entities[entityName]! as NSEntityDescription
        let objectID = newObjectID(for: entity, referenceObject: recordID)
        valuesDictionary[key] = objectID
      }
    }
    let incrementalStoreNode = NSIncrementalStoreNode(objectID: objectID, withValues: valuesDictionary, version: 1)
    return incrementalStoreNode
  }
  
  override public func newValue(forRelationship relationship: NSRelationshipDescription, forObjectWith objectID: NSManagedObjectID, with context: NSManagedObjectContext?) throws -> Any {
    
    let referenceObject = uniqueIDForObjectID(objectID: objectID)
    guard let backingObjectID = try objectIDForBackingObjectForEntity(entityName: objectID.entity.name!, withReferenceObject: referenceObject) else {
      if relationship.isToMany {
        return []
      } else {
        return NSNull()
      }
    }
    let backingObject = try backingMOC.existingObject(with: backingObjectID)
    if let relationshipManagedObjects = backingObject.value(forKey: relationship.name) as? Set<NSManagedObject> {
      var relationshipManagedObjectIDs = Set<NSManagedObjectID>()
      relationshipManagedObjects.forEach { object in
        let uniqueID = object.uniqueID
        let objectID = newObjectID(for: relationship.destinationEntity!, referenceObject: uniqueID)
        relationshipManagedObjectIDs.insert(objectID)
      }
      return relationshipManagedObjectIDs
    } else if let relationshipManagedObject = backingObject.value(forKey: relationship.name) as? NSManagedObject {
      let uniqueID = relationshipManagedObject.uniqueID
      return newObjectID(for: relationship.destinationEntity!, referenceObject: uniqueID)
    }
    return NSNull()
  }
  
  override public func obtainPermanentIDs(for array: [NSManagedObject]) throws -> [NSManagedObjectID] {
    return array.map { sourceObject in
      if let uniqueID = self.backingMOC.uniqueIDForInsertedObject(object: sourceObject) {
        return newObjectID(for: sourceObject.entity, referenceObject: uniqueID)
      } else {
        return newObjectID(for: sourceObject.entity, referenceObject: NSUUID().uuidString)
      }
    }
  }
  
  // MARK: - Requests

  override public func execute(_ request: NSPersistentStoreRequest, with context: NSManagedObjectContext?) throws -> Any {
    
    var result = Array<AnyObject>()
    try backingMOC.performBlockAndWait {
      if let context = context {
        if let fetchRequest = request as? NSFetchRequest<NSFetchRequestResult> {
          result = try self.executeFetchRequest(fetchRequest: fetchRequest, context: context) as AnyObject as! [AnyObject]
        } else if let saveChangesRequest = request as? NSSaveChangesRequest {
          result = try self.executeSaveChangesRequest(request: saveChangesRequest, context: context) as AnyObject as! [AnyObject]
        } else {
          throw StoreError.InvalidRequest
        }
      }
    }
    return result
  }
  
  // MARK: FetchRequest
  
  func executeFetchRequest(fetchRequest: NSFetchRequest<NSFetchRequestResult>, context: NSManagedObjectContext) throws -> [NSManagedObject] {
    let result = try backingMOC.fetch(fetchRequest) as! [NSManagedObject]
    return result.map { object in
      let recordID = object.uniqueID
      let entity = persistentStoreCoordinator!.managedObjectModel.entitiesByName[fetchRequest.entityName!]
      let objectID = newObjectID(for: entity!, referenceObject: recordID)
      let object = context.object(with: objectID)
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
        let backingObject = NSEntityDescription.insertNewObject(forEntityName: (sourceObject.entity.name)!, into: self.backingMOC) as NSManagedObject
        if let uniqueID = self.backingMOC.uniqueIDForInsertedObject(object: sourceObject) {
          backingObject.uniqueID = uniqueID
        } else {
          let uniqueID = self.uniqueIDForObjectID(objectID: sourceObject.objectID)
          backingObject.uniqueID = uniqueID
        }
        self.setAttributeValuesForBackingObject(backingObject: backingObject, sourceObject: sourceObject)
        try self.setRelationshipValuesForBackingObject(backingObject: backingObject, fromSourceObject: sourceObject)
        if context.doesNotAllowChangeRecording == false {
          self.changeManager.new(uniqueID: backingObject.uniqueID, changedObject: sourceObject)
        }
      }
    }
  }
  
  private func updateObjectsInBackingStore(objectsToUpdate objects: Set<NSManagedObject>, context: NSManagedObjectContext) throws {
    try backingMOC.performBlockAndWait {
      try objects.forEach { sourceObject in
        let referenceObject = self.uniqueIDForObjectID(objectID: sourceObject.objectID)
        guard let backingObjectID = try self.objectIDForBackingObjectForEntity(entityName: sourceObject.entity.name!, withReferenceObject: referenceObject) else {
          return
        }
        guard let backingObject = try? self.backingMOC.existingObject(with: backingObjectID) else {
          return
        }
        self.setAttributeValuesForBackingObject(backingObject: backingObject, sourceObject: sourceObject)
        try self.setRelationshipValuesForBackingObject(backingObject: backingObject, fromSourceObject: sourceObject)
        let changedValueKeys = sourceObject.changedValueKeys
        guard context.doesNotAllowChangeRecording == false && changedValueKeys.count > 0 else {
          return
        }
        self.changeManager.new(uniqueID: referenceObject, changedObject: sourceObject)
      }
    }
  }
  
  private func deleteObjectsFromBackingStore(objectsToDelete objects: Set<NSManagedObject>, context: NSManagedObjectContext) throws {
    try backingMOC.performBlockAndWait {
      try objects.forEach { sourceObject in
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: sourceObject.entity.name!)
        let referenceObject = self.uniqueIDForObjectID(objectID: sourceObject.objectID)
        fetchRequest.predicate = NSPredicate(equalsToUniqueID: referenceObject)
        fetchRequest.includesPropertyValues = false
        let results = try self.backingMOC.fetch(fetchRequest)
        guard let backingObject = results.last as? NSManagedObject else {
          return
        }
        self.backingMOC.delete(backingObject)
        guard context.doesNotAllowChangeRecording == false else {
          return
        }
        self.changeManager.new(uniqueID: referenceObject, changedObject: sourceObject)
      }
    }
  }
}
