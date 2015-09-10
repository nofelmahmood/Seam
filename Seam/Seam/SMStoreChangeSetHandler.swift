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
    
    func changedPropertyKeys(keys: [String], entity: NSEntityDescription) -> [String] {
        return keys.filter({ (key) -> Bool in
            let property = entity.propertiesByName[key]
            if property != nil && property is NSRelationshipDescription {
                let relationshipDescription: NSRelationshipDescription = property as! NSRelationshipDescription
                return relationshipDescription.toMany == false
            }
            return true
        })
    }
    
    func addExtraBackingStoreAttributes(toEntity entity: NSEntityDescription) {
        let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
        recordIDAttribute.name = SMLocalStoreRecordIDAttributeName
        recordIDAttribute.optional = false
        recordIDAttribute.indexed = true
        recordIDAttribute.attributeType = NSAttributeType.StringAttributeType
        entity.properties.append(recordIDAttribute)
        let recordEncodedValuesAttribute: NSAttributeDescription = NSAttributeDescription()
        recordEncodedValuesAttribute.name = SMLocalStoreRecordEncodedValuesAttributeName
        recordEncodedValuesAttribute.attributeType = NSAttributeType.BinaryDataAttributeType
        recordEncodedValuesAttribute.optional = true
        entity.properties.append(recordEncodedValuesAttribute)
    }
    
    func changeSetEntity() -> NSEntityDescription {
        let changeSetEntity: NSEntityDescription = NSEntityDescription()
        changeSetEntity.name = SMLocalStoreChangeSetEntityName
        let entityNameAttribute: NSAttributeDescription = NSAttributeDescription()
        entityNameAttribute.name = SMLocalStoreEntityNameAttributeName
        entityNameAttribute.attributeType = NSAttributeType.StringAttributeType
        entityNameAttribute.optional = true
        changeSetEntity.properties.append(entityNameAttribute)
        let recordIDAttribute: NSAttributeDescription = NSAttributeDescription()
        recordIDAttribute.name = SMLocalStoreRecordIDAttributeName
        recordIDAttribute.attributeType = NSAttributeType.StringAttributeType
        recordIDAttribute.optional = false
        recordIDAttribute.indexed = true
        changeSetEntity.properties.append(recordIDAttribute)
        let recordChangedPropertiesAttribute: NSAttributeDescription = NSAttributeDescription()
        recordChangedPropertiesAttribute.name = SMLocalStoreRecordChangedPropertiesAttributeName
        recordChangedPropertiesAttribute.attributeType = NSAttributeType.StringAttributeType
        recordChangedPropertiesAttribute.optional = true
        changeSetEntity.properties.append(recordChangedPropertiesAttribute)
        let recordChangeTypeAttribute: NSAttributeDescription = NSAttributeDescription()
        recordChangeTypeAttribute.name = SMLocalStoreChangeTypeAttributeName
        recordChangeTypeAttribute.attributeType = NSAttributeType.Integer16AttributeType
        recordChangeTypeAttribute.optional = false
        recordChangeTypeAttribute.defaultValue = NSNumber(short: SMLocalStoreRecordChangeType.RecordInserted.rawValue)
        changeSetEntity.properties.append(recordChangeTypeAttribute)
        let changeTypeQueuedAttribute: NSAttributeDescription = NSAttributeDescription()
        changeTypeQueuedAttribute.name = SMLocalStoreChangeQueuedAttributeName
        changeTypeQueuedAttribute.optional = false
        changeTypeQueuedAttribute.attributeType = NSAttributeType.BooleanAttributeType
        changeTypeQueuedAttribute.defaultValue = NSNumber(bool: false)
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
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(SMLocalStoreChangeSetEntityName, inManagedObjectContext: backingContext)
        changeSet.setValue(recordID, forKey: SMLocalStoreRecordIDAttributeName)
        changeSet.setValue(entityName, forKey: SMLocalStoreEntityNameAttributeName)
        changeSet.setValue(NSNumber(short: SMLocalStoreRecordChangeType.RecordInserted.rawValue), forKey: SMLocalStoreChangeTypeAttributeName)
    }
    
    func createChangeSet(ForUpdatedObject object: NSManagedObject, usingContext context: NSManagedObjectContext) {
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(SMLocalStoreChangeSetEntityName, inManagedObjectContext: context)
        let changedPropertyKeys = self.changedPropertyKeys(Array(object.changedValues().keys), entity: object.entity)
        let recordIDString: String = object.valueForKey(SMLocalStoreRecordIDAttributeName) as! String
        let changedPropertyKeysString = changedPropertyKeys.joinWithSeparator(",")
        changeSet.setValue(recordIDString, forKey: SMLocalStoreRecordIDAttributeName)
        changeSet.setValue(object.entity.name!, forKey: SMLocalStoreEntityNameAttributeName)
        changeSet.setValue(changedPropertyKeysString, forKey: SMLocalStoreRecordChangedPropertiesAttributeName)
        changeSet.setValue(NSNumber(short: SMLocalStoreRecordChangeType.RecordUpdated.rawValue), forKey: SMLocalStoreChangeTypeAttributeName)
    }
    
    func createChangeSet(ForDeletedObjectRecordID recordID:String, backingContext: NSManagedObjectContext) {
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(SMLocalStoreChangeSetEntityName, inManagedObjectContext: backingContext)
        changeSet.setValue(recordID, forKey: SMLocalStoreRecordIDAttributeName)
        changeSet.setValue(NSNumber(short: SMLocalStoreRecordChangeType.RecordDeleted.rawValue), forKey: SMLocalStoreChangeTypeAttributeName)
    }
    
    // MARK: Fetch
    private func changeSets(ForChangeType changeType:SMLocalStoreRecordChangeType, propertiesToFetch: Array<String>,  backingContext: NSManagedObjectContext) throws -> [AnyObject]? {
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: SMLocalStoreChangeSetEntityName)
        let predicate: NSPredicate = NSPredicate(format: "%K == %@", SMLocalStoreChangeTypeAttributeName, NSNumber(short: changeType.rawValue))
        fetchRequest.predicate = predicate
        fetchRequest.resultType = NSFetchRequestResultType.DictionaryResultType
        fetchRequest.propertiesToFetch = propertiesToFetch
        let results = try backingContext.executeFetchRequest(fetchRequest)
        return results
    }
    
    func recordIDsForDeletedObjects(backingContext: NSManagedObjectContext) throws -> [CKRecordID]? {
        let propertiesToFetch = [SMLocalStoreRecordIDAttributeName]
        let deletedObjectsChangeSets = try self.changeSets(ForChangeType: SMLocalStoreRecordChangeType.RecordDeleted, propertiesToFetch: propertiesToFetch, backingContext: backingContext)
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
        let fetchRequest = NSFetchRequest(entityName: SMLocalStoreChangeSetEntityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@ || %K == %@", SMLocalStoreChangeTypeAttributeName, NSNumber(short: SMLocalStoreRecordChangeType.RecordInserted.rawValue), SMLocalStoreChangeTypeAttributeName, NSNumber(short: SMLocalStoreRecordChangeType.RecordUpdated.rawValue))
        let results = try context.executeFetchRequest(fetchRequest)
        var ckRecords: [CKRecord] = [CKRecord]()
        if results.count > 0 {
            let recordIDSubstitution = "recordIDString"
            let predicate = NSPredicate(format: "%K == $recordIDString", SMLocalStoreRecordIDAttributeName)
            for result in results as! [NSManagedObject] {
                result.setValue(NSNumber(bool: true), forKey: SMLocalStoreChangeQueuedAttributeName)
                let entityName: String = result.valueForKey(SMLocalStoreEntityNameAttributeName) as! String
                let recordIDString: String = result.valueForKey(SMLocalStoreRecordIDAttributeName) as! String
                let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: entityName)
                fetchRequest.predicate = predicate.predicateWithSubstitutionVariables([recordIDSubstitution:recordIDString])
                fetchRequest.fetchLimit = 1
                let objects = try context.executeFetchRequest(fetchRequest)
                if objects.count > 0 {
                    let object: NSManagedObject = objects.last as! NSManagedObject
                    let changedPropertyKeys = result.valueForKey(SMLocalStoreRecordChangedPropertiesAttributeName) as? String
                    var changedPropertyKeysArray: [String]?
                    if changedPropertyKeys != nil && changedPropertyKeys!.isEmpty == false {
                        if changedPropertyKeys!.rangeOfString(",") != nil {
                            changedPropertyKeysArray = changedPropertyKeys!.componentsSeparatedByString(",")
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
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: SMLocalStoreChangeSetEntityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreChangeQueuedAttributeName, NSNumber(bool: true))
        let results = try context.executeFetchRequest(fetchRequest)
        for result in results as! [NSManagedObject] {
            result.setValue(NSNumber(bool: false), forKey: SMLocalStoreChangeQueuedAttributeName)
        }
        try context.saveIfHasChanges()
    }
    
    func removeAllQueuedChangeSets(backingContext context: NSManagedObjectContext) throws {
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: SMLocalStoreChangeSetEntityName)
        fetchRequest.includesPropertyValues = false
        fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreChangeQueuedAttributeName, NSNumber(bool: true))
        let results = try context.executeFetchRequest(fetchRequest)
        if results.count > 0 {
            for managedObject in results as! [NSManagedObject] {
                context.deleteObject(managedObject)
            }
            try context.saveIfHasChanges()
        }
    }
}