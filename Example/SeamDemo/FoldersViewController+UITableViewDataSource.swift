//
//  FoldersViewController+UITableViewDataSource.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 19/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

extension FoldersViewController: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let sectionInfo = fetchedResultsController.sections?[section] else {
      return 0
    }
    return sectionInfo.numberOfObjects
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: FolderTableViewCell.reuseIdentifier, for: indexPath) as! FolderTableViewCell
    let folder = fetchedResultsController.object(at: indexPath) as! Folder
    cell.configureWithFolder(folder)
    return cell
  }
}
