//    SMStoreChangeSetHandler.swift
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


let SMLocalStoreEntityNameAttributeName = "sm_LocalStore_EntityName"
let SMLocalStoreChangeTypeAttributeName="sm_LocalStore_ChangeType"
let SMLocalStoreRecordIDAttributeName="sm_LocalStore_RecordID"
let SMLocalStoreRecordEncodedValuesAttributeName = "sm_LocalStore_EncodedValues"
let SMLocalStoreRecordChangedPropertiesAttributeName = "sm_LocalStore_ChangedProperties"
let SMLocalStoreChangeQueuedAttributeName = "sm_LocalStore_Queued"

let SMLocalStoreChangeSetEntityName = "SM_LocalStore_ChangeSetEntity"

class SMStoreChangeSetHandler {
    
    static let defaultHandler = SMStoreChangeSetHandler()
    
    func changedPropertyKeys(_ keys: [String], entity: NSEntityDescription) -> [String] {
        return keys.filter({ (key) -> Bool in
            let property = entity.propertiesByName[key]
            if property != nil && property is NSRelationshipDescription {
                let relationshipDescription: NSRelationshipDescription = property as! NSRelationshipDescription
                return relationshipDescription.isToMany == false
            }
            return true
        })
    }
    
    func addExtraBackingStoreAttributes(toEntity entity: NSEntityDescription) {
        let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
        recordIDAttribute.name = SMLocalStoreRecordIDAttributeName
        recordIDAttribute.isOptional = false
        recordIDAttribute.isIndexed = true
        recordIDAttribute.attributeType = NSAttributeType.stringAttributeType
        entity.properties.append(recordIDAttribute)
        let recordEncodedValuesAttribute: NSAttributeDescription = NSAttributeDescription()
        recordEncodedValuesAttribute.name = SMLocalStoreRecordEncodedValuesAttributeName
        recordEncodedValuesAttribute.attributeType = NSAttributeType.binaryDataAttributeType
        recordEncodedValuesAttribute.isOptional = true
        entity.properties.append(recordEncodedValuesAttribute)
    }
    
    func changeSetEntity() -> NSEntityDescription {
        let changeSetEntity: NSEntityDescription = NSEntityDescription()
        changeSetEntity.name = SMLocalStoreChangeSetEntityName
        let entityNameAttribute: NSAttributeDescription = NSAttributeDescription()
        entityNameAttribute.name = SMLocalStoreEntityNameAttributeName
        entityNameAttribute.attributeType = NSAttributeType.stringAttributeType
        entityNameAttribute.isOptional = true
        changeSetEntity.properties.append(entityNameAttribute)
        let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
        recordIDAttribute.name = SMLocalStoreRecordIDAttributeName
        recordIDAttribute.attributeType = NSAttributeType.stringAttributeType
        recordIDAttribute.isOptional = false
        recordIDAttribute.isIndexed = true
        changeSetEntity.properties.append(recordIDAttribute)
        let recordChangedPropertiesAttribute: NSAttributeDescription = NSAttributeDescription()
        recordChangedPropertiesAttribute.name = SMLocalStoreRecordChangedPropertiesAttributeName
        recordChangedPropertiesAttribute.attributeType = NSAttributeType.stringAttributeType
        recordChangedPropertiesAttribute.isOptional = true
        changeSetEntity.properties.append(recordChangedPropertiesAttribute)
        let recordChangeTypeAttribute: NSAttributeDescription = NSAttributeDescription()
        recordChangeTypeAttribute.name = SMLocalStoreChangeTypeAttributeName
        recordChangeTypeAttribute.attributeType = NSAttributeType.integer16AttributeType
        recordChangeTypeAttribute.isOptional = false
        recordChangeTypeAttribute.defaultValue = NSNumber(value: SMLocalStoreRecordChangeType.recordInserted.rawValue)
        changeSetEntity.properties.append(recordChangeTypeAttribute)
        let changeTypeQueuedAttribute: NSAttributeDescription = NSAttributeDescription()
        changeTypeQueuedAttribute.name = SMLocalStoreChangeQueuedAttributeName
        changeTypeQueuedAttribute.isOptional = false
        changeTypeQueuedAttribute.attributeType = NSAttributeType.booleanAttributeType
        changeTypeQueuedAttribute.defaultValue = NSNumber(value: false)
        changeSetEntity.properties.append(changeTypeQueuedAttribute)
        return changeSetEntity
    }
    
