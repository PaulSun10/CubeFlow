import Foundation
import Testing
@testable import CubeFlow

@Suite("Smart device integration")
struct SmartDeviceIntegrationTests {
    @Test func timerReadySurvivesIdlePollingEchoAndStartTransition() {
        var readiness = GANTimerHardwareReadiness()

        readiness.consume(packetState: 0x05)
        #expect(!readiness.isReadyForStart)

        readiness.consume(packetState: 0x01)
        #expect(readiness.isReadyForStart)

        readiness.consume(packetState: 0x05)
        #expect(readiness.isReadyForStart)
        #expect(combinedReadiness(timerReady: readiness.isReadyForStart).isReady)

        readiness.consume(packetState: 0x03)
        #expect(readiness.isReadyForStart)
    }

    @Test func timerReadyResetsForAbortStopAndDisconnect() {
        #expect(!combinedReadiness(timerReady: false).isReady)

        for terminalState: UInt8 in [0x02, 0x04, 0x06, 0x07] {
            var readiness = GANTimerHardwareReadiness()
            readiness.consume(packetState: 0x01)
            readiness.consume(packetState: terminalState)
            #expect(!readiness.isReadyForStart)
        }

        var readiness = GANTimerHardwareReadiness()
        readiness.consume(packetState: 0x01)
        readiness.reset()
        #expect(!readiness.isReadyForStart)
    }

