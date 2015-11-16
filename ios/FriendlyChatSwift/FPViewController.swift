//
//  Copyright (c) 2015 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import UIKit
import FirebaseDatabase
import Firebase.SignIn
import Firebase.Core

@objc(FPViewController)
class FPViewController: UIViewController, UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate, GINInviteDelegate {

  // Instance variables
  @IBOutlet weak var textField: UITextField!
  @IBOutlet weak var sendButton: UIButton!
  var ref: Firebase!
  var messages: [FDataSnapshot]! = []
  var msglength: NSNumber = 10
  private var _refHandle: FirebaseHandle!
  private var userInt: UInt32 = arc4random()

  @IBOutlet weak var banner: GADBannerView!
  @IBOutlet weak var clientTable: UITableView!

  @IBAction func didSendMessage(sender: UIButton) {
    textFieldShouldReturn(textField)
  }

  @IBAction func didInvite(sender: UIButton) {
    let invite = GINInvite.inviteDialog()
    invite.setMessage("Message")
    invite.setTitle("Title")
    invite.setDeepLink("/invite")

    invite.open()
  }

  // [START invite_finished]
  func inviteFinishedWithInvitations(invitationIds: [AnyObject]!, error: NSError!) {
    if (error != nil) {
      print("Failed: " + error.localizedDescription)
    } else {
      print("Invitations sent")
    }
  }
  // [END invite_finished]

  override func viewDidLoad() {
    super.viewDidLoad()
    NSNotificationCenter.defaultCenter().addObserver(self, selector: "showReceivedMessage:",
      name:Constants.NotificationKeys.Message, object: nil)

    // This will change pending in cl/106974108
    if let plist = NSDictionary(contentsOfFile: NSBundle.mainBundle().pathForResource("GoogleService-Info", ofType: "plist")!) {
      self.ref = Firebase(url: plist["FIREBASE_DATABASE_URL"] as! String)
    }

    loadAd()
    self.clientTable.registerClass(UITableViewCell.self, forCellReuseIdentifier: "tableViewCell")
    fetchConfig()
  }

  func loadAd() {
    self.banner.adUnitID = FIRContext.sharedInstance().adUnitIDForBannerTest
    self.banner.rootViewController = self
    self.banner.loadRequest(GADRequest())
  }

  func fetchConfig() {
    // [START completion_handler]
    let completion:RCNDefaultConfigCompletion = {(config:RCNConfig!, status:RCNConfigStatus, error:NSError!) -> Void in
      if (error != nil) {
        // There has been an error fetching the config
        print("Error fetching config: \(error.localizedDescription)")
      } else {
        // Parse your config data
        // [START_EXCLUDE]
        // [START read_data]
        self.msglength = config.numberForKey("friendly_msg_length", defaultValue: 10)
        print("Friendly msg length config: \(self.msglength)")
        // [END read_data]
        // [END_EXCLUDE]
      }
    }
    // [END completion_handler]

    // [START fetch_config]
    let customVariables = ["build": "dev"]
    // 43200 secs = 12 hours
    RCNConfig.fetchDefaultConfigWithExpirationDuration(43200, customVariables: customVariables,
      completionHandler: completion)
    // [END fetch_config]
  }

  func textField(textField: UITextField, shouldChangeCharactersInRange range: NSRange, replacementString string: String) -> Bool {
    guard let text = textField.text else { return true }

    let newLength = text.utf16.count + string.utf16.count - range.length
    return newLength <= self.msglength.integerValue // Bool
  }

  override func viewWillAppear(animated: Bool) {
    self.messages.removeAll()
    // Listen for new messages in the Firebase database
    _refHandle = self.ref.childByAppendingPath("messages").observeEventType(.ChildAdded, withBlock: { (snapshot) -> Void in
      self.messages.append(snapshot)
      self.clientTable.insertRowsAtIndexPaths([NSIndexPath(forRow: self.messages.count-1, inSection: 0)], withRowAnimation: UITableViewRowAnimation.Automatic)
    })
  }

  override func viewWillDisappear(animated: Bool) {
    self.ref.removeObserverWithHandle(_refHandle)
  }

  // UITableViewDataSource protocol methods
  func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return messages.count
  }

  func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
    // Dequeue cell
    let cell: UITableViewCell! = self.clientTable .dequeueReusableCellWithIdentifier("tableViewCell", forIndexPath: indexPath)

    // Unpack message from Firebase DataSnapshot
    let messageSnapshot: FDataSnapshot! = self.messages[indexPath.row]
    let message = messageSnapshot.value as! Dictionary<String, String>
    let name = message[Constants.MessageFields.name] as String!
    let text = message[Constants.MessageFields.text] as String!
    cell!.textLabel?.text = name + ": " + text
    cell!.imageView?.image = UIImage(named: "ic_account_circle")
    if let photoUrl = message[Constants.MessageFields.photoUrl] {
      if let url = NSURL(string:photoUrl) {
        if let data = NSData(contentsOfURL: url) {
          cell!.imageView?.image = UIImage(data: data)
        }
      }
    }

    return cell!
  }

  // UITextViewDelegate protocol methods
  func textFieldShouldReturn(textField: UITextField) -> Bool {

    // Push data to Firebase Database
    if let user = AppState.sharedInstance.displayName {
      self.ref.childByAppendingPath("messages").childByAutoId().setValue([Constants.MessageFields.name: user, Constants.MessageFields.text: textField.text as String!, Constants.MessageFields.photoUrl: "\(AppState.sharedInstance.photoUrl)"])
    } else {
      self.ref.childByAppendingPath("messages").childByAutoId().setValue([Constants.MessageFields.name: "User\(self.userInt)", Constants.MessageFields.text: textField.text as String!, Constants.MessageFields.photoUrl: "\(AppState.sharedInstance.photoUrl)"])
    }
    textField.text = ""
    return true
  }

  func showReceivedMessage(notification: NSNotification) {
    if let info = notification.userInfo as? Dictionary<String,AnyObject> {
      if let aps = info["aps"] as? Dictionary<String, String> {
        showAlert("Message received", message: aps["alert"]!)
      }
    } else {
      print("Software failure. Guru meditation.")
    }
  }

  @IBAction func signOut(sender: UIButton) {
    let firebaseAuth = FIRAuth.init(forApp:FIRFirebaseApp.initializedAppWithAppId(FIRContext.sharedInstance().serviceInfo.googleAppID)!)
    firebaseAuth?.signOut()
    AppState.sharedInstance.signedIn = false
    performSegueWithIdentifier(Constants.Segues.FpToSignIn, sender: nil)
  }

  func showAlert(title:String, message:String) {
    dispatch_async(dispatch_get_main_queue()) {
      if #available(iOS 8.0, *) {
        let alert = UIAlertController(title: title,
            message: message, preferredStyle: .Alert)
        let dismissAction = UIAlertAction(title: "Dismiss", style: .Destructive, handler: nil)
        alert.addAction(dismissAction)
        self.presentViewController(alert, animated: true, completion: nil)
      } else {
          // Fallback on earlier versions
      }
    }
  }

  func guruMeditation() {
    let error = "Software failure. Guru meditation."
    showAlert("Error", message: error)
    print(error)
  }
}