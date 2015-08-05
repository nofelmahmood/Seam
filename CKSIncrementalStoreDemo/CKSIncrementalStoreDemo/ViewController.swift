//
//  TasksViewController.swift
//  Pomodoro
//
//  Created by Nofel Mahmood on 18/06/2015.
//  Copyright (c) 2015 Ninish. All rights reserved.
//

import UIKit
import CoreData

class ViewController: UIViewController,UITableViewDataSource,UITableViewDelegate,UITextFieldDelegate {
    
    @IBOutlet var tasksTableView:UITableView!
    @IBOutlet var newTaskTextField:UITextField!
    
    var tasks:Array<Task> = Array<Task>()
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.newTaskTextField.delegate = self
        NSNotificationCenter.defaultCenter().addObserver(self, selector: Selector("syncFinished:"), name: CKSIncrementalStoreDidFinishSyncOperationNotification, object: CoreDataStack.sharedStack.cksIncrementalStore)
        
        do
        {
            try self.loadTasks()
            self.tasksTableView.reloadData()
        }
        catch
        {
            print("Error")
        }
        
        // Do any additional setup after loading the view.
    }
    
    func textFieldShouldReturn(textField: UITextField) -> Bool {
        
        textField.resignFirstResponder()
        return true
    }
    func textFieldDidEndEditing(textField: UITextField) throws {
        
        let newTask:Task = NSEntityDescription.insertNewObjectForEntityForName("Task", inManagedObjectContext: CoreDataStack.sharedStack.managedObjectContext) as! Task
        newTask.name = textField.text!
        try CoreDataStack.sharedStack.managedObjectContext.save()
        
        textField.resignFirstResponder()
        try self.loadTasks()
        self.tasksTableView.reloadData()
    }
    func loadTasks() throws
    {
        let fetchRequest = NSFetchRequest(entityName: "Task")
        var results = try CoreDataStack.sharedStack.managedObjectContext.executeFetchRequest(fetchRequest)
        
        if results.count > 0
        {
            self.tasks = Array<Task>()
            for task in results as! [Task]
            {
                self.tasks.append(task)
            }
        }
        print("Tasks loaded \(results)", appendNewline: true)
        self.tasksTableView.reloadData()
    }
    
    func syncFinished(notification:NSNotification)
    {
        try! self.loadTasks()
        self.tasksTableView.reloadData()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        
        // Dispose of any resources that can be recreated.
    }
    
    func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) throws {
        
        if editingStyle == UITableViewCellEditingStyle.Delete
        {
            CoreDataStack.sharedStack.managedObjectContext.deleteObject(self.tasks[indexPath.row])
            try CoreDataStack.sharedStack.managedObjectContext.save()
            try self.loadTasks()
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: UITableViewRowAnimation.Left)
        }
    }
    
    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) throws {
        
        let alertViewController = UIAlertController(title: "New Task Name", message: "Enter new task name", preferredStyle: UIAlertControllerStyle.Alert)
        alertViewController.addTextFieldWithConfigurationHandler { (textField) -> Void in
            
            textField.placeholder = "Task Name"
            textField.keyboardType = UIKeyboardType.Default
        }
        let doneAction = UIAlertAction(title: "Done", style: UIAlertActionStyle.Default) { (alertAction) -> Void in
            
            let textField = alertViewController.textFields?.first
            let taskName = textField!.text
            NSOperationQueue.mainQueue().addOperationWithBlock({ ()  -> Void in
                
                do
                {
                    let newTask:Task = self.tasks[indexPath.row]
                    newTask.name = taskName!
                    try CoreDataStack.sharedStack.managedObjectContext.save()
                    self.tasksTableView.reloadData()
                }
                catch
                {
                    
                }
                
            })
        }
        alertViewController.addAction(doneAction)
        self.presentViewController(alertViewController, animated: true, completion: nil)
    }
    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        print("Tasks Count \(self.tasks.count)", appendNewline: true)
        return self.tasks.count
    }
    
    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        
        let cell: SimpleTableViewCell = tableView.dequeueReusableCellWithIdentifier("SimpleTableIdentifier") as! SimpleTableViewCell
        
        let task: Task = self.tasks[indexPath.row] as Task
        cell.label.text = task.name
        return cell
    }
    /*
    // MARK: - Navigation
    
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
    // Get the new view controller using segue.destinationViewController.
    // Pass the selected object to the new view controller.
    }
    */
    
}