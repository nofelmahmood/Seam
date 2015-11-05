//
//  StoreRelationshipTests.swift
//  Seam
//
//  Created by Nofel Mahmood on 05/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import XCTest

class StoreRelationshipTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
        let tasks = Task.all(inContext: nil) as? [Task]
        let tags = Tag.all(inContext: nil) as? [Tag]
        tasks?.forEach { task in
            CoreDataStack.defaultStack.managedObjectContext.deleteObject(task)
        }
        tags?.forEach { tag in
            CoreDataStack.defaultStack.managedObjectContext.deleteObject(tag)
        }
        try! CoreDataStack.defaultStack.managedObjectContext.save()
    }
    
    func testAddingTagToTaskWithToOneRelationship() {
        let task = Task.new(inContext: nil) as? Task
        task?.name = "TaskToTestTask"
        XCTAssertNotNil(task)
        let tag = Tag.new(inContext: nil) as? Tag
        tag?.name = "TagToTestTag"
        XCTAssertNotNil(tag)
        tag?.task = task!
        XCTAssertNotNil(try? CoreDataStack.defaultStack.managedObjectContext.save())
        CoreDataStack.defaultStack.managedObjectContext.reset()
        let fetchedTag = Tag.all(inContext: nil, satisfyingPredicate: NSPredicate(format: "name == %@", "TagToTestTag"))?.first as? Tag
        XCTAssertNotNil(fetchedTag)
        XCTAssertNotNil(fetchedTag!.task!.name!)
    }
    
    func testAddingTagToTaskToManyRelationship() {
        let task = Task.new(inContext: nil) as? Task
        task?.name = "TaskToTestTask"
        XCTAssertNotNil(task)
        let tag = Tag.new(inContext: nil) as? Tag
        tag?.name = "TagToTestTag"
        XCTAssertNotNil(tag)
        var tags = task?.tags?.allObjects as? [Tag]
        XCTAssertNotNil(tags)
        tags!.append(tag!)
        let tagsSet = Set(tags!)
        task!.tags = tagsSet
        XCTAssertNotNil(try? CoreDataStack.defaultStack.managedObjectContext.save())
        CoreDataStack.defaultStack.managedObjectContext.reset()
        let fetchedTag = Tag.all(inContext: nil, satisfyingPredicate: NSPredicate(format: "name == %@", "TagToTestTag"))?.first as? Tag
        XCTAssertNotNil(fetchedTag)
        XCTAssertNotNil(fetchedTag?.task?.name)
        XCTAssertEqual(fetchedTag!.task!.name, "TaskToTestTask")
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measureBlock {
            // Put the code you want to measure the time of here.
        }
    }
    
}
