import XCTest
import CoreBluetooth
@testable import CubeFlow

@MainActor final class PerformanceBattleSharingTests: XCTestCase {
    func testCachedPermutationsMatchIndependentGeometryAndPreserveEverySticker() throws {
        for size in [2, 3] {
            var state = CubeSurface.solved(size: size)
            for step in 0..<50 {
                for move in SmartCubeTargetPath.moves {
                    let turn = try XCTUnwrap(CubeLayerTurn(move))
                    XCTAssertEqual(turn.applying(to: state, size: size), turn.applyingGeometrically(to: state, size: size))
                }
                state = try XCTUnwrap(CubeLayerTurn(SmartCubeTargetPath.moves[(step * 7) % 18])?.applying(to: state, size: size))
            }
        }
    }

    func testComparableFaceletPerformance() throws {
        let turns = SmartCubeTargetPath.moves.compactMap(CubeLayerTurn.init)
        for size in [2, 3] {
            var checksum = 0, old: [Double] = [], new: [Double] = []
            for _ in 0..<3 {
                var state = CubeSurface.solved(size: size), start = ProcessInfo.processInfo.systemUptime
                for index in 0..<1000 { state = try XCTUnwrap(turns[index % 18].applyingGeometrically(to: state, size: size)) }
                old.append((ProcessInfo.processInfo.systemUptime - start) * 1000); checksum += state.count
                state = CubeSurface.solved(size: size); start = ProcessInfo.processInfo.systemUptime
                for index in 0..<1000 { state = try XCTUnwrap(turns[index % 18].applying(to: state, size: size)) }
                new.append((ProcessInfo.processInfo.systemUptime - start) * 1000); checksum += state.count
            }
            XCTAssertGreaterThan(checksum, 0)
            print("[CubePermutationPerf] size=\(size) turns=1000 old_ms=\(old) new_ms=\(new)")
        }
    }

    func testTwoSmartCubesRequireBothTargetsBeforeIndependentStartAndCompletion() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = SmartCubeBluetoothManager(testSavedDevices: SavedSmartCubeDevices(defaults: defaults))
        let ids = [UUID(), UUID()]
        let sessions = ids.map { id -> SmartCubePeripheralSession in
            let session = SmartCubePeripheralSession(central: CBCentralManager(delegate: nil, queue: nil))
            session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
            manager.debugInstallSession(session, for: id); return session
        }
        let owner = LocalBattleDevices(manager: manager)
        owner.setEnabled(true)
        owner.setConfiguration(.init(input: .smartCube, deviceID: ids[0]), for: .first)
        owner.setConfiguration(.init(input: .smartCube, deviceID: ids[1]), for: .second)
        owner.setTarget("R", event: .threeByThree, assignment: UUID(), for: .first)
        owner.setTarget("U", event: .threeByThree, assignment: UUID(), for: .second)
        var starts: [LocalBattlePlayer] = [], finishes: [LocalBattlePlayer] = []
        owner.start = { player, _ in starts.append(player); return true }
        owner.finish = { player, _ in finishes.append(player) }
        sessions[0].debugEmitPhysicalMove("R")
        XCTAssertEqual(owner.ready, [.first])
        sessions[0].debugEmitPhysicalMove("R'")
        XCTAssertTrue(starts.isEmpty); XCTAssertFalse(owner.ready.contains(.first))
        sessions[0].debugEmitPhysicalMove("R")
        sessions[1].debugEmitPhysicalMove("U")
        XCTAssertEqual(owner.ready.count, 2)
        sessions[0].debugEmitPhysicalMove("R'")
        XCTAssertEqual(starts, [.first]); XCTAssertEqual(finishes, [.first])
        sessions[1].debugEmitPhysicalMove("U'")
        XCTAssertEqual(starts, [.first, .second]); XCTAssertEqual(finishes, [.first, .second])
        owner.setEnabled(false)
        sessions[0].debugEmitPhysicalMove("R")
        XCTAssertEqual(starts.count, 2)
    }

    func testSameCubeCannotBeAssignedToBothPlayers() {
        let owner = LocalBattleDevices(), id = UUID()
        owner.setConfiguration(.init(input: .smartCube, deviceID: id), for: .first)
        owner.setConfiguration(.init(input: .smartCube, deviceID: id), for: .second)
        XCTAssertNil(owner.configuration(.second).deviceID)
        owner.setConfiguration(.init(input: .manual), for: .first)
        owner.setConfiguration(.init(input: .smartCube, deviceID: id), for: .second)
        XCTAssertEqual(owner.configuration(.second).deviceID, id)
    }

    func testReconnectionBoundaryCancelsOnlyItsPlayerWithoutRevivingAnOldSolve() {
        let manager = SmartCubeBluetoothManager(testSavedDevices: SavedSmartCubeDevices(defaults: UserDefaults(suiteName: UUID().uuidString)!))
        let ids = [UUID(), UUID()]
        let sessions = ids.map { id -> SmartCubePeripheralSession in
            let session = SmartCubePeripheralSession(central: CBCentralManager(delegate: nil, queue: nil))
            session.debugSeedConnectedState(deviceID: id, attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
            manager.debugInstallSession(session, for: id); return session
        }
        let owner = LocalBattleDevices(manager: manager)
        owner.setEnabled(true)
        owner.setConfiguration(.init(input: .smartCube, deviceID: ids[0]), for: .first)
        owner.setConfiguration(.init(input: .smartCube, deviceID: ids[1]), for: .second)
        owner.setTarget("R", event: .threeByThree, assignment: UUID(), for: .first)
        owner.setTarget("U", event: .threeByThree, assignment: UUID(), for: .second)
        var invalidated: [LocalBattlePlayer] = [], finished: [LocalBattlePlayer] = []
        owner.start = { _, _ in true }; owner.invalidate = { invalidated.append($0) }
        owner.finish = { player, _ in finished.append(player) }
        sessions[0].debugEmitPhysicalMove("R"); sessions[1].debugEmitPhysicalMove("U")
        sessions[0].debugEmitPhysicalMove("R"); sessions[1].debugEmitPhysicalMove("U")
        sessions[0].debugSeedConnectedState(deviceID: ids[0], attemptID: UUID(), facelets: CubeSurface.solved(size: 3))
        XCTAssertEqual(invalidated, [.first]); XCTAssertTrue(finished.isEmpty)
        sessions[0].debugEmitPhysicalMove("U"); sessions[0].debugEmitPhysicalMove("U'")
        XCTAssertTrue(finished.isEmpty, "A solved event after a session boundary cannot finish the abandoned solve")
        sessions[1].debugEmitPhysicalMove("U2")
        XCTAssertEqual(finished, [.second], "The other cube's active solve is independent")
        owner.setEnabled(false)
    }
}
