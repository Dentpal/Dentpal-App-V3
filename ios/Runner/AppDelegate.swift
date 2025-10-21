import Flutter
import UIKit
import GoogleMaps
import Firebase

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Configure Firebase
    FirebaseApp.configure()
    
    // Configure Google Maps
    GMSServices.provideAPIKey("AIzaSyBncNj8YjWmg-3XkSCqKIujzXihb6e8ZzI")
    
    GeneratedPluginRegistrant.register(with: self)
    
    // Register for remote notifications (APNs)
    application.registerForRemoteNotifications()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Handle APNs token registration
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Pass device token to Firebase Auth
    Auth.auth().setAPNSToken(deviceToken, type: AuthAPNSTokenType.unknown)
  }
  
  // Handle APNs registration failure
  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Failed to register for remote notifications: \(error)")
  }
  
  // Handle incoming APNs notifications
  override func application(_ application: UIApplication, didReceiveRemoteNotification notification: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    // Pass notification to Firebase Auth
    if Auth.auth().canHandleNotification(notification) {
      completionHandler(UIBackgroundFetchResult.noData)
      return
    }
    // Handle other remote notifications here if needed
    completionHandler(UIBackgroundFetchResult.noData)
  }
}
