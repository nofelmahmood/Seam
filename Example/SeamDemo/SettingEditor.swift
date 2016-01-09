//
//  SettingEditor.swift
//  SeamDemo
//
//  Created by Oskari Rauta on 9.1.2016.
//  Copyright © 2016 CloudKitSpace. All rights reserved.
//

import UIKit
import CoreData

class SettingEditor: UITableViewController {

    var settingObj: Setting!

    @IBOutlet var nameField : UITextField?
    @IBOutlet var valueField : UITextField?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.nameField!.text = self.settingObj.name
        self.valueField!.text = self.settingObj.value
    }

    override func viewDidAppear(animated: Bool) {
        self.valueField!.becomeFirstResponder()
        super.viewDidAppear(animated)
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        if indexPath.section == 0 && indexPath.row == 1 && !self.valueField!.isFirstResponder() {
            self.valueField!.becomeFirstResponder()
        }
    }
 
    @IBAction func saveValue(sender: AnyObject) {
        self.settingObj.value = self.valueField!.text
        try! CoreDataStack.defaultStack.managedObjectContext.save()
        self.navigationController!.popViewControllerAnimated(true)
    }
    
}
