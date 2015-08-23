##### CKSIncrementalStore has been merged into Seam. You can still use the old implementation from this [branch](https://github.com/nofelmahmood/Seam/tree/CKSIncrementalStore). I am busy documenting the new framework. This line will be removed once it is complete. Thank you for your patience and interest. :)

![](http://s14.postimg.org/ll5smugr5/Logo.png)

<p align="center">
 <strong><i>"Simplicity is the ultimate sophistication."</i></strong>
  
- Leonardo da Vinci
 </p>


Seam is a framework built to bridge gaps between CoreData and CloudKit. It almost handles all the CloudKit hassle. All you have to do is use it as a store type for your CoreData store. Local caching and sync is taken care of. It builds and exposes different features to facilitate and give control to the developer where it is demanded and required.

## CoreData to CloudKit

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

## Sync

Seam keeps the CoreData store in sync with the CloudKit Servers. It let's you know when the sync operation starts and finishes by throwing the following two notifications.
- SMStoreDidStartSyncOperationNotification
- SMStoreDidFinishSyncOperationNotification

#### Conflict Resolution Policies
In case of any sync conflicts, Seam exposes 4 conflict resolution policies.

- ClientTellsWhichWins

This policy requires you to set syncConflictResolutionBlock block of SMStore. You get both versions of the records as arguments. You do whatever changes you want on the second argument and return it.

- ServerRecordWins

This is the default. It considers the server record as the true record.

- ClientRecordWins

This considers the client record as the true record.

- KeepBoth

This saves both versions of the record.

## How to use

1. Declare a SMStore type property in the class where your CoreData stack resides.
1. Add it to your app's NSPersistentStoreCoordinator.
2. Assign the returned store to this property.
3. Enable Push Notifications for your app.
4. Implement didReceiveRemoteNotification Method.
5. Call smStore.handlePush()
6. Enjoy

## Support

### What it does support

Seam supports only user's CloudKit `Private Database` at this time. It creates and uses a custom zone to store data and fetch changes from the server.

### What it does not support

CloudKit `Public Database` and here's the two reasons why, straight from the docs.

1. [The disadvantage of using the default zone for storing records is that it does not have any special capabilities. You cannot save a group of records to iCloud atomically in the default zone. Similarly, you cannot use a CKFetchRecordChangesOperation object on records in the default zone.](https://developer.apple.com/library/prerelease/ios/documentation/CloudKit/Reference/CKRecordZone_class/index.html#//apple_ref/occ/clm/CKRecordZone/defaultRecordZone)

2. [ You cannot create custom zones in a public database.](https://developer.apple.com/library/prerelease/ios/documentation/CloudKit/Reference/CKRecordZone_class/index.html#//apple_ref/c/tdef/CKRecordZoneCapabilities)

## Getting Started 
Download the demo project. Run it and see the magic as it happens.

## Installation
CocoaPods is the recommended way of adding Seam to your project.

Add this `'Seam', '~> 0.6'` to your pod file.

## Credits
Seam was created by [Nofel Mahmood](http://twitter.com/NofelMahmood)

## Contact 
Follow Nofel Mahmood on [Twitter](http://twitter.com/NofelMahmood) and [GitHub](http://github.com/nofelmahmood) or email him at nofelmehmood@gmail.com

## License
Seam is available under the MIT license. See the LICENSE file for more info.
