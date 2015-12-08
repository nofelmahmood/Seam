//
//  StoreFetching.swift
//  Seam
//
//  Created by Nofel Mahmood on 05/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import XCTest
import CoreData
@testable import Seam

class StoreFetching: XCTestCase {
  var task: Task!
  var tag: Tag!
  override func setUp() {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
    task = Task.new(inContext: nil) as? Task
    task.name = "Task to test"
    tag = Tag.new(inContext: nil) as? Tag
    tag.name = "Tag to test"
    try! CoreDataStack.defaultStack.managedObjectContext.save()
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
    CoreDataStack.defaultStack.managedObjectContext.deleteObject(self.task!)
    CoreDataStack.defaultStack.managedObjectContext.deleteObject(self.tag!)
    try! CoreDataStack.defaultStack.managedObjectContext.save()
  }
  
  func testFetchingTasks() {
    let taskToTest = Task.all(inContext: nil, satisfyingPredicate: NSPredicate(format: "name = %@",task!.name!))?.first as? Task
    print(taskToTest?.name,taskToTest)
    XCTAssertNotNil(taskToTest)
    XCTAssertNotNil(taskToTest!.name)
  }
  
  func testFetchingOfTags() {
    let tags = Tag.all(inContext: nil) as? [Tag]
    XCTAssertNotNil(tags)
    tags!.forEach { t in
      XCTAssertNotNil(t.name)
      XCTAssertNotNil(tag?.name)
    }
  }
  
  func testFetchingOfAllTasksAndThenTagsForEachTask() {
    let tasks = Task.all(inContext: nil) as? [Task]
    XCTAssertNotNil(tasks)
    tasks!.forEach { task in
      XCTAssertNotNil(task.name)
      print(task.name!)
      XCTAssertNotNil(task.tags)
      task.tags!.forEach { tag in
        XCTAssertNotNil(tag.name!)
        print(tag.name!)
      }
    }
  }
  
  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measureBlock {
      // Put the code you want to measure the time of here.
    }
  }
  
}
