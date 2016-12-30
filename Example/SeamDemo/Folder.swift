//
//  Folder.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 19/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData


class Folder: NSManagedObject {

// Insert code here to add functionality to your managed object subclass
  class func folderWithName(name: String, inContext context: NSManagedObjectContext) -> Folder {
    let folder = Folder.new(inContext: context) as! Folder
    folder.name = name
    return folder
  }
}
