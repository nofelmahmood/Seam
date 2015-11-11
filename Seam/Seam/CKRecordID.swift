//
//  CKRecordID.swift
//  Seam
//
//  Created by Nofel Mahmood on 11/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CloudKit

extension CKRecordID {
    convenience init(change: Change) {
        self.init(recordName: change.uniqueID, zoneID: Zone.zoneID)
    }
}