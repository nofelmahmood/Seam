##### CKSIncrementalStore has been merged into Seam. You can still use the old implementation from this [branch](https://github.com/nofelmahmood/Seam/tree/CKSIncrementalStore). I am busy documenting the new framework. This line will be removed once it is complete. Thank you for your patience and interest. :)

![](http://s14.postimg.org/ll5smugr5/Logo.png)

<p align="center">
 <strong><i>"Simplicity is the ultimate sophistication."</i></strong>
  
- Leonardo da Vinci
 </p>


Seam is a framework built to bridge gaps between CoreData and CloudKit. It almost handles all the CloudKit hassle. All you have to do is use it as a store type for your CoreData store. Local caching and sync is taken care of. It builds and exposes different features to facilitate and give control to the developer where it is demanded and required.

## What becomes What

### Attributes

| CoreData  | CloudKit |
| ------------- | ------------- |
| NSDate    | Date/Time
| NSData | Bytes
| NSString  | String   |
| Integer16 | Int(64) |
| Integer32 | Int(64) |
| Integer64 | Int(64) |
| Decimal | Double | 
| Float | Double |
| Boolean | Int(64) |
| NSManagedObject | Reference |

**In the table above :** `Integer16`, `Integer32`, `Integer64`, `Decimal`, `Float` and `Boolean` are referring to the instance of `NSNumber` used to represent them in CoreData Models. `NSManagedObject` refers to a `to-one relationship` in a CoreData Model.

### Relationships

| CoreData Relationship  | Translation on CloudKit |
| ------------- | ------------- |
| To - one    | To one relationships are translated as CKReferences on the CloudKit Servers.|
| To - many    | To many relationships are not explicitly created. Seam only creates and manages to-one relationships on the CloudKit Servers. <br/> <strong>Example</strong> -> If an Employee has a to-one relationship to Department and Department has a to-many relationship to Employee than Seam will only create the former on the CloudKit Servers. It will fullfil the later by using the to-one relationship. If all employees of a department are accessed Seam will fulfil it by fetching all the employees that belong to that particular department.|

<strong>Note :</strong> You must create inverse relationships in your app's CoreData Model or Seam wouldn't be able to translate CoreData Models in to CloudKit Records. Unexpected errors and curroption of data can possibly occur.

### CloudKit Records


####Seeing is believing !
![](https://cdn.pbrd.co/images/1ueV7gsM.gif)

### Start by Adding it

```swift
var coordinator: NSPersistentStoreCoordinator? = NSPersistentStoreCoordinator(managedObjectModel:self.managedObjectModel)
let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("CKSIncrementalStore_iOSDemo.sqlite")
var error: NSError? = nil
var failureReason = "There was an error creating or loading the application's saved data."
  
var persistentStore:NSPersistentStore? = coordinator!.addPersistentStoreWithType(CKSIncrementalStore.type, configuration: nil, URL: url, options: nil, error: &error)

if persistentStore != nil
{
    self.cksIncrementalStore = persistentStore as? CKSIncrementalStore
    // Store it in a property.
}

```
#### How Sync Works

Sync operation uses a private instance of NSManagedObjectContext to perform the operation and throws two notifications to notify when the operation starts and finishes.

##### Notifications
* <b>CKSIncrementalStoreDidStartSyncOperationNotification</b>

Notification is posted when the sync operation starts.

`Example`

```swift
NSNotificationCenter.defaultCenter().addObserver(self, selector: "syncFinished:", name: CKSIncrementalStoreDidStartSyncOperationNotification, object: self.cksIncrementalStore)

```
* <b>CKSIncrementalStoreDidFinishSyncOperationNotification</b>

Notification is posted when the sync operation finishes.

`Example`

```swift
NSNotificationCenter.defaultCenter().addObserver(self, selector: "syncFinished:", name: CKSIncrementalStoreDidFinishSyncOperationNotification, object: self.cksIncrementalStore)
```

Sync works in two ways. One is manual and the other is automatic.

##### Ways to Sync
* <b>Manual Sync</b>

Anytime call triggerSync() on an instance of CKSIncrementalStore.

```swift
self.cksIncrementalStore.triggerSync()
```
* <b>Automatic Sync</b>

Well anytime you call save on an instance of `NSManagedObjectContext`, CKSIncrementalStore calls `triggerSync()` automatically. 

But what if some other device changes some records on the server. Don't worry we have you covered but we need some of your help too.

Enable [Push Notifications](http://code.tutsplus.com/tutorials/setting-up-push-notifications-on-ios--cms-21925) for your app. Then in your AppDelegate's method

```swift
func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) 
{
    self.cksIncrementalStore?.handlePush(userInfo: userInfo)
}
```
#### Sync Conflict Resolution

Life is usually filled up with conflicts and so is data. The good thing about "data" is that we can easily resolve conflicts using libraries like this one.

`CKSIncrementalStore supports 4 sync conflict resolution policies out of the box.`

* <b>GreaterModifiedDateWins</b>

This is the default. Record with the greater modified date is considered to be the true record.

* <b>UserTellsWhichWins</b>

Setting this sync policy requires that you set the `recordConflictResolutionBlock` instance of `CKSIncrementalStore`.

```swift
var recordConflictResolutionBlock:((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
```
It gives you two versions of the record. Client record and Server record. You do what ever changes you want on the server record and return it.

* <b>ServerRecordWins</b>

It simply considers the Server record as the true record.

* <b>ClientRecordWins</b>

It simply considers the Client record as the true record.

You can set any policy by passing it as an option while adding `CKSIncrementalStore` to `NSPersistentStoreCoordinator`.

```swift
var options:Dictionary<NSObject,AnyObject> = Dictionary<NSObject,AnyObject>()
options[CKSIncrementalStoreSyncConflictPolicyOption] = NSNumber(short: CKSStoresSyncConflictPolicy.ClientRecordWins.rawValue)
var persistentStore:NSPersistentStore? = coordinator!.addPersistentStoreWithType(CKSIncrementalStore.type, configuration: nil, URL: url, options: options, error: &error)
```
### What it does support

CKSIncrementalStore supports only user's CloudKit `Private Database` at this time. It creates and uses a custom zone to store data and fetch changes from the server.

### What it does not support

CloudKit `Public Database` and here's the two reasons why, straight from the docs.

1. [The disadvantage of using the default zone for storing records is that it does not have any special capabilities. You cannot save a group of records to iCloud atomically in the default zone. Similarly, you cannot use a CKFetchRecordChangesOperation object on records in the default zone.](https://developer.apple.com/library/prerelease/ios/documentation/CloudKit/Reference/CKRecordZone_class/index.html#//apple_ref/occ/clm/CKRecordZone/defaultRecordZone)

2. [ You cannot create custom zones in a public database.](https://developer.apple.com/library/prerelease/ios/documentation/CloudKit/Reference/CKRecordZone_class/index.html#//apple_ref/c/tdef/CKRecordZoneCapabilities)

## Getting Started 
See the sample iOS demo app. Run it on two devices and start adding, removing and modifying records and experience the magic.

## Installation
`CocoaPods` is the recommended way of adding CKSIncrementalStore to your project.

You want to to add pod `'CKSIncrementalStore', '~> 0.5.2'` similar to the following to your Podfile:
```
target 'MyApp' do
  pod 'CKSIncrementalStore', '~> 0.5.2'
end
```

Then run a `[sudo] pod install` inside your terminal, or from CocoaPods.app.


## Credits
CKSIncrementalStore was created by [Nofel Mahmood](http://twitter.com/NofelMahmood)

## Contact 
Follow Nofel Mahmood on [Twitter](http://twitter.com/NofelMahmood) and [GitHub](http://github.com/nofelmahmood) or email him at nofelmehmood@gmail.com

## License
CKSIncrementalStore is available under the MIT license. See the LICENSE file for more info.
