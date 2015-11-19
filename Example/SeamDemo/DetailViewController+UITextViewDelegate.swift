//
//  DetailViewController+UITextViewDelegate.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import Foundation
import CoreData
import UIKit

extension DetailViewController: UITextViewDelegate {
  func textViewDidChange(textView: UITextView) {
    note.text = textView.text
  }
}