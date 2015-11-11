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

class Sync: NSOperation {
  static let errorDomain = "com.seam.error.sync.errorDomain"
  enum Error: ErrorType {
    case LocalChangesFetchError
    case ConflictsDetected(conflictedRecords: [CKRecord])
    case UnknownError
  }
  private lazy var operationQueue: NSOperationQueue = {
    let operationQueue = NSOperationQueue()
    operationQueue.maxConcurrentOperationCount = 1
    return operationQueue
  }()
  private var backingPersistentStoreCoordinator: NSPersistentStoreCoordinator!
  private var persistentStoreCoordinator: NSPersistentStoreCoordinator!
  private var context: NSManagedObjectContext!
  private var changeManager: Change.Manager!
  var syncCompletionBlock: ((syncError: ErrorType?) -> ())?
  
  init(backingPersistentStoreCoordinator: NSPersistentStoreCoordinator, persistentStoreCoordinator: NSPersistentStoreCoordinator) {
    self.persistentStoreCoordinator = persistentStoreCoordinator
    self.backingPersistentStoreCoordinator = backingPersistentStoreCoordinator
  }
  
  // MARK: - Sync
  override func main() {
    context = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    context.persistentStoreCoordinator = backingPersistentStoreCoordinator
    do {
      try self.perform()
      syncCompletionBlock?(syncError: nil)
    } catch {
      syncCompletionBlock?(syncError: error)
    }
  }
  
  func perform() throws {
    do {
      try applyLocalChanges()
      try applyServerChanges()
    } catch Error.ConflictsDetected(conflictedRecords: let conflictedRecords) {
      resolveConflicts(conflictedRecords: conflictedRecords)
      do {
        try applyLocalChanges()
        try applyServerChanges()
      }
    }
  }
  
  // MARK: - Local Changes
  
  func localChanges() throws -> (insertedOrUpdatedCKRecords: [CKRecord], deletedCKRecordIDs: [CKRecordID]) {
    var insertedOrUpdatedCKRecords = [CKRecord]()
    var deletedCKRecordIDs = [CKRecordID]()
    if let localChanges = try changeManager.dequeueAll() {
      localChanges.forEach { change in
        if change.isDeletedType {
          let recordID = CKRecordID(change: change)
          deletedCKRecordIDs.append(recordID)
        } else {
          if let record = CKRecord.recordWithChange(change) {
            insertedOrUpdatedCKRecords.append(record)
          }
        }
      }
    }
    return (insertedOrUpdatedCKRecords: insertedOrUpdatedCKRecords, deletedCKRecordIDs: deletedCKRecordIDs)
  }
  
  func applyLocalChanges() throws {
    let changes = try localChanges()
    var recordsWithConflict = [CKRecord]()
    var allSavedRecords = [CKRecord]()
    let modifyRecordsOperation = CKModifyRecordsOperation(recordsToSave: changes.insertedOrUpdatedCKRecords, recordIDsToDelete: changes.deletedCKRecordIDs)
    modifyRecordsOperation.perRecordCompletionBlock = ({(record, error)->Void in
      if let error = error {
        if error.code == CKErrorCode.ServerRecordChanged.rawValue {
          if let record = record {
            recordsWithConflict.append(record)
          }
        }
      }
    })
    modifyRecordsOperation.modifyRecordsCompletionBlock = ({(savedRecords,deletedRecordIDs,error) -> Void in
      if let savedRecords = savedRecords {
        allSavedRecords.appendContentsOf(savedRecords)
      }
    })
    operationQueue.addOperation(modifyRecordsOperation)
    operationQueue.waitUntilAllOperationsAreFinished()
    guard recordsWithConflict.count == 0 else {
      throw Error.ConflictsDetected(conflictedRecords: recordsWithConflict)
    }
    try allSavedRecords.forEach { record in
      let fetchRequest = NSFetchRequest(entityName: record.recordType)
      fetchRequest.predicate = NSPredicate(equalsToUniqueID: record.recordID.recordName)
      if let managedObject = try context.executeFetchRequest(fetchRequest).first as? NSManagedObject {
        managedObject.setValue(record.encodedSystemFields, forKey: EncodedValues.name)
        try context.save()
      }
    }
  }
  
  // MARK: - Conflict Resolution
  
