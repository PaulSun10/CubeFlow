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
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Create the app-owned central even when iOS relaunches us for BLE restoration.
        if !SavedSmartCubeDevices.shared.devices.isEmpty || launchOptions?[.bluetoothCentrals] != nil {
            SmartCubeBluetoothManager.shared.prepareIfNeeded()
        }
        return true
    }

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

    private let persistenceController: PersistenceController
    @AppStorage("timerAccuracy") private var timerAccuracy = SolveTimeAccuracy.thousandths.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG && os(iOS) && targetEnvironment(simulator)
        if ProcessInfo.processInfo.environment["CUBEFLOW_DATA_TOOLBAR_UI_TEST"] == "1" {
            let store = PersistenceController(inMemory: true)
            let context = store.container.viewContext
            let source = Session(name: "Toolbar source", context: context)
            _ = Session(name: "Toolbar destination", context: context)
            for index in 0..<1_021 {
                _ = Solve(time: 9 + Double(index) / 100, scramble: "R U", event: "3x3", session: source, context: context)
            }
            try! context.save()
            persistenceController = store
        } else {
            persistenceController = .shared
        }
        #else
        persistenceController = .shared
        #endif
        registerSystemAppLanguage()
        #if os(iOS)
        TimerScrambleGenerator.prewarm()
        // Begin exactly the persisted visible event while SwiftUI mounts. The
        // Timer may consume it once only if the full context still matches.
        if UIApplication.shared.applicationState != .background,
           let id = UUID(uuidString: UserDefaults.standard.string(forKey: "selectedSessionID") ?? ""),
           let session = try? persistenceController.container.viewContext.fetchSession(with: id),
           let event = PuzzleEvent(rawValue: session.selectedEventRawValue),
           event != .threeByThreeMBLD,
           !(SessionTimingMethod(rawValue: session.selectedTimingMethodRawValue
                ?? UserDefaults.standard.string(forKey: "enteringTimesWith") ?? "timer") ?? .timer).usesSmartCube {
            let context = TimerScrambleGenerationContext(sessionID: id, event: event, multiBlindCount: 1,
                unavailableMessage: currentAppLocalizedString("timer.scramble_unavailable"))
            TimerLaunchScrambleReservation.shared.prepare(context) { context, complete in
                TimerScrambleGenerator.generate(for: context, reason: "launch-reservation", completion: complete)
            }
        }
        #endif
    }

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
        .environment(\.solveTimeAccuracy, SolveTimeAccuracy.resolved(from: timerAccuracy))
        .onChange(of: scenePhase) { phase in
            if phase == .active { registerSystemAppLanguage() }
        }
    }
}
