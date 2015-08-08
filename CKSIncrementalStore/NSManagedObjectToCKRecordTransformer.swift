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

extension NSManagedObjectContext
{
    func saveIfHasChanges() throws
    {
        if self.hasChanges
        {
            try self.save()
        }
    }
}

extension CKRecord
{
    private func allAttributeValuesAsManagedObjectAttributeValues(usingContext context: NSManagedObjectContext) -> [String:AnyObject]?
    {
        return self.dictionaryWithValuesForKeys(self.attributeKeys())
    }
    
    private func allCKReferencesAsManagedObjects(usingContext context: NSManagedObjectContext) -> [String:NSManagedObject]?
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
    
    public func createOrUpdateManagedObjectFromRecord(usingContext context: NSManagedObjectContext) throws
    {
        let entity = context.persistentStoreCoordinator?.managedObjectModel.entitiesByName[self.recordType]
        if entity?.name != nil
        {
            var managedObject: NSManagedObject?
            let recordIDString = self.recordID.recordName
            let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: entity!.name!)
            fetchRequest.fetchLimit = 1
            fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName, recordIDString)
            
            let setValuesOfManagedObject = ({(managedObject: NSManagedObject?) -> Void in
                
                if managedObject != nil
                {
                    let attributeValuesDictionary = self.allAttributeValuesAsManagedObjectAttributeValues(usingContext: context)
                    if attributeValuesDictionary != nil
                    {
                        managedObject!.setValuesForKeysWithDictionary(attributeValuesDictionary!)
                    }
                    let referencesValuesDictionary = self.allCKReferencesAsManagedObjects(usingContext: context)
                    if referencesValuesDictionary != nil
                    {
                        managedObject!.setValuesForKeysWithDictionary(referencesValuesDictionary!)
                    }
                }
            })
            
            do
            {
                let results = try context.executeFetchRequest(fetchRequest)
                if results.count > 0
                {
                    managedObject = results.last as? NSManagedObject
                }
                else
                {
                    managedObject = NSEntityDescription.insertNewObjectForEntityForName(entity!.name!, inManagedObjectContext: context)
                }
                
                setValuesOfManagedObject(managedObject)
            }
            catch let error as NSError?
            {
                print("Error executing request for fetching managed object \(error!)", appendNewline: true)
                setValuesOfManagedObject(managedObject)
            }
        }
        
        try context.saveIfHasChanges()
    }
}

extension NSManagedObject
{
    
}