  func resolveConflicts(conflictedRecords conflictedRecords: [CKRecord]) {
    let recordIDs = conflictedRecords.map({ $0.recordID })
    var conflictedRecordsByRecordIDs = [CKRecordID: CKRecord]()
    conflictedRecords.forEach { record in
      conflictedRecordsByRecordIDs[record.recordID] = record
    }
    var fetchedRecordsByRecordIDs: [CKRecordID: CKRecord]?
    let fetchRecordsOperation = CKFetchRecordsOperation(recordIDs: recordIDs)
    fetchRecordsOperation.fetchRecordsCompletionBlock = ({ (recordsByRecordIDs, error) in
      guard error == nil else {
        return
      }
      fetchedRecordsByRecordIDs = recordsByRecordIDs
    })
    operationQueue.addOperation(fetchRecordsOperation)
    operationQueue.waitUntilAllOperationsAreFinished()
    var conflicts = [Conflict]()
    if let fetchedRecordsByRecordIDs = fetchedRecordsByRecordIDs {
      fetchedRecordsByRecordIDs.forEach { (recordID, record) in
        guard let conflictedRecord = conflictedRecordsByRecordIDs[recordID] else {
          return
        }
        let entity = persistentStoreCoordinator.managedObjectModel.entitiesByName[record.recordType]!
        let clientVersion = conflictedRecord.dictionaryWithValuesForKeys(conflictedRecord.allKeys())
        let serverVersion = record.dictionaryWithValuesForKeys(record.allKeys())
        let conflict = Conflict(serverRecordID: recordID,entity: entity, clientVersion: clientVersion, serverVersion: serverVersion)
        conflicts.append(conflict)
      }
    }
  }
  
  // MARK: - Server Changes
  
  func serverChanges() -> (insertedOrUpdatedCKRecords: [CKRecord],deletedRecordIDs: [CKRecordID]) {
    let token = Token.sharedToken.rawToken()
    let fetchRecordChangesOperation = CKFetchRecordChangesOperation(recordZoneID: Zone.zoneID, previousServerChangeToken: token)
    var insertedOrUpdatedCKRecords: [CKRecord] = [CKRecord]()
    var deletedCKRecordIDs: [CKRecordID] = [CKRecordID]()
    fetchRecordChangesOperation.fetchRecordChangesCompletionBlock = { changeToken,clientChangeToken,operationError in
      if operationError == nil {
        if let changeToken = changeToken {
          Token.sharedToken.save(changeToken)
          Token.sharedToken.commit()
        }
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
    let deletedObjectUniqueIDs = changes.deletedRecordIDs.map({ $0.recordName })
    try persistentStoreCoordinator.managedObjectModel.entities.forEach { entity in
      let fetchRequest = NSFetchRequest(entityName: entity.name!)
      fetchRequest.predicate = NSPredicate(inUniqueIDs: deletedObjectUniqueIDs)
      let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
      try context.executeRequest(batchDeleteRequest)
    }
    let insertedOrUpdatedCKRecords = changes.insertedOrUpdatedCKRecords
    try insertedOrUpdatedCKRecords.forEach { record in
      let fetchRequest = NSFetchRequest(entityName: record.recordType)
      fetchRequest.predicate = NSPredicate(equalsToUniqueID: record.recordID.recordName)
      var managedObject = try context.executeFetchRequest(fetchRequest).first as? NSManagedObject
      if managedObject == nil {
        managedObject = NSEntityDescription.insertNewObjectForEntityForName(record.recordType, inManagedObjectContext: context)
      }
      if let managedObject = managedObject {
        if let entity = persistentStoreCoordinator.managedObjectModel.entitiesByName[managedObject.entity.name!] {
          let attributeValues = record.dictionaryWithValuesForKeys(entity.attributeNames)
          managedObject.setValuesForKeysWithDictionary(attributeValues)
          managedObject.setValue(record.encodedSystemFields, forKey: EncodedValues.name)
          let relationshipReferences = record.dictionaryWithValuesForKeys(entity.toOneRelationshipNames) as! [String: CKReference]
          try relationshipReferences.forEach { (name,reference) in
            if let referenceDestinationEntityName = entity.relationshipsByName[name]!.destinationEntity?.name {
              let fetchRequest = NSFetchRequest(entityName: referenceDestinationEntityName)
              fetchRequest.predicate = NSPredicate(equalsToUniqueID: reference.recordID.recordName)
              if let relationshipManagedObject = try context.executeFetchRequest(fetchRequest).first as? NSManagedObject {
                managedObject.setValue(relationshipManagedObject, forKey: name)
              }
            }
          }
        }
        try context.save()
      }
    }
  }
}