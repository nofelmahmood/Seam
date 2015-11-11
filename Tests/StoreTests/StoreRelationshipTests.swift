//
//  StoreRelationshipTests.swift
//  Seam
//
//  Created by Nofel Mahmood on 05/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import XCTest
import CoreData
@testable import Seam

class StoreRelationshipTests: XCTestCase {
  
  override func setUp() {
    // Put setup code here. This method is called before the invocation of each test method in the class.
    super.setUp()
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
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
  
  func testAddingTagsToATask() {
    let context = CoreDataStack.defaultStack.managedObjectContext
    let newTag = Tag.new(inContext: nil) as? Tag
    XCTAssertNotNil(newTag)
    newTag!.name = "newTag"
    let newAnotherTag = Tag.new(inContext: nil) as? Tag
    XCTAssertNotNil(newAnotherTag)
    newAnotherTag!.name = "newAnotherTag"
    let yetAnotherTag = Tag.new(inContext: nil) as? Tag
    XCTAssertNotNil(yetAnotherTag)
    yetAnotherTag!.name = "yetAnotherTag"
    let moreTag = Tag.new(inContext: nil) as? Tag
    XCTAssertNotNil(moreTag)
    moreTag!.name = "moreTag"
    let taskToAddTags = Task.new(inContext: nil) as? Task
    XCTAssertNotNil(taskToAddTags)
    let uniqueNameForTask = "@!TASKTOTEST@!"
    taskToAddTags!.name = uniqueNameForTask
    XCTAssertNotNil(try! context.save())
    context.reset()
    let allTags = Tag.all(inContext: nil) as? [Tag]
    XCTAssertNotNil(allTags)
    let uniqueTask = Task.all(inContext: nil, satisfyingPredicate: NSPredicate(format: "name == %@", uniqueNameForTask))?.first as? Task
    XCTAssertNotNil(uniqueTask)
    let taskTags = NSMutableSet(array: uniqueTask!.tags!.allObjects)
    allTags!.forEach { tag in
      taskTags.addObject(tag)
    }
    uniqueTask?.tags = NSSet(set: taskTags)
    XCTAssertNotNil(try! context.save())
  }
  
  func testAddingTagToAlreadyAddedTask() {
    let context = CoreDataStack.defaultStack.managedObjectContext
    let uniqueNameForTask = "@!TASKTOTEST@!"
    let task = Task.all(inContext: nil, whereKey: "name", isEqualToValue: uniqueNameForTask)?.first as? Task
    XCTAssertNotNil(task)
    XCTAssertNotNil(try! Tag.deleteAll(inContext: nil, whereKey: "name", isEqualToValue: "NEWTASKTOALREADDEDTAG"))
    XCTAssertNotNil(try! context.save())
    let tag = Tag.new(inContext: nil) as? Tag
    XCTAssertNotNil(tag)
    tag!.name = "NEWTASKTOALREADDEDTAG"
    tag!.task = task
    XCTAssertTrue(context.hasChanges)
    XCTAssertNotNil(try! context.save())
  }
  
  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measureBlock {
      // Put the code you want to measure the time of here.
    }
  }
  
}
