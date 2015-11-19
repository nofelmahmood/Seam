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

class Change {
  
  // MARK: - Change
  
  struct ChangeType {
    static let Inserted = NSNumber(int: 0)
    static let Updated = NSNumber(int: 1)
    static let Deleted = NSNumber(int: 2)
  }
  static let propertySeparator = ","

  var uniqueID: String {
    get {
      return managedObject.valueForKey(UniqueID.name) as! String
    } set {
      managedObject.setValue(newValue, forKey: UniqueID.name)
    }
  }
  var entityName: String {
    get {
      return managedObject.valueForKey(Properties.EntityName.name) as! String
    } set {
      managedObject.setValue(newValue, forKey: Properties.EntityName.name)
    }
  }
  var entity: NSEntityDescription {
    return managedObject.entity.managedObjectModel.entitiesByName[entityName]!
  }
  var type: NSNumber {
    get {
      return managedObject.valueForKey(Properties.ChangeType.name) as! NSNumber
    } set {
      managedObject.setValue(newValue, forKey: Properties.ChangeType.name)
    }
  }
  var properties: String? {
    get {
      return managedObject.valueForKey(Properties.ChangedProperties.name) as? String
    } set {
      guard let newValue = newValue else {
        managedObject.setValue(nil, forKey: Properties.ChangedProperties.name)
        return
      }
      if let oldProperties = managedObject.valueForKey(Properties.ChangedProperties.name) as? String {
        let newPropertiesArray = newValue.componentsSeparatedByString(Change.propertySeparator)
        let newPropertiesSet = Set(newPropertiesArray)
        let oldPropertiesArray = oldProperties.componentsSeparatedByString(Change.propertySeparator)
        let oldPropertiesSet = Set(oldPropertiesArray)
        let properties = Array(oldPropertiesSet.union(newPropertiesSet)).joinWithSeparator(Change.propertySeparator)
        managedObject.setValue(properties, forKey: Properties.ChangedProperties.name)
      } else {
        managedObject.setValue(newValue, forKey: Properties.ChangedProperties.name)
      }
    }
  }
  var queued: Bool {
    get {
      return (managedObject.valueForKey(Properties.ChangeQueued.name) as! NSNumber).boolValue
    } set {
      managedObject.setValue(newValue, forKey: Properties.ChangeQueued.name)
    }
  }
  var isDeletedType: Bool {
    let isDeletedType = type == Change.ChangeType.Deleted
    return isDeletedType
  }
  var isInsertedType: Bool {
    let isInsertedType = type == Change.ChangeType.Inserted
    return isInsertedType
  }
  var isUpdatedType: Bool {
    let isUpdatedType = type == Change.ChangeType.Updated
    return isUpdatedType
  }
  var changedPropertyValuesDictionary: [String: AnyObject]? {
    if let changedObject = changedObject {
      if let properties = properties?.componentsSeparatedByString(Change.propertySeparator) where isUpdatedType == true {
        return changedObject.dictionaryWithValuesForKeys(properties)
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
  var changedObject: NSManagedObject? {
    let context = managedObject.managedObjectContext!
    let fetchRequest = NSFetchRequest(entityName: entityName)
    fetchRequest.predicate = NSPredicate(equalsToUniqueID: uniqueID)
    do {
      let object = try context.executeFetchRequest(fetchRequest).first as? NSManagedObject
      return object
    } catch {
      return nil
    }
  }
  var changedObjectEncodedValues: NSData? {
    return changedObject?.valueForKey(EncodedValues.name) as? NSData
  }
  var managedObject: NSManagedObject!
  
  init(managedObject: NSManagedObject) {
    self.managedObject = managedObject
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
  
  // MARK: - Entity

  struct Entity {
    static let name = "Seam_ChangeRecord"
    static var entityDescription: NSEntityDescription {
      let entityDescription = NSEntityDescription()
      entityDescription.name = name
      entityDescription.properties.append(UniqueID.attributeDescription)
      entityDescription.properties.append(Properties.ChangeType.attributeDescription)
      entityDescription.properties.append(Properties.EntityName.attributeDescription)
      entityDescription.properties.append(Properties.ChangedProperties.attributeDescription)
      entityDescription.properties.append(Properties.ChangeQueued.attributeDescription)
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
    
    func new(uniqueID: String,type: NSNumber, entityName: String,inContext context: NSManagedObjectContext) throws -> Change {
      let object = NSEntityDescription.insertNewObjectForEntityForName(Entity.name, inManagedObjectContext: context)
      object.setValue(uniqueID, forKey: UniqueID.name)
      object.setValue(type, forKey: Properties.ChangeType.name)
      object.setValue(entityName, forKey: Properties.EntityName.name)
      try context.save()
      return Change(managedObject: object)
    }
    
    func new(changedObject: NSManagedObject) throws -> Change? {
      let context = changedObject.managedObjectContext!
      if changedObject.deleted {
        if let change = try changeFor(changedObject.uniqueID) {
          let insertedType = change.isInsertedType
          try remove(change)
          guard insertedType == false else {
            return nil
          }
        }
        try new(changedObject.uniqueID,type: Change.ChangeType.Deleted,
          entityName: changedObject.entity.name!,inContext: context)
      } else if changedObject.inserted {
        try new(changedObject.uniqueID,type: Change.ChangeType.Inserted,
          entityName: changedObject.entity.name!,inContext: context)
      } else if changedObject.updated {
        if let change =  try changeFor(changedObject.uniqueID) {
          guard change.type == Change.ChangeType.Updated else {
            return nil
          }
          change.properties = changedObject.changedPropertiesForChangeRecording
          try context.save()
          return change
        }  else {
          let change = try new(changedObject.uniqueID, type: Change.ChangeType.Updated, entityName: changedObject.entity.name!, inContext: context)
          change.properties = changedObject.changedPropertiesForChangeRecording
          try context.save()
          return change
        }
      }
      return nil
    }
    
    func remove(change: Change) throws {
      context.deleteObject(change.managedObject)
      try context.save()
    }
    
    func changeFor(uniqueID: String) throws -> Change? {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(equalsToUniqueID: uniqueID)
      let recordedChange = try context.executeFetchRequest(fetchRequest).first
      if let recordedChange  = recordedChange as? NSManagedObject {
        return Change(managedObject: recordedChange)
      }
      return nil
    }
    
    func dequeueAll() throws -> [Change]? {
      let batchUpdateRequest = NSBatchUpdateRequest(entityName: Entity.name)
      batchUpdateRequest.propertiesToUpdate = [Properties.ChangeQueued.name: NSNumber(bool: true)]
      try context.executeRequest(batchUpdateRequest)
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(changeIsQueued: true)
      let changes = try context.executeFetchRequest(fetchRequest) as? [NSManagedObject]
      return changes?.map({ Change(managedObject: $0) })
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