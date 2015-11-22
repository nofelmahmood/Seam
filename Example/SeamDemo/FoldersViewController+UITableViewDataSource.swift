//
//  FoldersViewController+UITableViewDataSource.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 19/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

extension FoldersViewController: UITableViewDataSource {
  func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return self.folders.count
  }
  
  func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCellWithIdentifier(FolderTableViewCell.reuseIdentifier, forIndexPath: indexPath) as! FolderTableViewCell
    let folder = self.folders[indexPath.row]
    cell.configureWithFolder(folder)
    return cell
  }
}
