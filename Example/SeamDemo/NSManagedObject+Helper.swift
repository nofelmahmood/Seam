//
//  NSManagedObject+Helper.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 03/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData

extension NSManagedObject {
  class func all(inContext context: NSManagedObjectContext) -> [NSManagedObject]? {
    let fetchRequest = NSFetchRequest(entityName: NSStringFromClass(self).componentsSeparatedByString(".").last!)
    if let result = try? context.executeFetchRequest(fetchRequest) {
      return result as? [NSManagedObject]
    }
    return nil
  }
  
  class func all(inContext context: NSManagedObjectContext, satisfyingPredicate predicate: NSPredicate) -> [NSManagedObject]? {
    let fetchRequest = NSFetchRequest(entityName: NSStringFromClass(self).componentsSeparatedByString(".").last!)
    fetchRequest.predicate = predicate
    if let result = try? context.executeFetchRequest(fetchRequest) {
      return result as? [NSManagedObject]
    }
    return nil
  }
  
  class func new(inContext context: NSManagedObjectContext) -> NSManagedObject? {
    return NSEntityDescription.insertNewObjectForEntityForName(NSStringFromClass(self).componentsSeparatedByString(".").last!, inManagedObjectContext: context)
  }
}