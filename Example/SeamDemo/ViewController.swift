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

class ViewController: UIViewController {
  @IBOutlet var tableView: UITableView!
  var notes: [Note]!
  override func viewDidLoad() {
    super.viewDidLoad()
    prepareDataSource()
    tableView.reloadData()
  }
  
  override func viewWillAppear(animated: Bool) {
    super.viewWillAppear(animated)
    let context = CoreDataStack.defaultStack.managedObjectContext
    try! context.save()
    context.performSyncAndMerge {
      NSOperationQueue.mainQueue().addOperationWithBlock {
        self.prepareDataSource()
        self.tableView.reloadData()
      }
    }
  }
  
  func prepareDataSource() {
    let context = CoreDataStack.defaultStack.managedObjectContext
    notes = Note.all(inContext: context) as! [Note]
  }
  
  override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
  }
  
  override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
    if segue.identifier == "Detail" {
      
    }
  }
}

