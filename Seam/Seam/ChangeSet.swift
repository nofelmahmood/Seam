//
//  ChangeSet.swift
//  Seam
//
//  Created by Nofel Mahmood on 04/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData

protocol ChangeRecordable {
    func recordChangeForManagedObject(object: NSManagedObject, inContext context: NSManagedObjectContext) throws
    func recordedChangeForUniqueID(id: String, inContext context: NSManagedObjectContext) throws -> NSManagedObject?
    func removeAllPreviousRecordedChanges(forUniqueID id: String, inContext context: NSManagedObjectContext)
    func removeAllQueuedRecordedChanges(inContext context: NSManagedObjectContext) throws
    func dequeueAllRecordedChanges(inContext context: NSManagedObjectContext) throws -> [NSManagedObject]?
    func enqueueAllDequeuedRecordedChanges(inContext context: NSManagedObjectContext) throws
}

extension NSManagedObject {
    var changedPropertiesForChangeRecording: String {
        let changedProperties = Array(self.changedValues().keys).filter { propertyName in
            guard let relationshipDescription = entity.propertiesByName[propertyName] as? NSRelationshipDescription else {
                return true
            }
            return !relationshipDescription.toMany
        }
        return changedProperties.joinWithSeparator(ChangeSetProperties.separator)
    }
    
    func changedPropertiesForChangeRecording(byMergingWithPreviouslyChangedProperties changedProperties: String) -> String {
        let newChangedPropertiesSet = Set(changedPropertiesForChangeRecording.componentsSeparatedByString(ChangeSetProperties.separator))
        let changedPropertiesSet = Set(changedProperties.componentsSeparatedByString(ChangeSetProperties.separator))
        return changedPropertiesSet.union(newChangedPropertiesSet).joinWithSeparator(ChangeSetProperties.separator)
    }
}

extension Store: ChangeRecordable {
    func recordChangeForManagedObject(object: NSManagedObject, inContext context: NSManagedObjectContext) throws {
        if object.deleted {
            removeAllPreviousRecordedChanges(forUniqueID: object.uniqueID, inContext: context)
            let change = NSEntityDescription.insertNewObjectForEntityForName(ChangeSetProperties.Entity.name, inManagedObjectContext: context)
            change.setValue(object.uniqueID, forKey: ChangeSetProperties.Entity.Attributes.UniqueID.name)
            change.setValue(ChangeSetProperties.ChangeType.Deleted, forKey: ChangeSetProperties.Entity.Attributes.ChangeType.name)
            try context.save()
        } else if object.inserted {
            let change = NSEntityDescription.insertNewObjectForEntityForName(ChangeSetProperties.Entity.name, inManagedObjectContext: context)
            change.setValue(object.uniqueID, forKey: ChangeSetProperties.Entity.Attributes.UniqueID.name)
            change.setValue(ChangeSetProperties.ChangeType.Inserted, forKey: ChangeSetProperties.Entity.Attributes.ChangeType.name)
            try context.save()
        } else if object.updated {
            if let recordedChange = try recordedChangeForUniqueID(object.uniqueID, inContext: context) {
                let changeType = recordedChange.valueForKey(ChangeSetProperties.Entity.Attributes.ChangeType.name) as! NSNumber
                if changeType == ChangeSetProperties.ChangeType.Inserted {
                    return
                } else if changeType == ChangeSetProperties.ChangeType.Updated {
                    let changedProperties = object.valueForKey(ChangeSetProperties.Entity.Attributes.ChangedProperties.name) as! String
                    let mergedChangedProperties = object.changedPropertiesForChangeRecording(byMergingWithPreviouslyChangedProperties: changedProperties)
                    recordedChange.setValue(mergedChangedProperties, forKey: ChangeSetProperties.Entity.Attributes.ChangedProperties.name)
                    try context.save()
                }
            }  else {
                let change = NSEntityDescription.insertNewObjectForEntityForName(ChangeSetProperties.Entity.name, inManagedObjectContext: context)
                change.setValue(object.uniqueID, forKey: ChangeSetProperties.Entity.Attributes.UniqueID.name)
                change.setValue(ChangeSetProperties.ChangeType.Updated, forKey: ChangeSetProperties.Entity.Attributes.ChangeType.name)
                change.setValue(object.changedPropertiesForChangeRecording, forKey: ChangeSetProperties.Entity.Attributes.ChangedProperties.name)
                try context.save()
            }
        }
    }
    
    func recordedChangeForUniqueID(id: String, inContext context: NSManagedObjectContext) throws -> NSManagedObject? {
        let fetchRequest = NSFetchRequest(entityName: ChangeSetProperties.Entity.name)
        fetchRequest.predicate = NSPredicate(uniqueID: id)
        let recordedChange = try context.executeFetchRequest(fetchRequest).first
        return recordedChange as? NSManagedObject
    }
    
    func removeAllPreviousRecordedChanges(forUniqueID id: String, inContext context: NSManagedObjectContext) {
        let fetchRequest = NSFetchRequest(entityName: ChangeSetProperties.Entity.name)
        fetchRequest.predicate = NSPredicate(uniqueID: id)
        if let changes = try? context.executeFetchRequest(fetchRequest) {
            (changes as? [NSManagedObject])?.forEach { object in
                context.deleteObject(object)
                try! context.save()
            }
        }
    }

    func removeAllQueuedRecordedChanges(inContext context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest(entityName: ChangeSetProperties.Entity.name)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", ChangeSetProperties.Entity.Attributes.ChangeQueued.name, NSNumber(bool: true))
        let batchDeleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
        try context.executeRequest(batchDeleteRequest)
    }
    
    func enqueueAllDequeuedRecordedChanges(inContext context: NSManagedObjectContext) throws {
        let batchUpdateRequest = NSBatchUpdateRequest(entityName: ChangeSetProperties.Entity.name)
        batchUpdateRequest.predicate = NSPredicate(format: "%K == %@", ChangeSetProperties.Entity.Attributes.ChangeQueued.name, NSNumber(bool: true))
        batchUpdateRequest.propertiesToUpdate = [ChangeSetProperties.Entity.Attributes.ChangeQueued.name: NSNumber(bool: false)]
        try context.executeRequest(batchUpdateRequest)
    }
    
    func dequeueAllRecordedChanges(inContext context: NSManagedObjectContext) throws -> [NSManagedObject]? {
        let fetchRequest = NSFetchRequest(entityName: ChangeSetProperties.Entity.name)
        let changes = try context.executeFetchRequest(fetchRequest)
        return changes as? [NSManagedObject]
    }
}
