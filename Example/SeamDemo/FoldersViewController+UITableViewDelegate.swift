//
//  FoldersViewController+UITableViewDelegate.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 19/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

extension FoldersViewController: UITableViewDelegate {
  func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
    if editingStyle == .Delete {
      let folder = fetchedResultsController.objectAtIndexPath(indexPath) as! Folder
      self.confirmDeletion(folder)
    }
  }
  
  func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
    self.performSegueWithIdentifier("Notes", sender: self)
  }
}