//    NSManagedObjectContext.swift
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
import CoreData
import CloudKit

let ContextDoesNotAllowChangeRecording = "ContextDoesNotAllowChangeRecording"
let UniqueIDsForInsertedObjectsKey = "UniqueIDsForInsertedObjectsKey"

extension NSManagedObjectContext {
  var doesNotAllowChangeRecording: Bool {
    get {
      guard let optionValue = userInfo[ContextDoesNotAllowChangeRecording]?.boolValue else {
        return false
      }
      return optionValue
    } set {
      userInfo[ContextDoesNotAllowChangeRecording] = newValue
    }
  }
  
  func saveIfHasChanges() throws {
    if hasChanges {
      try save()
    }
  }
  
  func setUniqueIDForInsertedObject(uniqueID: String, object: NSManagedObject) {
    if var insertedObjectsWithUniqueIDs = userInfo[UniqueIDsForInsertedObjectsKey] as? [NSManagedObject: String] {
      insertedObjectsWithUniqueIDs[object] = uniqueID
      userInfo[UniqueIDsForInsertedObjectsKey] = insertedObjectsWithUniqueIDs
    } else {
      userInfo[UniqueIDsForInsertedObjectsKey] = [object: uniqueID]
    }
  }
  
  func uniqueIDForInsertedObject(object: NSManagedObject) -> String? {
    if let insertedObjectsWithUniqueIDs = userInfo[UniqueIDsForInsertedObjectsKey] as? [NSManagedObject: String] {
      return insertedObjectsWithUniqueIDs[object]
    }
    return nil
  }
  
  func performBlockAndWait(block: () throws -> ()) throws {
    var blockError: ErrorType?
    performBlockAndWait {
      do {
        try block()
      } catch {
        blockError = error
      }
    }
    if let blockError = blockError {
      throw blockError
    }
  }
  
  func objectWithUniqueID(id: String, inEntity entityName: String) throws -> NSManagedObject? {
    let fetchRequest = NSFetchRequest(entityName: entityName)
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: id)
    return try executeFetchRequest(fetchRequest).first as? NSManagedObject
  }
  
  func objectIDWithUniqueID(id: String, inEntity entityName: String) throws -> NSManagedObjectID? {
    let fetchRequest = NSFetchRequest(entityName: entityName)
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: id)
    fetchRequest.resultType = .ManagedObjectIDResultType
    return try executeFetchRequest(fetchRequest).first as? NSManagedObjectID
  }
  
  func objectWithBackingObjectID(backingObjectID: NSManagedObjectID) throws -> NSManagedObject? {
    let fetchRequest = NSFetchRequest(entityName: backingObjectID.entity.name!)
    fetchRequest.predicate = NSPredicate(backingObjectID: backingObjectID)
    return try executeFetchRequest(fetchRequest).first as? NSManagedObject
  }
  
  func newObject(uniqueID: String, encodedValues: NSData?, inEntity entityName: String) -> NSManagedObject {
    let managedObject = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: self)
    return managedObject
  }
  
  func objectIDForBackingObjectForEntity(entityName: String, uniqueID: String) throws -> NSManagedObjectID? {
    let fetchRequest = NSFetchRequest(entityName: entityName)
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: uniqueID)
    fetchRequest.resultType = .ManagedObjectIDResultType
    return try executeFetchRequest(fetchRequest).first as? NSManagedObjectID
  }
  
  func insertObject(fromRecord record: CKRecord, backingContext context: NSManagedObjectContext) throws {
    let entityName = record.recordType
    let uniqueID = record.recordID.recordName
    let entity = persistentStoreCoordinator!.managedObjectModel.entitiesByName[entityName]!
    let managedObject = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: self)
    context.setUniqueIDForInsertedObject(uniqueID, object: managedObject)
    let attributeValues = record.dictionaryWithValuesForKeys(entity.attributeNames)
    let assetValues = record.dictionaryWithValuesForKeys(entity.assetAttributeNames)
    let locationValues = record.dictionaryWithValuesForKeys(entity.locationAttributeNames)
    managedObject.setValuesForKeysWithDictionary(attributeValues)
    managedObject.setValuesForKeysWithDictionary(assetValues)
    managedObject.setValuesForKeysWithDictionary(locationValues)
    let relationshipReferences = record.dictionaryWithValuesForKeys(entity.toOneRelationshipNames)
    try relationshipReferences.forEach { (name,reference) in
      guard reference as! NSObject != NSNull() else {
        return
      }
      if let referenceDestinationEntityName = entity.relationshipsByName[name]!.destinationEntity?.name {
        let uniqueID = reference.recordID.recordName
        if let relationshipBackingObjectID = try context.objectIDForBackingObjectForEntity(referenceDestinationEntityName, uniqueID: uniqueID) {
          if let relationshipManagedObject = try objectWithBackingObjectID(relationshipBackingObjectID) {
            managedObject.setValue(relationshipManagedObject, forKey: name)
          }
        }
      }
    }
  }
  
  func updateObject(fromRecord record: CKRecord, objectID: NSManagedObjectID, backingContext context: NSManagedObjectContext) throws {
    guard let managedObject = try objectWithBackingObjectID(objectID) else {
      return
    }
    let entity = managedObject.entity
    let attributeValues = record.dictionaryWithValuesForKeys(entity.attributeNames)
    let assetValues = record.dictionaryWithValuesForKeys(entity.assetAttributeNames)
    let locationValues = record.dictionaryWithValuesForKeys(entity.locationAttributeNames)
    managedObject.setValuesForKeysWithDictionary(attributeValues)
    managedObject.setValuesForKeysWithDictionary(assetValues)
    managedObject.setValuesForKeysWithDictionary(locationValues)
    let relationshipReferences = record.dictionaryWithValuesForKeys(entity.toOneRelationshipNames)
    try relationshipReferences.forEach { (name, reference) in
      guard reference as! NSObject != NSNull() else {
        return
      }
      if let referenceDestinationEntityName = entity.relationshipsByName[name]!.destinationEntity?.name {
        let uniqueID = reference.recordID.recordName
        if let relationshipBackingObjectID = try context.objectIDForBackingObjectForEntity(referenceDestinationEntityName, uniqueID: uniqueID) {
          if let relationshipManagedObject = try objectWithBackingObjectID(relationshipBackingObjectID) {
            managedObject.setValue(relationshipManagedObject, forKey: name)
          }
        }
      }
    }
  }
  
  func deleteObjectsWithUniqueIDs(ids: [String], inEntities entityNames: [String]) throws {
    try entityNames.forEach { entityName in
     try ids.forEach { uniqueID in
        let fetchRequest = NSFetchRequest(entityName: entityName)
        fetchRequest.predicate = NSPredicate(equalsToUniqueID: uniqueID)
        fetchRequest.includesPropertyValues = false
        if let managedObject = try executeFetchRequest(fetchRequest).first as? NSManagedObject {
          deleteObject(managedObject)
        }
      }
    }
  }
}