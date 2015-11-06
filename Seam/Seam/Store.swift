//    Store.swift
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


import CoreData
import CloudKit
import ObjectiveC

extension NSManagedObject {
    var sm_uniqueID: String {
        return valueForKey(EntityAttributes.UniqueID.name) as! String
    }
}

extension NSPredicate {
    class func sm_UniqueIDEqualsToIDPredicate(id: String) -> NSPredicate {
        return NSPredicate(format: "%K == %@", EntityAttributes.UniqueID.name,id)
    }
}

public class Store: NSIncrementalStore {
    private var backingPSC: NSPersistentStoreCoordinator?
    private lazy var backingMOC: NSManagedObjectContext = {
        var backingMOC = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        backingMOC.persistentStoreCoordinator = self.backingPSC
        backingMOC.retainsRegisteredObjects = true
        return backingMOC
        }()
    
    override public class func initialize() {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: type)
    }
    
    class public var type:String {
        return NSStringFromClass(self)
    }
    
    override public func loadMetadata() throws {
        metadata = [
            NSStoreUUIDKey: NSProcessInfo().globallyUniqueString,
            NSStoreTypeKey: self.dynamicType.type
        ]
        guard let backingMOM = self.modifiedModelForBackingStore() else {
            throw Error.Store.BackingStore.ModelCreationFailed
        }
        backingPSC = NSPersistentStoreCoordinator(managedObjectModel: backingMOM)
        guard let backingPSC = backingPSC else {
            throw Error.Store.BackingStore.PersistentStoreInitializationFailed
        }
        guard let _ = try? backingPSC.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: URL, options: nil) else {
            throw Error.Store.BackingStore.CreationFailed
        }
    }
    
    // MARK: - Translation
    func uniqueIDForObjectID(objectID: NSManagedObjectID) -> String {
        return referenceObjectForObjectID(objectID) as! String
    }
    
    // MARK: - Model
    func modifiedModelForBackingStore() -> NSManagedObjectModel? {
        guard let model = persistentStoreCoordinator?.managedObjectModel.copy() as? NSManagedObjectModel else {
            return nil
        }
        model.entities.forEach({ entity in
            entity.properties.append(EntityAttributes.UniqueID.attributeDescription)
            entity.properties.append(EntityAttributes.EncodedValues.attributeDescription)
        })
        model.entities.append(ChangeSet.Entity.entityDescription)
        return model
    }
    
    // MARK: - Faulting
    override public func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        let recordID = uniqueIDForObjectID(objectID)
        let fetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
        fetchRequest.predicate = NSPredicate.sm_UniqueIDEqualsToIDPredicate(recordID)
        fetchRequest.resultType = .DictionaryResultType
        fetchRequest.propertiesToFetch = objectID.entity.propertyNamesToFetch
        let results = try backingMOC.executeFetchRequest(fetchRequest)
        var backingObjectValues = results.last as! [String: NSObject]
        backingObjectValues.forEach({ (key, value) in
            if let managedObject = value as? NSManagedObject {
                let recordID  = managedObject.sm_uniqueID
                let entities = persistentStoreCoordinator!.managedObjectModel.entitiesByName
                let entityName = managedObject.entity.name!
                let entity = entities[entityName]! as NSEntityDescription
                let objectID = newObjectIDForEntity(entity, referenceObject: recordID)
                backingObjectValues[key] = objectID
            }
        })
        let incrementalStoreNode = NSIncrementalStoreNode(objectID: objectID, withValues: backingObjectValues, version: 1)
        return incrementalStoreNode
    }
    
    override public func newValueForRelationship(relationship: NSRelationshipDescription, forObjectWithID objectID: NSManagedObjectID, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        let referenceObject = uniqueIDForObjectID(objectID)
        guard let backingObjectID = try objectIDForBackingObjectForEntity(objectID.entity.name!, withReferenceObject: referenceObject) else {
            if relationship.toMany {
                return []
            } else {
                return NSNull()
            }
        }
        let backingObject = try backingMOC.existingObjectWithID(backingObjectID)
        if let relationshipManagedObjects = backingObject.valueForKey(relationship.name) as? Set<NSManagedObject> {
            var relationshipManagedObjectIDs = Set<NSManagedObjectID>()
            relationshipManagedObjects.forEach { object in
                let uniqueID = object.sm_uniqueID
                relationshipManagedObjectIDs.insert(newObjectIDForEntity(relationship.destinationEntity!, referenceObject: uniqueID))
            }
            return relationshipManagedObjectIDs
        } else if let relationshipManagedObject = backingObject.valueForKey(relationship.name) as? NSManagedObject {
            let uniqueID = relationshipManagedObject.sm_uniqueID
            return newObjectIDForEntity(relationship.destinationEntity!, referenceObject: uniqueID)
        }
        return NSNull()
    }
    
    override public func obtainPermanentIDsForObjects(array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        return array.map({ newObjectIDForEntity($0.entity, referenceObject: NSUUID().UUIDString) })
    }
    
    // MARK: Attribute and Relationship Setters
    func setAttributeValuesForBackingObject(backingObject: NSManagedObject, sourceObject: NSManagedObject) {
        if backingObject.valueForKey(EntityAttributes.UniqueID.name) == nil {
            let uniqueID = uniqueIDForObjectID(sourceObject.objectID)
            backingObject.setValue(uniqueID, forKey: EntityAttributes.UniqueID.name)
        }
        let keys = sourceObject.entity.attributeNames
        let valuesForKeys = sourceObject.dictionaryWithValuesForKeys(keys)
        backingObject.setValuesForKeysWithDictionary(valuesForKeys)
    }
    
    func setRelationshipValuesForBackingObject(backingObject: NSManagedObject,fromSourceObject sourceObject: NSManagedObject) throws {
        try sourceObject.entity.relationships.forEach({ relationship in
            guard !sourceObject.hasFaultForRelationshipNamed(relationship.name) else {
                return
            }
            guard sourceObject.valueForKey(relationship.name) != nil else {
                return
            }
            if let relationshipManagedObjects = sourceObject.valueForKey(relationship.name) as? Set<NSManagedObject> {
                var backingRelationshipManagedObjects = Set<NSManagedObject>()
                try relationshipManagedObjects.forEach { relationshipManagedObject in
                    guard !relationshipManagedObject.objectID.temporaryID else {
                        return
                    }
                    let referenceObject = uniqueIDForObjectID(relationshipManagedObject.objectID)
                    if let backingRelationshipObjectID = try objectIDForBackingObjectForEntity(relationshipManagedObject.entity.name!, withReferenceObject: referenceObject) {
                        let backingRelationshipObject = try backingMOC.existingObjectWithID(backingRelationshipObjectID)
                        backingRelationshipManagedObjects.insert(backingRelationshipObject)
                    }
                }
                backingObject.setValue(backingRelationshipManagedObjects, forKey: relationship.name)
            } else if let relationshipManagedObject = sourceObject.valueForKey(relationship.name) as? NSManagedObject {
                guard !relationshipManagedObject.objectID.temporaryID else {
                    return
                }
                let referenceObject = uniqueIDForObjectID(relationshipManagedObject.objectID)
                if let backingRelationshipObjectID = try objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject) {
                    if let backingRelationshipObject = try? backingMOC.existingObjectWithID(backingRelationshipObjectID) {
                        backingObject.setValue(backingRelationshipObject, forKey: relationship.name)
                    }
                }
            }
        })
    }

    // MARK: - Requests
    public override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        if let context = context {
            if let fetchRequest = request as? NSFetchRequest {
                return try executeFetchRequest(fetchRequest, context: context)
            } else if let saveChangesRequest = request as? NSSaveChangesRequest {
                return try executeSaveChangesRequest(saveChangesRequest, context: context)
            } else {
                throw Error.Store.MainStore.InvalidRequest
            }
        }
        return []
    }

    // MARK: FetchRequest
    func executeFetchRequest(fetchRequest: NSFetchRequest, context: NSManagedObjectContext) throws -> [NSManagedObject] {
        if let result = try? backingMOC.executeFetchRequest(fetchRequest) {
            if let fetchedObjects = result as? [NSManagedObject] {
                return fetchedObjects.map({ object in
                    let recordID = object.sm_uniqueID
                    let entity = persistentStoreCoordinator!.managedObjectModel.entitiesByName[fetchRequest.entityName!]
                    let objectID = newObjectIDForEntity(entity!, referenceObject: recordID)
                    let object = context.objectWithID(objectID)
                    return object
                })
            }
        }
        return []
    }

    // MARK: SaveChangesRequest
    private func executeSaveChangesRequest(saveChangesRequest: NSSaveChangesRequest,context: NSManagedObjectContext) throws -> [AnyObject] {
        try self.deleteObjectsFromBackingStore(objectsToDelete: context.deletedObjects, mainContext: context)
        try self.insertObjectsInBackingStore(objectsToInsert: context.insertedObjects, mainContext: context)
        try self.updateObjectsInBackingStore(objectsToUpdate: context.updatedObjects)
        try self.backingMOC.saveIfHasChanges()
        return []
    }
    
    func objectIDForBackingObjectForEntity(entityName: String, withReferenceObject referenceObject: String) throws -> NSManagedObjectID? {
        let fetchRequest = NSFetchRequest(entityName: entityName)
        fetchRequest.resultType = .ManagedObjectIDResultType
        fetchRequest.predicate = NSPredicate.sm_UniqueIDEqualsToIDPredicate(referenceObject)
        let results = try backingMOC.executeFetchRequest(fetchRequest)
        return results.last as? NSManagedObjectID
    }
    
    func insertObjectsInBackingStore(objectsToInsert objects:Set<NSManagedObject>, mainContext: NSManagedObjectContext) throws {
        try objects.forEach({ sourceObject in
            let managedObject = NSEntityDescription.insertNewObjectForEntityForName((sourceObject.entity.name)!, inManagedObjectContext: backingMOC) as NSManagedObject
            let referenceObject = uniqueIDForObjectID(sourceObject.objectID)
            managedObject.setValue(referenceObject, forKey: EntityAttributes.UniqueID.name)
            try backingMOC.obtainPermanentIDsForObjects([managedObject])
            setAttributeValuesForBackingObject(managedObject, sourceObject: sourceObject)
            try setRelationshipValuesForBackingObject(managedObject, fromSourceObject: sourceObject)
            mainContext.willChangeValueForKey("objectID")
            try mainContext.obtainPermanentIDsForObjects([sourceObject])
            mainContext.didChangeValueForKey("objectID")
            try backingMOC.saveIfHasChanges()
        })
    }
    
    private func updateObjectsInBackingStore(objectsToUpdate objects: Set<NSManagedObject>) throws {
        try objects.forEach({ sourceObject in
            let recordID = uniqueIDForObjectID(sourceObject.objectID)
            if let backingObjectID = try objectIDForBackingObjectForEntity(sourceObject.entity.name!, withReferenceObject: recordID) {
                if let backingObject = try? backingMOC.existingObjectWithID(backingObjectID) {
                    setAttributeValuesForBackingObject(backingObject, sourceObject: sourceObject)
                    try setRelationshipValuesForBackingObject(backingObject, fromSourceObject: sourceObject)
                    try backingMOC.saveIfHasChanges()
                }
            }
        })
    }
    
    private func deleteObjectsFromBackingStore(objectsToDelete objects: Set<NSManagedObject>, mainContext: NSManagedObjectContext) throws {
        try objects.forEach({ managedObject in
            let fetchRequest = NSFetchRequest(entityName: managedObject.entity.name!)
            let recordID = uniqueIDForObjectID(managedObject.objectID)
            fetchRequest.predicate = NSPredicate.sm_UniqueIDEqualsToIDPredicate(recordID)
            fetchRequest.includesPropertyValues = false
            let results = try backingMOC.executeFetchRequest(fetchRequest)
            if let backingObject = results.last as? NSManagedObject {
                backingMOC.deleteObject(backingObject)
                try backingMOC.saveIfHasChanges()
            }
        })
    }
}