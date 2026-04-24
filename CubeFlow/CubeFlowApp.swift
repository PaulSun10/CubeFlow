//
//  CubeFlowApp.swift
//  CubeFlow
//
//  Created by Paul Sun on 3/2/26.
//

import SwiftUI
import CoreData

#if os(iOS)
final class CubeFlowAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppOrientationManager.supportedOrientations
    }
}

enum AppOrientationManager {
    static var supportedOrientations: UIInterfaceOrientationMask = defaultSupportedOrientations
    private static var orientationResetGeneration = 0

    static var defaultSupportedOrientations: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    static func reset() {
        resetToPortrait()
    }

    static func resetToPortrait() {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            supportedOrientations = defaultSupportedOrientations
            return
        }

        orientationResetGeneration += 1
        let generation = orientationResetGeneration

        apply(.portrait, preferredOrientation: .portrait)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard generation == orientationResetGeneration else { return }
            apply(defaultSupportedOrientations, preferredOrientation: .portrait)
        }
    }

    static func set(_ orientations: UIInterfaceOrientationMask, preferredOrientation: UIInterfaceOrientation) {
        orientationResetGeneration += 1
        apply(orientations, preferredOrientation: preferredOrientation)
    }

    private static func apply(_ orientations: UIInterfaceOrientationMask, preferredOrientation: UIInterfaceOrientation) {
        supportedOrientations = orientations

        guard UIDevice.current.userInterfaceIdiom == .phone else { return }

        if #available(iOS 16.0, *) {
            let geometryPreferences = UIWindowScene.GeometryPreferences.iOS(interfaceOrientations: orientations)
            let windowScene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
            windowScene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            windowScene?.requestGeometryUpdate(geometryPreferences)
        } else {
            UIDevice.current.setValue(preferredOrientation.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    private static func refreshSupportedOrientations() {
        if #available(iOS 16.0, *) {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first?
                .windows
                .first?
                .rootViewController?
                .setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
#endif

@main
struct CubeFlowApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(CubeFlowAppDelegate.self) private var appDelegate
    #endif

    private let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                IPadContentView()
            } else {
                IPhoneContentView()
            }
            #elseif os(macOS)
            MacContentView()
            #else
            ContentView()
            #endif
        }
        .environment(\.managedObjectContext, persistenceController.container.viewContext)
    }
}
