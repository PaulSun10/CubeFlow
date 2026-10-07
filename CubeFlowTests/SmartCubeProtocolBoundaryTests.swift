import Foundation
import Testing
@testable import CubeFlow

@Suite("Smart cube protocol boundaries")
struct SmartCubeProtocolBoundaryTests {
    @Test func qiyiAddressUsesOnlyItsManufacturerRecord() {
        #expect(QiYiCubeProtocolParser.resolvedMAC(
            manufacturerDataHex: "0405E6A00000A3CC", deviceName: "QY-QYSC-S-A0E6"
        ) == "CC:A3:00:00:A0:E6")
        #expect(QiYiCubeProtocolParser.resolvedMAC(
            manufacturerDataHex: "FFFFE6A00000A3CC", deviceName: "QY-QYSC-S-A0E6"
        ) == nil)
        #expect(QiYiCubeProtocolParser.resolvedMAC(
            manufacturerDataHex: nil, deviceName: "QY-QYSC-A-A0E6"
        ) == "CC:A2:00:00:A0:E6")
    }

    @Test func qiyiDiscoveryDoesNotAdmitGANSmartTimer() {
        let service = ["FFF0"]
        let qiyi = SmartCubeDiscoveryClassifier.protocolHint(
            name: "QY-QYSC-S-A0E6", serviceIdentifiers: service
        )
        #expect(qiyi == .qiyi)
        #expect(SmartCubeDiscoveryClassifier.isSupportedSmartCube(
            name: "QY-QYSC-S-A0E6", serviceIdentifiers: service, protocolHint: qiyi
        ))

        let timer = SmartCubeDiscoveryClassifier.protocolHint(
            name: "GAN Smart Timer", serviceIdentifiers: service
        )
        #expect(timer == .unknown)
        #expect(!SmartCubeDiscoveryClassifier.isSupportedSmartCube(
            name: "GAN Smart Timer", serviceIdentifiers: service, protocolHint: timer
        ))
    }

    @Test func qiyiRecordedHelloAndFirstMove() throws {
        let parser = try #require(QiYiCubeProtocolParser(macAddress: "CC:A3:00:00:A0:E6"))
        #expect(parser.helloPacket() == bytes(
            "3852B5FA66FDC408149B113BADE5B00942D85DEA0716E80B6467FA8027C9BA2F"
        ))

        _ = parser.consume(bytes(
            "AA4F6D9CD1ACDB1207D332037BE4912B9CCD2F402FA46B8A7ADC0870FE251DFB2A994B6AFA694C5926EEDB4A12A0C4F4"
        ))
        let hello = parser.consume(bytes(
            "FF214E906D6EE4F4AA8BE2FECCC9A17D9CCD2F402FA46B8A7ADC0870FE251DFB58446C521D98E6979EE7B2D535D24B07"
        ))
        #expect(hello.events.contains { event in
            if case .facelets(let facelets, _) = event {
                return facelets == SmartCubeBluetoothManager.solvedFacelets
            }
            return false
        })

        let turn = parser.consume(bytes(
            "5C2FCF219565794CAB31ED7B34D2C1AFDC09ECADAF400930C8A54C4D422F652BFEDD15B5C7A0AE4EB6CA612425E30B2DAADD489DE230471C6D8B42A8CD6CEDDDAADD489DE230471C6D8B42A8CD6CEDDD3DEC43D6F974612A6D8B0FE123DCA44C"
        ))
        #expect(turn.events.contains { event in
            if case .move(let move) = event { return move.move == "R" }
            return false
        })
    }

    @Test func moyuIgnoresUnusedHistorySlots() {
        let parser = GANCubeProtocolParser(kind: .moyu, puzzleSize: 3)
        var baseline = [UInt8](repeating: 0, count: 20)
        baseline[0] = 0xA5
        baseline[11] = 10
        _ = parser.handleStateEvent(baseline)

        var turn = [UInt8](repeating: 0xFF, count: 20)
        turn[0] = 0xA5
        turn[11] = 11
        setBits(&turn, start: 96, length: 5, value: 0) // Latest slot is F; unused slots remain 0x1F.
        let events = parser.handleStateEvent(turn)
        #expect(events.contains { event in
            if case .move(let move) = event { return move.move == "F" }
            return false
        })
    }

    @Test func weiPo2A3PreservesNativeValuesAndCounterWithoutCanonicalFacelets() throws {
        let parser = GANCubeProtocolParser(kind: .moyu, puzzleSize: 2)
        let baseline = parser.handleStateEvent(bytes(
            "A3 00 02 49 49 26 DB 92 4B 6D 3A 00 00 00 00 00 00 00 00 00"
        ))
        guard case .weiPo2State(let initial) = try #require(baseline.first) else {
            Issue.record("Expected WeiPo native state")
            return
        }
        #expect(initial.turnCounter == 0x3A)
        #expect(initial.stickerValues == (0..<6).flatMap { Array(repeating: UInt8($0), count: 4) })

        let forward = parser.handleStateEvent(bytes(
            "A3 0C 34 51 41 06 59 92 4B 6D 3B 00 00 00 00 00 00 00 00 00"
        ))
        guard case .weiPo2State(let turned) = try #require(forward.first) else {
            Issue.record("Expected WeiPo native turn state")
            return
        }
        #expect(turned.turnCounter == 0x3B)
        #expect(turned.stickerValues == [
            0, 3, 0, 3, 2, 1, 2, 1, 2, 0, 2, 0,
            3, 1, 3, 1, 4, 4, 4, 4, 5, 5, 5, 5
        ])
        #expect(!forward.contains { if case .facelets = $0 { return true }; return false })
    }

    @Test func weiPo2A5UsesNativeCounterAndCodeNotThreeByThreeOffsets() throws {
        let parser = GANCubeProtocolParser(kind: .moyu, puzzleSize: 2)
        _ = parser.handleStateEvent(bytes(
            "A3 00 02 49 49 26 DB 92 4B 6D 3A 00 00 00 00 00 00 00 00 00"
        ))
        var packet = [UInt8](repeating: 0xFF, count: 20)
        packet[0] = 0xA5
        packet[11] = 0xE0 // The 3x3 counter must not be read.
        packet[13] = 0x3B
        packet[14] = 0x00 // Latest native code 0 occupies the high three bits.
        let events = parser.handleStateEvent(packet)
        guard case .weiPo2Turn(let turn) = try #require(events.first) else {
            Issue.record("Expected WeiPo native turn")
            return
        }
        #expect(turn.code == 0)
        #expect(turn.turnCounter == 0x3B)
        #expect(turn.missedTurnCount == 0)
        #expect(!events.contains { if case .move = $0 { return true }; return false })

        packet[13] = 0x3E
        packet[14] = 0xA0 // Native code 5; two intermediate turns were not observed.
        let gap = parser.handleStateEvent(packet)
        guard case .weiPo2Turn(let latest) = try #require(gap.first) else {
            Issue.record("Expected latest native turn after gap")
            return
        }
        #expect(latest.code == 5)
        #expect(latest.missedTurnCount == 2)
    }

    @Test func weiPo2CapturedInversePairsUseThreeBitNativeCodes() throws {
        let parser = GANCubeProtocolParser(kind: .moyu, puzzleSize: 2)
        _ = parser.handleStateEvent(bytes(
            "A3 00 02 49 49 26 DB 92 4B 6D 52 00 00 00 00 00 00 00 00 00"
        ))
        let captured: [(UInt8, UInt8, UInt8)] = [
            (0x53, 0x89, 4), (0x54, 0xB1, 5), // F, F'
            (0x55, 0x56, 2), (0x56, 0x6A, 3), // U, U'
            (0x57, 0x0D, 0), (0x58, 0x21, 1), // R, R'
            (0x59, 0x84, 4), (0x5A, 0xB0, 5), // B, B'
            (0x5B, 0x56, 2), (0x5C, 0x6A, 3), // D, D'
            (0x5D, 0x0D, 0), (0x5E, 0x21, 1)  // L, L'
        ]
        for (counter, capturedByte, expectedCode) in captured {
            var packet = [UInt8](repeating: 0, count: 20)
            packet[0] = 0xA5
            packet[13] = counter
            packet[14] = capturedByte
            let events = parser.handleStateEvent(packet)
            guard case .weiPo2Turn(let turn) = try #require(events.first) else {
                Issue.record("Expected WeiPo native turn")
                return
            }
            #expect(turn.code == expectedCode)
            #expect(turn.turnCounter == counter)
            #expect(turn.missedTurnCount == 0)
        }
    }

    private func bytes(_ hex: String) -> [UInt8] {
        let characters = Array(hex.filter { !$0.isWhitespace })
        return stride(from: 0, to: characters.count, by: 2).compactMap { index in
            UInt8(String(characters[index...index + 1]), radix: 16)
        }
    }

    private func setBits(_ bytes: inout [UInt8], start: Int, length: Int, value: Int) {
        for offset in 0..<length {
            let bit = (value >> (length - offset - 1)) & 1
            let index = start + offset
            let mask = UInt8(1 << (7 - index % 8))
            if bit == 0 {
                bytes[index / 8] &= ~mask
            } else {
                bytes[index / 8] |= mask
            }
        }
    }
}
