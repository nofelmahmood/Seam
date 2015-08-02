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
    var setupOperationCompletionBlock:((customZoneCreated:Bool,customZoneSubscriptionCreated:Bool)->Void)?
    
    
    init(cloudDatabase:CKDatabase?) {
        
        self.database = cloudDatabase
        super.init()
    }
    
    override func main() {
        
        let operationQueue = NSOperationQueue()
        let zone = CKRecordZone(zoneName: CKSIncrementalStoreCloudDatabaseCustomZoneName)
        var error: NSError?
        let modifyRecordZonesOperation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        modifyRecordZonesOperation.database = self.database
        modifyRecordZonesOperation.modifyRecordZonesCompletionBlock = ({(savedRecordZones, deletedRecordZonesIDs, operationError) -> Void in
            
            error = operationError
            let customZoneWasCreated:AnyObject? = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreCustomZoneKey)
            let customZoneSubscriptionWasCreated:AnyObject? = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreZoneSubcriptionKey)
            
            if ((operationError == nil || customZoneWasCreated != nil) && customZoneSubscriptionWasCreated == nil)
            {
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: CKSIncrementalStoreCloudStoreCustomZoneKey)
                let recordZoneID = CKRecordZoneID(zoneName: CKSIncrementalStoreCloudDatabaseSyncSubcriptionName, ownerName: CKOwnerDefaultName)
                let subscription = CKSubscription(zoneID: recordZoneID, subscriptionID: CKSIncrementalStoreCloudDatabaseSyncSubcriptionName, options: CKSubscriptionOptions(rawValue: 0))
                
                let subscriptionNotificationInfo = CKNotificationInfo()
                subscriptionNotificationInfo.alertBody = ""
                subscriptionNotificationInfo.shouldSendContentAvailable = true
                subscription.notificationInfo = subscriptionNotificationInfo
                subscriptionNotificationInfo.shouldBadge = false
                
                let subscriptionsOperation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
                subscriptionsOperation.database=self.database
                subscriptionsOperation.modifySubscriptionsCompletionBlock=({ (modified,created,operationError) -> Void in
                    
                    if operationError == nil
                    {
                        NSUserDefaults.standardUserDefaults().setBool(true, forKey: CKSIncrementalStoreCloudStoreZoneSubcriptionKey)
                    }
                    error = operationError
                })
                
                operationQueue.addOperation(subscriptionsOperation)
            }
        })
        
        operationQueue.addOperation(modifyRecordZonesOperation)
        operationQueue.waitUntilAllOperationsAreFinished()
        
        if self.setupOperationCompletionBlock != nil
        {
            if error == nil
            {
                self.setupOperationCompletionBlock!(customZoneCreated: true, customZoneSubscriptionCreated: true)
            }
            else
            {
                if NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreCloudStoreCustomZoneKey) == nil
                {
                    self.setupOperationCompletionBlock!(customZoneCreated: false, customZoneSubscriptionCreated: false)
                }
                else
                {
                    self.setupOperationCompletionBlock!(customZoneCreated: true, customZoneSubscriptionCreated: false)
                }
            }
        }
    }
}