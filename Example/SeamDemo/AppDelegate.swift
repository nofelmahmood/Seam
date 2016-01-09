//
//  AppDelegate.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 12/08/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData
import Seam

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    var appSettings : UIAppSettings = UIAppSettings.defaultSettings
    
    func application(application: UIApplication, willFinishLaunchingWithOptions launchOptions: [NSObject : AnyObject]?) -> Bool {
        
        if let store = CoreDataStack.defaultStack.store {
            
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "syncBegins:",name: SMStoreDidStartSyncingNotification, object: nil)
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "syncEnds:", name: SMStoreDidFinishSyncingNotification, object: nil)
            
            store.subscribeToPushNotifications({ successful in
                print("Subscription ", successful)
                guard successful else { return }
            })
            store.sync(nil)
        }
        
        self.appSettings.initSettings()
        
        return true
    }
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        
        return true
    }
    
    func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) {
        CoreDataStack.defaultStack.store?.sync(nil)
    }
    
    func applicationWillResignActive(application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
    }
    
    
    func applicationDidEnterBackground(application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }
    
    func applicationWillEnterForeground(application: UIApplication) {
        // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
    }
    
    func applicationDidBecomeActive(application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }
    
    func applicationWillTerminate(application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
        // Saves changes in the application's managed object context before the application terminates.
    }
    
    func syncBegins(notification: NSNotification) {
        print("\nNOTIFICATION: started sync operation\n")
    }
    
    func syncEnds(notification: NSNotification) {
        
        let settingsForRemoval : NSMutableArray = NSMutableArray()
        
        print("\nNOTIFICATION: did sync operation\n")
        
        // Routine for making sure that records from cloud overwrite existing records.
        
        for (index, key) in notification.userInfo!.keys.enumerate() {
            if key == "inserted" {
                for (index2, value) in notification.userInfo!.values.enumerate() {
                    if index == index2 {
                        
                        for item in ( value as! NSSet ) {
                            
                            if item.isKindOfClass(Setting) {
                                let updatedSetting : Setting = item as! Setting
                                let settingsArray : NSArray? = CoreDataStack.getAllSettingObjectsByCreationDate(updatedSetting.name!)
                                if (( settingsArray != nil ) && ( settingsArray!.count > 0 )) {
                                    
                                    for (index, settingItem) in settingsArray!.enumerate() {
                                        if ( index != 0 ) {
                                            settingsForRemoval.addObject(settingItem as! Setting)
                                        }
                                    }
                                    
                                }
                            }
                            
                        }
                        
                        
                    }
                }
            }
        }
        
        CoreDataStack.defaultStack.managedObjectContext.performBlockAndWait({ Void in
            CoreDataStack.defaultStack.managedObjectContext.mergeChangesFromContextDidSaveNotification(notification)
        })
        
        var needsSave : Bool = false
        
        if settingsForRemoval.count > 0 {
            print("Removing ", settingsForRemoval.count, " old setting entries which where overwritten by values from cloud.")
            
            for obj in settingsForRemoval {
                CoreDataStack.defaultStack.managedObjectContext.deleteObject(obj as! Setting)
            }
            
            needsSave = true
            
        }
        
        if needsSave {
            try! CoreDataStack.defaultStack.managedObjectContext.save()
            CoreDataStack.defaultStack.store!.sync(nil)
        }
        
    }
    
    
}

