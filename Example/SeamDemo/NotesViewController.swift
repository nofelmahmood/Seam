//
//  ViewController.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 12/08/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData
import Seam

extension NotesViewController: NSFetchedResultsControllerDelegate {
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
        if let cell = tableView.cellForRowAtIndexPath(indexPath) as? CustomTableViewCell {
          let note = controller.objectAtIndexPath(indexPath) as! Note
          cell.configureWithNote(note)
        }
      }
    case .Delete:
      if let indexPath = indexPath {
        tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
      }
    case .Move:
      if let indexPath = indexPath, let newIndexPath = newIndexPath {
        let object = controller.objectAtIndexPath(newIndexPath) as! Note
        if let cell = tableView.cellForRowAtIndexPath(indexPath) as? CustomTableViewCell {
          cell.configureWithNote(object)
        }
        tableView.moveRowAtIndexPath(indexPath, toIndexPath: newIndexPath)
      }
    }
  }
}
class NotesViewController: UIViewController {
  let context = CoreDataStack.defaultStack.managedObjectContext
  var folderObjectID: NSManagedObjectID!
  var fetchedResultsController: NSFetchedResultsController!
  var segueForNewNote = true
  @IBOutlet var tableView: UITableView!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    let fetchRequest = NSFetchRequest(entityName: "Note")
    let folder = context.objectWithID(folderObjectID) as! Folder
    fetchRequest.predicate = NSPredicate(format: "folder == %@", folder.uniqueObjectID!)
    let sortDescriptor = NSSortDescriptor(key: "text", ascending: false)
    fetchRequest.sortDescriptors = [sortDescriptor]
    fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: nil, cacheName: nil)
    fetchedResultsController.delegate = self
    tableView.delegate = self
    tableView.dataSource = self
    do {
      try prepareDataSource()
      tableView.reloadData()
    } catch {
      print(error)
    }
  }

  func prepareDataSource() throws {
    try fetchedResultsController.performFetch()
  }
  
  func tempContextDidSave(notification: NSNotification) {
    print("GOT FROM TEMPCONTEXT ",notification)
    let context = CoreDataStack.defaultStack.managedObjectContext
    context.mergeChangesFromContextDidSaveNotification(notification)
  }
  
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
    let destinationViewController = segue.destinationViewController as! NoteDetailViewController
    let tempContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
    tempContext.persistentStoreCoordinator = CoreDataStack.defaultStack.persistentStoreCoordinator
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "tempContextDidSave:", name: NSManagedObjectContextDidSaveNotification, object: tempContext)
    destinationViewController.tempContext = tempContext
    if segueForNewNote {
      destinationViewController.folderObjectID = folderObjectID
    } else if let selectedItemIndexPath = tableView.indexPathForSelectedRow {
      let note = fetchedResultsController.objectAtIndexPath(selectedItemIndexPath) as! Note
      destinationViewController.folderObjectID = folderObjectID
      destinationViewController.noteObjectID = note.objectID
    }
  }
}

