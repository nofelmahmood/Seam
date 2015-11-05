//
//  NSManagedObject+Helper.swift
//  Seam
//
//  Created by Nofel Mahmood on 05/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData

extension NSManagedObject {
    class func all(inContext context: NSManagedObjectContext?) -> [NSManagedObject]? {
        var managedObjectContext = CoreDataStack.defaultStack.managedObjectContext
        if let context = context {
            managedObjectContext = context
        }
        let fetchRequest = NSFetchRequest(entityName: NSStringFromClass(self).componentsSeparatedByString(".").last!)
        if let result = try? managedObjectContext.executeFetchRequest(fetchRequest) {
            return result as? [NSManagedObject]
        }
        return nil
    }
    
    class func all(inContext context: NSManagedObjectContext?, satisfyingPredicate predicate: NSPredicate) -> [NSManagedObject]? {
        var managedObjectContext = CoreDataStack.defaultStack.managedObjectContext
        if let context = context {
            managedObjectContext = context
        }
        let fetchRequest = NSFetchRequest(entityName: NSStringFromClass(self).componentsSeparatedByString(".").last!)
        fetchRequest.predicate = predicate
        if let result = try? managedObjectContext.executeFetchRequest(fetchRequest) {
            return result as? [NSManagedObject]
        }
        return nil
    }
    
    class func new(inContext context: NSManagedObjectContext?) -> NSManagedObject? {
        var managedObjectContext = CoreDataStack.defaultStack.managedObjectContext
        if let context = context {
            managedObjectContext = context
        }
        return NSEntityDescription.insertNewObjectForEntityForName(NSStringFromClass(self).componentsSeparatedByString(".").last!, inManagedObjectContext: managedObjectContext)
    }
}