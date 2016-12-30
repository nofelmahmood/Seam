//    NSEntityDescription.swift
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

extension NSAttributeDescription {
  var isCKAsset: Bool {
    return valueTransformerName == CKAssetTransformer.name
  }
  var isCLLocation: Bool {
    return valueTransformerName == CLLocationTransformer.name
  }
}

extension NSEntityDescription {
  var propertyNamesToFetch: [String] {
    return attributeNames + toOneRelationshipNames + assetAttributeNames + locationAttributeNames
  }
  
  var allAttributesByName: [String: NSAttributeDescription] {
    var allAttributesByName = [String: NSAttributeDescription]()
    attributeNames.forEach { name in
      if let attribute = propertiesByName[name] as? NSAttributeDescription where attribute.isCKAsset == false {
        allAttributesByName[name] = attribute
      }
    }
    return allAttributesByName
  }
  
  var attributeNames: [String] {
   return attributesByName.filter { $0.1.isCKAsset == false && $0.1.isCLLocation == false }.map { $0.0 }
  }
  
  var assetAttributes: [NSAttributeDescription] {
    return Array(attributesByName.values).filter { $0.isCKAsset }
  }
  
  var assetAttributeNames: [String] {
    return assetAttributes.map { $0.name }
  }
  
  var assetAttributesByName: [String: NSAttributeDescription] {
    var assetAttributesByName = [String: NSAttributeDescription]()
    assetAttributes.forEach { attribute in
      assetAttributesByName[attribute.name] = attribute
    }
    return assetAttributesByName
  }
  
  var locationAttributes: [NSAttributeDescription] {
    return Array(attributesByName.values).filter { $0.isCLLocation }
  }
  
  var locationAttributeNames: [String] {
    return locationAttributes.map { $0.name }
  }
  
  var locationAttributesByName: [String: NSAttributeDescription] {
    var locationAttributesByName = [String: NSAttributeDescription]()
    locationAttributes.forEach { attribute in
      locationAttributesByName[attribute.name] = attribute
    }
    return locationAttributesByName
  }
  
  var relationships: [NSRelationshipDescription] {
    return Array(relationshipsByName.values)
  }
  
  var relationshipNames: [String] {
    return Array(relationshipsByName.keys)
  }
  
  var toOneRelationships: [NSRelationshipDescription] {
    return Array(relationshipsByName.values).filter({ $0.toMany == false })
  }
  
  var toOneRelationshipNames: [String] {
    return Array(toOneRelationshipsByName.keys)
  }
  
  var toOneRelationshipsByName: [String:NSRelationshipDescription] {
    var dictionary = [String: NSRelationshipDescription]()
    relationshipsByName.forEach({ (key,value) in
      if value.toMany == false {
        dictionary[key] = value
      }
    })
    return dictionary
  }
}
