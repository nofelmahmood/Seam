//    Properties.swift
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
import CoreData

public let SeamStoreType = Store.type

public let SMStoreDidStartSyncingNotification = "Seam.SMStoreDidStartSyncingNotification"
public let SMStoreDidFinishSyncingNotification = "Seam.SMStoreDidFinishSyncingNotification"

public let SMServerObjectWinsConflictResolutionPolicy = "Seam.SMServerObjectWinsConflictResolutionPolicy"
public let SMClientObjectWinsConflictResolutionPolicy = "Seam.SMClientObjectWinsConflictResolutionPolicy"

// MARK: Options

public let SMSyncConflictResolutionPolicyOption = "Seam.SMSyncConflictResolutionPolicyOption"
public let SMCloudKitZoneNameOption = "Seam.SMCloudKitZoneNameOption"

// MARK: Zone Properties

let ZoneNameKey = "com.seam.zone.name"
let ZoneSubscriptionNameKey = "com.seam.zone.name"

// MARK: General

struct UniqueID {
  static let name = "sm_entityAttribute_uniqueID"
  static var attributeDescription: NSAttributeDescription {
    let attributeDescription = NSAttributeDescription()
    attributeDescription.name = name
    attributeDescription.attributeType = .StringAttributeType
    attributeDescription.optional = false
    attributeDescription.indexed = true
    return attributeDescription
  }
}