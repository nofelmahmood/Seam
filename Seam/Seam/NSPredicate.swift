//
//  NSPredicate.swift
//  Seam
//
//  Created by Nofel Mahmood on 11/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation

extension NSPredicate {
  convenience init(equalsToUniqueID id: String) {
    self.init(format: "%K == %@", UniqueID.name,id)
  }
  convenience init(inUniqueIDs ids: [String]) {
    self.init(format: "%K IN %@",UniqueID.name,ids)
  }
  convenience init(changeIsQueued queued: Bool) {
    self.init(format: "%K == %@", Change.Properties.ChangeQueued.name,queued)
  }
}