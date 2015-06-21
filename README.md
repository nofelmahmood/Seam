#CKSIncrementalStore
CloudKit meets CoreData. 
CKSIncrementalStore is a subclass of [NSIncrementalStore](https://developer.apple.com/library/prerelease/ios/documentation/CoreData/Reference/NSIncrementalStore_Class/index.html) subclass which automatically maintains a SQLite local cache (using CoreData) of user’s private data on CloudKit Servers and keeps it in sync.</p>

####Let the code do the talking !

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

