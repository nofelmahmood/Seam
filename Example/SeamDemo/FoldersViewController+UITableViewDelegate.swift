//
//  FoldersViewController+UITableViewDelegate.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 19/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

extension FoldersViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
    if editingStyle == .delete {
      let folder = fetchedResultsController.object(at: indexPath) as! Folder
      self.confirmDeletion(folder)
    }
  }
  
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    self.performSegue(withIdentifier: "Notes", sender: self)
  }
}
