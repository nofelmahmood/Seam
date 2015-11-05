//
//  Error.swift
//  Seam
//
//  Created by Nofel Mahmood on 02/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation

struct Error {
    struct Store {
        static let domain = "com.seam.error.store.errorDomain"
        enum BackingStore: ErrorType {
            case CreationFailed
            case ModelCreationFailed
            case PersistentStoreInitializationFailed
        }
        enum MainStore: ErrorType {
            case InvalidRequest
        }
    }
}