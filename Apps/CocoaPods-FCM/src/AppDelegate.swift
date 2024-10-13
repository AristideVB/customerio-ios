import CioMessagingInApp
import CioMessagingPushFCM
import CioTracking
import FirebaseCore
import FirebaseMessaging
import Foundation
import SampleAppsCommon
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        print("App launched, initializing Firebase and Customer.io SDKs.")

        // Initialize Firebase SDK
        FirebaseApp.configure()
        print("Firebase SDK initialized.")

        // Initialize Customer.io SDK
        let appSetSettings = CioSettingsManager().appSetSettings
        let siteId = appSetSettings?.siteId ?? BuildEnvironment.CustomerIO.siteId
        let apiKey = appSetSettings?.apiKey ?? BuildEnvironment.CustomerIO.apiKey

        print("Initializing Customer.io with site ID: \(siteId) and API key.")
        CustomerIO.initialize(siteId: siteId, apiKey: apiKey, region: .US) { config in
            config.autoTrackPushEvents = true
            config.logLevel = .debug
            appSetSettings?.configureCioSdk(config: &config)
        }
        print("Customer.io SDK initialized.")

        // Initialize in-app messaging
        MessagingInApp.initialize(eventListener: self)
        MessagingPushFCM.initialize { config in
            config.autoFetchDeviceToken = true
        }
        print("MessagingPushFCM initialized.")

        // Request permission for notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error.localizedDescription)")
            }
            if granted {
                print("Notification permissions granted.")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("Notification permissions denied.")
            }
        }

        // Set Firebase Messaging delegate
        Messaging.messaging().delegate = self

        return true
    }

    // Called when APNs successfully registers the device and provides a device token
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Convert APNs device token to string (for logging purposes)
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let tokenString = tokenParts.joined()
        print("APNs device token received: \(tokenString)")

        // Assign APNs token to Firebase
        Messaging.messaging().apnsToken = deviceToken
        print("APNs token assigned to Firebase.")

        // Fetch FCM token after setting APNs token
        Messaging.messaging().token { token, error in
            if let error = error {
                print("Error fetching FCM token: \(error.localizedDescription)")
            } else if let token = token {
                print("FCM token received: \(token)")
                // Register the FCM token with Customer.io
                MessagingPush.shared.registerDeviceToken(token)
                print("FCM token registered with Customer.io: \(token)")
            } else {
                print("FCM token is nil.")
            }
        }
    }

    // Called when APNs registration fails
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

extension AppDelegate: MessagingDelegate {
    // Called when a new FCM token is generated or refreshed
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken = fcmToken else {
            print("FCM token is nil, skipping registration with Customer.io.")
            return
        }

        print("New FCM token received: \(fcmToken), registering with Customer.io.")
        // Register the FCM token with Customer.io
        MessagingPush.shared.registerDeviceToken(fcmToken)
        print("FCM token registered with Customer.io.")
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    // Handle push notification click or interaction
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        print("Push notification clicked: \(response.notification.request.content.userInfo)")
        CustomerIO.shared.track(
            name: "push clicked",
            data: ["push": response.notification.request.content.userInfo]
        )
        completionHandler()
    }

    // Optional: Handle displaying notification while the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        print("Push notification received in foreground: \(notification.request.content.userInfo)")
        completionHandler([.alert, .sound, .badge])
    }
}

extension AppDelegate: InAppEventListener {
    func messageShown(message: InAppMessage) {
        print("In-app message shown: \(message.messageId)")
        CustomerIO.shared.track(
            name: "inapp shown",
            data: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func messageDismissed(message: InAppMessage) {
        print("In-app message dismissed: \(message.messageId)")
        CustomerIO.shared.track(
            name: "inapp dismissed",
            data: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func errorWithMessage(message: InAppMessage) {
        print("Error with in-app message: \(message.messageId)")
        CustomerIO.shared.track(
            name: "inapp error",
            data: ["delivery-id": message.deliveryId ?? "(none)", "message-id": message.messageId]
        )
    }

    func messageActionTaken(message: InAppMessage, actionValue: String, actionName: String) {
        print("In-app message action taken: \(actionName), action value: \(actionValue)")
        CustomerIO.shared.track(
            name: "inapp action",
            data: [
                "delivery-id": message.deliveryId ?? "(none)",
                "message-id": message.messageId,
                "action-value": actionValue,
                "action-name": actionName
            ]
        )
    }
}
