//    Change.swift
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

class Change: NSManagedObject {
  @NSManaged var entityName: String?
  @NSManaged var type: NSNumber?
  @NSManaged var properties: String?
  @NSManaged var queued: NSNumber?
  @NSManaged var creationDate: NSDate
  
  var separatedProperties: [String]? {
    return properties?.componentsSeparatedByString(Change.propertySeparator)
  }
  var isDeletedType: Bool {
    return type == ChangeType.Deleted
  }
  var isInsertedType: Bool {
    return type == ChangeType.Inserted
  }
  var isUpdatedType: Bool {
    return type == ChangeType.Updated
  }
  var isQueued: Bool {
    return queued!.boolValue
  }
  
  func addProperties(props: [String]) {
    guard let separatedProperties = separatedProperties else {
      properties = props.joinWithSeparator(Change.propertySeparator)
      return
    }
    let union = Set(separatedProperties).union(Set(props))
    properties = union.joinWithSeparator(Change.propertySeparator)
  }
  
  struct ChangeType {
    static let Inserted = NSNumber(int: 0)
    static let Updated = NSNumber(int: 1)
    static let Deleted = NSNumber(int: 2)
  }
  static let propertySeparator = ","
  
  // MARK: - Entity
  
  struct Entity {
    static let name = "Seam_Change"
    static var entityDescription: NSEntityDescription {
      let entityDescription = NSEntityDescription()
      entityDescription.name = name
      entityDescription.properties.append(UniqueID.attributeDescription)
      entityDescription.properties.append(Properties.ChangeType.attributeDescription)
      entityDescription.properties.append(Properties.EntityName.attributeDescription)
      entityDescription.properties.append(Properties.ChangedProperties.attributeDescription)
      entityDescription.properties.append(Properties.ChangeQueued.attributeDescription)
      entityDescription.properties.append(Properties.CreationDate.attributeDescription)
      entityDescription.managedObjectClassName = "Seam.Change"
      return entityDescription
    }
  }
  
  // MARK: Properties

  struct Properties {
    struct ChangeType {
      static let name = "type"
      static var attributeDescription: NSAttributeDescription {
        let attributeDescription = NSAttributeDescription()
        attributeDescription.name = name
        attributeDescription.attributeType = .Integer16AttributeType
        attributeDescription.optional = false
        attributeDescription.indexed = true
        return attributeDescription
      }
    }
    struct EntityName {
      static let name = "entityName"
      static var attributeDescription: NSAttributeDescription {
        let attributeDescription = NSAttributeDescription()
        attributeDescription.name = name
        attributeDescription.attributeType = .StringAttributeType
        attributeDescription.optional = false
        attributeDescription.indexed = true
        return attributeDescription
      }
    }
    struct ChangedProperties {
      static let name = "properties"
      static var attributeDescription: NSAttributeDescription {
        let attributeDescription = NSAttributeDescription()
        attributeDescription.name = name
        attributeDescription.attributeType = .StringAttributeType
        attributeDescription.optional = true
        return attributeDescription
      }
    }
    struct ChangeQueued {
      static let name = "queued"
      static var attributeDescription: NSAttributeDescription {
        let attributeDescription = NSAttributeDescription()
        attributeDescription.name = name
        attributeDescription.attributeType = .BooleanAttributeType
        attributeDescription.optional = false
        attributeDescription.defaultValue = NSNumber(bool: false)
        return attributeDescription
      }
    }
    struct CreationDate {
      static let name = "creationDate"
      static var attributeDescription: NSAttributeDescription {
        let attributeDescription = NSAttributeDescription()
        attributeDescription.name = name
        attributeDescription.attributeType = .DateAttributeType
        attributeDescription.optional = false
        return attributeDescription
      }
    }
  }
  
  // MARK: - Manager
  
  class Manager {
    private var changeContext: NSManagedObjectContext!
    private var mainContext: NSManagedObjectContext?
    
    init(changeContext: NSManagedObjectContext) {
      self.changeContext = changeContext
    }
    
