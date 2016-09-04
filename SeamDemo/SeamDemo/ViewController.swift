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
        
        let moc = CoreDataStack.defaultStack.managedObjectContext
        
        do
        {
            try moc.save()
        }
        catch
        {
            print("Error thrown baby\n")
        }
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Task")
        do
        {
            let results = try moc.fetch(fetchRequest)
            for result in results as! [Task]
            {
                result.name = "\(result.name!) ClientChange"
            }
            try moc.save()
        }
        catch
        {
            
        }

        let task: Task = NSEntityDescription.insertNewObject(forEntityName: "Task", into: moc) as! Task
        task.name = "HElaLuia"
        
        let cycling: Task = NSEntityDescription.insertNewObject(forEntityName: "Task", into: moc) as! Task
        cycling.name = "Foolish"
        
        let biking: Task = NSEntityDescription.insertNewObject(forEntityName: "Task", into: moc) as! Task
        biking.name = "Acting"
        
        let outdoorTasksTag = NSEntityDescription.insertNewObject(forEntityName: "Tag", into: moc) as! Tag
        outdoorTasksTag.name = "AnotherTag"
        
        let newTasksTag = NSEntityDescription.insertNewObject(forEntityName: "Tag", into: moc) as! Tag
        newTasksTag.name = "Just Another Tag"
        newTasksTag.task = biking
        
        outdoorTasksTag.task = cycling
      
      
        if moc.hasChanges
        {
            do
            {
                try moc.save()
            }
            catch let error as NSError?
            {
                print("Error Occured \(error!)\n")
            }
        }
        CoreDataStack.defaultStack.seamStore!.triggerSync()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

