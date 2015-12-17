//    Sync.swift
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

import Foundation
import CloudKit
import CoreData

public typealias Changes = (insertedOrUpdatedObjectsInfo: [(uniqueID: String, entityName: String)], deletedObjectsInfo: [(uniqueID: String, entityName: String)])
typealias CompletionBlock = ((saveNotification: NSNotification? ,syncError: ErrorType?) -> ())

class Sync: NSOperation {
  
  // MARK: Error
  
  static let errorDomain = "com.seam.error.sync.errorDomain"
  
  enum Error: ErrorType {
    case LocalChangesFetchError
    case ConflictsDetected(conflictedRecordsWithChanges: [(record: CKRecord, change: Change)])
    case ConflictedRecordsFetchFailed
    case UnknownError
  }
  
  private lazy var operationQueue: NSOperationQueue = {
    let operationQueue = NSOperationQueue()
    operationQueue.maxConcurrentOperationCount = 1
    return operationQueue
  }()
  
  var store: Store!
  
  private var zone: Zone {
    return self.store.zone
  }
  
  private var backingPersistentStoreCoordinator: NSPersistentStoreCoordinator {
    return store.backingPSC
  }
  
  private var persistentStoreCoordinator: NSPersistentStoreCoordinator {
    return store.persistentStoreCoordinator!
  }
  
  private var conflictResolutionBlock: ConflictResolutionBlock? {
    return store.syncConflictResolutionBlock
  }
  
  private lazy var backingStoreContext: NSManagedObjectContext = {
    let backingStoreContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    backingStoreContext.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
    return backingStoreContext
  }()
  
