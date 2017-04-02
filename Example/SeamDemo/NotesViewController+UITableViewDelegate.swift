//
//  ViewController+UITableViewDelegate.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

extension NotesViewController: UITableViewDelegate {
  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    segueForNewNote = false
    self.performSegue(withIdentifier: "Detail", sender: self)
  }
}
