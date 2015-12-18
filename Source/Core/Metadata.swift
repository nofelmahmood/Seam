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
import CloudKit

// Metadata is a subclass of NSManagedObject. This class is added to backing store model automatically and used by the backing store to save record metadata received from CloudKit against every CKRecord.
class Metadata: NSManagedObject {
  @NSManaged var entityName: String?
  @NSManaged var data: NSData?
  
  /**
   *  Entity information for Metadata.
   */
  struct Entity {
    static let name = "Seam_Metadata"
    static var entityDescription: NSEntityDescription {
      let entityDescription = NSEntityDescription()
      entityDescription.name = name
      entityDescription.properties.append(UniqueID.attributeDescription)
      entityDescription.properties.append(Properties.Data.attributeDescription)
      entityDescription.managedObjectClassName = "Seam.Metadata"
      return entityDescription
    }
  }

  // MARK: Properties 
  
  /**
  *  Properties information belonging to Metadata entity.
  */
  struct Properties {
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
  
  /// Metadata.Manager is a class used to manage metadata by the store.
  class Manager {
    var context: NSManagedObjectContext!
    
    /**
     Initializer to initialize Manager with an instance of NSManagedObjectContext attached to backing instance of NSPersistentStoreCoordinator.
     
     - parameter context: An instance of NSManagedObjectContext.
     
     */
    init(context: NSManagedObjectContext) {
      self.context = context
    }
    
    /**
     Helper method to retrieve metadata belonging to record with unique ID.
     
     - parameter id: Unique id of the record.
     
     - throws: CoreData fetch request error.
     
     - returns: An optional that might or might not contain saved instance of Metadata for the provided unique ID.
     */
    func metadataWithUniqueID(id: String) throws -> Metadata? {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(equalsToUniqueID: id)
      return try context.executeFetchRequest(fetchRequest).first as? Metadata
    }
    
    /**
     Helper method to save metadata for a CKRecord.
     
     - parameter record: An instance of CKRecord for which metadata is to be saved.
     
     - throws: CoreData save error.
     */
    func setMetadata(forRecord record: CKRecord) throws {
      let uniqueID = record.recordID.recordName
      let encodedData = record.encodedSystemFields
      if let metadata = try metadataWithUniqueID(uniqueID) {
        metadata.data = encodedData
      } else if let metadata = NSEntityDescription.insertNewObjectForEntityForName(Entity.name, inManagedObjectContext: context) as? Metadata {
        metadata.uniqueID = uniqueID
        metadata.data = encodedData
      }
      try context.saveIfHasChanges()
    }
    
    /**
     Helper method to delete metadata for the unique IDs provided in the list.
     
     - parameter ids: An array containing unique IDs.
     
     - throws: CoreData fetch request error.
     */
    func deleteMetadataForUniqueIDs(ids: [String]) throws {
      let fetchRequest = NSFetchRequest(entityName: Entity.name)
      fetchRequest.predicate = NSPredicate(inUniqueIDs: ids)
      (try context.executeFetchRequest(fetchRequest)).forEach { object in
        let managedObject = object as! NSManagedObject
        context.deleteObject(managedObject)
      }
    }
  }
}
