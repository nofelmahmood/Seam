//
//  NSManagedObject+Helper.swift
//  Seam
//
//  Created by Nofel Mahmood on 05/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData

extension NSManagedObjectContext {
  class var mainContext: NSManagedObjectContext {
    return CoreDataStack.defaultStack.managedObjectContext
  }
}

extension NSManagedObject {
  private class func mainContextIfContextIsNil(context: NSManagedObjectContext?) -> NSManagedObjectContext {
    guard let context = context else {
      return NSManagedObjectContext.mainContext
    }
    return context
  }
  
  private class func className() -> String {
    return NSStringFromClass(self).componentsSeparatedByString(".").last!
  }
  
  class func all(inContext context: NSManagedObjectContext?) -> [NSManagedObject]? {
    let managedObjectContext = mainContextIfContextIsNil(context)
    let fetchRequest = NSFetchRequest(entityName: className())
    if let result = try? managedObjectContext.executeFetchRequest(fetchRequest) {
      return result as? [NSManagedObject]
    }
    return nil
  }
  
  class func all(inContext context: NSManagedObjectContext?, satisfyingPredicate predicate: NSPredicate) -> [NSManagedObject]? {
    let managedObjectContext = mainContextIfContextIsNil(context)
    let fetchRequest = NSFetchRequest(entityName: className())
    fetchRequest.predicate = predicate
    if let result = try? managedObjectContext.executeFetchRequest(fetchRequest) {
      return result as? [NSManagedObject]
    }
    return nil
  }
  
  class func all(inContext context: NSManagedObjectContext?, whereKey key: String, isEqualToValue value: NSObject) -> [NSManagedObject]? {
    let managedObjectContext = mainContextIfContextIsNil(context)
    let fetchRequest = NSFetchRequest(entityName: className())
    fetchRequest.predicate = NSPredicate(format: "%K == %@", key,value)
    if let result = try? managedObjectContext.executeFetchRequest(fetchRequest) {
      return result as? [NSManagedObject]
    }
    return nil
  }
  
  class func new(inContext context: NSManagedObjectContext?) -> NSManagedObject? {
    let managedObjectContext = mainContextIfContextIsNil(context)
    return NSEntityDescription.insertNewObjectForEntityForName(className(), inManagedObjectContext: managedObjectContext)
  }
  
  class func deleteAll(inContext context: NSManagedObjectContext?) throws {
    let managedObjectContext = mainContextIfContextIsNil(context)
    let fetchRequest = NSFetchRequest(entityName: className())
    let objects = try managedObjectContext.executeFetchRequest(fetchRequest)
    try objects.forEach { object in
      managedObjectContext.deleteObject(object as! NSManagedObject)
      try managedObjectContext.save()
    }
  }
  
  class func deleteAll(inContext context: NSManagedObjectContext?, whereKey key:String, isEqualToValue value: NSObject) throws {
    let managedObjectContext = mainContextIfContextIsNil(context)
    let fetchRequest = NSFetchRequest(entityName: className())
    fetchRequest.predicate = NSPredicate(format: "%K == %@", key,value)
    let objects = try managedObjectContext.executeFetchRequest(fetchRequest)
    try objects.forEach { object in
      managedObjectContext.deleteObject(object as! NSManagedObject)
      try managedObjectContext.save()
    }
  }
  
  func addObject(value: NSManagedObject, forKey: String) {
    self.willChangeValueForKey(forKey, withSetMutation: NSKeyValueSetMutationKind.UnionSetMutation, usingObjects: NSSet(object: value) as! Set<NSObject>)
    let items = self.mutableSetValueForKey(forKey)
    items.addObject(value)
    self.didChangeValueForKey(forKey, withSetMutation: NSKeyValueSetMutationKind.UnionSetMutation, usingObjects: NSSet(object: value) as! Set<NSObject>)
  }
}