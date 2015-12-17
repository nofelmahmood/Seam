//    NSPredicate.swift
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

extension NSPredicate {
  convenience init(equalsToUniqueID id: String) {
    self.init(format: "%K == %@", UniqueID.name,id)
  }
  
  convenience init(equalsToUniqueID id: String, andChangeType type: NSNumber) {
    let typePropertyName = Change.Properties.ChangeType.name
    self.init(format: "%K == %@ && %K == %@", UniqueID.name,id,typePropertyName,type)
  }
  
  convenience init(backingObjectID objectID: NSManagedObjectID) {
    self.init(format: "self == %@", objectID)
  }
  
  convenience init(inUniqueIDs ids: [String]) {
    self.init(format: "%K IN %@",UniqueID.name,ids)
  }
  
  class var preferenceZoneNamePredicate: NSPredicate {
    return NSPredicate(format: "%K == %@", Preference.Properties.Key.name, Preference.Default.zoneName)
  }
  
  class var preferenceZoneSubscriptionNamePredicate: NSPredicate {
    return NSPredicate(format: "%K == %@", Preference.Properties.Key.name, Preference.Default.zoneSubscriptionName)
  }
}