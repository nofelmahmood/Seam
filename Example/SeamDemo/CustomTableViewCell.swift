//
//  CustomTableViewCell.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

class CustomTableViewCell: UITableViewCell {
  @IBOutlet var noteLabel: UILabel!
  
  func configureWithNote(note: Note) {
    noteLabel.text = note.text
  }
  
  override func prepareForReuse() {
    super.prepareForReuse()
    noteLabel.text = ""
  }
}