    init(changeContext: NSManagedObjectContext, mainContext: NSManagedObjectContext) {
      self.changeContext = changeContext
      self.mainContext = mainContext
    }
    
    func hasChanges() -> Bool {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      var error: NSError?
      return changeContext.countForFetchRequest(fetchRequest, error: &error) > 0 ? true: false
    }
    
    func new(uniqueID: String,type: NSNumber, entityName: String) -> Change {
      let change = NSEntityDescription.insertNewObjectForEntityForName(Entity.name, inManagedObjectContext: changeContext) as! Change
      change.uniqueID = uniqueID
      change.type = type
      change.entityName = entityName
      change.creationDate = NSDate()
      return change
    }
    
//    func new(uniqueID: String,changedObject: NSManagedObject) throws -> Change? {
//      if changedObject.deleted {
//        if let change = try changeFor(uniqueID) {
//          guard change.isInsertedType == false else {
//            changeContext.deleteObject(change)
//            return nil
//          }
//        }
//        new(uniqueID,type: ChangeType.Deleted,
//          entityName: changedObject.entity.name!)
//      } else if changedObject.inserted {
//        new(uniqueID,type: ChangeType.Inserted,
//          entityName: changedObject.entity.name!)
//      } else if changedObject.updated {
//        if let change =  try changeFor(uniqueID)  {
//          guard change.isUpdatedType else {
//            return nil
//          }
//          change.addProperties(changedObject.changedValueKeys)
//          return change
//        }  else {
//          let change = new(uniqueID, type: Change.ChangeType.Updated, entityName: changedObject.entity.name!)
//          change.addProperties(changedObject.changedValueKeys)
//          return change
//        }
//      }
//      return nil
//    }
//    
    private func changeFor(uniqueID: String) throws -> Change? {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(changeIsNotQueuedAndEqualsToID: uniqueID)
      return try changeContext.executeFetchRequest(fetchRequest).first as? Change
    }
    
    func dequeueAll() throws -> [Change]? {
      let batchUpdateRequest = NSBatchUpdateRequest(entityName: Entity.name)
      batchUpdateRequest.propertiesToUpdate = [Properties.ChangeQueued.name: NSNumber(bool: true)]
      try changeContext.executeRequest(batchUpdateRequest)
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(changeIsQueued: true)
      let dateSortDescriptor = NSSortDescriptor(key: Properties.CreationDate.name, ascending: true)
      fetchRequest.sortDescriptors = [dateSortDescriptor]
      return try changeContext.executeFetchRequest(fetchRequest) as? [Change]
    }
    
    func removeAllQueued() throws {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(changeIsQueued: true)
      let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
      try changeContext.executeRequest(batchDeleteRequest)
    }
    
    func enqueueBackAllDequeuedChanges() throws {
      let batchUpdateRequest = NSBatchUpdateRequest(entityName: Entity.name)
      batchUpdateRequest.predicate = NSPredicate(changeIsQueued: true)
      batchUpdateRequest.propertiesToUpdate = [Properties.ChangeQueued.name: NSNumber(bool: false)]
      try changeContext.executeRequest(batchUpdateRequest)
    }
    
    func objectForChange(change: Change) throws -> NSManagedObject? {
      let fetchRequest = NSFetchRequest(entityName: change.entityName!)
      fetchRequest.predicate = NSPredicate(equalsToUniqueID: change.uniqueID)
      return try mainContext?.executeFetchRequest(fetchRequest).first as? NSManagedObject
    }
    
    func changedPropertyValuesDictionaryForChange(change: Change) throws -> [String: AnyObject]? {
      guard let changedObject = try objectForChange(change) else {
        return nil
      }
      if let changedProperties = change.separatedProperties where change.isUpdatedType {
        return changedObject.dictionaryWithValuesForKeys(changedProperties)
      } else  {
        let keys = changedObject.entity.attributeNames + changedObject.entity.toOneRelationshipNames + changedObject.entity.assetAttributeNames + changedObject.entity.locationAttributeNames
        return changedObject.dictionaryWithValuesForKeys(keys)
      }
    }
  }
}
