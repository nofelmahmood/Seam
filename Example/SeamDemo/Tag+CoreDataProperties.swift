//
//  Tag+CoreDataProperties.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 03/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//
//  Choose "Create NSManagedObject Subclass…" from the Core Data editor menu
//  to delete and recreate this implementation file for your updated model.
//

import Foundation
import CoreData

extension Tag {

    @NSManaged var name: String?
    @NSManaged var task: Task?

}
