//    Token.swift
//
//    The MIT License (MIT)
//
//    Copyright (c) 2015 Nofel Mahmood ( https://twitter.com/NofelMahmood )
//
//    Permission is hereby granted, free of charge, to any person obtaining a copy
//    of this software and associated documentation files (the "Software"), to deal
//    in the Software without restriction, including without limitation the rights
//    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//    copies of the Software, and to permit persons to whom the Software is
//    furnished to do so, subject to the following conditions:
//
//    The above copyright notice and this permission notice shall be included in all
//    copies or substantial portions of the Software.
//
//    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//    SOFTWARE.

import Foundation
import CloudKit

class Token {
  static let Key = "com.seam.syncToken.key"
  private var newToken: CKServerChangeToken?
  static let sharedToken = Token()
  
  func rawToken() -> CKServerChangeToken? {
    guard let rawToken = NSUserDefaults.standardUserDefaults().objectForKey(Token.Key) as? NSData else {
      return nil
    }
    return NSKeyedUnarchiver.unarchiveObjectWithData(rawToken) as? CKServerChangeToken
  }
  
  func save(token: CKServerChangeToken) {
    newToken = token
  }
  
  func discard() {
    newToken = nil
  }
  
  func unCommittedToken() -> CKServerChangeToken? {
    return newToken
  }
  
  func commit() {
    guard let newToken = newToken else {
      return
    }
    let archivedToken = NSKeyedArchiver.archivedDataWithRootObject(newToken)
    NSUserDefaults.standardUserDefaults().setObject(archivedToken, forKey: Token.Key)
  }
  
  func reset() {
    discard()
    NSUserDefaults.standardUserDefaults().setObject(nil, forKey: Token.Key)
  }
}
