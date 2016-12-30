//
//  FoldersViewController.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 19/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData
import Seam

// MARK: NSFetchedResultsControllerDelegate

extension FoldersViewController: NSFetchedResultsControllerDelegate {
  func controllerWillChangeContent(controller: NSFetchedResultsController) {
    tableView.beginUpdates()
  }
  func controllerDidChangeContent(controller: NSFetchedResultsController) {
    tableView.endUpdates()
  }
  func controller(controller: NSFetchedResultsController, didChangeObject anObject: AnyObject, atIndexPath indexPath: NSIndexPath?, forChangeType type: NSFetchedResultsChangeType, newIndexPath: NSIndexPath?) {
    switch(type) {
    case .Insert:
      if let indexPath = newIndexPath {
        tableView.insertRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
      }
    case .Update:
      if let indexPath = indexPath {
        if let cell = tableView.cellForRowAtIndexPath(indexPath) as? FolderTableViewCell {
          let folder = controller.objectAtIndexPath(indexPath) as! Folder
          cell.configureWithFolder(folder)
        }
      }
    case .Delete:
      if let indexPath = indexPath {
        tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
      }
    case .Move:
      if let indexPath = indexPath, let newIndexPath = newIndexPath {
        let object = controller.objectAtIndexPath(newIndexPath) as! Folder
        if let cell = tableView.cellForRowAtIndexPath(indexPath) as? FolderTableViewCell {
          cell.configureWithFolder(object)
        }
        tableView.moveRowAtIndexPath(indexPath, toIndexPath: newIndexPath)
      }
    }
  }
}

class FoldersViewController: UIViewController {
  @IBOutlet var tableView: UITableView!
  
  var context = CoreDataStack.defaultStack.managedObjectContext
  var fetchedResultsController: NSFetchedResultsController!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.
    let fetchRequest = NSFetchRequest(entityName: "Folder")
    let sortDescriptor = NSSortDescriptor(key: "name", ascending: false)
    fetchRequest.sortDescriptors = [sortDescriptor]
    fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
    fetchedResultsController.delegate = self
    do {
      try prepareDataSource()
      tableView.reloadData()
    } catch {
      print(error)
    }
  }
  
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
    if let store = CoreDataStack.defaultStack.store {
      NSNotificationCenter.defaultCenter().addObserver(self, selector: "didSync:", name: SMStoreDidFinishSyncingNotification, object: nil)
      store.subscribeToPushNotifications({ successful in
        print("Subscription ", successful)
        guard successful else { return }
      })
      store.sync(nil)
    }
  }
  
  func didSync(notification: NSNotification) {
    let context = CoreDataStack.defaultStack.managedObjectContext
    context.performBlockAndWait {
      context.mergeChangesFromContextDidSaveNotification(notification)
    }
  }
  
  func prepareDataSource() throws {
    try fetchedResultsController.performFetch()
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
      let folder = fetchedResultsController.objectAtIndexPath(selectedIndexPath) as! Folder
      destinationViewController.folderObjectID = folder.objectID
    }
  }
}
