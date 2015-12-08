//
//  DetailViewController.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData

class NoteDetailViewController: UIViewController {
  @IBOutlet var textView: UITextView!
  var context = CoreDataStack.defaultStack.managedObjectContext
  var note: Note!
  var folderObjectID: NSManagedObjectID!
  
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
    textView.becomeFirstResponder()
  }
  
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)
    if note == nil {
      note = Note.new(inContext: context) as! Note
      let folder = context.objectWithID(folderObjectID) as! Folder
      note.folder = folder
    }
    textView.text = note.text
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillShow:", name: UIKeyboardWillShowNotification, object: nil)
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillHide:", name: UIKeyboardWillHideNotification, object: nil)
  }
  
  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)
    NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardWillShowNotification, object: nil)
    NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardWillHideNotification, object: nil)
    if let noteText = note.text where noteText.isEmpty == false {
      try! context.save()
    }
  }
  
  // MARK: Keyboard

  func keyboardWillShow(notification: NSNotification) {
    guard let userInfo = notification.userInfo else {
      return
    }
    var keyboardFrame = userInfo["UIKeyboardFrameEndUserInfoKey"]!.CGRectValue
    keyboardFrame = textView.convertRect(keyboardFrame, fromView: nil)
    let intersect = CGRectIntersection(keyboardFrame, textView.bounds)
    if !CGRectIsNull(intersect) {
      let duration = userInfo["UIKeyboardAnimationDurationUserInfoKey"]!.doubleValue
      UIView.animateWithDuration(duration, animations: {
        self.textView.contentInset = UIEdgeInsetsMake(0, 0, intersect.size.height, 0)
        self.textView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, intersect.size.height, 0)
      })
    }
  }
  
  func keyboardWillHide(notification: NSNotification) {
    guard let userInfo = notification.userInfo else {
      return
    }
    let duration = userInfo["UIKeyboardAnimationDurationUserInfoKey"]!.doubleValue
    UIView.animateWithDuration(duration) { 
      self.textView.contentInset = UIEdgeInsetsZero
      self.textView.scrollIndicatorInsets = UIEdgeInsetsZero
    }
  }
  
  // MARK: IBAction
  
  @IBAction func doneButtonDidPress(sender: AnyObject) {
    try! context.save()
  }

}
