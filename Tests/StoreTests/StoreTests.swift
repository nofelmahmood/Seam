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
  
  override func setUp() {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  
  func testStoreCreation() {
    let managedObjectContext = CoreDataStack.defaultStack.managedObjectContext
    XCTAssertNotNil(managedObjectContext)
  }
  
  func testCreationOfObjects() {
    let task = Task.new(inContext: nil) as? Task
    XCTAssertNotNil(task)
    task!.name = "New Task"
    let tag = Tag.new(inContext: nil) as? Tag
    XCTAssertNotNil(tag)
    tag!.name = "New Tag"
    tag!.task = task
    XCTAssertNotNil(try? CoreDataStack.defaultStack.managedObjectContext.save())
  }
  
  func testChangingOfAlreadyCreatedTask() {
    let task = Task.all(inContext: nil, whereKey: "name", isEqualToValue: "New Task")?.first as? Task
    XCTAssertNotNil(task)
    task!.name = "Dagha New Task"
    XCTAssertNotNil(try? CoreDataStack.defaultStack.managedObjectContext.save())
  }
  
  func testDeletingATask() {
    let task = Task.all(inContext: nil, whereKey: "name", isEqualToValue: "Dagha New Task")?.first as? Task
    XCTAssertNotNil(task)
    CoreDataStack.defaultStack.managedObjectContext.deleteObject(task!)
    XCTAssertNotNil(try? CoreDataStack.defaultStack.managedObjectContext.save())
  }
  
  func testFetchingOfTasks() {
    let tasks = Task.all(inContext: nil) as? [Task]
    XCTAssertNotNil(tasks)
    tasks!.forEach { task in
      XCTAssertNotNil(task.name)
      print(task.name!)
    }
  }
  
  func testFetchingOfTags() {
    let tags = Tag.all(inContext: nil) as? [Tag]
    XCTAssertNotNil(tags)
    tags!.forEach { tag in
      XCTAssertNotNil(tag.name)
      print(tag.name!)
    }
  }
  
  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measureBlock {
      // Put the code you want to measure the time of here.
    }
  }
  
}
