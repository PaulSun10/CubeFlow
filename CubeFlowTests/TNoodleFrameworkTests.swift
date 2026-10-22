import XCTest
@testable import CubeFlow

final class TNoodleFrameworkTests: XCTestCase {
    private func fixture() throws -> URL {
        let app = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try plist(["CFBundleIdentifier": "test.cubeflow.app", "CFBundlePackageType": "APPL"], to: app)
        addTeardownBlock { try? FileManager.default.removeItem(at: app) }
        return app
    }
    private func plist(_ values: [String: String], to folder: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            .write(to: folder.appendingPathComponent("Info.plist"))
    }
    func testProductionResolverFindsFrameworkExecutableWithoutLoadingIt() throws {
        let app = try fixture()
        let framework = app.appendingPathComponent("Frameworks/TNoodleRuntime.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try plist(["CFBundleIdentifier": "test.cubeflow.runtime", "CFBundlePackageType": "FMWK",
                   "CFBundleExecutable": "TNoodleRuntime"], to: framework)
        let binary = framework.appendingPathComponent("TNoodleRuntime")
        try Data().write(to: binary)
        let bundle = try XCTUnwrap(Bundle(url: app))
        XCTAssertEqual(TNoodleNativeBridge.runtimeLibraryURL(in: bundle)?.standardizedFileURL, binary.standardizedFileURL)
        XCTAssertFalse(try XCTUnwrap(Bundle(url: framework)).isLoaded, "Resolving metadata must not execute a device binary")
        try FileManager.default.removeItem(at: binary)
        XCTAssertNil(TNoodleNativeBridge.runtimeLibraryURL(in: bundle))
    }
    func testBareDylibDoesNotSatisfyFrameworkContract() throws {
        let app = try fixture()
        try Data().write(to: app.appendingPathComponent("lib-scrambles.dylib"))
        let frameworks = app.appendingPathComponent("Frameworks")
        try FileManager.default.createDirectory(at: frameworks, withIntermediateDirectories: true)
        try Data().write(to: frameworks.appendingPathComponent("lib-scrambles.dylib"))
        XCTAssertNil(TNoodleNativeBridge.runtimeLibraryURL(in: try XCTUnwrap(Bundle(url: app))))
    }
    func testSimulatorRetainsUnavailableTNoodleAndExistingFastGenerator() throws {
        #if targetEnvironment(simulator)
        XCTAssertNil(TNoodleNativeBridge.scramble(forEventIndex: TNoodlePuzzleRegistry.three.rawValue))
        XCTAssertEqual(TNoodleNativeBridge.initializationErrorDescription(), "TNoodle is unavailable on Simulator.")
        TNoodleNativeBridge.prewarm()
        let context = TimerScrambleGenerationContext(sessionID: UUID(), event: .threeByThree,
            multiBlindCount: 1, unavailableMessage: "Unavailable")
        let generated = TimerScrambleGenerator.generateSynchronously(for: context)
        XCTAssertEqual(generated.primaryScramble, "Unavailable", "Do not replace the existing device-only 3x3 generator")
        let fast = TimerScrambleGenerationContext(sessionID: UUID(), event: .fourByFourFast,
            multiBlindCount: 1, unavailableMessage: "Unavailable")
        let tokens = TimerScrambleGenerator.generateSynchronously(for: fast).primaryScramble.split(separator: " ")
        XCTAssertEqual(tokens.count, 40)
        XCTAssertTrue(tokens.allSatisfy { token in
            ["R", "L", "Rw", "Lw", "U", "D", "Uw", "Dw", "F", "B", "Fw", "Bw"]
                .contains(String(token).replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "2", with: ""))
        })
        #endif
    }
}
