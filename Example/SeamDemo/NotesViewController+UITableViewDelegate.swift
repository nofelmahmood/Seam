//
//  ViewController+UITableViewDelegate.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

extension NotesViewController: UITableViewDelegate {
  func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
    segueForNewNote = false
    self.performSegueWithIdentifier("Detail", sender: self)
  }
}