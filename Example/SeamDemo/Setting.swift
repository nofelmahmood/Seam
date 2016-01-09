//
//  Setting.swift
//  SeamDemo
//
//  Created by Oskari Rauta on 9.1.2016.
//  Copyright © 2016 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData


class Setting: NSManagedObject {

// Insert code here to add functionality to your managed object subclass
    class func settingWithNameAndValue(name: String, value: String, inContext context: NSManagedObjectContext) -> Setting {
        let setting = Setting.new(inContext: context) as! Setting
        setting.name = name
        setting.value = value
        setting.dateCreated = NSDate()
        return setting
    }

}
