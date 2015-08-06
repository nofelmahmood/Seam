//    CKSIncrementalStoreChangeSetHandler.swift
//
//    The MIT License (MIT)
//
//    Copyright (c) 2015 Nofel Mahmood (https://twitter.com/NofelMahmood)
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


import UIKit
import CoreData
import CloudKit

class CKSIncrementalStoreChangeSetHandler {

    static let defaultHandler = CKSIncrementalStoreChangeSetHandler()
    
    // MARK: Creation
    class func createChangeSet(ForInsertedObjectRecordID recordID: String, entityName: String, backingContext: NSManagedObjectContext)
    {
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(CKSChangeSetEntityName, inManagedObjectContext: backingContext)
        changeSet.setValue(recordID, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        changeSet.setValue(entityName, forKey: CKSIncrementalStoreLocalStoreEntityNameAttributeName)
        changeSet.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordInserted.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
    }
    
    class func createChangeSet(ForUpdatedObjectRecordID recordID: String, changedPropertiesKeys: Array<String>, entityName: String, backingContext: NSManagedObjectContext)
    {
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(CKSChangeSetEntityName, inManagedObjectContext: backingContext)
        let changedPropertyKeysString = ",".join(changedPropertiesKeys)
        changeSet.setValue(recordID, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        changeSet.setValue(changedPropertyKeysString, forKey: CKSIncrementalStoreLocalStoreRecordChangedPropertiesAttributeName)
        changeSet.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordUpdated.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
    }
    
    class func createChangeSet(ForDeletedObjectRecordID recordID:String, backingContext: NSManagedObjectContext)
    {
        let changeSet = NSEntityDescription.insertNewObjectForEntityForName(CKSChangeSetEntityName, inManagedObjectContext: backingContext)
        changeSet.setValue(recordID, forKey: CKSIncrementalStoreLocalStoreRecordIDAttributeName)
        changeSet.setValue(NSNumber(short: CKSLocalStoreRecordChangeType.RecordDeleted.rawValue), forKey: CKSIncrementalStoreLocalStoreChangeTypeAttributeName)
    }
    
    // MARK: Fetch
    private func updatedRecords(backingContext: NSManagedObjectContext) throws -> [CKRecord]?
    {
        
    }
    
    private func insertedRecords(backingContext: NSManagedObjectContext) throws -> [CKRecord]?
    {
        
    }
    
    private func recordIDsForDeletedObjects(backingContext: NSManagedObjectContext) throws -> [CKRecordID]?
    {
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: CKSChangeSetEntityName)
        let predicate: NSPredicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreChangeTypeAttributeName, NSNumber(short: CKSLocalStoreRecordChangeType.RecordDeleted.rawValue))
        fetchRequest.predicate = predicate
        fetchRequest.resultType = NSFetchRequestResultType.DictionaryResultType
        fetchRequest.propertiesToFetch = [CKSIncrementalStoreLocalStoreRecordIDAttributeName]
        let results = try backingContext.executeFetchRequest(fetchRequest)
        if results.count > 0
        {
            return results.map({ (object) -> CKRecordID in
                
                let valuesDictionary: Dictionary<String,NSObject> = object as! Dictionary<String,NSObject>
                let recordID: String = valuesDictionary[CKSIncrementalStoreLocalStoreRecordIDAttributeName] as! String
                let cksRecordZoneID: CKRecordZoneID = CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName)
                return CKRecordID(recordName: recordID, zoneID: cksRecordZoneID)
            })
        }
        
        return nil
    }
    
    func localChangesInCKRepresentation() -> (insertedOrUpdatedCKRecords: [CKRecord]?, deletedCKRecordIDs: [CKRecordID]?)
    {
        
    }
    
    func removeAllChangeSets(backingContext: NSManagedObjectContext) throws
    {
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: CKSChangeSetEntityName)
        let results = try backingContext.executeFetchRequest(fetchRequest)
        if results.count > 0
        {
            for result in results
            {
                let managedObject: NSManagedObject = result as! NSManagedObject
                backingContext.deleteObject(managedObject)
            }
            
            if backingContext.hasChanges
            {
                try backingContext.save()
            }
        }
    }
    


}




