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

let SMStoreErrorDomain = "SMStoreErrorDomain"
let SMLocalStoreRecordIDAttributeName = "sm_recordID_Attribute"
public let SeamStoreType = Store.type

extension NSManagedObject {
    var sm_uniqueID: String {
        return valueForKey(SMLocalStoreRecordIDAttributeName) as! String
    }
}

public class Store: NSIncrementalStore {
    private var backingPSC: NSPersistentStoreCoordinator?
    private lazy var backingMOC: NSManagedObjectContext = {
        var moc = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        moc.persistentStoreCoordinator = self.backingPSC
        moc.retainsRegisteredObjects = true
        return moc
        }()
    
    override public class func initialize() {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: type)
    }
    
    class public var type:String {
        return NSStringFromClass(self)
    }
    
    override init(persistentStoreCoordinator root: NSPersistentStoreCoordinator?, configurationName name: String?, URL url: NSURL, options: [NSObject : AnyObject]?) {
        super.init(persistentStoreCoordinator: root, configurationName: name, URL: url, options: options)
        print(url)
    }
    
    override public func loadMetadata() throws {
        metadata = [
            NSStoreUUIDKey: NSProcessInfo().globallyUniqueString,
            NSStoreTypeKey: self.dynamicType.type
        ]
        let storeURL = self.URL
        let backingMOM: NSManagedObjectModel? = self.backingModel()
        if backingMOM != nil {
            backingPSC = NSPersistentStoreCoordinator(managedObjectModel: backingMOM!)
            do {
                try backingPSC?.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: nil)
            } catch {
                throw Error.BackingStoreCreationFailed
            }
            return
        }
        throw Error.BackingStoreCreationFailed
    }
    
    // MARK: Translation
    func uniqueIDForObjectID(objectID: NSManagedObjectID) -> String {
        return referenceObjectForObjectID(objectID) as! String
    }
    
    // MARK: Model
    func backingModel() -> NSManagedObjectModel? {
        if let moc = persistentStoreCoordinator?.managedObjectModel.copy() as? NSManagedObjectModel {
            moc.entities.forEach({
                let recordIDAttribute = NSAttributeDescription()
                recordIDAttribute.name = SMLocalStoreRecordIDAttributeName
                recordIDAttribute.attributeType = .StringAttributeType
                recordIDAttribute.optional = false
                recordIDAttribute.indexed = true
                $0.properties.append(recordIDAttribute)
            })
            return moc
        }
        return nil
    }
    
    override public func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext?) throws -> AnyObject {
        if let context = context {
            if let fetchRequest = request as? NSFetchRequest {
                return try executeFetchRequest(fetchRequest, context: context)
            } else if let saveChangesRequest = request as? NSSaveChangesRequest {
                return try executeSaveChangesRequest(saveChangesRequest, context: context)
            } else {
                throw Error.InvalidRequest
            }
        }
        return []
    }
    
    // MARK: Faulting
    override public func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext) throws -> NSIncrementalStoreNode {
        let recordID = uniqueIDForObjectID(objectID)
        let fetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,recordID)
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
        let recordID = uniqueIDForObjectID(objectID)
        let fetchRequest = NSFetchRequest(entityName: objectID.entity.name!)
        let predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,recordID)
        fetchRequest.predicate = predicate
        let results = try backingMOC.executeFetchRequest(fetchRequest)
        if let managedObject = results.first as? NSManagedObject {
            if relationship.toMany {
                if let relationshipObjects = managedObject.valueForKey(relationship.name) as? Set<NSManagedObject> {
                    var objectIDs = [NSManagedObjectID]()
                    relationshipObjects.forEach({ object in
                        let recordID = object.sm_uniqueID
                        objectIDs.append(newObjectIDForEntity(object.entity, referenceObject: recordID))
                    })
                    return objectIDs
                }
            } else {
                if let relationshipObject = managedObject.valueForKey(relationship.name) as? NSManagedObject {
                    let recordID = uniqueIDForObjectID(relationshipObject.objectID)
                    return newObjectIDForEntity(relationshipObject.entity, referenceObject: recordID)
                }
                return NSNull()
            }
        }
        return NSNull()
    }
    
    override public func obtainPermanentIDsForObjects(array: [NSManagedObject]) throws -> [NSManagedObjectID] {
        return array.map({ newObjectIDForEntity($0.entity, referenceObject: NSUUID().UUIDString) })
    }
    
    // MARK : Fetch Request
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
    
    // MARK : SaveChanges Request
    private func executeSaveChangesRequest(saveChangesRequest: NSSaveChangesRequest,context: NSManagedObjectContext) throws -> [AnyObject] {
        try self.insertObjectsInBackingStore(objectsToInsert: context.insertedObjects, mainContext: context)
        try self.updateObjectsInBackingStore(objectsToUpdate: context.updatedObjects)
        try self.deleteObjectsFromBackingStore(objectsToDelete: context.deletedObjects, mainContext: context)
        try self.backingMOC.saveIfHasChanges()
        return []
    }
    
    func objectIDForBackingObjectForEntity(entityName: String, withReferenceObject referenceObject: String?) throws -> NSManagedObjectID? {
        if referenceObject == nil {
            return nil
        }
        let fetchRequest = NSFetchRequest(entityName: entityName)
        fetchRequest.resultType = .ManagedObjectIDResultType
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,referenceObject!)
        let results = try self.backingMOC.executeFetchRequest(fetchRequest)
        if results.count > 0 {
            return results.last as? NSManagedObjectID
        }
        return nil
    }
    
    private func setRelationshipValuesForBackingObject(backingObject:NSManagedObject,sourceObject:NSManagedObject) throws {
        for relationship in Array(sourceObject.entity.relationshipsByName.values) as [NSRelationshipDescription] {
            if sourceObject.hasFaultForRelationshipNamed(relationship.name) || sourceObject.valueForKey(relationship.name) == nil {
                continue
            }
            if relationship.toMany {
                let relationshipValue = sourceObject.valueForKey(relationship.name) as! Set<NSManagedObject>
                var backingRelationshipValue = Set<NSManagedObject>()
                for relationshipObject in relationshipValue {
                    let relationshipManagedObject = relationshipObject
                    if relationshipManagedObject.objectID.temporaryID == false {
                        let referenceObject = uniqueIDForObjectID(relationshipManagedObject.objectID)
                        let backingRelationshipObjectID = try objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject)
                        if backingRelationshipObjectID != nil {
                            let backingRelationshipObject = try backingObject.managedObjectContext?.existingObjectWithID(backingRelationshipObjectID!)
                            backingRelationshipValue.insert(backingRelationshipObject!)
                        }
                    }
                }
                backingObject.setValue(backingRelationshipValue, forKey: relationship.name)
            } else {
                let relationshipValue = sourceObject.valueForKey(relationship.name) as! NSManagedObject
                if relationshipValue.objectID.temporaryID == false {
                    let referenceObject = uniqueIDForObjectID(relationshipValue.objectID)
                    let backingRelationshipObjectID = try objectIDForBackingObjectForEntity(relationship.destinationEntity!.name!, withReferenceObject: referenceObject)
                    if backingRelationshipObjectID != nil {
                        let backingRelationshipObject = try backingMOC.existingObjectWithID(backingRelationshipObjectID!)
                        backingObject.setValue(backingRelationshipObject, forKey: relationship.name)
                    }
                }
            }
        }
    }
    
    func insertObjectsInBackingStore(objectsToInsert objects:Set<NSManagedObject>, mainContext: NSManagedObjectContext) throws {
        try objects.forEach({ sourceObject in
            let managedObject = NSEntityDescription.insertNewObjectForEntityForName((sourceObject.entity.name)!, inManagedObjectContext: backingMOC) as NSManagedObject
            let keys = Array(sourceObject.entity.attributeNames)
            let dictionary = sourceObject.dictionaryWithValuesForKeys(keys)
            managedObject.setValuesForKeysWithDictionary(dictionary)
            let referenceObject = uniqueIDForObjectID(sourceObject.objectID)
            managedObject.setValue(referenceObject, forKey: SMLocalStoreRecordIDAttributeName)
            mainContext.willChangeValueForKey("objectID")
            try mainContext.obtainPermanentIDsForObjects([managedObject])
            mainContext.didChangeValueForKey("objectID")
            try self.setRelationshipValuesForBackingObject(managedObject, sourceObject: sourceObject)
            try self.backingMOC.saveIfHasChanges()
        })
    }
    
    private func deleteObjectsFromBackingStore(objectsToDelete objects: Set<NSManagedObject>, mainContext: NSManagedObjectContext) throws {
        let predicateObjectRecordIDKey = "objectRecordID"
        let predicate = NSPredicate(format: "%K == $objectRecordID", SMLocalStoreRecordIDAttributeName)
        try objects.forEach({ managedObject in
            let fetchRequest = NSFetchRequest(entityName: managedObject.entity.name!)
            let recordID = uniqueIDForObjectID(managedObject.objectID)
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables([predicateObjectRecordIDKey: recordID])
            fetchRequest.includesPropertyValues = false
            let results = try backingMOC.executeFetchRequest(fetchRequest)
            if let backingObject = results.last as? NSManagedObject {
                backingMOC.deleteObject(backingObject)
            }
            try backingMOC.saveIfHasChanges()
        })
    }
    
    private func updateObjectsInBackingStore(objectsToUpdate objects: Set<NSManagedObject>) throws {
        let predicateObjectRecordIDKey = "objectRecordID"
        let predicate = NSPredicate(format: "%K == $objectRecordID", SMLocalStoreRecordIDAttributeName)
        try objects.forEach({ managedObject in
            let fetchRequest = NSFetchRequest(entityName: managedObject.entity.name!)
            let recordID = uniqueIDForObjectID(managedObject.objectID)
            fetchRequest.predicate = predicate.predicateWithSubstitutionVariables([predicateObjectRecordIDKey:recordID])
            let results = try backingMOC.executeFetchRequest(fetchRequest)
            let backingObject = results.last as! NSManagedObject
            let keys = Array(persistentStoreCoordinator!.managedObjectModel.entitiesByName[managedObject.entity.name!]!.attributesByName.keys)
            let sourceObjectValues = managedObject.dictionaryWithValuesForKeys(keys)
            backingObject.setValuesForKeysWithDictionary(sourceObjectValues)
            try setRelationshipValuesForBackingObject(backingObject, sourceObject: managedObject)
            try backingMOC.saveIfHasChanges()
        })
    }
}