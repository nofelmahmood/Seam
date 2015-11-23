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

class Change: NSManagedObject {
  @NSManaged var entityName: String?
  @NSManaged var type: NSNumber?
  @NSManaged var properties: String?
  @NSManaged var queued: NSNumber?
  
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
  var changedObject: NSManagedObject? {
    let context = managedObjectContext!
    let fetchRequest = NSFetchRequest(entityName: entityName!)
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: uniqueID)
    let object = try? context.executeFetchRequest(fetchRequest).first
    guard let managedObject = object as? NSManagedObject else {
      return nil
    }
    return managedObject
  }
  var changedPropertyValuesDictionary: [String: AnyObject]? {
    if let changedObject = changedObject {
      if let changedProperties = separatedProperties where isUpdatedType {
        return changedObject.dictionaryWithValuesForKeys(changedProperties)
      } else  {
        let keys = changedObject.entity.attributeNames + changedObject.entity.toOneRelationshipNames + changedObject.entity.assetAttributeNames
        var dictionary = changedObject.dictionaryWithValuesForKeys(keys)
        dictionary[EncodedValues.name] = nil
        dictionary[UniqueID.name] = nil
        return dictionary
      }
    }
    return nil
  }
  
  class func modifiedModel(fromModel model: NSManagedObjectModel) -> NSManagedObjectModel? {
    guard let model = model.copy() as? NSManagedObjectModel else {
      return nil
    }
    model.entities.forEach { entity in
      entity.properties.append(UniqueID.attributeDescription)
      entity.properties.append(EncodedValues.attributeDescription)
    }
    model.entities.append(Entity.entityDescription)
    return model
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
      entityDescription.managedObjectClassName = "Seam.Change"
      return entityDescription
    }
  }
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
    struct  EntityName {
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
    struct  ChangedProperties {
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
  }
  
  // MARK: - Manager
  
  class Manager {
    private var context: NSManagedObjectContext!
    
    init(managedObjectContext: NSManagedObjectContext) {
      context = managedObjectContext
    }
    
    func hasChanges() -> Bool {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      var error: NSError?
      return context.countForFetchRequest(fetchRequest, error: &error) > 0 ? true: false
    }
    
    func new(uniqueID: String,type: NSNumber, entityName: String) -> Change {
      let change = NSEntityDescription.insertNewObjectForEntityForName(Entity.name, inManagedObjectContext: context) as! Change
      change.uniqueID = uniqueID
      change.type = type
      change.entityName = entityName
      return change
    }
    
    func new(uniqueID: String,changedObject: NSManagedObject) throws -> Change? {
      if changedObject.deleted {
        if let change = try changeFor(changedObject.uniqueID) {
          guard change.isInsertedType == false else {
            context.deleteObject(change)
            return nil
          }
        }
        new(uniqueID,type: ChangeType.Deleted,
          entityName: changedObject.entity.name!)
      } else if changedObject.inserted {
        new(uniqueID,type: ChangeType.Inserted,
          entityName: changedObject.entity.name!)
      } else if changedObject.updated {
        if let change =  try changeFor(uniqueID)  {
          guard change.isUpdatedType else {
            return nil
          }
          change.addProperties(changedObject.changedValueKeys)
          return change
        }  else {
          let change = new(uniqueID, type: Change.ChangeType.Updated, entityName: changedObject.entity.name!)
          change.addProperties(changedObject.changedValueKeys)
          return change
        }
      }
      return nil
    }
    
    func changeFor(uniqueID: String) throws -> Change? {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(changeIsNotQueuedAndEqualsToID: uniqueID)
      return try context.executeFetchRequest(fetchRequest).first as? Change
    }
    
    func dequeueAll() throws -> [Change]? {
      let batchUpdateRequest = NSBatchUpdateRequest(entityName: Entity.name)
      batchUpdateRequest.propertiesToUpdate = [Properties.ChangeQueued.name: NSNumber(bool: true)]
      try context.executeRequest(batchUpdateRequest)
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(changeIsQueued: true)
      return try context.executeFetchRequest(fetchRequest) as? [Change]
    }
    
    func removeAllQueued() throws {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(changeIsQueued: true)
      let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
      try context.executeRequest(batchDeleteRequest)
    }
    
    func enqueueBackAllDequeuedChanges() throws {
      let batchUpdateRequest = NSBatchUpdateRequest(entityName: Entity.name)
      batchUpdateRequest.predicate = NSPredicate(changeIsQueued: true)
      batchUpdateRequest.propertiesToUpdate = [Properties.ChangeQueued.name: NSNumber(bool: false)]
      try context.executeRequest(batchUpdateRequest)
    }
  }
}
