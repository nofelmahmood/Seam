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

extension NSManagedObjectContext {
  
  public func performSyncAndMerge(completionBlock: (()->())?) {
    var store: Store?
    persistentStoreCoordinator?.persistentStores.forEach { persistentStore in
      if let persistentStore = persistentStore as? Store {
        store = persistentStore
      }
    }
    if let store = store {
      store.performContextBasedSync { (insertedOrUpdatedObjectIDs, deletedObjectIDs, successful) in
        if successful {
          self.performBlock {
            insertedOrUpdatedObjectIDs?.forEach { objectID in
              let object = self.objectWithID(objectID)
              self.refreshObject(object, mergeChanges: false)
            }
            deletedObjectIDs?.forEach { objectID in
              let object = self.objectWithID(objectID)
              self.deleteObject(object)
            }
            completionBlock?()
          }
        } else {
          completionBlock?()
        }
      }
    } else {
      completionBlock?()
    }
  }
  
  func objectWithUniqueID(id: String, inEntity entityName: String) throws -> NSManagedObject? {
    let fetchRequest = NSFetchRequest(entityName: entityName)
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: id)
    return try executeFetchRequest(fetchRequest).first as? NSManagedObject
  }
  
  func newObject(uniqueID: String, encodedValues: NSData?, inEntity entityName: String) -> NSManagedObject {
    let managedObject = NSEntityDescription.insertNewObjectForEntityForName(entityName, inManagedObjectContext: self)
    managedObject.setValue(uniqueID, forKey: UniqueID.name)
    managedObject.setValue(encodedValues, forKey: EncodedValues.name)
    return managedObject
  }
  
  func createOrUpdateObject(fromRecord record: CKRecord, inEntity entity: NSEntityDescription) throws -> NSManagedObject  {
    let uniqueID = record.recordID.recordName
    var managedObject: NSManagedObject! = try objectWithUniqueID(uniqueID, inEntity: record.recordType)
    if managedObject == nil {
      managedObject = newObject(uniqueID, encodedValues: record.encodedSystemFields, inEntity: record.recordType)
    }
    managedObject.setValue(record.encodedSystemFields, forKey: EncodedValues.name)
    let attributeValues = record.dictionaryWithValuesForKeys(entity.attributeNames)
    var assetValues = record.dictionaryWithValuesForKeys(entity.assetAttributeNames)
    assetValues.forEach { (key, value) in
      guard value as! NSObject != NSNull() else {
        assetValues[key] = nil
        return
      }
      let asset = value as! CKAsset
      assetValues[key] = asset.fileURL
    }
    managedObject.setValuesForKeysWithDictionary(attributeValues)
    managedObject.setValuesForKeysWithDictionary(assetValues)
    let relationshipReferences = record.dictionaryWithValuesForKeys(entity.toOneRelationshipNames)
    try relationshipReferences.forEach { (name,reference) in
      guard reference as! NSObject != NSNull() else {
        return
      }
      if let referenceDestinationEntityName = entity.relationshipsByName[name]!.destinationEntity?.name {
        let fetchRequest = NSFetchRequest(entityName: referenceDestinationEntityName)
        fetchRequest.predicate = NSPredicate(equalsToUniqueID: reference.recordID.recordName)
        if let relationshipManagedObject = try executeFetchRequest(fetchRequest).first as? NSManagedObject {
          managedObject.setValue(relationshipManagedObject, forKey: name)
        }
      }
    }
    return managedObject
  }
  
  func createOrUpdateObjects(fromRecords records: [CKRecord], inEntities entitiesByName: [String: NSEntityDescription]) throws -> (insertedObjectIDs: [NSManagedObjectID], updatedObjectIDs: [NSManagedObjectID]) {
    var insertedObjectIDs = [NSManagedObjectID]()
    var updatedObjectIDs = [NSManagedObjectID]()
    try records.forEach { record in
      let entity = entitiesByName[record.recordType]!
      let managedObject = try createOrUpdateObject(fromRecord: record, inEntity: entity)
      if managedObject.inserted {
        insertedObjectIDs.append(managedObject.objectID)
      } else if managedObject.updated {
        updatedObjectIDs.append(managedObject.objectID)
      }
    }
    return (insertedObjectIDs, updatedObjectIDs)
  }
  
  func deleteObjectsWithUniqueIDs(var ids: [String], inEntities entityNames: [String]) throws -> [(uniqueID: String, entityName: String)] {
    var deletedObjectsInfo = [(uniqueID: String, entityName: String)]()
    try entityNames.forEach { entityName in
     try ids.forEach { uniqueID in
        let fetchRequest = NSFetchRequest(entityName: entityName)
        fetchRequest.predicate = NSPredicate(equalsToUniqueID: uniqueID)
        fetchRequest.includesPropertyValues = false
        if let managedObject = try executeFetchRequest(fetchRequest).first as? NSManagedObject {
          deleteObject(managedObject)
          let info = (uniqueID, entityName)
          deletedObjectsInfo.append(info)
          let index = ids.indexOf(uniqueID)!
          ids.removeAtIndex(index)
        }
      }
    }
    return deletedObjectsInfo
  }
}