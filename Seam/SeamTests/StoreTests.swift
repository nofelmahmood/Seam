//
//  StoreTests.swift
//  Seam
//
//  Created by Nofel Mahmood on 02/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import XCTest
import CoreData
@testable import Seam

class StoreTests: XCTestCase {
//    lazy var persistentStoreCoordinator: NSPersistentStoreCoordinator = {
//        let psc = NSPersistentStoreCoordinator(managedObjectModel: self.managedObjectModel)
//        let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("StoreTest.sqlite")
//        let result = try? psc.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: url, options: nil)
//        return psc
//    }()
//    lazy var managedObjectModel: NSManagedObjectModel = {
//        let mom = NSManagedObjectModel()
//        let taskEntity = NSEntityDescription()
//        taskEntity.name = "Task"
//        let tagEntity = NSEntityDescription()
//        tagEntity.name = "Tag"
//        let taskNameAttribute = NSAttributeDescription()
//        taskNameAttribute.name = "name"
//        taskEntity.properties.append(taskNameAttribute)
//        let taskTagRelationship = NSRelationshipDescription()
//        taskTagRelationship.name = "tags"
//        taskTagRelationship.destinationEntity = tagEntity
//        taskTagRelationship.maxCount = NSIntegerMax
//        taskEntity.properties.append(taskTagRelationship)
//        let tagNameAttribute = NSAttributeDescription()
//        tagNameAttribute.name = "name"
//        tagEntity.properties.append(tagNameAttribute)
//        let tagTaskRelationship = NSRelationshipDescription()
//        tagTaskRelationship.name = "task"
//        tagTaskRelationship.maxCount = 1
//        tagTaskRelationship.destinationEntity = taskEntity
//        tagTaskRelationship.inverseRelationship = taskTagRelationship
//        taskTagRelationship.inverseRelationship = tagTaskRelationship
//        mom.entities.appendContentsOf([taskEntity, tagEntity])
//        return mom
//    }()
//    lazy var managedObjectContext: NSManagedObjectContext = {
//        let moc = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
//        moc.persistentStoreCoordinator = self.persistentStoreCoordinator
//        return moc
//    }()
//    lazy var applicationDocumentsDirectory: NSURL = {
//        // The directory the application uses to store the Core Data store file. This code uses a directory named "com.CloudKitSpace.SeamDemo" in the application's documents Application Support directory.
//        let urls = NSFileManager.defaultManager().URLsForDirectory(.ApplicationSupportDirectory, inDomains: .UserDomainMask)
//        return urls[urls.count-1]
//    }()
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testStoreCreation() {
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
