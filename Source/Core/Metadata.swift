//    Metadata.swift
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

class Metadata: NSManagedObject {
  @NSManaged var entityName: String?
  @NSManaged var data: NSData?
  
  struct Entity {
    static let name = "Seam_Metadata"
    static var entityDescription: NSEntityDescription {
      let entityDescription = NSEntityDescription()
      entityDescription.name = name
      entityDescription.properties.append(UniqueID.attributeDescription)
      entityDescription.properties.append(Properties.EntityName.attributeDescription)
      entityDescription.properties.append(Properties.Data.attributeDescription)
      entityDescription.managedObjectClassName = "Seam.Metadata"
      return entityDescription
    }
  }
  
  // MARK: Properties

  struct Properties {
    struct EntityName {
      static let name = "entityName"
      static var attributeDescription: NSAttributeDescription {
        let attributeDescription = NSAttributeDescription()
        attributeDescription.name = name
        attributeDescription.attributeType = .StringAttributeType
        attributeDescription.optional = false
        return attributeDescription
      }
    }
    struct Data {
      static let name = "data"
      static var attributeDescription: NSAttributeDescription {
        let attributeDescription = NSAttributeDescription()
        attributeDescription.name = name
        attributeDescription.attributeType = .BinaryDataAttributeType
        attributeDescription.optional = false
        return attributeDescription
      }
    }
  }
  
  class Manager {
    var context: NSManagedObjectContext!
    
    init(context: NSManagedObjectContext) {
      self.context = context
    }
    
    func metadataWithUniqueID(id: String) throws -> Metadata? {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(equalsToUniqueID: id)
      return try context.executeFetchRequest(fetchRequest).first as? Metadata
    }
    
    func setMetadataForUniqueID(id: String, entityName: String, data: NSData) throws {
      if let metadata = try metadataWithUniqueID(id) {
        metadata.data = data
      } else if let metadata = NSEntityDescription.insertNewObjectForEntityForName(Entity.name, inManagedObjectContext: context) as? Metadata {
        metadata.uniqueID = id
        metadata.data = data
        metadata.entityName = entityName
      }
      try context.save()
    }
    
    func deleteMetadataForUniqueIDs(ids: [String]) throws {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(inUniqueIDs: ids)
      let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
      try context.executeRequest(batchDeleteRequest)
    }
  }
}
