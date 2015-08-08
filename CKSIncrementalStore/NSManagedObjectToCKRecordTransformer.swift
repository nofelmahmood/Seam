//
//  NSManagedObjectToCKRecordTransformer.swift
//  
//
//  Created by Nofel Mahmood on 07/08/2015.
//
//

import UIKit
import CoreData
import CloudKit


extension CKRecord
{
    func allAttributeValuesAsManagedObjectAttributeValues(usingContext context: NSManagedObjectContext) -> [String:AnyObject]?
    {
        return self.dictionaryWithValuesForKeys(self.attributeKeys())
    }
    
    func allCKReferencesAsManagedObjects(usingContext context: NSManagedObjectContext) -> [String:NSManagedObject]?
    {
        let entity = context.persistentStoreCoordinator?.managedObjectModel.entitiesByName[self.recordType]
        if entity != nil
        {
            let referencesValuesDictionary = self.dictionaryWithValuesForKeys(self.referencesKeys())
            var managedObjectsDictionary: Dictionary<String,NSManagedObject> = Dictionary<String,NSManagedObject>()
            for (key,value) in referencesValuesDictionary
            {
                let relationshipDescription = entity!.relationshipsByName[key]
                if relationshipDescription?.destinationEntity?.name != nil
                {
                    let recordIDString = (value as! CKReference).recordID.recordName
                    let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: relationshipDescription!.destinationEntity!.name!)
                    fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName,recordIDString)
                    fetchRequest.fetchLimit = 1
                    do
                    {
                        let results = try context.executeFetchRequest(fetchRequest)
                        if results.count > 0
                        {
                            let relationshipManagedObject: NSManagedObject = results.last as! NSManagedObject
                            managedObjectsDictionary[key] = relationshipManagedObject
                        }
                        
                    }
                    catch
                    {
                        print("Failed to find relationship managed object for Key \(key) RecordID \(recordIDString)", appendNewline: true)
                    }
                }
            }
            return managedObjectsDictionary
        }
        return nil
    }
    
    func createOrUpdateManagedObject(usingContext context: NSManagedObjectContext)
    {
        
    }
}

extension NSManagedObject
{
    func ckRecord()
    {
        
    }
}