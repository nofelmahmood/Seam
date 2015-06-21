#CKSIncrementalStore
CloudKit meets CoreData. 
CKSIncrementalStore is a subclass of [NSIncrementalStore](https://developer.apple.com/library/prerelease/ios/documentation/CoreData/Reference/NSIncrementalStore_Class/index.html) which automatically maintains a SQLite local cache (using CoreData) of user’s private data on CloudKit Servers and keeps it in sync.</p>

####Seeing is believing !

```swift
var coordinator: NSPersistentStoreCoordinator? = NSPersistentStoreCoordinator(managedObjectModel:self.managedObjectModel)
let url = self.applicationDocumentsDirectory.URLByAppendingPathComponent("CKSIncrementalStore_iOSDemo.sqlite")
var error: NSError? = nil
var failureReason = "There was an error creating or loading the application's saved data."
  
var persistentStore:NSPersistentStore? = coordinator!.addPersistentStoreWithType(CKSIncrementalStore.type, configuration: nil, URL: url, options: nil, error: &error)

if persistentStore != nil
{
    self.cksIncrementalStore = persistentStore as? CKSIncrementalStore
    // Its best to have a property for the IncrementalStore
}

```
#### Did I mentioned Sync earlier !

Yes! CKSIncrementalStore automatically keeps the data in sync with the CloudKit servers. There are two ways to do that.

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
#### Sync Conflicts

We all have conflicts in our lives and so does data. Sometimes we don't have answers to the ones in life but we do have for the ones here :P

`CKSIncrementalStore supports 4 sync conflict resolution policies out of the box.`

* <b>GreaterModifiedDateWins</b>

This is the default. Record with the greater modified date is considered to the true record.

* <b>UserTellsWhichWins</b>

Setting this sync policy requires that you set the `recordConflictResolutionBlock` instance of `CKSIncrementalStore`.

```swift
var recordConflictResolutionBlock:((clientRecord:CKRecord,serverRecord:CKRecord)->CKRecord)?
```
It gives you two records. Client record and Server record. You do what ever changes you want on the server record and return it.

* <b>ServerRecordWins</b>

It simply considers the Server record as the true record.

* <b>ClientRecordWins</b>

It simply considers the Client record as the true record.

You can set any policy by setting the `cksStoresSyncConflictPolicy` property of an instance of `CKSIncrementalStore`
```swift
self.cksIncrementalStore.cksStoresSyncConflictPolicy = CKSStoresSyncConflictPolicy.ClientRecordWins
```

## Getting Started 
See the sample demos. Run the iOS App on two devices and start adding, removing and modifying records and experience the magic.

## Installation
`CocoaPods` is the recommended way of adding CKSIncrementalStore to your project.

```
platform :ios, '8.0'

pod 'CKSIncrementalStore'
```

## Credits
CKSIncrementalStore was created by [Nofel Mahmood](http://twitter.com/NofelMahmood)

## Contact 
Follow Nofel Mahmood on [Twitter](http://twitter.com/NofelMahmood) and [GitHub](http://github.com/nofelmahmood) or email me at nofelmehmood@gmail.com

## License
CKSIncrementalStore is available under the MIT license. See the LICENSE file for more info.
