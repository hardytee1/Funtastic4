//
//  AppDelegate.swift
//  Funtastic4
//
//  Created by Hardy Tee on 18/10/26.
//

import CloudKit
import UIKit

/// SwiftUI has no hook for opening a CloudKit share link, so a scene delegate catches it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    /// The link opened the app from scratch.
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {
            TripStore.shared.receiveInvite(metadata)
        }
    }

    /// The link was opened while the app was already running.
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        TripStore.shared.receiveInvite(cloudKitShareMetadata)
    }
}
