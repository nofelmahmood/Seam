//
//  NSManagedObjectToCKRecordTransformer.swift
//  
//
//  Created by Nofel Mahmood on 07/08/2015.
//
//

import UIKit
import CoreData
import CloudKit

protocol NSManagedObjectToCKRecordTransformer
{
    func transformedValue(valueToTransform value: NSManagedObject)
    func reverseTransformedValue(valueToReverseTransform value: CKRecord)
}

extension NSManagedObjectToCKRecordTransformer
{
    func transformedValue(valueToTransform value: NSManagedObject)
    {
        let 
    }
    
    func reverseTransformedValue(valueToReverseTransform value: CKRecord)
    {
        
    }

}