    func modelForLocalStore(usingModel model: NSManagedObjectModel) -> NSManagedObjectModel {
        let backingModel: NSManagedObjectModel = model.copy() as! NSManagedObjectModel
        for entity in backingModel.entities {
            self.addExtraBackingStoreAttributes(toEntity: entity)
        }
        backingModel.entities.append(self.changeSetEntity())
        return backingModel
    }
    
    // MARK: Creation
    func createChangeSet(ForInsertedObjectRecordID recordID: String, entityName: String, backingContext: NSManagedObjectContext) {
        let changeSet = NSEntityDescription.insertNewObject(forEntityName: SMLocalStoreChangeSetEntityName, into: backingContext)
        changeSet.setValue(recordID, forKey: SMLocalStoreRecordIDAttributeName)
        changeSet.setValue(entityName, forKey: SMLocalStoreEntityNameAttributeName)
        changeSet.setValue(NSNumber(value: SMLocalStoreRecordChangeType.recordInserted.rawValue), forKey: SMLocalStoreChangeTypeAttributeName)
    }
    
    func createChangeSet(ForUpdatedObject object: NSManagedObject, usingContext context: NSManagedObjectContext) {
        let changeSet = NSEntityDescription.insertNewObject(forEntityName: SMLocalStoreChangeSetEntityName, into: context)
        let changedPropertyKeys = self.changedPropertyKeys(Array(object.changedValues().keys), entity: object.entity)
        let recordIDString: String = object.value(forKey: SMLocalStoreRecordIDAttributeName) as! String
        let changedPropertyKeysString = changedPropertyKeys.joined(separator: ",")
        changeSet.setValue(recordIDString, forKey: SMLocalStoreRecordIDAttributeName)
        changeSet.setValue(object.entity.name!, forKey: SMLocalStoreEntityNameAttributeName)
        changeSet.setValue(changedPropertyKeysString, forKey: SMLocalStoreRecordChangedPropertiesAttributeName)
        changeSet.setValue(NSNumber(value: SMLocalStoreRecordChangeType.recordUpdated.rawValue), forKey: SMLocalStoreChangeTypeAttributeName)
    }
    
    func createChangeSet(ForDeletedObjectRecordID recordID:String, backingContext: NSManagedObjectContext) {
        let changeSet = NSEntityDescription.insertNewObject(forEntityName: SMLocalStoreChangeSetEntityName, into: backingContext)
        changeSet.setValue(recordID, forKey: SMLocalStoreRecordIDAttributeName)
        changeSet.setValue(NSNumber(value: SMLocalStoreRecordChangeType.recordDeleted.rawValue), forKey: SMLocalStoreChangeTypeAttributeName)
    }
    
