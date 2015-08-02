//
//  CKRecord.swift
//  
//
//  Created by Nofel Mahmood on 02/08/2015.
//
//

import UIKit
import CloudKit

extension CKRecord
{
    class func recordWithEncodedFields(encodedFields: NSData) -> CKRecord
    {
        let coder = NSKeyedUnarchiver(forReadingWithData: encodedFields)
        let record: CKRecord = CKRecord(coder: coder)!
        coder.finishDecoding()
        return record
    }
    
    func encodedSystemFields() -> NSData
    {
        let data = NSMutableData()
        let coder = NSKeyedArchiver(forWritingWithMutableData: data)
        self.encodeSystemFieldsWithCoder(coder)
        coder.finishEncoding()
        return data
    }
}
