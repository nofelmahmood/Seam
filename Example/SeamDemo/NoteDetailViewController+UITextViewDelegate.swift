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

extension NoteDetailViewController: UITextViewDelegate {
//  func textViewDidChange(textView: UITextView) {
//    note.text = textView.text
//  }
  
  func textViewDidEndEditing(textView: UITextView) {
    print("Printing from END EDITING ",note)
    note.text = textView.text
  }
//  func textViewDidEndEditing(textView: UITextView) {
//    try! context.save()
//  }
}