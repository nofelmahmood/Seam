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
    let deletionResult = try? CoreDataStack.defaultStack.managedObjectContext.save()
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
    XCTAssertNotNil(try? CoreDataStack.defaultStack.managedObjectContext.save())
  }
  
  func testAddingOfObjects() {
    let task = NSEntityDescription.insertNewObjectForEntityForName("Task", inManagedObjectContext: CoreDataStack.defaultStack.managedObjectContext) as! Task
    task.name = "Programming"
    let result = try? CoreDataStack.defaultStack.managedObjectContext.save()
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
    let saveResult = try? CoreDataStack.defaultStack.managedObjectContext.save()
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
    let tags = Tag.all(inContext: CoreDataStack.defaultStack.managedObjectContext) as? [Tag]
    let task = Task.new(inContext: CoreDataStack.defaultStack.managedObjectContext) as? Task
    task?.name = "NewTaskForSettingTags"
    XCTAssertNotNil(tags)
    XCTAssertNotNil(task)
    tags!.forEach { tag in
      tag.task = task!
    }
    XCTAssertNotNil(try? CoreDataStack.defaultStack.managedObjectContext.save())
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
  
  func testAddingObjectsAndRelationships() {
    let task = NSEntityDescription.insertNewObjectForEntityForName("Task", inManagedObjectContext: CoreDataStack.defaultStack.managedObjectContext) as? Task
    XCTAssertNotNil(task)
    task!.name = "Test Task"
    let tag = NSEntityDescription.insertNewObjectForEntityForName("Tag", inManagedObjectContext: CoreDataStack.defaultStack.managedObjectContext) as? Tag
    XCTAssertNotNil(tag)
    tag!.name = "Tag for Test Task"
    var tags = task!.tags?.allObjects
    XCTAssertNotNil(tags)
    tags!.append(tag!)
    task!.tags = Set(tags as! [NSManagedObject])
    let saveResult = try? CoreDataStack.defaultStack.managedObjectContext.save()
    XCTAssertNotNil(saveResult)
    CoreDataStack.defaultStack.managedObjectContext.reset()
    let fetchRequest = NSFetchRequest(entityName: "Task")
    let fetchResult = try? CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
    XCTAssertNotNil(fetchResult)
    let tasks = fetchResult as? [Task]
    XCTAssertNotNil(tasks)
    tasks!.forEach({ task in
      print("Task \(task.name!)")
      XCTAssertNotNil(task.tags)
      task.tags!.forEach({ tag in
        print("Tag \(tag.name!)")
      })
    })
  }
  
  func testFetchingOfTagAndSettingItToNewTask() {
    let tasks = Task.all(inContext: CoreDataStack.defaultStack.managedObjectContext) as? [Task]
    XCTAssertNotNil(tasks)
    let tags = Tag.all(inContext: CoreDataStack.defaultStack.managedObjectContext) as? [Tag]
    XCTAssertNotNil(tags)
    let newTask = Task.new(inContext: CoreDataStack.defaultStack.managedObjectContext) as? Task
    XCTAssertNotNil(newTask)
    newTask!.name = "Dagha Rora"
    print("OLD VALUES")
    tasks!.forEach({ task in
      print("\(task.name!)")
      XCTAssertNotNil(task.tags)
      task.tags!.forEach({ tag in
        print("\(tag.name!)")
      })
    })
    tags!.forEach({ tag in
      tag.task = newTask!
    })
    let saveResult = try? CoreDataStack.defaultStack.managedObjectContext.save()
    XCTAssertNotNil(saveResult)
    CoreDataStack.defaultStack.managedObjectContext.reset()
  }
  
  func testAccessingOfToOneRelationship() {
    let tag = Tag.all(inContext: CoreDataStack.defaultStack.managedObjectContext)?.first as? Tag
    XCTAssertNotNil(tag)
    print(tag!.name!)
    print(tag!.task?.name)
  }
  
  func testAccessingOfToManyRelationship() {
    let task = Task.all(inContext: CoreDataStack.defaultStack.managedObjectContext, satisfyingPredicate: NSPredicate(format: "name = %@","Dagha Rora"))?.first as? Task
    print(task?.name)
    XCTAssertNotNil(task)
    XCTAssertNotNil(task?.tags)
    let tagsArray = task!.tags!.allObjects as? [Tag]
    XCTAssertNotNil(tagsArray)
    tagsArray!.forEach({ tag in
      XCTAssertNotNil(tag.name)
      print(tag.name)
    })
  }
  
  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measureBlock {
      // Put the code you want to measure the time of here.
    }
  }
  
}
