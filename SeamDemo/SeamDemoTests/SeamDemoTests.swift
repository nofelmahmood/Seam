//
//  SeamDemoTests.swift
//  SeamDemoTests
//
//  Created by Nofel Mahmood on 12/08/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import XCTest
import CoreData
@testable import SeamDemo

class SeamDemoTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testStoreCreation() {
        let _ = CoreDataStack.defaultStack.managedObjectContext
    }
    
    func testDeletionOfTasks() {
        let fetchRequest = NSFetchRequest(entityName: "Task")
        fetchRequest.includesPropertyValues = false
        let result = try? CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
        XCTAssertNotNil(result)
        let objects = result as? [Task]
        XCTAssertNotNil(objects)
        objects!.forEach({
            CoreDataStack.defaultStack.managedObjectContext.deleteObject($0)
        })
        let deletionResult = try? CoreDataStack.defaultStack.managedObjectContext.saveIfHasChanges()
        XCTAssertNotNil(deletionResult)
    }
    
    func testDeletionOfTags() {
        let fetchRequest = NSFetchRequest(entityName: "Tag")
        fetchRequest.includesPropertyValues = false
        let result = try? CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
        XCTAssertNotNil(result)
        let objects = result as? [Tag]
        XCTAssertNotNil(objects)
        objects!.forEach({
            print($0.name)
            CoreDataStack.defaultStack.managedObjectContext.deleteObject($0)
        })
        let deletionResult = try? CoreDataStack.defaultStack.managedObjectContext.saveIfHasChanges()
        XCTAssertNotNil(deletionResult)
    }
    
    func testAddingOfObjects() {
        let task = NSEntityDescription.insertNewObjectForEntityForName("Task", inManagedObjectContext: CoreDataStack.defaultStack.managedObjectContext) as! Task
        task.name = "Programming"
        let result = try? CoreDataStack.defaultStack.managedObjectContext.saveIfHasChanges()
        XCTAssertNotNil(result)
        let fetchRequest = NSFetchRequest(entityName: "Task")
        let fetchResult = try? CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
        XCTAssertNotNil(fetchResult)
        let objects = fetchResult as? [Task]
        XCTAssertNotNil(objects)
        objects!.forEach({
            XCTAssertNotNil($0.name)
            print($0.name)
        })
    }
    
    func testUpdatingOfObjects() {
        let fetchRequest = NSFetchRequest(entityName: "Task")
        let result = try? CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
        XCTAssertNotNil(result)
        let objects = result as? [Task]
        XCTAssertNotNil(objects)
        objects!.forEach({
            XCTAssertNotNil($0.name)
            $0.name = "task name changed"
        })
        let saveResult = try? CoreDataStack.defaultStack.managedObjectContext.saveIfHasChanges()
        XCTAssertNotNil(saveResult)
    }
    
    func testFetchingOfObjects() {
        let fetchRequest = NSFetchRequest(entityName: "Task")
        let result = try? CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
        XCTAssertNotNil(result)
        let objects = result as? [Task]
        XCTAssertNotNil(objects)
        objects!.forEach({
            XCTAssertNotNil($0.name)
            print($0.name!)
        })
    }
    
    func testSettingRelationshipsUsingANewObject() {
        let tag = NSEntityDescription.insertNewObjectForEntityForName("Tag", inManagedObjectContext: CoreDataStack.defaultStack.managedObjectContext) as? Tag
        XCTAssertNotNil(tag)
        tag!.name = "New Tag for Task"
        let fetchRequest = NSFetchRequest(entityName: "Task")
        let result = try? CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
        XCTAssertNotNil(result)
        let objects = result as? [Task]
        XCTAssertNotNil(objects)
        objects!.forEach({
            tag!.task = $0
        })
        let saveResult = try? CoreDataStack.defaultStack.managedObjectContext.saveIfHasChanges()
        XCTAssertNotNil(saveResult)
    }
    
    func testFetchingOfObjectsWithRelationships() {
        let fetchRequest = NSFetchRequest(entityName: "Task")
        let result = try? CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
        XCTAssertNotNil(result)
        let objects = result as? [Task]
        XCTAssertNotNil(objects)
        objects!.forEach({
            let tagName = ($0.tags?.allObjects.first as? Tag)?.name
            XCTAssertNotNil(tagName)
            print(tagName)
        })
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
