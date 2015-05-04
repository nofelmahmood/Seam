//
//  CloudKitIncrementalStore.swift
//  
//
//  Created by Nofel Mahmood on 26/03/2015.
//
//

import CoreData
import CloudKit
import ObjectiveC

let CKSStoreType="CloudKitStoreType"
let CKSStoreDefaultDatabaseType="CloudKitStoreDefaultDatabaseType"
enum CloudKitStoreDatabaseType
{
    case Public,Private
}
class CKSIncrementalStore: NSIncrementalStore {
    
    lazy var cachedValues:NSMutableDictionary={
        return NSMutableDictionary()
    }()
    lazy var operationQueue:NSOperationQueue={
        
        return NSOperationQueue()
    }()
    
    override class func initialize()
    {
        NSPersistentStoreCoordinator.registerStoreClass(self, forStoreType: self.type)
    }
    
    class var type:String{
        return NSStringFromClass(self)
    }
    
    override func loadMetadata(error: NSErrorPointer) -> Bool {
        
//        var storeURL=self.URL
        self.metadata=[
            NSStoreUUIDKey:NSProcessInfo().globallyUniqueString,
            NSStoreTypeKey:self.dynamicType.type
        ]
//        var model:NSManagedObjectModel!=self.persistentStoreCoordinator?.managedObjectModel.copy() as! NSManagedObjectModel
//        
//        
//        for entity in model.entities
//        {
//            if entity.superentity==true
//            {
//                continue
//            }
//            var enDes:NSEntityDescription=entity as! NSEntityDescription
//            var lastModifiedAttributeDesc:NSAttributeDescription=NSAttributeDescription()
//            lastModifiedAttributeDesc.name="lastModifiedDate"
//            lastModifiedAttributeDesc.attributeType=NSAttributeType.DateAttributeType
//            lastModifiedAttributeDesc.indexed=true
//            
//            var creationAttributeDesc:NSAttributeDescription=NSAttributeDescription()
//            creationAttributeDesc.name="createdDate"
//            creationAttributeDesc.attributeType=NSAttributeType.DateAttributeType
//            creationAttributeDesc.indexed=true
//            
//            enDes.properties.append(lastModifiedAttributeDesc)
//            enDes.properties.append(creationAttributeDesc)
//
//        }
        return true
    }
    override func executeRequest(request: NSPersistentStoreRequest, withContext context: NSManagedObjectContext, error: NSErrorPointer) -> AnyObject? {
        
        
        if request.requestType==NSPersistentStoreRequestType.FetchRequestType
        {
            var fetchRequest:NSFetchRequest=request as! NSFetchRequest
            return self.executeInResponseToFetchRequest(fetchRequest, context: context, error: error)
        }
        else if request.requestType==NSPersistentStoreRequestType.SaveRequestType
        {
            var saveChangesRequest:NSSaveChangesRequest=request as! NSSaveChangesRequest
            return self.executeInResponseToSaveChangesRequest(saveChangesRequest, context: context, error: error)
        }
        else if request.requestType==NSPersistentStoreRequestType.BatchUpdateRequestType
        {
            var batchUpdateRequest:NSBatchUpdateRequest=request as! NSBatchUpdateRequest
            return self.executeInResponseToBatchUpdateRequest(batchUpdateRequest, context: context, error: error)
        }
        return nil
    }
    override func newValuesForObjectWithID(objectID: NSManagedObjectID, withContext context: NSManagedObjectContext, error: NSErrorPointer) -> NSIncrementalStoreNode? {
        
        var uniqueIdentifier:NSString=self.identifier(objectID) as! NSString
        var object:CKRecord=self.cachedValues.objectForKey(uniqueIdentifier) as! CKRecord
        var keys:NSArray=object.allKeys() as NSArray
        var values:NSMutableDictionary=NSMutableDictionary()
        for key in keys
        {
            values.setValue(object.objectForKey(key as! String), forKey: key as! String)
        }
        var incrementalStoreNode:NSIncrementalStoreNode=NSIncrementalStoreNode(objectID: objectID, withValues: values as [NSObject : AnyObject], version: 1)
        return incrementalStoreNode
    }
//    override func obtainPermanentIDsForObjects(array: [AnyObject], error: NSErrorPointer) -> [AnyObject]? {
//        
//
//    }
    // MARK : Request Methods
    func executeInResponseToFetchRequest(fetchRequest:NSFetchRequest,context:NSManagedObjectContext,error:NSErrorPointer)->NSArray
    {
        var ckOperation:CKQueryOperation=self.cloudKitRequestOperationFromFetchRequest(fetchRequest, context: context) as! CKQueryOperation
        
        var record:CKRecord?
        var results:NSMutableArray=NSMutableArray()
        ckOperation.recordFetchedBlock=({ (record) -> Void in
            
            var ckRecord:CKRecord=record!
            var objectID=self.objectID(ckRecord.recordID.recordName, entity: fetchRequest.entity!)
            self.cachedValues.setObject(ckRecord, forKey: ckRecord.recordID.recordName)
            var object=context.objectWithID(objectID)
            results.addObject(object)
        })
        
        self.operationQueue.addOperation(ckOperation)
        self.operationQueue.waitUntilAllOperationsAreFinished()
        return results

    }
    func executeInResponseToSaveChangesRequest(saveRequest:NSSaveChangesRequest,context:NSManagedObjectContext,error:NSErrorPointer)->NSArray
    {
        var insertedObjects=saveRequest.insertedObjects
        var updatedObjects=saveRequest.updatedObjects
        var deletedObjects=saveRequest.deletedObjects
        
        
        
        return NSArray()
    }
    func executeInResponseToBatchUpdateRequest(batchUpdateRequest:NSBatchUpdateRequest,context:NSManagedObjectContext,error:NSErrorPointer)->NSArray
    {
        return NSArray()
    }
    override func obtainPermanentIDsForObjects(array: [AnyObject], error: NSErrorPointer) -> [AnyObject]? {
        
        var objectIDs:NSMutableArray=NSMutableArray()
        
        for managedObject in array
        {
            var mObj:NSManagedObject=managedObject as! NSManagedObject
            objectIDs.addObject(self.objectID(NSUUID().UUIDString, entity: mObj.entity))
        }
        
        return objectIDs as [AnyObject]
    }
    // MARK : Mapping Methods

