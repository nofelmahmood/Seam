//
//  FoldersViewController.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 19/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData

class FoldersViewController: UIViewController {
  @IBOutlet var tableView: UITableView!
  
  var folders: [Folder]!
  var context = CoreDataStack.defaultStack.managedObjectContext
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.
    prepareDataSource()
    tableView.reloadData()
  }
  
  func prepareDataSource() {
    folders = Folder.all(inContext: context) as! [Folder]
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  func confirmDeletion(folder: Folder) {
    let alertController = UIAlertController(title: "Delete \"\(folder.name!)\"", message: "Are you sure?", preferredStyle: .ActionSheet)
    let yesAction = UIAlertAction(title: "Yes", style: .Destructive, handler: { alertAction in
      self.context.deleteObject(folder)
      try! self.context.save()
      self.prepareDataSource()
      self.tableView.reloadData()
    })
    let noAction = UIAlertAction(title: "No", style: .Cancel, handler: { alertAction in
      self.dismissViewControllerAnimated(true, completion: nil)
    })
    alertController.addAction(yesAction)
    alertController.addAction(noAction)
    presentViewController(alertController, animated: true, completion: nil)
  }
  
  func addFolder(name: String) {
    Folder.folderWithName(name, inContext: context)
    try! context.save()
    prepareDataSource()
    tableView.reloadData()
  }
  
  // MARK: IBActions
  @IBAction func didPressAddButton(sender: AnyObject) {
    let alertController = UIAlertController(title: "New Folder", message: "Enter a name for the Folder", preferredStyle: .Alert)
    var folderName: String?
    let saveAction = UIAlertAction(title: "Save", style: .Default, handler: { alertAction in
      if let folderName = folderName where folderName.isEmpty == false {
        self.addFolder(folderName)
      }
    })
    saveAction.enabled = false
    let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: { alertAction in
      self.dismissViewControllerAnimated(true, completion: nil)
    })
    alertController.addTextFieldWithConfigurationHandler { textField in
      textField.placeholder = "Folder Name"
      NSNotificationCenter.defaultCenter().addObserverForName(UITextFieldTextDidChangeNotification, object: textField, queue: NSOperationQueue.mainQueue()) { (notification) in
        saveAction.enabled = textField.text != ""
        folderName = textField.text
      }
    }
    alertController.addAction(saveAction)
    alertController.addAction(cancelAction)
    presentViewController(alertController, animated: true, completion: nil)
  }

  
  // MARK: - Navigation
  
  // In a storyboard-based application, you will often want to do a little preparation before navigation
  override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
  // Get the new view controller using segue.destinationViewController.
  // Pass the selected object to the new view controller.
    let destinationViewController = segue.destinationViewController as! NotesViewController
    if let selectedIndexPath = tableView.indexPathForSelectedRow {
      let folder = folders[selectedIndexPath.row]
      destinationViewController.folderObjectID = folder.objectID
    }
  }
  
  
}
