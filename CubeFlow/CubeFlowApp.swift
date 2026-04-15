//
//  CubeFlowApp.swift
//  CubeFlow
//
//  Created by Paul Sun on 3/2/26.
//

import SwiftUI
import SwiftData

@main
struct CubeFlowApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            Session.self,
            Solve.self,
        ])
        do {
            let localConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .none
            )
            return try ModelContainer(for: schema, configurations: [localConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

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
        .modelContainer(sharedModelContainer)
    }
}
