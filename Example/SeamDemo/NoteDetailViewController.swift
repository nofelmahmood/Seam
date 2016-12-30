//
//  DetailViewController.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData

// MARK: UIImagePickerControllerDelegate

extension NoteDetailViewController: UIImagePickerControllerDelegate {
  func imagePickerController(picker: UIImagePickerController, didFinishPickingImage image: UIImage, editingInfo: [String : AnyObject]?) {
    let textAttachment = NSTextAttachment()
    textAttachment.image = image
    let attributedString = NSAttributedString(attachment: textAttachment)
    let mutableAttributedTextViewString = NSMutableAttributedString(attributedString: textView.attributedText)
    mutableAttributedTextViewString.appendAttributedString(attributedString)
    textView.attributedText = mutableAttributedTextViewString
    dismissViewControllerAnimated(true, completion: nil)
  }
  func imagePickerControllerDidCancel(picker: UIImagePickerController) {
    dismissViewControllerAnimated(true, completion: nil)
  }
}

extension NoteDetailViewController: UINavigationControllerDelegate {
  
}

class NoteDetailViewController: UIViewController {
  @IBOutlet var textView: UITextView!
  lazy var imagePickerController: UIImagePickerController = {
    let imagePickerController = UIImagePickerController()
    imagePickerController.delegate = self
    imagePickerController.sourceType = .SavedPhotosAlbum
    return imagePickerController
  }()
  var tempContext: NSManagedObjectContext!
  var note: Note!
  var noteObjectID: NSManagedObjectID?
  var folderObjectID: NSManagedObjectID!
  
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
    textView.becomeFirstResponder()
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    if let noteObjectID = noteObjectID {
      note = tempContext.objectWithID(noteObjectID) as! Note
    } else {
      note = Note.new(inContext: tempContext) as! Note
      note.folder = tempContext.objectWithID(folderObjectID) as? Folder
    }
    textView.text = note.text
  }
  
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillShow:", name: UIKeyboardWillShowNotification, object: nil)
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "keyboardWillHide:", name: UIKeyboardWillHideNotification, object: nil)
  }
  
  override func viewWillDisappear(animated: Bool) {
    super.viewWillDisappear(animated)
    NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardWillShowNotification, object: nil)
    NSNotificationCenter.defaultCenter().removeObserver(self, name: UIKeyboardWillHideNotification, object: nil)
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
  
  @IBAction func cameraButtonDidPress() {
    presentViewController(imagePickerController, animated: true, completion: nil)
  }
  
  @IBAction func doneButtonDidPress(sender: AnyObject) {
    textView.resignFirstResponder()
    if let noteText = textView.text where noteText.isEmpty == false {
      note.text = noteText
      tempContext.performBlockAndWait {
        do {
         try self.tempContext.save()
        } catch {
          print("Error saving ", error)
        }
      }
    }
  }
}
