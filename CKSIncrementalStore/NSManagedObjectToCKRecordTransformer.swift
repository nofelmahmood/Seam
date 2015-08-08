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
    func managedObject(usingContext context: NSManagedObjectContext) throws -> NSManagedObject
    {
        let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: self.recordType)
        fetchRequest.fetchLimit = 1
        fetchRequest.predicate = NSPredicate(format: "%K == %@", CKSIncrementalStoreLocalStoreRecordIDAttributeName, self.recordID.recordName)
        let results = try context.executeFetchRequest(fetchRequest)
        let managedObject: NSManagedObject?
        if results.count > 0
        {
            managedObject = results.last as! NSManagedObject
        }
        else
        {
            managedObject = NSEntityDescription.insertNewObjectForEntityForName(self.recordType, inManagedObjectContext: context)
        }
        
        let valuesDictionary = self.dictionaryWithValuesForKeys(self.allKeys())        
        for (key,value) in valuesDictionary
        {
            
        }
    }
}

extension NSManagedObject
{
    func ckRecord()
    {
        
    }
}