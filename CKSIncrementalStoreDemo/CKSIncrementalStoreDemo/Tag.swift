//
//  Tag.swift
//  CKSIncrementalStoreDemo
//
//  Created by Nofel Mahmood on 19/07/2015.
//  Copyright (c) 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData

class Tag: NSManagedObject {

    @NSManaged var tagName: String
    @NSManaged var task: Task

}
