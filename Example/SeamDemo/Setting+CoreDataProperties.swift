//
//  Setting+CoreDataProperties.swift
//  SeamDemo
//
//  Created by Oskari Rauta on 9.1.2016.
//  Copyright © 2016 CloudKitSpace. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Setting {

    @NSManaged var name: String?
    @NSManaged var value: String?
    @NSManaged var dateCreated: NSDate?

}
