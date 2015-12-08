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
  static let errorDomain = "com.seam.error.sync.errorDomain"
  enum Error: ErrorType {
    case LocalChangesFetchError
    case ConflictsDetected(conflictedRecords: [CKRecord])
    case ConflictedRecordsFetchFailed
    case UnknownError
  }
  private lazy var operationQueue: NSOperationQueue = {
    let operationQueue = NSOperationQueue()
    operationQueue.maxConcurrentOperationCount = 1
    return operationQueue
  }()
  var store: Store!
  private var backingPersistentStoreCoordinator: NSPersistentStoreCoordinator {
    return store.backingPSC!
  }
  private var persistentStoreCoordinator: NSPersistentStoreCoordinator {
    return store.persistentStoreCoordinator!
  }
  private lazy var backingStoreContext: NSManagedObjectContext = {
    let backingStoreContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    backingStoreContext.persistentStoreCoordinator = self.backingPersistentStoreCoordinator
    return backingStoreContext
  }()
  private lazy var storeContext: NSManagedObjectContext = {
    let storeContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    storeContext.persistentStoreCoordinator = self.persistentStoreCoordinator
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
    try setupZone()
  }
  
  func setupZone() throws {
    try Zone.createZone(operationQueue)
    try Zone.createSubscription(operationQueue)
  }
  
  func storeContextDidSave(notification: NSNotification) {
    storeContextSaveNotification = notification
  }
  
  func perform() throws {
    do {
      try applyLocalChanges()
      try applyServerChanges()
      try backingStoreContext.save()
      try storeContext.save()
    } catch Error.ConflictsDetected(conflictedRecords: let conflictedRecords) {
      do {
        try resolveConflicts(conflictedRecords: conflictedRecords)
        try applyLocalChanges()
        try applyServerChanges()
        try backingStoreContext.save()
        try storeContext.save()
      }
    }
  }
  
  // MARK: - Local Changes
  
  func localChanges() throws -> (insertedOrUpdatedRecordsAndChanges: [(record: CKRecord, change: Change)], deletedCKRecordIDs: [CKRecordID]) {
    var insertedOrUpdatedRecordsAndChanges = [(record: CKRecord, change: Change)]()
    var deletedCKRecordIDs = [CKRecordID]()
    guard let localChanges = try changeManager.dequeueAll() else {
      return (insertedOrUpdatedRecordsAndChanges: insertedOrUpdatedRecordsAndChanges, deletedCKRecordIDs: deletedCKRecordIDs)
    }
    queuedChanges = localChanges
    try queuedChanges.forEach { change in
      if change.isDeletedType {
        let recordID = CKRecordID(uniqueID: change.uniqueID)
        deletedCKRecordIDs.append(recordID)
      } else {
        let entity = persistentStoreCoordinator.managedObjectModel.entitiesByName[change.entityName!]!
        if let propertyValueDictionary = try changeManager.changedPropertyValuesDictionaryForChange(change) {
          let encodedMetadata = try metadataManager.metadataWithUniqueID(change.uniqueID)?.data
          let record = CKRecord.record(change.uniqueID, entity: entity, propertyValuesDictionary: propertyValueDictionary, encodedMetadata: encodedMetadata)
          insertedOrUpdatedRecordsAndChanges.append((record: record, change: change))
        }
      }
    }
    
    return (insertedOrUpdatedRecordsAndChanges: insertedOrUpdatedRecordsAndChanges, deletedCKRecordIDs: deletedCKRecordIDs)
  }
  
  func applyLocalChanges() throws {
    let changes = try localChanges()
    var conflictsDetected = false
    var insertedOrUpdatedCKRecordsAndChangesWithIDs = [CKRecordID: (record: CKRecord, change: Change)]()
    changes.insertedOrUpdatedRecordsAndChanges.forEach {
      insertedOrUpdatedCKRecordsAndChangesWithIDs[$0.record.recordID] = $0
    }
    let insertedOrUpdatedCKRecords = changes.insertedOrUpdatedRecordsAndChanges.map { $0.record }
    let deletedCKRecordIDs = changes.deletedCKRecordIDs
    let modifyRecordsOperation = CKModifyRecordsOperation(recordsToSave: insertedOrUpdatedCKRecords, recordIDsToDelete: deletedCKRecordIDs)
    modifyRecordsOperation.perRecordCompletionBlock = { (record, error) in
      if let error = error where error.code == CKErrorCode.ServerRecordChanged.rawValue {
        conflictsDetected = true
      }
    }
    modifyRecordsOperation.modifyRecordsCompletionBlock = { (savedRecords, deletedRecordIDs, error) in
      if let error = error where error.code == CKErrorCode.PartialFailure.rawValue {
//        if let errorDict = error.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecordID: NSError] {
//          
//        }
      }
    }
    operationQueue.addOperation(modifyRecordsOperation)
    operationQueue.waitUntilAllOperationsAreFinished()
    try changes.insertedOrUpdatedRecordsAndChanges.forEach {
      let record = $0.record
      let uniqueID = record.recordID.recordName
      let entityName = record.recordType
      let encodedSystemFields = record.encodedSystemFields
      try metadataManager.setMetadataForUniqueID(uniqueID, entityName: entityName, data: encodedSystemFields)
    }
    guard conflictsDetected == false else {
      try changeManager.enqueueBackAllDequeuedChanges()
      throw Error.ConflictsDetected(conflictedRecords: insertedOrUpdatedCKRecords)
    }
    try changeManager.removeAllQueued()
  }
  
  // MARK: - Conflict Resolution
  
  func resolveConflicts(conflictedRecords conflictedRecords: [CKRecord]) throws {
    let recordIDs = conflictedRecords.map { $0.recordID }
    var conflictedRecordsByRecordIDs = [CKRecordID:CKRecord]()
    conflictedRecords.forEach { record in
      conflictedRecordsByRecordIDs[record.recordID] = record
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
    guard fetchedRecordsByRecordIDs != nil else {
      throw Error.ConflictedRecordsFetchFailed
    }
    guard let recordsByRecordIDs = fetchedRecordsByRecordIDs else {
      return
    }
    try recordsByRecordIDs.forEach { (recordID, record) in
      if let conflictResolutionPolicy = conflictResolutionPolicy {
        if conflictResolutionPolicy == SMServerObjectWinsConflictResolutionPolicy {
//          try storeContext.createOrUpdateObject(fromRecord: record)
        } else if conflictResolutionPolicy == SMClientObjectWinsConflictResolutionPolicy {
          
        } else if conflictResolutionPolicy == SMKeepBothObjectsConflictResolutionPolicy {
          
        }
      }
    }
  }
  
  func recordValueDictionaryForConflictResolution(entity: NSEntityDescription, inout valueDictionary: [String: AnyObject]) throws {
    let toOneRelationshipKeys = entity.toOneRelationshipNames
    let toOneRelationshipsByName = entity.toOneRelationshipsByName
    try toOneRelationshipKeys.forEach { key in
      guard let reference = valueDictionary[key] as? CKReference else {
        return
      }
      let uniqueReferenceID = reference.recordID.recordName
      let destinationEntityName = toOneRelationshipsByName[key]!.destinationEntity!.name!
      let relationshipObjectID = try storeContext.objectIDWithUniqueID(uniqueReferenceID, inEntity: destinationEntityName)
      valueDictionary[key] = relationshipObjectID
    }
  }
  
  // MARK: - Server Changes
  
  func serverChanges() -> (insertedOrUpdatedCKRecords: [CKRecord],deletedRecordIDs: [CKRecordID]) {
    let token = Token.sharedToken.rawToken()
    let fetchRecordChangesOperation = CKFetchRecordChangesOperation(recordZoneID: Zone.zoneID, previousServerChangeToken: token)
    var insertedOrUpdatedCKRecords: [CKRecord] = [CKRecord]()
    var deletedCKRecordIDs: [CKRecordID] = [CKRecordID]()
    fetchRecordChangesOperation.fetchRecordChangesCompletionBlock = { changeToken,clientChangeToken,operationError in
      if let changeToken = changeToken where operationError == nil {
        Token.sharedToken.save(changeToken)
        Token.sharedToken.commit()
      }
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
      if let objectID = try backingStoreContext.objectIDForBackingObjectForEntity(record.recordType, uniqueID: record.recordID.recordName) {
        try storeContext.updateObject(fromRecord: record, objectID: objectID, backingContext: backingStoreContext)
      } else {
        try storeContext.insertObject(fromRecord: record, backingContext: backingStoreContext)
      }
    }
    try changes.insertedOrUpdatedCKRecords.forEach {
      let uniqueID = $0.recordID.recordName
      let entityName = $0.recordType
      let encodedSystemFields = $0.encodedSystemFields
      try metadataManager.setMetadataForUniqueID(uniqueID, entityName: entityName, data: encodedSystemFields)
    }
  }
}