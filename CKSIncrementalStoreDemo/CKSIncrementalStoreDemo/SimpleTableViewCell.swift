//
//  SimpleTableViewCell.swift
//  CKSIncrementalStoreDemo
//
//  Created by Nofel Mahmood on 05/08/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

class SimpleTableViewCell: UITableViewCell {

    @IBOutlet var label: UILabel!
    override func awakeFromNib() {
        super.awakeFromNib()
        // Initialization code
    }

    override func setSelected(selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)

        // Configure the view for the selected state
    }

}
