//
//  CKSIncrementalStoreSyncOperationTokenHandler.swift
//  
//
//  Created by Nofel Mahmood on 02/08/2015.
//
//

import UIKit
import CloudKit

class CKSIncrementalStoreSyncOperationTokenHandler
{
    static let defaultHandler = CKSIncrementalStoreSyncOperationTokenHandler()
    private var newToken: CKServerChangeToken?
    
    func token()->CKServerChangeToken?
    {
        if NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreSyncOperationFetchChangeTokenKey) != nil
        {
            let fetchTokenKeyArchived = NSUserDefaults.standardUserDefaults().objectForKey(CKSIncrementalStoreSyncOperationFetchChangeTokenKey) as! NSData
            return NSKeyedUnarchiver.unarchiveObjectWithData(fetchTokenKeyArchived) as? CKServerChangeToken
        }
        
        return nil
    }
    
    func save(serverChangeToken serverChangeToken:CKServerChangeToken)
    {
        self.newToken = serverChangeToken
    }
    
    func commit()
    {
        if self.newToken != nil
        {
            NSUserDefaults.standardUserDefaults().setObject(NSKeyedArchiver.archivedDataWithRootObject(self.newToken!), forKey: CKSIncrementalStoreSyncOperationFetchChangeTokenKey)
        }
    }
    
    func delete()
    {
        if self.token() != nil
        {
            NSUserDefaults.standardUserDefaults().setObject(nil, forKey: CKSIncrementalStoreSyncOperationFetchChangeTokenKey)
        }
    }
}