    // MARK: Fetch
    fileprivate func changeSets(ForChangeType changeType:SMLocalStoreRecordChangeType, propertiesToFetch: Array<String>,  backingContext: NSManagedObjectContext) throws -> [AnyObject]? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: SMLocalStoreChangeSetEntityName)
        let predicate: NSPredicate = NSPredicate(format: "%K == %@", SMLocalStoreChangeTypeAttributeName, NSNumber(value: changeType.rawValue))
        fetchRequest.predicate = predicate
        fetchRequest.resultType = NSFetchRequestResultType.dictionaryResultType
        fetchRequest.propertiesToFetch = propertiesToFetch
        let results = try backingContext.fetch(fetchRequest)
        return results
    }
    
    func recordIDsForDeletedObjects(_ backingContext: NSManagedObjectContext) throws -> [CKRecordID]? {
        let propertiesToFetch = [SMLocalStoreRecordIDAttributeName]
        let deletedObjectsChangeSets = try self.changeSets(ForChangeType: SMLocalStoreRecordChangeType.recordDeleted, propertiesToFetch: propertiesToFetch, backingContext: backingContext)
        if deletedObjectsChangeSets!.count > 0 {
            return deletedObjectsChangeSets!.map({ (object) -> CKRecordID in
                let valuesDictionary: Dictionary<String,NSObject> = object as! Dictionary<String,NSObject>
                let recordID: String = valuesDictionary[SMLocalStoreRecordIDAttributeName] as! String
                let cksRecordZoneID: CKRecordZoneID = CKRecordZoneID(zoneName: SMStoreCloudStoreCustomZoneName, ownerName: CKOwnerDefaultName)
                return CKRecordID(recordName: recordID, zoneID: cksRecordZoneID)
            })
        }
        return nil
    }
    
    func recordsForUpdatedObjects(backingContext context: NSManagedObjectContext) throws -> [CKRecord]? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: SMLocalStoreChangeSetEntityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@ || %K == %@", SMLocalStoreChangeTypeAttributeName, NSNumber(value: SMLocalStoreRecordChangeType.recordInserted.rawValue), SMLocalStoreChangeTypeAttributeName, NSNumber(value: SMLocalStoreRecordChangeType.recordUpdated.rawValue))
        let results = try context.fetch(fetchRequest)
        var ckRecords: [CKRecord] = [CKRecord]()
        if results.count > 0 {
            let recordIDSubstitution = "recordIDString"
            let predicate = NSPredicate(format: "%K == $recordIDString", SMLocalStoreRecordIDAttributeName)
            for result in results {
                result.setValue(NSNumber(value: true), forKey: SMLocalStoreChangeQueuedAttributeName)
                let entityName: String = result.value(forKey: SMLocalStoreEntityNameAttributeName) as! String
                let recordIDString: String = result.value(forKey: SMLocalStoreRecordIDAttributeName) as! String
                let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                fetchRequest.predicate = predicate.withSubstitutionVariables([recordIDSubstitution:recordIDString])
                fetchRequest.fetchLimit = 1
                let objects = try context.fetch(fetchRequest)
                if objects.count > 0 {
                    let object = objects.last!
                    let changedPropertyKeys = result.value(forKey: SMLocalStoreRecordChangedPropertiesAttributeName) as? String
                    var changedPropertyKeysArray: [String]?
                    if changedPropertyKeys != nil && changedPropertyKeys!.isEmpty == false {
                        if changedPropertyKeys!.range(of: ",") != nil {
                            changedPropertyKeysArray = changedPropertyKeys!.components(separatedBy: ",")
                        } else {
                            changedPropertyKeysArray = [changedPropertyKeys!]
                        }
                    }
                    let ckRecord = object.createOrUpdateCKRecord(usingValuesOfChangedKeys: changedPropertyKeysArray)
                    if ckRecord != nil {
                        ckRecords.append(ckRecord!)
                    }
                }
            }
        }
        try context.saveIfHasChanges()
        return ckRecords
    }

    func removeAllQueuedChangeSetsFromQueue(backingContext context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: SMLocalStoreChangeSetEntityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreChangeQueuedAttributeName, NSNumber(value: true))
        let results = try context.fetch(fetchRequest)
        for result in results {
            result.setValue(NSNumber(value: false), forKey: SMLocalStoreChangeQueuedAttributeName)
        }
        try context.saveIfHasChanges()
    }
    
    func removeAllQueuedChangeSets(backingContext context: NSManagedObjectContext) throws {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: SMLocalStoreChangeSetEntityName)
        fetchRequest.includesPropertyValues = false
        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreChangeQueuedAttributeName, NSNumber(value: true))
        let results = try context.fetch(fetchRequest)
        if results.count > 0 {
            for managedObject in results {
                context.delete(managedObject)
            }
            try context.saveIfHasChanges()
        }
    }
}
