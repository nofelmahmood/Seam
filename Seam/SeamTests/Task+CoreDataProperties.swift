//
//  Task+CoreDataProperties.swift
//  Seam
//
//  Created by Nofel Mahmood on 05/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Task {

    @NSManaged var name: String?
    @NSManaged var tags: NSSet?

}
