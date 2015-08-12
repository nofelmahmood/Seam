//
//  AppDelegate.swift
//  CKSIncrementalStoreDemo
//
//  Created by Nofel Mahmood on 23/06/2015.
//  Copyright (c) 2015 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData
import Seam

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    
    var window: UIWindow?
    
    func application(application: UIApplication, didFinishLaunchingWithOptions launchOptions: [NSObject: AnyObject]?) -> Bool {
        // Override point for customization after application launch.
        let options = UIUserNotificationType.Alert.rawValue | UIUserNotificationType.Badge.rawValue | UIUserNotificationType.Sound.rawValue
        let option = UIUserNotificationType(rawValue: options)
        application.registerUserNotificationSettings(UIUserNotificationSettings(forTypes: option, categories: nil))
        application.registerForRemoteNotifications()
        
        //        var task: Task = NSEntityDescription.insertNewObjectForEntityForName("Task", inManagedObjectContext: CoreDataStack.sharedStack.managedObjectContext!) as! Task
        //        task.name = "My Task"
        //
        //        var tag: Tag = NSEntityDescription.insertNewObjectForEntityForName("Tag", inManagedObjectContext: CoreDataStack.sharedStack.managedObjectContext!) as! Tag
        //
        //        tag.tagName = "New Tag"
        //        tag.task = task
        //
        do
        {
            try CoreDataStack.sharedStack.managedObjectContext.save()
            let fetchRequest: NSFetchRequest = NSFetchRequest(entityName: "Tag")
            var results = try CoreDataStack.sharedStack.managedObjectContext.executeFetchRequest(fetchRequest)
            
            let task: Task = NSEntityDescription.insertNewObjectForEntityForName("Task", inManagedObjectContext: CoreDataStack.sharedStack.managedObjectContext) as! Task
            task.name = "NewTask"
            
            if results.count > 0
            {
                let result: Tag? = results.first as? Tag
                
                var set: Set<NSObject> = Set<NSObject>()
                set.insert(result!)
                result?.task.tags = set
            }
            
            try CoreDataStack.sharedStack.managedObjectContext.save()
        }
        catch
        {
            
        }
        
        return true
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
    
    func application(application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: NSData) {
        
        print("did register", appendNewline: false)
    }
    
    func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) {
        
        CoreDataStack.sharedStack.cksIncrementalStore?.handlePush(userInfo: userInfo)
    }
    
    func application(application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: NSError) {
        
        print("Did fail to register", appendNewline: false)
    }
    
}