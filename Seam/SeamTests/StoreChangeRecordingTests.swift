//
//  StoreChangeRecordingTests.swift
//  Seam
//
//  Created by Nofel Mahmood on 07/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import XCTest
import CoreData
@testable import Seam

class StoreChangeRecordingTests: XCTestCase {
  
  override func setUp() {
    super.setUp()
    // Put setup code here. This method is called before the invocation of each test method in the class.
  }
  
  override func tearDown() {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    super.tearDown()
  }
  
  func testChangeRecording() {
    let task = Task.new(inContext: nil) as? Task
    XCTAssertNotNil(task)
    task!.name = "NewForChangeRecording"
    XCTAssertNotNil(try! CoreDataStack.defaultStack.managedObjectContext.save())
    
  }
  
  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measureBlock {
      // Put the code you want to measure the time of here.
    }
  }
  
}
