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
  func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    tableView.beginUpdates()
  }
  func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
    tableView.endUpdates()
  }
  func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
    switch(type) {
    case .insert:
      if let indexPath = newIndexPath {
        tableView.insertRows(at: [indexPath], with: .automatic)
      }
    case .update:
      if let indexPath = indexPath {
        if let cell = tableView.cellForRow(at: indexPath) as? CustomTableViewCell {
          let note = controller.object(at: indexPath) as! Note
          cell.configureWithNote(note)
        }
      }
    case .delete:
      if let indexPath = indexPath {
        tableView.deleteRows(at: [indexPath], with: .automatic)
      }
    case .move:
      if let indexPath = indexPath, let newIndexPath = newIndexPath {
        let object = controller.object(at: newIndexPath) as! Note
        if let cell = tableView.cellForRow(at: indexPath) as? CustomTableViewCell {
          cell.configureWithNote(object)
        }
        tableView.moveRow(at: indexPath, to: newIndexPath)
      }
    }
  }
}
class NotesViewController: UIViewController {
  let context = CoreDataStack.defaultStack.managedObjectContext
  var folderObjectID: NSManagedObjectID!
  var fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult>!
  var segueForNewNote = true
  @IBOutlet var tableView: UITableView!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Note")
    let folder = context.object(with: folderObjectID) as! Folder
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
  
  func tempContextDidSave(_ notification: Notification) {
    print("GOT FROM TEMPCONTEXT ",notification)
    let context = CoreDataStack.defaultStack.managedObjectContext
    context.mergeChanges(fromContextDidSave: notification)
  }
  
  override func viewWillAppear(_ animated: Bool) {
    super.viewWillAppear(animated)
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
    let destinationViewController = segue.destination as! NoteDetailViewController
    let tempContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
    tempContext.persistentStoreCoordinator = CoreDataStack.defaultStack.persistentStoreCoordinator
    NotificationCenter.default.addObserver(self, selector: #selector(NotesViewController.tempContextDidSave(_:)), name: NSNotification.Name.NSManagedObjectContextDidSave, object: tempContext)
    destinationViewController.tempContext = tempContext
    if segueForNewNote {
      destinationViewController.folderObjectID = folderObjectID
    } else if let selectedItemIndexPath = tableView.indexPathForSelectedRow {
      let note = fetchedResultsController.object(at: selectedItemIndexPath) as! Note
      destinationViewController.folderObjectID = folderObjectID
      destinationViewController.noteObjectID = note.objectID
    }
  }
}

