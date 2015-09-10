//    SMServerStoreSetupOperation.swift
//
//    The MIT License (MIT)
//
//    Copyright (c) 2015 Nofel Mahmood ( https://twitter.com/NofelMahmood )
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.


import Foundation
import CloudKit

let SMStoreCloudStoreCustomZoneName = "SMStoreCloudStore_CustomZone"
let SMStoreCloudStoreSubscriptionName = "SM_CloudStore_Subscription"

class SMServerStoreSetupOperation:NSOperation {
    
    var database:CKDatabase?
    var setupOperationCompletionBlock:((customZoneCreated:Bool,customZoneSubscriptionCreated:Bool)->Void)?
    
    init(cloudDatabase:CKDatabase?) {
        self.database = cloudDatabase
        super.init()
    }
    
    override func main() {
        let operationQueue = NSOperationQueue()
        let zone = CKRecordZone(zoneName: SMStoreCloudStoreCustomZoneName)
        var error: NSError?
        let modifyRecordZonesOperation = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
        modifyRecordZonesOperation.database = self.database
        modifyRecordZonesOperation.modifyRecordZonesCompletionBlock = ({(savedRecordZones, deletedRecordZonesIDs, operationError) -> Void in
            error = operationError
            let customZoneWasCreated:AnyObject? = NSUserDefaults.standardUserDefaults().objectForKey(SMStoreCloudStoreCustomZoneName)
            let customZoneSubscriptionWasCreated:AnyObject? = NSUserDefaults.standardUserDefaults().objectForKey(SMStoreCloudStoreSubscriptionName)
            if ((operationError == nil || customZoneWasCreated != nil) && customZoneSubscriptionWasCreated == nil) {
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: SMStoreCloudStoreCustomZoneName)
                let recordZoneID = CKRecordZoneID(zoneName: SMStoreCloudStoreCustomZoneName, ownerName: CKOwnerDefaultName)
                let subscription = CKSubscription(zoneID: recordZoneID, subscriptionID: SMStoreCloudStoreSubscriptionName, options: CKSubscriptionOptions(rawValue: 0))
                let subscriptionNotificationInfo = CKNotificationInfo()
                subscriptionNotificationInfo.alertBody = ""
                subscriptionNotificationInfo.shouldSendContentAvailable = true
                subscription.notificationInfo = subscriptionNotificationInfo
                subscriptionNotificationInfo.shouldBadge = false
                let subscriptionsOperation = CKModifySubscriptionsOperation(subscriptionsToSave: [subscription], subscriptionIDsToDelete: nil)
                subscriptionsOperation.database = self.database
                subscriptionsOperation.modifySubscriptionsCompletionBlock=({ (modified,created,operationError) -> Void in
                    if operationError == nil {
                        NSUserDefaults.standardUserDefaults().setBool(true, forKey: SMStoreCloudStoreSubscriptionName)
                    }
                    error = operationError
                })
                operationQueue.addOperation(subscriptionsOperation)
            }
        })
        operationQueue.addOperation(modifyRecordZonesOperation)
        operationQueue.waitUntilAllOperationsAreFinished()
        if self.setupOperationCompletionBlock != nil {
            if error == nil {
                self.setupOperationCompletionBlock!(customZoneCreated: true, customZoneSubscriptionCreated: true)
            } else {
                if NSUserDefaults.standardUserDefaults().objectForKey(SMStoreCloudStoreCustomZoneName) == nil {
                    self.setupOperationCompletionBlock!(customZoneCreated: false, customZoneSubscriptionCreated: false)
                } else {
                    self.setupOperationCompletionBlock!(customZoneCreated: true, customZoneSubscriptionCreated: false)
                }
            }
        }
    }
}