//
//  CoreDataStack+Settings.swift
//  HourTracker2
//
//  Created by Oskari Rauta on 2.1.2016.
//  Copyright © 2016 Oskari Rauta. All rights reserved.
//

import Foundation
import CoreData

extension CoreDataStack {
        
    static func getAllSettingObjectsByCreationDate(withName: String) -> NSArray? {
        
        let fetchRequest = NSFetchRequest(entityName: "Setting")
        let sortDescriptor = NSSortDescriptor(key: "dateCreated", ascending: true)
        
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.predicate = NSPredicate(format: "name == %@", withName.lowercaseString)
        
        do {
            let resultArray : NSArray? = try CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
            return resultArray
        } catch {
            return nil
        }
    }

    static func getSettingObject(withName: String) -> Setting? {
        
        let fetchRequest = NSFetchRequest(entityName: "Setting")
        let sortDescriptor = NSSortDescriptor(key: "name", ascending: false)
        
        fetchRequest.sortDescriptors = [sortDescriptor]
        fetchRequest.predicate = NSPredicate(format: "name == %@", withName.lowercaseString)
        
        do {
            let resultArray : NSArray? = try CoreDataStack.defaultStack.managedObjectContext.executeFetchRequest(fetchRequest)
            return resultArray == nil ? nil : ( resultArray!.count == 0 ? nil : resultArray!.objectAtIndex(0) as? Setting)
        } catch {
            return nil
        }
    }

    static func newSettingObject(withName: String) -> Setting {
        
        var settingObject : Setting? = CoreDataStack.getSettingObject(withName.lowercaseString)
        
        if settingObject == nil {
            settingObject = NSEntityDescription.insertNewObjectForEntityForName("Setting", inManagedObjectContext: CoreDataStack.defaultStack.managedObjectContext) as? Setting
            
            settingObject!.name = withName.lowercaseString
            settingObject!.value = ""
            settingObject!.dateCreated = NSDate()
        }
        
        return settingObject!
    }
    
}

class UIAppSettings {
    
    static let defaultSettings = UIAppSettings()

    private var autoSave : Bool = true
    
    var setting1 : String {
        get {
            var settingObj : Setting? = CoreDataStack.getSettingObject("setting1")
            if settingObj == nil {
                settingObj = CoreDataStack.newSettingObject("setting1")
                settingObj!.value = "value1"
                if self.autoSave {
                    try! CoreDataStack.defaultStack.managedObjectContext.save()
                }
            }
            return settingObj!.value!
        }
        set {
            let settingObj : Setting? = CoreDataStack.newSettingObject("setting1")
            settingObj!.value = newValue
            if self.autoSave {
                try! CoreDataStack.defaultStack.managedObjectContext.save()
            }
        }
    }

    var setting2 : String {
        get {
            var settingObj : Setting? = CoreDataStack.getSettingObject("setting2")
            if settingObj == nil {
                settingObj = CoreDataStack.newSettingObject("setting2")
                settingObj!.value = "value2"
                if self.autoSave {
                    try! CoreDataStack.defaultStack.managedObjectContext.save()
                }
            }
            return settingObj!.value!
        }
        set {
            let settingObj : Setting? = CoreDataStack.newSettingObject("setting2")
            settingObj!.value = newValue
            if self.autoSave {
                try! CoreDataStack.defaultStack.managedObjectContext.save()
            }
        }
    }

    var setting3 : String {
        get {
            var settingObj : Setting? = CoreDataStack.getSettingObject("setting3")
            if settingObj == nil {
                settingObj = CoreDataStack.newSettingObject("setting3")
                settingObj!.value = "value3"
                if self.autoSave {
                    try! CoreDataStack.defaultStack.managedObjectContext.save()
                }
            }
            return settingObj!.value!
        }
        set {
            let settingObj : Setting? = CoreDataStack.newSettingObject("setting3")
            settingObj!.value = newValue
            if self.autoSave {
                try! CoreDataStack.defaultStack.managedObjectContext.save()
            }
        }
    }
    
    func initSettings() { // Make sure settings exist - if they don't, create them with initial values..
        
        self.autoSave = false
        
        let _ = self.setting1
        let _ = self.setting2
        let _ = self.setting3

        self.autoSave = true
        try! CoreDataStack.defaultStack.managedObjectContext.save()
        CoreDataStack.defaultStack.store!.sync(nil)
        
    }
    
}
