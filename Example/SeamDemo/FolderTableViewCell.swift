//
//  FolderTableViewCell.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 19/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

class FolderTableViewCell: UITableViewCell {
  static let reuseIdentifier = "FolderTableViewCell"
  @IBOutlet var nameLabel: UILabel!
  
  func configureWithFolder(folder: Folder) {
    nameLabel.text = folder.name
  }
  override func prepareForReuse() {
    self.nameLabel.text = ""
  }
}