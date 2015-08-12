//    CKSIncrementalStoreChangeSetHandler.swift
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

class CKSIncrementalStoreChangeSetHandler {

    static let defaultHandler = CKSIncrementalStoreChangeSetHandler()
    
    func changedPropertyKeys(keys: [String], entity: NSEntityDescription) -> [String]
    {
        return keys.filter({ (key) -> Bool in
            
            let property = entity.propertiesByName[key]
            if property != nil && property is NSRelationshipDescription
            {
                let relationshipDescription: NSRelationshipDescription = property as! NSRelationshipDescription
                return relationshipDescription.toMany == false
            }
            return true
        })
    }
    
    // MARK: Creation
    func createChangeSet(ForInsertedObjectRecordID recordID: String, entityName: String, backingContext: NSManagedObjectContext)
    {
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(CKSChangeSetEntityName, inManagedObjectContext: backingContext)
        changeSet.setValue(recordID, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        changeSet.setValue(entityName, forKey: CKSIncrementalStoreLocalStoreEntityNameAttributeName)
        changeSet.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordInserted.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
    }
    
    func createChangeSet(ForUpdatedObject object: NSManagedObject, usingContext context: NSManagedObjectContext)
    {
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(CKSChangeSetEntityName, inManagedObjectContext: context)
        let changedPropertyKeys = self.changedPropertyKeys(object.changedValues().keys.array, entity: object.entity)
        let recordIDString: String = object.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
        let changedPropertyKeysString = ",".join(changedPropertyKeys)
        changeSet.setValue(recordIDString, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        changeSet.setValue(changedPropertyKeysString, forKey: CKSIncrementalStoreLocalStoreRecordChangedPropertiesAttributeName)
        changeSet.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordUpdated.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
    }
    
    func createChangeSet(ForDeletedObjectRecordID recordID:String, backingContext: NSManagedObjectContext)
    {
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(CKSChangeSetEntityName, inManagedObjectContext: backingContext)
        changeSet.setValue(recordID, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        changeSet.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordDeleted.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
    }
    
    // MARK: Fetch
    private func changeSets(ForChangeType changeType:CKSLocalStoreRecordChangeType, propertiesToFetch: Array<String>,  backingContext: NSManagedObjectContext) throws -> [AnyObject]?
    {
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: CKSChangeSetEntityName)
        let predicate: NSPredicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreChangeTypeAttributeName, NSNumber(short: changeType.rawValue))
        fetchRequest.predicate = predicate
        fetchRequest.resultType = NSFetchRequestResultType.DictionaryResultType
        fetchRequest.propertiesToFetch = propertiesToFetch
        
        let results = try backingContext.executeFetchRequest(fetchRequest)
        
        return results
    }
    
    private func recordIDsForDeletedObjects(backingContext: NSManagedObjectContext) throws -> [CKRecordID]?
    {
        let propertiesToFetch = [CKSIncrementalStoreLocalStoreRecordIDAttributeName]
        let deletedObjectsChangeSets = try self.changeSets(ForChangeType: CKSLocalStoreRecordChangeType.RecordDeleted, propertiesToFetch: propertiesToFetch, backingContext: backingContext)
        
        if deletedObjectsChangeSets!.count > 0
        {
            return deletedObjectsChangeSets!.map({ (object) -> CKRecordID in
                
                let valuesDictionary: Dictionary<String,NSObject> = object as! Dictionary<String,NSObject>
                let recordID: String = valuesDictionary[CKSIncrementalStoreLocalStoreRecordIDAttributeName] as! String
                let cksRecordZoneID: CKRecordZoneID = CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName)
                return CKRecordID(recordName: recordID, zoneID: cksRecordZoneID)
            })
        }
        
        return nil
    }
    
    private func recordsForUpdatedObjects(backingContext context: NSManagedObjectContext) throws -> [CKRecord]?
    {
        let fetchRequest = NSFetchRequest(entityName: CKSChangeSetEntityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@ || %K == %@", CKSIncrementalStoreLocalStoreChangeTypeAttributeName, NSNumber(short: CKSLocalStoreRecordChangeType.RecordInserted.rawValue), CKSIncrementalStoreLocalStoreChangeTypeAttributeName, NSNumber(short: CKSLocalStoreRecordChangeType.RecordUpdated.rawValue))
        
        let results = try context.executeFetchRequest(fetchRequest)
        var ckRecords: [CKRecord] = [CKRecord]()
        
        if results.count > 0
        {
            let recordIDSubstitution = "recordIDString"
            let predicate = NSPredicate(format: "%K == $recordIDString", CKSIncrementalStoreLocalStoreRecordIDAttributeName)
            
            for result in results as! [NSManagedObject]
            {
                result.setValue(NSNumber(bool: true), forKey: CKSIncrementalStoreLocalStoreChangeQueuedAttributeName)
                let entityName: String = result.valueForKey(CKSIncrementalStoreLocalStoreEntityNameAttributeName) as! String
                let recordIDString: String = result.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: entityName)
                fetchRequest.predicate = predicate.predicateWithSubstitutionVariables([recordIDSubstitution:recordIDString])
                fetchRequest.fetchLimit = 1
                let objects = try context.executeFetchRequest(fetchRequest)
                if objects.count > 0
                {
                    let object: NSManagedObject = objects.last as! NSManagedObject
                    let changedPropertyKeys = result.valueForKey(CKSIncrementalStoreLocalStoreRecordChangedPropertiesAttributeName) as! String
                    var changedPropertyKeysArray: [String]?
                    if changedPropertyKeys.isEmpty == false
                    {
                        changedPropertyKeysArray = changedPropertyKeys.componentsSeparatedByString(",")
                    }
                    let ckRecord = object.createOrUpdateCKRecord(usingValuesOfChangedKeys: changedPropertyKeysArray)
                    if ckRecord != nil
                    {
                        ckRecords.append(ckRecord!)
                    }
                }
            }
        }
        try context.saveIfHasChanges()
        return ckRecords
    }

    func removeAllQueuedChangeSetsFromQueue(backingContext context: NSManagedObjectContext) throws
    {
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: CKSChangeSetEntityName)
        fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreChangeQueuedAttributeName, NSNumber(bool: true))
        let results = try context.executeFetchRequest(fetchRequest)
        
        for result in results as! [NSManagedObject]
        {
            result.setValue(NSNumber(bool: false), forKey: CKSIncrementalStoreLocalStoreChangeQueuedAttributeName)
        }
        
        try context.saveIfHasChanges()
    }
    
    func removeAllQueuedChangeSets(backingContext context: NSManagedObjectContext) throws
    {
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: CKSChangeSetEntityName)
        fetchRequest.includesPropertyValues = false
        fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreChangeQueuedAttributeName, NSNumber(bool: true))
        let results = try context.executeFetchRequest(fetchRequest)
        
        if results.count > 0
        {
            for result in results
            {
                let managedObject: NSManagedObject = result as! NSManagedObject
                context.deleteObject(managedObject)
            }
            
            try context.saveIfHasChanges()
        }
    }
}