    func cloudKitModifyRecordsOperationFromSaveChangesRequest(saveChangesRequest:NSSaveChangesRequest,context:NSManagedObjectContext)->NSOperation
    {
        return NSOperation()
    }
    func cloudKitRequestOperationFromFetchRequest(fetchRequest:NSFetchRequest,context:NSManagedObjectContext)->NSOperation
    {
        var requestPredicate:NSPredicate=NSPredicate(value: true)
        if (fetchRequest.predicate != nil)
        {
            requestPredicate=fetchRequest.predicate!
        }
        
        var query:CKQuery=CKQuery(recordType: fetchRequest.entityName, predicate: requestPredicate)
        if (fetchRequest.sortDescriptors != nil)
        {
            query.sortDescriptors=fetchRequest.sortDescriptors!
        }
        
        var queryOperation:CKQueryOperation=CKQueryOperation(query: query)
        queryOperation.resultsLimit=fetchRequest.fetchLimit
        if (fetchRequest.propertiesToFetch != nil)
        {
            queryOperation.desiredKeys=fetchRequest.propertiesToFetch
        }
        queryOperation.database=CKContainer.defaultContainer().privateCloudDatabase
        return queryOperation
    }
    
    func ckRecordFromManagedObject(managedObject:NSManagedObject)->CKRecord
    {
        var identifier:NSString=self.identifier(managedObject.objectID) as! NSString
        var recordID:CKRecordID=CKRecordID(recordName: identifier as String)
        var record:CKRecord=CKRecord(recordType: managedObject.entity.name, recordID: recordID)

        var attributes:NSDictionary=managedObject.entity.attributesByName as NSDictionary
        
        for key in attributes.allKeys
        {
//            var key:String=key as! String
//            
//            managedObject.dynamicType
//            var valueForKey: AnyObject?=managedObject.valueForKey(key)
//            record.setObject(valueForKey as! NSString, forKey: key)
        
        }
        return record
        
    }
    func identifier(objectID:NSManagedObjectID)->AnyObject
    {
        return self.referenceObjectForObjectID(objectID)
    }
    func objectID(identifier:String,entity:NSEntityDescription)->NSManagedObjectID
    {
        var objectID:NSManagedObjectID=self.newObjectIDForEntity(entity, referenceObject: identifier)
        return objectID
    }
    

}
