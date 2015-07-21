//
//  CKSIncrementalStoreCloudStoreSetupOperation.swift
//  
//
//  Created by Nofel Mahmood on 20/07/2015.
//
//

import UIKit
import CloudKit

let CKSIncrementalStoreCloudStoreCustomZoneKey = "CKSIncrementalStoreCloudStoreCustomZoneKey"
let CKSIncrementalStoreCloudStoreZoneSubcriptionKey = "CKSIncrementalStoreCloudStoreZoneSubcriptionKey"

class CKSIncrementalStoreCloudStoreSetupOperation:NSOperation {
    
    var database:CKDatabase?
    var setupOperationCompletionBlock:((customZoneCreated: Bool,customZoneSubscriptionCreated: Bool,error: NSError?)->Void)?
    
    
    init(cloudDatabase:CKDatabase?) {
        
        self.database = cloudDatabase
        super.init()
    }
    
    override func main() {
        
        var error:NSError?
        
        var operationQueue = NSOperationQueue()
        var zone = CKRecordZone(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName)
        
        var modifyRecordZonesOperation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        modifyRecordZonesOperation.database = self.database
        modifyRecordZonesOperation.modifyRecordZonesCompletionBlock = ({(savedRecordZones,deletedRecordZonesIDs , operationError) -> Void in
            
            error = operationError
            var customZoneWasCreated:AnyObject? = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreCustomZoneKey)
            var customZoneSubscriptionWasCreated:AnyObject? = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreZoneSubcriptionKey)
            
            if ((operationError == nil || customZoneWasCreated != nil) && customZoneSubscriptionWasCreated == nil)
            {
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: CKSIncrementalStoreCloudStoreCustomZoneKey)
                var subcription:CKSubscription = CKSubscription(zoneID: CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName, ownerName: CKOwnerDefaultName), subscriptionID: CKSIncrementalStoreCloudDatabaseSyncSubcriptionName, options: nil)
                
                var subcriptionNotificationInfo = CKNotificationInfo()
                subcriptionNotificationInfo.alertBody = ""
                subcriptionNotificationInfo.shouldSendContentAvailable = true
                subcription.notificationInfo = subcriptionNotificationInfo
                subcriptionNotificationInfo.shouldBadge = false
                
                var subcriptionsOperation = CKModifySubscriptionsOperation(subscriptionsToSave: [subcription], subscriptionIDsToDelete: nil)
                subcriptionsOperation.database=self.database
                subcriptionsOperation.modifySubscriptionsCompletionBlock=({ (modified,created,operationError) -> Void in
                    
                    error = operationError
                    if operationError == nil
                    {
                        NSUserDefaults.standardUserDefaults().setBool(true, forKey: CKSIncrementalStoreCloudStoreZoneSubcriptionKey)
                    }
                })
                
                operationQueue.addOperation(subcriptionsOperation)
            }
        })
        
        operationQueue.addOperation(modifyRecordZonesOperation)
        operationQueue.waitUntilAllOperationsAreFinished()
        
        if self.setupOperationCompletionBlock != nil
        {
            if error == nil
            {
                self.setupOperationCompletionBlock!(customZoneCreated: true,customZoneSubscriptionCreated: true,error: error)
            }
            else
            {
                if NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreCustomZoneKey) == nil
                {
                    self.setupOperationCompletionBlock!(customZoneCreated: false, customZoneSubscriptionCreated: false, error: error)
                }
                else
                {
                    self.setupOperationCompletionBlock!(customZoneCreated: true, customZoneSubscriptionCreated: false, error: error)
                }
            }
        }
    }
}