    @Test func ganTimerServiceIsExcludedFromSmartCubeDiscovery() {
        let services = ["FFF0"]
        let hint = SmartCubeDiscoveryClassifier.protocolHint(
            name: "GAN Smart Timer",
            serviceIdentifiers: services
        )

        #expect(hint == .unknown)
        #expect(!SmartCubeDiscoveryClassifier.isSupportedSmartCube(
            name: "GAN Smart Timer",
            serviceIdentifiers: services,
            protocolHint: hint
        ))
    }

    @Test func supportedCubeFamiliesRemainDiscoverable() {
        let fixtures: [(String, [String], SmartCubeProtocolKind)] = [
            ("GAN12ui", ["00000010-0000-FFF7-FFF6-FFF5FFF4FFF0"], .ganGen4),
            ("GAN Cube", [], .ganGen4),
            ("WCU_MY32", ["0783B03E-7735-B5A0-1760-A305D2795CB0"], .moyu),
            ("Giiker", [], .giiker)
        ]

        for (name, services, expectedHint) in fixtures {
            let hint = SmartCubeDiscoveryClassifier.protocolHint(
                name: name,
                serviceIdentifiers: services
            )
            #expect(hint == expectedHint)
            #expect(SmartCubeDiscoveryClassifier.isSupportedSmartCube(
                name: name,
                serviceIdentifiers: services,
                protocolHint: hint
            ))
        }
    }

    @Test func batteryPercentagesUseContinuousValidatedValues() {
        #expect(DeviceBatteryLevel.clamped(-1) == 0)
        #expect(DeviceBatteryLevel.clamped(1) == 1)
        #expect(DeviceBatteryLevel.clamped(82) == 82)
        #expect(DeviceBatteryLevel.clamped(101) == 100)
        #expect(GANTimerBatteryLevel.percentage(from: Data([0])) == 0)
        #expect(GANTimerBatteryLevel.percentage(from: Data([82])) == 82)
        #expect(GANTimerBatteryLevel.percentage(from: Data([100])) == 100)
        #expect(GANTimerBatteryLevel.percentage(from: Data([101])) == nil)
        #expect(GANTimerBatteryLevel.percentage(from: Data()) == nil)
    }

    @Test func savedCubeNamesAndAvailableAutoConnectSelection() {
        let ganID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let moyuID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let gan = SavedSmartCubeDevice(
            id: ganID, originalName: "GAN16ui_C014", modelName: "GAN 16 UI",
            protocolFamily: SmartCubeProtocolKind.ganGen4.rawValue,
            puzzleSize: 3, customName: " Paul's GAN ", autoConnect: true
        )
        var moyu = SavedSmartCubeDevice(
            id: moyuID, originalName: "WCU_MY22", modelName: "MoYu WeiPo V5 AI",
            protocolFamily: SmartCubeProtocolKind.moyu.rawValue,
            puzzleSize: 2, customName: nil, autoConnect: true
        )
        #expect(gan.displayName == "Paul's GAN")
        #expect(moyu.displayName == "WCU_MY22")
        #expect(gan.modelName == "GAN 16 UI")
        moyu.customName = " "
        #expect(moyu.displayName == moyu.originalName)
        #expect(SavedSmartCubeSelection.preferredAvailableID(
            devices: [gan, moyu], lastActiveID: ganID, availableIDs: [moyuID]
        ) == moyuID)
        #expect(SavedSmartCubeSelection.preferredAvailableID(
            devices: [gan, moyu], lastActiveID: ganID, availableIDs: [ganID, moyuID]
        ) == ganID)
        #expect(SavedSmartCubeSelection.preferredAvailableID(
            devices: [gan, moyu], lastActiveID: ganID, availableIDs: []
        ) == nil)
    }

    @Test func liveDurationUsesMinutesAtSixtyForFractionalAndIntegerPrecision() {
        #expect(SolveMetrics.formatTime(59.99, decimals: 2, numeralPreferences: .defaults) == "59.99")
        #expect(SolveMetrics.formatTime(60, decimals: 2, numeralPreferences: .defaults) == "1:00.00")
        #expect(SolveMetrics.formatTime(75.42, decimals: 2, numeralPreferences: .defaults) == "1:15.42")
        #expect(SolveMetrics.formatTime(125.43, decimals: 2, numeralPreferences: .defaults) == "2:05.43")
        #expect(SolveMetrics.formatTime(60, decimals: 0, numeralPreferences: .defaults) == "1:00")
        #expect(SolveMetrics.formatTime(75.42, decimals: 0, numeralPreferences: .defaults) == "1:15")
    }

    @Test func twoByTwoLocalSolvedReferenceTracksVerifiedNativeTurns() throws {
        let deviceID = UUID()
        let native = try #require(SmartCubeBluetoothManager.facelets(afterApplying: "R U", puzzleSize: 2))
        let solved = CubeSurface.solved(size: 2)
        var reference = SmartCubeSoftwareResetReference(
            deviceID: deviceID, expectedDeviceFacelets: native, localFacelets: solved
        )
        #expect(reference.resolve(deviceID: deviceID, snapshot: native, forceAuthoritative: false) == .preserveLocal(solved))
        let applied = reference.apply("F")
        #expect(applied)
        let expectedNative = try #require(SmartCubeBluetoothManager.facelets(native, applying: "F"))
        let expectedLocal = try #require(SmartCubeBluetoothManager.facelets(solved, applying: "F"))
        #expect(reference.resolve(deviceID: deviceID, snapshot: expectedNative, forceAuthoritative: false) == .preserveLocal(expectedLocal))
        #expect(reference.resolve(deviceID: deviceID, snapshot: native, forceAuthoritative: false) == .useAuthoritative(native))
    }

    @Test func combinedReadyTracksScrambleValidityWithoutStalePresentationState() {
        let inputs = CombinedSolveReadiness(
            smartCubeConnected: true,
            smartCubeObservationReady: true,
            scrambleVerified: true,
            smartCubeReady: true,
            smartTimerConnected: true,
            smartTimerReady: true
        )
        #expect(inputs.isReady)
        let invalidated = CombinedSolveReadiness(
            smartCubeConnected: inputs.smartCubeConnected,
            smartCubeObservationReady: inputs.smartCubeObservationReady,
            scrambleVerified: false,
            smartCubeReady: inputs.smartCubeReady,
            smartTimerConnected: inputs.smartTimerConnected,
            smartTimerReady: inputs.smartTimerReady
        )
        #expect(!invalidated.isReady)
        #expect(inputs.isReady)
    }

    private func combinedReadiness(timerReady: Bool) -> CombinedSolveReadiness {
        CombinedSolveReadiness(
            smartCubeConnected: true,
            smartCubeObservationReady: true,
            scrambleVerified: true,
            smartCubeReady: true,
            smartTimerConnected: true,
            smartTimerReady: timerReady
        )
    }
}
