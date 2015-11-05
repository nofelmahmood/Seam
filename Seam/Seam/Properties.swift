//
//  Properties.swift
//  Seam
//
//  Created by Nofel Mahmood on 04/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData

public let SeamStoreType = Store.type

// MARK: - EntityAttributes

struct EntityAttributes {
    struct UniqueID {
        static let name = "sm_recordID_Attribute"
        static var attributeDescription: NSAttributeDescription {
            let attributeDescription = NSAttributeDescription()
            attributeDescription.name = name
            attributeDescription.attributeType = .StringAttributeType
            attributeDescription.optional = false
            attributeDescription.indexed = true
            return attributeDescription
        }
    }
    struct EncodedValues {
        static let name = "sm_encodedValues_Attribute"
        static var attributeDescription: NSAttributeDescription {
            let attributeDescription = NSAttributeDescription()
            attributeDescription.name = name
            attributeDescription.attributeType = .BinaryDataAttributeType
            attributeDescription.optional = true
            return attributeDescription
        }
    }
    
}

// MARK: - ChangeSet

struct ChangeSet {
    struct ChangeType {
        static let Inserted = 0
        static let Updated = 1
        static let Deleted = 2
    }
    struct Entity {
        static let name = "sm_entity_ChangeSet"
        static var entityDescription: NSEntityDescription {
            let entityDescription = NSEntityDescription()
            entityDescription.name = name
            entityDescription.properties.append(Attributes.UniqueID.attributeDescription)
            entityDescription.properties.append(Attributes.ChangeType.attributeDescription)
            entityDescription.properties.append(Attributes.EntityName.attributeDescription)
            return entityDescription
        }
        struct Attributes {
            struct UniqueID {
                static let name = EntityAttributes.UniqueID.name
                static let attributeDescription = EntityAttributes.UniqueID.attributeDescription
            }
            struct ChangeType {
                static let name = "sm_entity_ChangeSet_attribute_changeType"
                static var attributeDescription: NSAttributeDescription {
                    let attributeDescription = NSAttributeDescription()
                    attributeDescription.name = name
                    attributeDescription.attributeType = .Integer16AttributeType
                    attributeDescription.optional = false
                    attributeDescription.indexed = true
                    return attributeDescription
                }
            }
            struct  EntityName {
                static let name = "sm_entity_ChangeSet_attribute_entityName"
                static var attributeDescription: NSAttributeDescription {
                    let attributeDescription = NSAttributeDescription()
                    attributeDescription.name = name
                    attributeDescription.attributeType = .StringAttributeType
                    attributeDescription.optional = false
                    attributeDescription.indexed = true
                    return attributeDescription
                }
            }
        }
    }
}