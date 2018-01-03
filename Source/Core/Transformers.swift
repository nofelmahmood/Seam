//    Transformers.swift
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

struct Transformers {
  static func registerAll() {
    let assetTransformer = CKAssetTransformer()
    let locationTransformer = CLLocationTransformer()
    ValueTransformer.setValueTransformer(assetTransformer, forName: NSValueTransformerName(rawValue: CKAssetTransformer.name))
    ValueTransformer.setValueTransformer(locationTransformer, forName: NSValueTransformerName(rawValue: CLLocationTransformer.name))
  }
}

class CKAssetTransformer: ValueTransformer {
  static let name = "CKAssetTransformer"
  
  override class func transformedValueClass() -> AnyClass {
    return CKAsset.self
  }
  
  override class func allowsReverseTransformation() -> Bool {
    return true
  }
  
  override func transformedValue(_ value: Any?) -> Any? {
    guard let value = value else {
      return nil
    }
    return NSKeyedArchiver.archivedData(withRootObject: value)
  }
  
  override func reverseTransformedValue(_ value: Any?) -> Any? {
    guard let value = value as? NSData else {
      return nil
    }
    return NSKeyedUnarchiver.unarchiveObject(with: value as Data)
  }
}

class CLLocationTransformer: ValueTransformer {
  static let name = "CLLocationTransformer"
  
  override class func transformedValueClass() -> AnyClass {
    return CLLocation.self
  }
  
  override class func allowsReverseTransformation() -> Bool {
    return true
  }
  
  override func transformedValue(_ value: Any?) -> Any? {
    guard let value = value else {
      return nil
    }
    return NSKeyedArchiver.archivedData(withRootObject: value)
  }
  
  override func reverseTransformedValue(_ value: Any?) -> Any? {
    guard let value = value as? NSData else {
      return nil
    }
    return NSKeyedUnarchiver.unarchiveObjectWithData(value as Data)
  }
}
