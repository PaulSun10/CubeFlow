#if DEBUG
import XCTest
import SwiftUI
import CoreBluetooth
import Vision
@testable import CubeFlow

@MainActor final class SmartCubeDiscoveryListTests: XCTestCase {
    func testActualCompactTimerBatteryRowRendersInBothAppearances() async throws {
        let manager = SmartCubeBluetoothManager.shared, id = UUID()
        manager.prepareIfNeeded(); try await Task.sleep(nanoseconds: 150_000_000)
        let session = manager.debugMakeRoutedSession(for: id)
        session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3),
                                       name: "GAN CUBE", battery: 76)
        manager.selectActiveDevice(id)
        defer { manager.disconnect(deviceID: id) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: CompatibleNavigationContainer {
            VStack { ConnectedDeviceStatusRows(usesCompactLinks: true, showsSmartTimer: false).padding(24) }
        })
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        for appearance in [UIUserInterfaceStyle.light, .dark] {
            window.overrideUserInterfaceStyle = appearance
            try await Task.sleep(nanoseconds: 150_000_000)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Actual compact Timer battery " + (appearance == .light ? "light" : "dark")
            attachment.lifetime = .keepAlways; add(attachment)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            XCTAssertTrue(text.contains("76%"), text)
            XCTAssertFalse(text.contains("Connected"), "No extra connected status is introduced")
        }
    }
    private func discovered(_ id: UUID, name: String = "Other GAN") -> SmartCubeDiscoveredDevice {
        .init(id: id, name: name, rssi: -45, protocolHint: .ganGen4,
              advertisedServices: [], manufacturerDataHex: nil, macAddress: nil)
    }
    private func remember(_ id: UUID, name: String, store: SavedSmartCubeDevices) {
        let identity = SmartCubeIdentity.resolve(advertisedName: "GAN16ui_Test", protocolFamily: .ganGen4,
            protocolConfirmed: true, protocolInfo: nil, serviceIdentifiers: [])
        store.remember(id: id, identity: identity, fallbackName: name)
        store.rename(id, to: name)
    }
    func testIdentityPartitionDiscoveryDisappearanceAndPersistenceAcrossRestart() throws {
        let suite = "DeviceList." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedSmartCubeDevices(defaults: defaults), a = UUID(), b = UUID(), c = UUID()
        remember(a, name: "Same GAN", store: store); remember(b, name: "Same GAN", store: store)
        var rows = SmartCubeDeviceListSnapshot(saved: store.devices, discovered: [discovered(b), discovered(c), discovered(c)],
            connected: [], connecting: [])
        XCTAssertEqual(Set(rows.saved.map(\.id)), [a, b])
        XCTAssertEqual(rows.connectableSavedIDs, [b])
        XCTAssertEqual(rows.other.map(\.id), [c])
        rows = .init(saved: store.devices, discovered: [], connected: [], connecting: [])
        XCTAssertEqual(rows.saved.count, 2); XCTAssertTrue(rows.connectableSavedIDs.isEmpty)
        remember(c, name: "Other GAN", store: store)
        rows = .init(saved: SavedSmartCubeDevices(defaults: defaults).devices,
            discovered: [discovered(b), discovered(c)], connected: [c], connecting: [b])
        XCTAssertEqual(rows.saved.count, 3); XCTAssertTrue(rows.other.isEmpty)
        XCTAssertTrue(rows.connectableSavedIDs.isEmpty)
        store.forget(b)
        rows = .init(saved: store.devices, discovered: [discovered(b)], connected: [c], connecting: [])
        XCTAssertEqual(rows.other.map(\.id), [b])
    }
    func testMountedSavedSectionAppearsOnlyWhileSavedDevicesExist() async throws {
        let suite = "EmptyDeviceList." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedSmartCubeDevices(defaults: defaults), manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: CompatibleNavigationContainer {
            List { SmartCubeDiscoverySections(manager: manager, saved: store, connect: { _ in }, manage: { _ in }) }
                .navigationTitle("Smart Cube")
        }.environment(\.locale, Locale(identifier: "en")))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func labels(_ name: String) throws -> String {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let empty = try labels("No saved devices hides entire My Devices section")
        XCTAssertFalse(empty.contains("my devices"), empty)
        XCTAssertFalse(empty.contains("no saved"), empty)
        XCTAssertTrue(empty.contains("other devices"), empty)
        let id = UUID()
        remember(id, name: "Offline Cube", store: store)
        try await Task.sleep(nanoseconds: 200_000_000)
        let saved = try labels("Saved offline device restores My Devices")
        for text in ["my devices", "offline cube", "disconnected", "other devices"] {
            XCTAssertTrue(saved.contains(text), saved)
        }
        XCTAssertNil(manager.activeDeviceID)
        store.forget(id)
        try await Task.sleep(nanoseconds: 200_000_000)
        let forgotten = try labels("Forgetting final saved device removes My Devices")
        XCTAssertFalse(forgotten.contains("my devices"), forgotten)
        XCTAssertFalse(forgotten.contains("offline cube"), forgotten)
        XCTAssertFalse(forgotten.contains("no saved"), forgotten)
        XCTAssertTrue(forgotten.contains("other devices"), forgotten)
    }
    func testMountedNativeListWithNoActiveDeviceRetainsSavedAndRefreshesOtherDevices() async throws {
        let suite = "MountedDeviceList." + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SavedSmartCubeDevices(defaults: defaults), manager = SmartCubeBluetoothManager(testSavedDevices: store)
        let a = UUID(), b = UUID(), c = UUID()
        remember(a, name: "Offline Cube", store: store); remember(b, name: "Nearby Cube", store: store)
        manager.debugSetDiscoveries([discovered(b), discovered(c)])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = UIHostingController(rootView: CompatibleNavigationContainer {
            List { SmartCubeDiscoverySections(manager: manager, saved: store, connect: { _ in }, manage: { _ in }) }
                .navigationTitle("Smart Cube")
        }.environment(\.locale, Locale(identifier: "en")))
        window.windowLevel = .alert + 1; window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func labels(_ name: String) throws -> String {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let initial = try labels("Native My Devices and Other Devices without Active")
        for text in ["offline cube", "nearby cube", "other gan", "connect"] { XCTAssertTrue(initial.contains(text), initial) }
        XCTAssertNil(manager.activeDeviceID)
        manager.debugSetDiscoveries([])
        try await Task.sleep(nanoseconds: 100_000_000)
        let refreshed = try labels("Discovery cleared; saved devices retained")
        XCTAssertTrue(refreshed.contains("offline cube")); XCTAssertTrue(refreshed.contains("nearby cube"))
        XCTAssertFalse(refreshed.contains("other gan"))
        XCTAssertNil(manager.activeDeviceID)
    }
}
#endif
