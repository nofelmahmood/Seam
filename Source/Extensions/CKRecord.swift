//    CKRecord.swift
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

extension CKRecord {
  var encodedSystemFields: NSData {
    let data = NSMutableData()
    let coder = NSKeyedArchiver(forWritingWithMutableData: data)
    encodeSystemFieldsWithCoder(coder)
    coder.finishEncoding()
    return data
  }
  
  class func recordWithEncodedData(data: NSData) -> CKRecord {
    let coder = NSKeyedUnarchiver(forReadingWithData: data)
    let record = CKRecord(coder: coder)!
    coder.finishDecoding()
    return record
  }
  
//  class func record(uniqueID: String, entity: NSEntityDescription, propertyValuesDictionary: [String: AnyObject], encodedMetadata: NSData?) -> CKRecord {
//    var record: CKRecord?
//    if let metadata = encodedMetadata {
//      record = CKRecord.recordWithEncodedData(metadata)
//    } else {
//      let recordID = CKRecordID(uniqueID: uniqueID)
//      record = CKRecord(recordType: entity.name!, recordID: recordID)
//    }
//    propertyValuesDictionary.forEach { (key, value) in
//      guard value as! NSObject != NSNull() else {
//        record?.setObject(nil, forKey: key)
//        return
//      }
//      if let referenceManagedObject = value as? NSManagedObject {
//        let referenceUniqueID = referenceManagedObject.uniqueID
//        let referenceRecordID = CKRecordID(recordName: referenceUniqueID, zoneID: Zone.zoneID)
//        let reference = CKReference(recordID: referenceRecordID, action: CKReferenceAction.DeleteSelf)
//        record?.setObject(reference, forKey: key)
//      } else {
//        record?.setValue(value, forKey: key)
//      }
//    }
//    return record!
//  }
}
