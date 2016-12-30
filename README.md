![seamlogo](https://cloud.githubusercontent.com/assets/3306263/11891970/83208bf0-a585-11e5-98b5-3ac6bff009d9.png)


[![Pod Version](https://img.shields.io/badge/pod-v0.6-blue.svg)](https://img.shields.io/cocoapods/v/Alamofire.svg)
[![Carthage Compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)
[![Platform](https://img.shields.io/badge/platform-iOS%20--%20OSX-lightgrey.svg)](https://img.shields.io/badge/platform-iOS%20--%20OSX-lightgrey.svg)
[![License](https://img.shields.io/packagist/l/doctrine/orm.svg)](https://img.shields.io/packagist/l/doctrine/orm.svg)

Seam allows you to sync your CoreData Stores with CloudKit.

## Topics

- [Features](#features)
- [Requirements](#requirements)
- [Communication](#communication)
- [Installation](#installation)
- [Usage](#usage)
- [Getting Started](#getting-started)
- [FAQ](#faq)
- [Apps](#apps)
- [Author](#author)
- [License](#license)

## Features
- Automatic mapping of CoreData Models to CloudKit Private Databases
- Supports Assets
- Background Sync 
- Conflict Resolution

## Requirements

- iOS 8.0+ / Mac OS X 10.10+
- Xcode 7.1+

## Communication

- If you want to contribute submit a [pull request](https://github.com/nofelmahmood/Seam/pulls).
- If your app uses Seam I'll be glad to add it to the list. Edit the [List](APPS.md) and submit a [pull request](https://github.com/nofelmahmood/Seam/pulls).
- If you found a bug [open an issue](https://github.com/nofelmahmood/Seam/issues).
- If you have a feature request [open an issue](https://github.com/nofelmahmood/Seam/issues).
- If you have a question, ask it on [Stack Overflow](http://stackoverflow.com).

Please read the [Contributing Guidelines](CONTRIBUTING.md) before doing any of above.

## Installation

### Cocoapods

[CocoaPods](http://cocoapods.org) is a dependency manager for Cocoa projects. You can install it with the following command:

```bash
$ gem install cocoapods
```

To integrate Seam into your Xcode project using CocoaPods, specify it in your `Podfile`:

```ruby
source 'https://github.com/CocoaPods/Specs.git'
platform :ios, '8.0'
use_frameworks!

pod 'Seam', '~> 0.6'
```

Then, run the following command:

```bash
$ pod install
```

### Carthage

[Carthage](https://github.com/Carthage/Carthage) is a decentralized dependency manager that builds your dependencies and provides you with binary frameworks.

You can install Carthage with [Homebrew](http://brew.sh/) using the following command:

```bash
$ brew update
$ brew install carthage
```

To integrate Seam into your Xcode project using Carthage, specify it in your `Cartfile`:

```ogdl
github "Seam/Seam" ~> 0.6
```

Run `carthage update` to build the framework and drag the built `Seam.framework` into your Xcode project.

## Usage

Add a Store type of ```SeamStoreType``` to a NSPersistentStoreCoordinator in your CoreData stack:

``` swift
let persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: yourModel)
let seamStore = try persistentStoreCoordinator.addPersistentStoreWithType(SeamStoreType, 
                                                                          configuration: nil, 
                                                                          URL: url, options: nil) as? Store
```
Observe the following two Notifications to know when the Sync Operation starts and finishes:

``` swift

NSNotificationCenter.defaultCenter().addObserver(self, selector: "didStartSyncing:",
                                                name: SMStoreDidStartSyncingNotification,
                                                object: seamStore)

NSNotificationCenter.defaultCenter().addObserver(self, selector: "didFinishSyncing:",
                                                name: SMStoreDidFinishSyncingNotification,
                                                object: seamStore)                                               

func didStartSyncing(notification: NSNotification) {
  // Prepare for new data before syncing completes
}
  
func didFinishSyncing(notification: NSNotification) {
  // Merge Changes into your context after syncing completes
  mainContext.mergeChangesFromStoreDidFinishSyncingNotification(notification)
}
  
```

Finally call sync whenever and wherever you want:

```swift
seamStore.sync(nil)
```

To trigger sync whenever a change happens on the CloudKit Servers. Subscribe the store to receive Push Notifications from the CloudKit Servers.

```swift
seamStore.subscribeToPushNotifications({ successful in
    guard successful else { return }
    // Ensured that subscription was created successfully
})

// In your AppDelegate

func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject]) {
    seamStore.sync(nil)
}
```


## Attributes

All CloudKit Attributes are mapped automatically to your CoreData attributes with the exception of [CKAsset](https://developer.apple.com/library/ios/documentation/CloudKit/Reference/CKAsset_class/) and [CLLocation](https://developer.apple.com/library/ios/documentation/CoreLocation/Reference/CLLocation_Class/).

CKAsset and CLLocation can be used by setting the corresponding attribute as Transformable in your CoreData Model.

| CloudKit  | CoreData |
| ------------- | ------------- |
| NSDate    | NSDate
| NSData | NSData
| NSString  | NSString   |
| NSNumber | NSNumber |
| CKReference | NSManagedObject |
| CKAsset | Transformable |
| CLLocation | Transformable |

### Transformable Attributes

CKAsset and CLLocation can be used in your CoreData model as Transformable attributes.

1. To use **CKAsset** set **Transformable** as AttributeType and **CKAssetTransformer** as value transformer name for the attribute.

![](https://cloud.githubusercontent.com/assets/3306263/11773251/f342fd36-a248-11e5-8b55-519400fdb600.png)

2. To use **CLLocation** set **Transformable** as AttributeType and **CLLocationTransformer** as value transformer name for the attribute.

![](https://cloud.githubusercontent.com/assets/3306263/11773252/f3459564-a248-11e5-89eb-197c32ef245a.png)


## Relationships

| CoreData Relationship  | Translation on CloudKit |
| ------------- | ------------- |
| To - one    | To one relationships are translated as CKReferences on the CloudKit Servers.|
| To - many    | To many relationships are not explicitly created. Seam only creates and manages to-one relationships on the CloudKit Servers. <br/> <strong>Example</strong> -> If an Employee has a to-one relationship to Department and Department has a to-many relationship to Employee than Seam will only create the former on the CloudKit Servers. It will fullfil the later by using the to-one relationship. If all employees of a department are accessed Seam will fulfil it by fetching all the employees that belong to that particular department.|

<strong>Note :</strong> You must create inverse relationships in your app's CoreData Model or Seam wouldn't be able to translate CoreData Models in to CloudKit Records. Unexpected errors and curroption of data can possibly occur.

## Getting Started 

Download the demo project. Run it and see the magic as it happens.

## FAQ

### tvOS Support ?
tvOS provides no persistent local storage. Seam uses SQLITE file to keep a local copy of your database which is not possible with tvOS.

## Apps

A [list of Apps](APPS.md) which are using **Seam**.

## Author

Seam is owned and maintained by [Nofel Mahmood](http://twitter.com/NofelMahmood).

You can follow him on [Twitter](http://twitter.com/NofelMahmood) and [Medium](http://medium.com/@nofelmahmood)

## License

Seam is available under the MIT license. See the [LICENSE file](LICENSE.md) for more info.
