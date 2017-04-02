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
        if let cell = tableView.cellForRow(at: indexPath) as? FolderTableViewCell {
          let folder = controller.object(at: indexPath) as! Folder
          cell.configureWithFolder(folder)
        }
      }
    case .delete:
      if let indexPath = indexPath {
        tableView.deleteRows(at: [indexPath], with: .automatic)
      }
    case .move:
      if let indexPath = indexPath, let newIndexPath = newIndexPath {
        let object = controller.object(at: newIndexPath) as! Folder
        if let cell = tableView.cellForRow(at: indexPath) as? FolderTableViewCell {
          cell.configureWithFolder(object)
        }
        tableView.moveRow(at: indexPath, to: newIndexPath)
      }
    }
  }
}

class FoldersViewController: UIViewController {
  @IBOutlet var tableView: UITableView!
  
  var context = CoreDataStack.defaultStack.managedObjectContext
  var fetchedResultsController: NSFetchedResultsController<NSFetchRequestResult>!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    // Do any additional setup after loading the view.
    let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Folder")
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
  
  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    if let store = CoreDataStack.defaultStack.store {
      NotificationCenter.defaultCenter().addObserver(self, selector: "didSync:", name: SMStoreDidFinishSyncingNotification, object: nil)
      store.subscribeToPushNotifications({ successful in
        print("Subscription ", successful)
        guard successful else { return }
      })
      store.sync(nil)
    }
  }
  
  func didSync(_ notification: Notification) {
    let context = CoreDataStack.defaultStack.managedObjectContext
    context.performAndWait {
      context.mergeChanges(fromContextDidSave: notification)
    }
  }
  
  func prepareDataSource() throws {
    try fetchedResultsController.performFetch()
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  func confirmDeletion(_ folder: Folder) {
    let alertController = UIAlertController(title: "Delete \"\(folder.name!)\"", message: "Are you sure?", preferredStyle: .actionSheet)
    let yesAction = UIAlertAction(title: "Yes", style: .destructive, handler: { alertAction in
      self.context.delete(folder)
      try! self.context.save()
    })
    let noAction = UIAlertAction(title: "No", style: .cancel, handler: { alertAction in
      self.dismiss(animated: true, completion: nil)
    })
    alertController.addAction(yesAction)
    alertController.addAction(noAction)
    present(alertController, animated: true, completion: nil)
  }
  
  func addFolder(_ name: String) {
    Folder.folderWithName(name, inContext: context)
    try! context.save()
  }
  
  // MARK: IBActions
  @IBAction func didPressAddButton(_ sender: AnyObject) {
    let alertController = UIAlertController(title: "New Folder", message: "Enter a name for the Folder", preferredStyle: .alert)
    var folderName: String?
    let saveAction = UIAlertAction(title: "Save", style: .default, handler: { alertAction in
      if let folderName = folderName, folderName.isEmpty == false {
        self.addFolder(folderName)
      }
    })
    saveAction.isEnabled = false
    let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: { alertAction in
      self.dismiss(animated: true, completion: nil)
    })
    alertController.addTextField { textField in
      textField.placeholder = "Folder Name"
      NotificationCenter.default.addObserver(forName: NSNotification.Name.UITextFieldTextDidChange, object: textField, queue: OperationQueue.main) { (notification) in
        saveAction.isEnabled = textField.text != ""
        folderName = textField.text
      }
    }
    alertController.addAction(saveAction)
    alertController.addAction(cancelAction)
    present(alertController, animated: true, completion: nil)
  }

  
  // MARK: - Navigation
  
  // In a storyboard-based application, you will often want to do a little preparation before navigation
  override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
  // Get the new view controller using segue.destinationViewController.
  // Pass the selected object to the new view controller.
    let destinationViewController = segue.destination as! NotesViewController
    if let selectedIndexPath = tableView.indexPathForSelectedRow {
      let folder = fetchedResultsController.object(at: selectedIndexPath) as! Folder
      destinationViewController.folderObjectID = folder.objectID
    }
  }
}
