//
//  ViewController+UITableViewDataSource.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

extension NotesViewController: UITableViewDataSource {
  func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let sectionInfo = fetchedResultsController.sections?[section] else {
      return 0
    }
    print(sectionInfo.numberOfObjects)
    return sectionInfo.numberOfObjects
  }
  
  func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCellWithIdentifier("CustomTableViewCell", forIndexPath: indexPath) as? CustomTableViewCell
    print(fetchedResultsController.objectAtIndexPath(indexPath))
    let note = fetchedResultsController.objectAtIndexPath(indexPath) as! Note
    cell?.configureWithNote(note)
    return cell!
  }
}
