//    NSEntityDescription+Helpers.swift
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

extension NSEntityDescription {
    
    func attributesByNameByRemovingBackingStoreAttributes() -> [String:NSAttributeDescription] {
        var attributesByName = self.attributesByName
        attributesByName.removeValue(forKey: SMLocalStoreRecordIDAttributeName)
        attributesByName.removeValue(forKey: SMLocalStoreRecordEncodedValuesAttributeName)
        return attributesByName
    }
    
    func toOneRelationships() -> [NSRelationshipDescription] {
        return Array(self.relationshipsByName.values).filter({ (relationshipDescription) -> Bool in
            return relationshipDescription.isToMany == false
        })
    }
    
    func toOneRelationshipsByName() -> [String:NSRelationshipDescription] {
        var relationshipsByNameDictionary: Dictionary<String,NSRelationshipDescription> = Dictionary<String,NSRelationshipDescription>()
        for (key,value) in self.relationshipsByName {
            if value.isToMany == true {
                continue
            }
            relationshipsByNameDictionary[key] = value
        }
        return relationshipsByNameDictionary
    }
}
