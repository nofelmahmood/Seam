//
//  SettingsViewController.swift
//  SeamDemo
//
//  Created by Oskari Rauta on 9.1.2016.
//  Copyright © 2016 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData
import Seam

extension SettingsViewController: NSFetchedResultsControllerDelegate {
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
                if let cell = tableView.cellForRowAtIndexPath(indexPath) as UITableViewCell! {
                    let setting = controller.objectAtIndexPath(indexPath) as! Setting
                    cell.textLabel!.text = setting.name!
                    cell.detailTextLabel!.text = setting.value!
                }
            }
        case .Delete:
            if let indexPath = indexPath {
                tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
            }
        case .Move:
            if let indexPath = indexPath, let newIndexPath = newIndexPath {
                let object = controller.objectAtIndexPath(newIndexPath) as! Setting
                if let cell = tableView.cellForRowAtIndexPath(indexPath) as UITableViewCell! {
                    cell.textLabel!.text = object.name!
                    cell.detailTextLabel!.text = object.value!
                }
                tableView.moveRowAtIndexPath(indexPath, toIndexPath: newIndexPath)
            }
        }
    }
}


class SettingsViewController: UIViewController {
    @IBOutlet var tableView: UITableView!
    
    var context = CoreDataStack.defaultStack.managedObjectContext
    var fetchedResultsController: NSFetchedResultsController!

    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        let fetchRequest = NSFetchRequest(entityName: "Setting")
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
    
    override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        if let store = CoreDataStack.defaultStack.store {
            NSNotificationCenter.defaultCenter().addObserver(self, selector: "didSync:", name: SMStoreDidFinishSyncingNotification, object: nil)
            store.subscribeToPushNotifications({ successful in
                print("Subscription ", successful)
                guard successful else { return }
            })
            store.sync(nil)
        }
    }
    
    func didSync(notification: NSNotification) {
        let context = CoreDataStack.defaultStack.managedObjectContext
        context.performBlockAndWait {
            context.mergeChangesFromContextDidSaveNotification(notification)
        }
    }
    
    func prepareDataSource() throws {
        try fetchedResultsController.performFetch()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func confirmDeletion(setting: Setting) {
        let alertController = UIAlertController(title: "Delete \"\(setting.name!)\"", message: "Are you sure?", preferredStyle: .ActionSheet)
        let yesAction = UIAlertAction(title: "Yes", style: .Destructive, handler: { alertAction in
            self.context.deleteObject(setting)
            try! self.context.save()
        })
        let noAction = UIAlertAction(title: "No", style: .Cancel, handler: { alertAction in
            self.dismissViewControllerAnimated(true, completion: nil)
        })
        alertController.addAction(yesAction)
        alertController.addAction(noAction)
        presentViewController(alertController, animated: true, completion: nil)
    }
    
    func addSetting(name: String, withValue: String) {
        Setting.settingWithNameAndValue(name, value: withValue, inContext: context)
        try! context.save()
    }
    
    // MARK: IBActions
    @IBAction func didPressAddButton(sender: AnyObject) {
        let alertController = UIAlertController(title: "New Folder", message: "Enter a name for the Folder", preferredStyle: .Alert)
        var settingName: String?
        var settingValue: String?
        let saveAction = UIAlertAction(title: "Save", style: .Default, handler: { alertAction in
            if let settingName = settingName where settingName.isEmpty == false {
                if let settingValue = settingValue where true == true {
                    self.addSetting(settingName, withValue: settingValue)
                }
            }
        })
        saveAction.enabled = false
        let cancelAction = UIAlertAction(title: "Cancel", style: .Cancel, handler: { alertAction in
            self.dismissViewControllerAnimated(true, completion: nil)
        })
        alertController.addTextFieldWithConfigurationHandler { textField in
            textField.placeholder = "Setting Name"
            NSNotificationCenter.defaultCenter().addObserverForName(UITextFieldTextDidChangeNotification, object: textField, queue: NSOperationQueue.mainQueue()) { (notification) in
                saveAction.enabled = textField.text != ""
                var saveEnabled: Bool = textField.text != ""
                settingName = textField.text
                if saveEnabled {
                    for var index = 0; index < self.tableView.numberOfRowsInSection(0); index++ {
                        let obj = self.fetchedResultsController.objectAtIndexPath(NSIndexPath(forRow: index, inSection: 0)) as! Setting
                        if obj.name!.lowercaseString == settingName!.lowercaseString {
                            saveEnabled = false
                            break
                        }
                    }
                }
                saveAction.enabled = saveEnabled
            }
        }
        alertController.addTextFieldWithConfigurationHandler { textField in
            textField.placeholder = "Setting Value"
            NSNotificationCenter.defaultCenter().addObserverForName(UITextFieldTextDidChangeNotification, object: textField, queue: NSOperationQueue.mainQueue()) { (notification) in
                settingValue = textField.text
            }
        }
        
        alertController.addAction(saveAction)
        alertController.addAction(cancelAction)
        presentViewController(alertController, animated: true, completion: nil)
    }
    
    
    // MARK: - Navigation
    
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        let destinationViewController = segue.destinationViewController as! SettingEditor
        if let selectedIndexPath = tableView.indexPathForSelectedRow {
            let setting = fetchedResultsController.objectAtIndexPath(selectedIndexPath) as! Setting
            destinationViewController.settingObj = setting
        }
    }

}
