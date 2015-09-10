//    CKRecord+NSManagedObject.swift
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

extension CKRecord {
    
    func allAttributeKeys(usingAttributesByNameFromEntity attributesByName: [String:NSAttributeDescription]) -> [String] {
        return self.allKeys().filter({ (key) -> Bool in
            return attributesByName[key] != nil
        })
    }
    
    func allReferencesKeys(usingRelationshipsByNameFromEntity relationshipsByName: [String:NSRelationshipDescription]) -> [String] {
        return self.allKeys().filter({ (key) -> Bool in
            return relationshipsByName[key] != nil
        })
    }
    
    class func recordWithEncodedFields(encodedFields: NSData) -> CKRecord {
        let coder = NSKeyedUnarchiver(forReadingWithData: encodedFields)
        let record: CKRecord = CKRecord(coder: coder)!
        coder.finishDecoding()
        return record
    }
    
    func encodedSystemFields() -> NSData {
        let data = NSMutableData()
        let coder = NSKeyedArchiver(forWritingWithMutableData: data)
        self.encodeSystemFieldsWithCoder(coder)
        coder.finishEncoding()
        return data
    }
    
    private func allAttributeValuesAsManagedObjectAttributeValues(usingContext context: NSManagedObjectContext) -> [String:AnyObject]? {
        let entity = context.persistentStoreCoordinator?.managedObjectModel.entitiesByName[self.recordType]
        return self.dictionaryWithValuesForKeys(self.allAttributeKeys(usingAttributesByNameFromEntity: entity!.attributesByName))
    }
    
    private func allCKReferencesAsManagedObjects(usingContext context: NSManagedObjectContext) -> [String:AnyObject]? {
        // Fix it : Need to fix relationships. No relationships are being saved at the moment
        let entity = context.persistentStoreCoordinator?.managedObjectModel.entitiesByName[self.recordType]
        if entity != nil {
            let referencesValuesDictionary = self.dictionaryWithValuesForKeys(self.allReferencesKeys(usingRelationshipsByNameFromEntity: entity!.relationshipsByName))
            var managedObjectsDictionary: Dictionary<String,AnyObject> = Dictionary<String,AnyObject>()
            for (key,value) in referencesValuesDictionary {
                if (value as? String) != nil && (value as! String) == SMCloudRecordNilValue {
                    managedObjectsDictionary[key] = SMCloudRecordNilValue
                    continue
                }
                let relationshipDescription = entity!.relationshipsByName[key]
                if relationshipDescription?.destinationEntity?.name != nil {
                    let recordIDString = (value as! CKReference).recordID.recordName
                    let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: relationshipDescription!.destinationEntity!.name!)
                    fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName,recordIDString)
                    fetchRequest.fetchLimit = 1
                    do {
                        let results = try context.executeFetchRequest(fetchRequest)
                        if results.count > 0 {
                            let relationshipManagedObject: NSManagedObject = results.last as! NSManagedObject
                            managedObjectsDictionary[key] = relationshipManagedObject
                        }
                    } catch {
                        print("Failed to find relationship managed object for Key \(key) RecordID \(recordIDString)", terminator: "\n")
                    }
                }
            }
            return managedObjectsDictionary
        }
        return nil
    }
    
    public func createOrUpdateManagedObjectFromRecord(usingContext context: NSManagedObjectContext) throws -> NSManagedObject? {
        
        let entity = context.persistentStoreCoordinator?.managedObjectModel.entitiesByName[self.recordType]
        if entity?.name != nil {
            var managedObject: NSManagedObject?
            let recordIDString = self.recordID.recordName
            let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: entity!.name!)
            fetchRequest.fetchLimit = 1
            fetchRequest.predicate = NSPredicate(format: "%K == %@", SMLocalStoreRecordIDAttributeName, recordIDString)
            let results = try context.executeFetchRequest(fetchRequest)
            if results.count > 0 {
                managedObject = results.last as? NSManagedObject
                if managedObject != nil {
                    managedObject!.setValue(self.encodedSystemFields(), forKey: SMLocalStoreRecordEncodedValuesAttributeName)
                    let attributeValuesDictionary = self.allAttributeValuesAsManagedObjectAttributeValues(usingContext: context)
                    if attributeValuesDictionary != nil {
                        managedObject!.setValuesForKeysWithDictionary(attributeValuesDictionary!)
                    }
                    let referencesValuesDictionary = self.allCKReferencesAsManagedObjects(usingContext: context)
                    if referencesValuesDictionary != nil {
                        for (key,value) in referencesValuesDictionary! {
                            if (value as? String) != nil && (value as! String) == SMCloudRecordNilValue {
                                managedObject!.setValue(nil, forKey: key)
                            } else {
                                managedObject!.setValue(value, forKey: key)
                            }
                        }
                    }
                }
            } else {
                managedObject = NSEntityDescription.insertNewObjectForEntityForName(entity!.name!, inManagedObjectContext: context)
                if managedObject != nil {
                    managedObject!.setValue(recordIDString, forKey: SMLocalStoreRecordIDAttributeName)
                    managedObject!.setValue(self.encodedSystemFields(), forKey: SMLocalStoreRecordEncodedValuesAttributeName)
                    let attributeValuesDictionary = self.allAttributeValuesAsManagedObjectAttributeValues(usingContext: context)
                    if attributeValuesDictionary != nil {
                        managedObject!.setValuesForKeysWithDictionary(attributeValuesDictionary!)
                    }
                    let referencesValuesDictionary = self.allCKReferencesAsManagedObjects(usingContext: context)
                    if referencesValuesDictionary != nil {
                        for (key,value) in referencesValuesDictionary! {
                            if (value as? String) != nil && (value as! String) == SMCloudRecordNilValue {
                                managedObject!.setValue(nil, forKey: key)
                            } else {
                                managedObject!.setValue(value, forKey: key)
                            }
                        }
                    }
                }
            }
            return managedObject
        }
        return nil
    }
}
