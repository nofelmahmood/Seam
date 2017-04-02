//
//  ViewController+UITableViewDataSource.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 18/11/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit

extension NotesViewController: UITableViewDataSource {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    guard let sectionInfo = fetchedResultsController.sections?[section] else {
      return 0
    }
    print(sectionInfo.numberOfObjects)
    return sectionInfo.numberOfObjects
  }
  
  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "CustomTableViewCell", for: indexPath) as? CustomTableViewCell
    print(fetchedResultsController.object(at: indexPath))
    let note = fetchedResultsController.object(at: indexPath) as! Note
    cell?.configureWithNote(note)
    return cell!
  }
}
