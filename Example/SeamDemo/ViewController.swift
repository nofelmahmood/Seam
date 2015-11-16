//
//  ViewController.swift
//  SeamDemo
//
//  Created by Nofel Mahmood on 12/08/2015.
//  Copyright © 2015 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
      let context = CoreDataStack.defaultStack.managedObjectContext
//      if let task = Task.new(inContext: context) as? Task {
//        task.name = "Task that must be synced"
//        try! context.save()
//      }
      
      let allTasks = Task.all(inContext: context) as? [Task]
      print("Tasks")
      allTasks?.forEach { task in
        print(task.name)
      }
//      let newTask = Task.new(inContext: context) as? Task
//      newTask?.name = "NewTaskSendToServer"
//      try! context.save()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
}

