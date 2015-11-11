//    Zone.swift
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

struct Zone {
  static let name = "Seam_CustomZone"
  static let subscriptionName = "Seam_CustomZone_Subscription"
  static var zone: CKRecordZone {
    return CKRecordZone(zoneID: zoneID)
  }
  static var zoneID: CKRecordZoneID {
    return CKRecordZoneID(zoneName: name, ownerName: CKOwnerDefaultName)
  }
  private static var zoneExists: Bool {
    return NSUserDefaults.standardUserDefaults().objectForKey("com.seam.zone") != nil ? true: false
  }
  private static var zoneSubscriptionExists: Bool {
    return NSUserDefaults.standardUserDefaults().objectForKey("com.seam.zone.subscription") != nil ? true : false
  }
  
  static func createZone(completionBlock: ((error: NSError?)->())?) {
    CKContainer.defaultContainer().privateCloudDatabase.saveRecordZone(zone, completionHandler: {
      zone,error in
      completionBlock?(error: error)
    })
  }
  
  static func createSubscription(completionBlock: ((error: NSError?) -> ())?) {
    let subscription = CKSubscription(zoneID: zoneID, subscriptionID: name, options: CKSubscriptionOptions(rawValue: 0))
    let subscriptionNotificationInfo = CKNotificationInfo()
    subscriptionNotificationInfo.alertBody = ""
    subscriptionNotificationInfo.shouldSendContentAvailable = true
    subscription.notificationInfo = subscriptionNotificationInfo
    subscriptionNotificationInfo.shouldBadge = false
    CKContainer.defaultContainer().privateCloudDatabase.saveSubscription(subscription, completionHandler: { subscription,error in
      completionBlock?(error: error)
    })
  }
}