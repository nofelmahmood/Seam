//
//  Note.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData


class Note: NSManagedObject {

// Insert code here to add functionality to your managed object subclass
  var photoURL: NSURL? {
    get {
      return self.photo as? NSURL
    } set {
      self.photo = newValue
    }
  }
}
