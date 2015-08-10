//    Transformers.swift
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
    
    public func createOrUpdateManagedObjectFromRecord(usingContext context: NSManagedObjectContext) throws -> NSManagedObject?
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
            try context.saveIfHasChanges()
            return managedObject
        }
        return nil
    }
}

extension NSEntityDescription
{
    func toOneRelationships() -> [NSRelationshipDescription]
    {
        return self.relationshipsByName.values.array.filter({ (relationshipDescription) -> Bool in
            return relationshipDescription.toMany == false
        })
    }
    
    func toOneRelationshipsByName() -> [String:NSRelationshipDescription]
    {
        var relationshipsByNameDictionary: Dictionary<String,NSRelationshipDescription> = Dictionary<String,NSRelationshipDescription>()
        for (key,value) in self.relationshipsByName
        {
            if value.toMany == true
            {
                continue
            }
            
            relationshipsByNameDictionary[key] = value
        }
        return relationshipsByNameDictionary
    }
}

extension NSManagedObject
{
    private func setAllAttributesValuesAsCKRecordAttributeValues(ofCKRecord ckRecord:CKRecord)
    {
        let attributes = self.entity.attributesByName.keys.array
        let valuesDictionary = self.dictionaryWithValuesForKeys(attributes)
        for (key,_) in valuesDictionary
        {
            let attributeDescription = self.entity.attributesByName[key]
            if attributeDescription != nil
            {
                switch(attributeDescription!.attributeType)
                {
                case .StringAttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! String, forKey: attributeDescription!.name)
                    
                case .DateAttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSDate, forKey: attributeDescription!.name)
                    
                case .BinaryDataAttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSData, forKey: attributeDescription!.name)
                    
                case .BooleanAttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSNumber, forKey: attributeDescription!.name)
                    
                case .DecimalAttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSNumber, forKey: attributeDescription!.name)
                    
                case .DoubleAttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSNumber, forKey: attributeDescription!.name)
                    
                case .FloatAttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSNumber, forKey: attributeDescription!.name)
                    
                case .Integer16AttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSNumber, forKey: attributeDescription!.name)
                    
                case .Integer32AttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSNumber, forKey: attributeDescription!.name)
                    
                case .Integer64AttributeType:
                    ckRecord.setObject(self.valueForKey(attributeDescription!.name) as! NSNumber, forKey: attributeDescription!.name)
                default:
                    break
                }
            }
            
        }
    }
    
    private func setAllRelationshipsAsCKReferences(ofCKRecord ckRecord: CKRecord)
    {
        let relationships = self.entity.toOneRelationships()
        for relationship in relationships
        {
            let relationshipManagedObject = self.valueForKey(relationship.name)
            if relationshipManagedObject != nil
            {
                let recordIDString: String = self.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
                let ckRecordZoneID: CKRecordZoneID = CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName)
                let ckRecordID: CKRecordID = CKRecordID(recordName: recordIDString, zoneID: ckRecordZoneID)
                let ckReference: CKReference = CKReference(recordID: ckRecordID, action: CKReferenceAction.DeleteSelf)
                ckRecord.setObject(ckReference, forKey: relationship.name)
            }
        }
    }
    
    public func createOrUpdateCKRecord(usingEncodedFields encodedFields: NSData?) -> CKRecord?
    {
        var ckRecord: CKRecord?
        if encodedFields != nil
        {
            ckRecord = CKRecord.recordWithEncodedFields(encodedFields!)
        }
        else
        {
            let recordIDString = self.valueForKey(CKSIncrementalStoreLocalStoreRecordIDAttributeName) as! String
            let ckRecordZoneID: CKRecordZoneID = CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName)
            let ckRecordID: CKRecordID = CKRecordID(recordName: recordIDString, zoneID: ckRecordZoneID)
            ckRecord = CKRecord(recordType: self.entity.name!, recordID: ckRecordID)
        }
        self.setAllAttributesValuesAsCKRecordAttributeValues(ofCKRecord: ckRecord!)
        self.setAllRelationshipsAsCKReferences(ofCKRecord: ckRecord!)
        return ckRecord
    }
}