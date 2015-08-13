//
//  Task+CoreDataProperties.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 13/08/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//
//  Delete this file and regenerate it using "Create NSManagedObject Subclass…"
//  to keep your implementation up to date with your model.
//

import Foundation
import CoreData

extension Task {

    @NSManaged var name: String?
    @NSManaged var tags: NSSet?

}
