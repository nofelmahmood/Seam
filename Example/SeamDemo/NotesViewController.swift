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

class NotesViewController: UIViewController {
  let context = CoreDataStack.defaultStack.managedObjectContext
  @IBOutlet var tableView: UITableView!
  var folderObjectID: NSManagedObjectID!
  var notes: [Note]!
  
  override func viewDidLoad() {
    super.viewDidLoad()
    prepareDataSource()
    tableView.reloadData()
  }
  
  override func viewDidAppear(animated: Bool) {
    super.viewDidAppear(animated)
    prepareDataSource()
    tableView.reloadData()
    context.performSyncAndMerge(nil)
  }
  
  func prepareDataSource() {
    let folder = context.objectWithID(folderObjectID) as! Folder
    notes = folder.notes!.allObjects as! [Note]
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
    destinationViewController.folderObjectID = folderObjectID
    if let selectedItemIndexPath = tableView.indexPathForSelectedRow {
      let note = notes[selectedItemIndexPath.row]
      destinationViewController.note = note
    }
  }
}

