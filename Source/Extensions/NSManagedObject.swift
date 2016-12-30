//    NSManagedObject.swift
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
import CloudKit

extension NSManagedObject {

  var uniqueID: String {
    get {
      return valueForKey(UniqueID.name) as! String
    } set {
      setValue(newValue, forKey: UniqueID.name)
    }
  }
  
  var changedValueKeys: [String] {
    let propertiesToTrack = self.entity.attributeNames + self.entity.assetAttributeNames + self.entity.toOneRelationshipNames
    return changedValues().keys.filter { propertiesToTrack.contains($0) }
  }
  
  public var uniqueObjectID: NSManagedObjectID? {
    var seamStore: Store?
    managedObjectContext?.persistentStoreCoordinator?.persistentStores.forEach {
      if let store = $0 as? Store {
        seamStore = store
      }
    }
    let referenceObject = seamStore?.referenceObjectForObjectID(objectID) as! String
    do {
      let backingObjectID = try seamStore?.objectIDForBackingObjectForEntity(entity.name!, withReferenceObject: referenceObject)
      return backingObjectID
    } catch {
      return nil
    }
  }
}