  private lazy var storeContext: NSManagedObjectContext = {
    let storeContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    storeContext.persistentStoreCoordinator = self.persistentStoreCoordinator
    storeContext.retainsRegisteredObjects = true
    storeContext.doesNotAllowChangeRecording = true
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "storeContextDidSave:", name: NSManagedObjectContextDidSaveNotification, object: storeContext)
    return storeContext
  }()
  
  private lazy var changeManager: Change.Manager = {
    let changeManager = Change.Manager(changeContext: self.backingStoreContext, mainContext: self.storeContext)
    return changeManager
  }()
  
  private lazy var metadataManager: Metadata.Manager = {
    var metadataContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    metadataContext.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
    return Metadata.Manager(context: metadataContext)
  }()
  
  private var insertedObjectsWithUniqueIDs = [String: NSManagedObject]()
  private var storeContextSaveNotification: NSNotification?
  private var queuedChanges = [Change]()
  var conflictResolutionPolicy: String?
  var onCompletion: CompletionBlock?
  
  init(store: Store!) {
    self.store = store
  }
  
  // MARK: - Sync
  
  override func main() {
    do {
      try setup()
      try perform()
      print("COMPLETED SYNC ", storeContextSaveNotification)
      onCompletion?(saveNotification: storeContextSaveNotification, syncError: nil)
    } catch {
      print("COMPLETED SYNC WITH ERROR ",error)
      onCompletion?(saveNotification: nil, syncError: error)
    }
  }
  
  func setup() throws {
    let zoneID = zone.zone.zoneID
    var zoneExists = false
    let fetchRecordZonesOperation = CKFetchRecordZonesOperation(recordZoneIDs: [zoneID])
    fetchRecordZonesOperation.fetchRecordZonesCompletionBlock = { recordZonesByID, error in
      guard let allRecordZonesByID = recordZonesByID where error == nil else {
        return
      }
      zoneExists = allRecordZonesByID[zoneID] != nil
    }
    let operationQueue = NSOperationQueue()
    operationQueue.addOperation(fetchRecordZonesOperation)
    operationQueue.waitUntilAllOperationsAreFinished()
    guard zoneExists == false else {
      return
    }
    try zone.createZone()
  }
  
  func storeContextDidSave(notification: NSNotification) {
    storeContextSaveNotification = notification
  }
  
  func perform() throws {
    do {
      try applyLocalChanges()
      if changeManager.hasChanges() == false {
        try applyServerChanges()
      }
      try backingStoreContext.saveIfHasChanges()
      try storeContext.saveIfHasChanges()
    } catch Error.ConflictsDetected(let conflictedRecordsWithChanges) {
      do {
        try resolveConflicts(conflictedRecordsWithChanges)
        try applyLocalChanges()
        if changeManager.hasChanges() == false {
          try applyServerChanges()
        }
        try backingStoreContext.saveIfHasChanges()
        try storeContext.saveIfHasChanges()
      }
    }
  }
  
  // MARK: - Local Changes
  
  func ckRecord(uniqueID: String, entity: NSEntityDescription, propertyValuesDictionary: [String: AnyObject], encodedMetadata: NSData?) -> CKRecord {
    var record: CKRecord?
    let recordZoneID = zone.zone.zoneID
    if let metadata = encodedMetadata {
      record = CKRecord.recordWithEncodedData(metadata)
    } else {
      let recordID = CKRecordID(recordName: uniqueID, zoneID: recordZoneID)
      record = CKRecord(recordType: entity.name!, recordID: recordID)
    }
    propertyValuesDictionary.forEach { (key, value) in
      guard value as! NSObject != NSNull() else {
        record?.setObject(nil, forKey: key)
        return
      }
      if let referenceManagedObject = value as? NSManagedObject {
        let referenceUniqueID = store.referenceObjectForObjectID(referenceManagedObject.objectID) as! String
        let referenceRecordID = CKRecordID(recordName: referenceUniqueID, zoneID: recordZoneID)
        let reference = CKReference(recordID: referenceRecordID, action: CKReferenceAction.DeleteSelf)
        record?.setObject(reference, forKey: key)
      } else {
        record?.setValue(value, forKey: key)
      }
    }
    return record!
  }
  
  func localChanges() throws -> (insertedOrUpdatedRecordsAndChanges: [(record: CKRecord, change: Change)], deletedCKRecordIDs: [CKRecordID]) {
    var insertedOrUpdatedRecordsAndChanges = [(record: CKRecord, change: Change)]()
    var deletedCKRecordIDs = [CKRecordID]()
    guard let localChanges = try changeManager.all() else {
      return (insertedOrUpdatedRecordsAndChanges: insertedOrUpdatedRecordsAndChanges, deletedCKRecordIDs: deletedCKRecordIDs)
    }
    try localChanges.forEach { change in
      if change.isDeletedType {
        let recordZoneID = zone.zone.zoneID
        let recordID = CKRecordID(recordName: change.uniqueID, zoneID: recordZoneID)
        deletedCKRecordIDs.append(recordID)
      } else {
        let entity = persistentStoreCoordinator.managedObjectModel.entitiesByName[change.entityName!]!
        let uniqueID = change.uniqueID
        let entityName = change.entityName!
        guard let backingObjectID = try backingStoreContext.objectIDForBackingObjectForEntity(entityName, uniqueID: uniqueID) else {
          return
        }
        guard let managedObject = try storeContext.objectWithBackingObjectID(backingObjectID) else {
          return
        }
        if let propertyValueDictionary = changeManager.changedPropertyValuesDictionaryForChange(change, changedObject: managedObject) {
          let encodedMetadata = try metadataManager.metadataWithUniqueID(change.uniqueID)?.data
          let record = ckRecord(change.uniqueID, entity: entity, propertyValuesDictionary: propertyValueDictionary, encodedMetadata: encodedMetadata)
          insertedOrUpdatedRecordsAndChanges.append((record: record, change: change))
        }
      }
    }
    
    return (insertedOrUpdatedRecordsAndChanges: insertedOrUpdatedRecordsAndChanges, deletedCKRecordIDs: deletedCKRecordIDs)
  }
  
  func applyLocalChanges() throws {
    let changes = try localChanges()
    var conflictedRecords = [CKRecord]()
    var insertedOrUpdatedCKRecordsAndChangesWithIDs = [CKRecordID: (record: CKRecord, change: Change)]()
    changes.insertedOrUpdatedRecordsAndChanges.forEach {
      insertedOrUpdatedCKRecordsAndChangesWithIDs[$0.record.recordID] = $0
    }
    let insertedOrUpdatedCKRecords = changes.insertedOrUpdatedRecordsAndChanges.map { $0.record }
    let deletedCKRecordIDs = changes.deletedCKRecordIDs
    let modifyRecordsOperation = CKModifyRecordsOperation(recordsToSave: insertedOrUpdatedCKRecords, recordIDsToDelete: deletedCKRecordIDs)
    modifyRecordsOperation.perRecordCompletionBlock = { (record, error) in
      if let record = record, let error = error where error.code == CKErrorCode.ServerRecordChanged.rawValue {
        conflictedRecords.append(record)
      }
    }
    operationQueue.addOperation(modifyRecordsOperation)
    operationQueue.waitUntilAllOperationsAreFinished()
    try changes.insertedOrUpdatedRecordsAndChanges.forEach {
      try metadataManager.setMetadata(forRecord: $0.record)
    }
    guard conflictedRecords.count == 0 else {
      var conflictedRecordsWithChanges = [(record: CKRecord, change: Change)]()
      conflictedRecords.forEach { record in
        guard let recordWithChange = insertedOrUpdatedCKRecordsAndChangesWithIDs[record.recordID] else {
          return
        }
        conflictedRecordsWithChanges.append(recordWithChange)
      }
      throw Error.ConflictsDetected(conflictedRecordsWithChanges: conflictedRecordsWithChanges)
    }
    let changeObjects = changes.insertedOrUpdatedRecordsAndChanges.map { $0.change }
    changeManager.remove(changeObjects)
  }
  
  // MARK: - Conflict Resolution
  
  func resolveConflicts(conflictedRecordsWithChanges: [(record: CKRecord, change: Change)]) throws {
    let recordIDs = conflictedRecordsWithChanges.map { $0.record.recordID }
    var conflictedRecordsByRecordIDsAndChanges = [CKRecordID: (record: CKRecord, change: Change)]()
    conflictedRecordsWithChanges.forEach { (record, change) in
      conflictedRecordsByRecordIDsAndChanges[record.recordID] = (record: record, change: change)
    }
    var fetchedRecordsByRecordIDs: [CKRecordID: CKRecord]?
    let fetchRecordsOperation = CKFetchRecordsOperation(recordIDs: recordIDs)
    fetchRecordsOperation.fetchRecordsCompletionBlock = { (recordsByRecordIDs, error) in
      guard error == nil else {
        return
      }
      fetchedRecordsByRecordIDs = recordsByRecordIDs
    }
    operationQueue.addOperation(fetchRecordsOperation)
    operationQueue.waitUntilAllOperationsAreFinished()
    guard let recordsByRecordIDs = fetchedRecordsByRecordIDs else {
      throw Error.ConflictedRecordsFetchFailed
    }
    try recordsByRecordIDs.forEach { (recordID, record) in
      try metadataManager.setMetadata(forRecord: record)
      let serverWins = {
        try self.insertOrUpdateObject(fromRecord: record)
        let conflictedRecordAndChange = conflictedRecordsByRecordIDsAndChanges[recordID]!
        let change = conflictedRecordAndChange.change
        self.changeManager.remove([change])
      }
      if let conflictResolutionBlock = conflictResolutionBlock {
        let info: ConflictResolutionInfo
        let conflictedRecordAndChange = conflictedRecordsByRecordIDsAndChanges[recordID]!
        let uniqueID = record.recordID.recordName
        if let allUpdatedTypeChanges = try changeManager.allUpdatedType(forUniqueID: uniqueID) {
          var allChangedProperties = Set<String>()
          allUpdatedTypeChanges.forEach { change in
            let separatedProperties = change.separatedProperties!
            allChangedProperties.unionInPlace(separatedProperties)
          }
          info.pendingLocallyChangedProperties = Array(allChangedProperties)
          let localRecord = conflictedRecordAndChange.record
          let serverRecord = record
          let localRecordValueDictionary = try recordValueDictionaryForConflictResolution(localRecord)
          let serverRecordValueDictionary = try recordValueDictionaryForConflictResolution(serverRecord)
          info.localValues = localRecordValueDictionary
          info.serverValues = serverRecordValueDictionary
          let conflictResolutionReturnedInfo = conflictResolutionBlock(conflictResolutionInfo: info)
          changeManager.remove(allUpdatedTypeChanges)
          let change = changeManager.new(uniqueID, type: Change.ChangeType.Updated, entityName: record.recordType)
          change.properties = conflictResolutionReturnedInfo.pendingLocallyChangedProperties.joinWithSeparator(Change.propertySeparator)
        }
      }
      if let conflictResolutionPolicy = conflictResolutionPolicy {
        if conflictResolutionPolicy == SMServerObjectWinsConflictResolutionPolicy {
          try serverWins()
        }
      } else {
        try serverWins()
      }
    }
  }
  
  func recordValueDictionaryForConflictResolution(record: CKRecord) throws -> [String: AnyObject] {
    let entityName = record.recordType
    let entity = persistentStoreCoordinator.managedObjectModel.entitiesByName[entityName]!
    let toOneRelationshipKeys = entity.toOneRelationshipNames
    let toOneRelationshipsByName = entity.toOneRelationshipsByName
    let propertyKeys = Array(entity.attributesByName.keys) + toOneRelationshipKeys
    var valueDictionary = record.dictionaryWithValuesForKeys(propertyKeys)
    try toOneRelationshipKeys.forEach { key in
      guard let reference = valueDictionary[key] as? CKReference else {
        return
      }
      let uniqueReferenceID = reference.recordID.recordName
      let destinationEntityName = toOneRelationshipsByName[key]!.destinationEntity!.name!
      let relationshipObjectID = try storeContext.objectIDForBackingObjectForEntity(uniqueReferenceID, uniqueID: destinationEntityName)
      valueDictionary[key] = relationshipObjectID
    }
    return valueDictionary
  }
  
  // MARK: - Server Changes
  
  func insertOrUpdateObject(fromRecord record: CKRecord) throws {
    try storeContext.performBlockAndWait {
      let entityName = record.recordType
      let uniqueID = record.recordID.recordName
      var managedObject: NSManagedObject!
      if let objectID = try self.backingStoreContext.objectIDForBackingObjectForEntity(entityName, uniqueID: uniqueID) {
        managedObject = try self.storeContext.objectWithBackingObjectID(objectID)
      }
      if managedObject == nil {
        managedObject = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: self.storeContext)
        self.insertedObjectsWithUniqueIDs[uniqueID] = managedObject
        self.store.setUniqueIDForInsertedObject(uniqueID, insertedObject: managedObject)
        try self.storeContext.obtainPermanentIDsForObjects([managedObject])
      }
      let entity = managedObject.entity
      let attributeKeys = Array(entity.attributesByName.keys)
      let attributeValues = record.dictionaryWithValuesForKeys(attributeKeys)
      managedObject.setValuesForKeysWithDictionary(attributeValues)
      let relationshipReferences = record.dictionaryWithValuesForKeys(entity.toOneRelationshipNames)
      try relationshipReferences.forEach { (name,reference) in
        guard reference as! NSObject != NSNull() else {
          return
        }
        guard let referenceDestinationEntity = entity.relationshipsByName[name]!.destinationEntity else {
          return
        }
        let relationshipUniqueID = reference.recordID.recordName
        if let relationshipManagedObject = self.insertedObjectsWithUniqueIDs[relationshipUniqueID] {
          managedObject.setValue(relationshipManagedObject, forKey: name)
        } else if let relationshipBackingObjectID = try self.backingStoreContext.objectIDForBackingObjectForEntity(referenceDestinationEntity.name!, uniqueID: relationshipUniqueID) {
          guard let relationshipManagedObject = try self.storeContext.objectWithBackingObjectID(relationshipBackingObjectID) else {
            return
          }
          managedObject.setValue(relationshipManagedObject, forKey: name)
        }
      }
    }
  }
  
  func serverChanges() -> (insertedOrUpdatedCKRecords: [CKRecord],deletedRecordIDs: [CKRecordID]) {
    let token = Token.sharedToken.rawToken()
    let recordZoneID = zone.zone.zoneID
    let fetchRecordChangesOperation = CKFetchRecordChangesOperation(recordZoneID: recordZoneID, previousServerChangeToken: token)
    var insertedOrUpdatedCKRecords: [CKRecord] = [CKRecord]()
    var deletedCKRecordIDs: [CKRecordID] = [CKRecordID]()
    fetchRecordChangesOperation.fetchRecordChangesCompletionBlock = { changeToken,clientChangeToken,operationError in
      guard let changeToken = changeToken where operationError == nil else {
        return
      }
      Token.sharedToken.save(changeToken)
      Token.sharedToken.commit()
    }
    fetchRecordChangesOperation.recordChangedBlock = { record in
      insertedOrUpdatedCKRecords.append(record)
    }
    fetchRecordChangesOperation.recordWithIDWasDeletedBlock = { recordID in
      deletedCKRecordIDs.append(recordID)
    }
    operationQueue.addOperation(fetchRecordChangesOperation)
    operationQueue.waitUntilAllOperationsAreFinished()
    return (insertedOrUpdatedCKRecords,deletedCKRecordIDs)
  }
  
  func applyServerChanges() throws {
    let changes = serverChanges()
    let deletedObjectUniqueIDs = changes.deletedRecordIDs.map { $0.recordName }
    let entityNames = Array(persistentStoreCoordinator.managedObjectModel.entitiesByName.keys)
    try storeContext.deleteObjectsWithUniqueIDs(deletedObjectUniqueIDs, inEntities: entityNames)
    try changes.insertedOrUpdatedCKRecords.forEach { record in
      try insertOrUpdateObject(fromRecord: record)
    }
    try metadataManager.deleteMetadataForUniqueIDs(deletedObjectUniqueIDs)
    try changes.insertedOrUpdatedCKRecords.forEach {
      try metadataManager.setMetadata(forRecord: $0)
    }
  }
}