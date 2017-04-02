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
  func imagePickerController(_ picker: UIImagePickerController, didFinishPickingImage image: UIImage, editingInfo: [String : AnyObject]?) {
    let textAttachment = NSTextAttachment()
    textAttachment.image = image
    let attributedString = NSAttributedString(attachment: textAttachment)
    let mutableAttributedTextViewString = NSMutableAttributedString(attributedString: textView.attributedText)
    mutableAttributedTextViewString.append(attributedString)
    textView.attributedText = mutableAttributedTextViewString
    dismiss(animated: true, completion: nil)
  }
  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    dismiss(animated: true, completion: nil)
  }
}

extension NoteDetailViewController: UINavigationControllerDelegate {
  
}

class NoteDetailViewController: UIViewController {
  @IBOutlet var textView: UITextView!
  lazy var imagePickerController: UIImagePickerController = {
    let imagePickerController = UIImagePickerController()
    imagePickerController.delegate = self
    imagePickerController.sourceType = .savedPhotosAlbum
    return imagePickerController
  }()
  var tempContext: NSManagedObjectContext!
  var note: Note!
  var noteObjectID: NSManagedObjectID?
  var folderObjectID: NSManagedObjectID!
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    textView.becomeFirstResponder()
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    if let noteObjectID = noteObjectID {
      note = tempContext.object(with: noteObjectID) as! Note
    } else {
      note = Note.new(inContext: tempContext) as! Note
      note.folder = tempContext.object(with: folderObjectID) as? Folder
    }
    textView.text = note.text
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
    NotificationCenter.default.addObserver(self, selector: #selector(NoteDetailViewController.keyboardWillShow(_:)), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(NoteDetailViewController.keyboardWillHide(_:)), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
  }
  
  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow, object: nil)
    NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide, object: nil)
  }
  
  // MARK: Keyboard

  func keyboardWillShow(_ notification: Notification) {
    guard let userInfo = notification.userInfo else {
      return
    }
    var keyboardFrame = (userInfo["UIKeyboardFrameEndUserInfoKey"]! as AnyObject).cgRectValue
    keyboardFrame = textView.convert(keyboardFrame!, from: nil)
    let intersect = keyboardFrame?.intersection(textView.bounds)
    if !(intersect?.isNull)! {
      let duration = (userInfo["UIKeyboardAnimationDurationUserInfoKey"]! as AnyObject).doubleValue
      UIView.animate(withDuration: duration!, animations: {
        self.textView.contentInset = UIEdgeInsetsMake(0, 0, (intersect?.size.height)!, 0)
        self.textView.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, (intersect?.size.height)!, 0)
      })
    }
  }
  
  func keyboardWillHide(_ notification: Notification) {
    guard let userInfo = notification.userInfo else {
      return
    }
    let duration = (userInfo["UIKeyboardAnimationDurationUserInfoKey"]! as AnyObject).doubleValue
    UIView.animate(withDuration: duration!, animations: { 
      self.textView.contentInset = UIEdgeInsets.zero
      self.textView.scrollIndicatorInsets = UIEdgeInsets.zero
    }) 
  }
  
  // MARK: IBAction
  
  @IBAction func cameraButtonDidPress() {
    present(imagePickerController, animated: true, completion: nil)
  }
  
  @IBAction func doneButtonDidPress(_ sender: AnyObject) {
    textView.resignFirstResponder()
    if let noteText = textView.text, noteText.isEmpty == false {
      note.text = noteText
      tempContext.performAndWait {
        do {
         try self.tempContext.save()
        } catch {
          print("Error saving ", error)
        }
      }
    }
  }
}
