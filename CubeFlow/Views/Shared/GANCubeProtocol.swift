#if os(iOS)
import Foundation

enum GANCubeCommand {
    case requestFacelets
    case requestHardware
    case requestBattery
    case requestReset
    case requestMoveHistory(startMoveCount: Int, numberOfMoves: Int)

    var label: String {
        switch self {
        case .requestFacelets: return "Request facelets"
        case .requestHardware: return "Request hardware"
        case .requestBattery: return "Request battery"
        case .requestReset: return "Reset cube state"
        case .requestMoveHistory: return "Request move history"
        }
    }

    var isHighFrequency: Bool {
        if case .requestMoveHistory = self { return true }
        return false
    }
}

enum SmartCubeParsedEvent {
    case move(SmartCubeMoveEvent)
    case facelets(String, serial: Int)
    case battery(Int)
    case hardware(String)
    case gyro(String)
    case debug(String, String)
    case holdPendingMove(seconds: TimeInterval)
    case requestMoveHistory(startMoveCount: Int, numberOfMoves: Int)
}

private struct GANBufferedMove: Equatable {
    let count: Int
    let move: SmartCubeMoveEvent
}

final class GANCubeCipher {
    private let key: [UInt8]
    private let iv: [UInt8]

    convenience init(salt: [UInt8]) {
        self.init(
            rootKey: [0x01, 0x02, 0x42, 0x28, 0x31, 0x91, 0x16, 0x07, 0x20, 0x05, 0x18, 0x54, 0x42, 0x11, 0x12, 0x53],
            rootIV: [0x11, 0x03, 0x32, 0x28, 0x21, 0x01, 0x76, 0x27, 0x20, 0x95, 0x78, 0x14, 0x32, 0x12, 0x02, 0x43],
            salt: salt
        )
    }

    init(rootKey: [UInt8], rootIV: [UInt8], salt: [UInt8]) {
        let baseKey = rootKey
        let baseIV = rootIV
        var saltedKey = baseKey
        var saltedIV = baseIV
        for index in 0..<min(6, salt.count) {
            saltedKey[index] = UInt8((Int(baseKey[index]) + Int(salt[index])) % 0xFF)
            saltedIV[index] = UInt8((Int(baseIV[index]) + Int(salt[index])) % 0xFF)
        }
        key = saltedKey
        iv = saltedIV
    }

    func encrypt(_ data: [UInt8]) -> [UInt8] {
        guard data.count >= 16 else { return data }
        var result = data
        cryptChunk(in: &result, offset: 0, operation: CCOperation(kCCEncrypt))
        if result.count > 16 {
            cryptChunk(in: &result, offset: result.count - 16, operation: CCOperation(kCCEncrypt))
        }
        return result
    }

    func decrypt(_ data: [UInt8]) -> [UInt8]? {
        guard data.count >= 16 else { return data }
        var result = data
        if result.count > 16 {
            guard cryptChunk(in: &result, offset: result.count - 16, operation: CCOperation(kCCDecrypt)) else { return nil }
        }
        guard cryptChunk(in: &result, offset: 0, operation: CCOperation(kCCDecrypt)) else { return nil }
        return result
    }

    @discardableResult
    private func cryptChunk(in buffer: inout [UInt8], offset: Int, operation: CCOperation) -> Bool {
        guard offset >= 0, offset + 16 <= buffer.count else { return false }
        let input = Array(buffer[offset..<(offset + 16)])
        var output = [UInt8](repeating: 0, count: 16)
        var outputLength = 0
        let outputCapacity = output.count
        let status = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                input.withUnsafeBytes { inputBytes in
                    output.withUnsafeMutableBytes { outputBytes in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(0),
                            keyBytes.baseAddress,
                            kCCKeySizeAES128,
                            ivBytes.baseAddress,
                            inputBytes.baseAddress,
                            input.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess, outputLength == 16 else { return false }
        buffer.replaceSubrange(offset..<(offset + 16), with: output)
        return true
    }
}

final class GANCubeProtocolParser {
    private let kind: SmartCubeProtocolKind
    private var lastSerial: Int?
    private var ganPreviousMoveCount: Int?
    private var ganLatestMoveCount: Int?
    private var ganMoveBuffer: [GANBufferedMove] = []
    private var ganHistoryRequestDates: [String: Date] = [:]
    private var moYuPreviousMoveCount: Int?
    private var hardwareInfo: [Int: String] = [:]

    init(kind: SmartCubeProtocolKind) {
        self.kind = kind
    }

    func resetMoveTracking() {
        // Mark the local state as trusted so the next live move is accepted immediately after a manual reset.
        lastSerial = 0
        ganPreviousMoveCount = nil
        ganLatestMoveCount = nil
        ganMoveBuffer.removeAll()
        ganHistoryRequestDates.removeAll()
    }

    func commandMessage(for command: GANCubeCommand) -> [UInt8]? {
        switch kind {
        case .moyu:
            var message = [UInt8](repeating: 0, count: 20)
            switch command {
            case .requestHardware:
                message[0] = 0xA1
            case .requestFacelets:
                message[0] = 0xA3
            case .requestBattery:
                message[0] = 0xA4
            case .requestReset, .requestMoveHistory:
                return nil
            }
            return message
        case .ganGen4:
            var message = [UInt8](repeating: 0, count: 20)
            switch command {
            case .requestFacelets:
                message.replaceSubrange(0..<6, with: [0xDD, 0x04, 0x00, 0xED, 0x00, 0x00])
            case .requestHardware:
                hardwareInfo = [:]
                message.replaceSubrange(0..<5, with: [0xDF, 0x03, 0x00, 0x00, 0x00])
            case .requestBattery:
                message.replaceSubrange(0..<6, with: [0xDD, 0x04, 0x00, 0xEF, 0x00, 0x00])
            case .requestReset:
                message.replaceSubrange(0..<16, with: [0xD2, 0x0D, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0x00, 0x00, 0x00])
            case .requestMoveHistory(let startMoveCount, let numberOfMoves):
                let adjusted = Self.adjustedGANHistoryWindow(startMoveCount: startMoveCount, numberOfMoves: numberOfMoves)
                message[0] = 0xD1
                message[1] = 0x04
                message[2] = UInt8(adjusted.start & 0xFF)
                message[4] = UInt8(adjusted.count & 0xFF)
            }
            return message
        case .ganGen2:
            var message = [UInt8](repeating: 0, count: 20)
            switch command {
            case .requestFacelets: message[0] = 0x04
            case .requestHardware: message[0] = 0x05
            case .requestBattery: message[0] = 0x09
            case .requestReset:
                message = [0x0A, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .requestMoveHistory:
                return nil
            }
            return message
        case .ganGen3:
            var message = [UInt8](repeating: 0, count: 16)
            switch command {
            case .requestFacelets: message.replaceSubrange(0..<2, with: [0x68, 0x01])
            case .requestHardware: message.replaceSubrange(0..<2, with: [0x68, 0x04])
            case .requestBattery: message.replaceSubrange(0..<2, with: [0x68, 0x07])
            case .requestReset: message.replaceSubrange(0..<16, with: [0x68, 0x05, 0x05, 0x39, 0x77, 0x00, 0x00, 0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0x00, 0x00, 0x00])
            case .requestMoveHistory(let startMoveCount, let numberOfMoves):
                let adjusted = Self.adjustedGANHistoryWindow(startMoveCount: startMoveCount, numberOfMoves: numberOfMoves)
                message[0] = 0x68
                message[1] = 0x03
                message[2] = UInt8(adjusted.start & 0xFF)
                message[4] = UInt8(adjusted.count & 0xFF)
            }
            return message
        default:
            return nil
        }
    }

    func handleStateEvent(_ message: [UInt8]) -> [SmartCubeParsedEvent] {
        switch kind {
        case .moyu:
            return handleMoYu(message)
        case .ganGen4:
            return handleGen4(message)
        case .ganGen2:
            return handleGen2(message)
        case .ganGen3:
            return handleGen3(message)
        default:
            return []
        }
    }


    private func handleMoYu(_ message: [UInt8]) -> [SmartCubeParsedEvent] {
        guard let eventType = message.first else { return [] }
        switch eventType {
        case 0xA1:
            let modelBytes = Array(message.dropFirst().prefix(8)).filter { $0 != 0 }
            let model = String(bytes: modelBytes, encoding: .ascii) ?? "WCU_MY32"
            let hardware = "\(model) HW \(byte(message, 9)).\(byte(message, 10)) SW \(byte(message, 11)).\(byte(message, 12))"
            return [.hardware(hardware)]
        case 0xA3:
            let values = readMoYuFaceletValues(from: Array(message.dropFirst().prefix(18)))
            guard values.count >= 48 else { return [] }
            let serial = byte(message, 19)
            moYuPreviousMoveCount = serial
            return [.facelets(Self.moYuFaceletsToKociemba(values), serial: serial)]
        case 0xA4:
            return [.battery(min(byte(message, 1), 100))]
        case 0xA5:
            return moYuMoveEvents(from: message)
        case 0xAB:
            let values = (0..<4).map { index -> Double in
                let offset = 1 + index * 4
                guard offset + 3 < message.count else { return 0 }
                let unsigned = UInt32(message[offset]) | (UInt32(message[offset + 1]) << 8) | (UInt32(message[offset + 2]) << 16) | (UInt32(message[offset + 3]) << 24)
                return Double(Int32(bitPattern: unsigned)) / pow(2.0, 30.0)
            }
            // MoYu order is w, x, -z, y.
            return [.gyro(String(format: "x %.2f y %.2f z %.2f w %.2f", values[1], values[3], -values[2], values[0]))]
        case 0xAC:
            return [.gyro("gyro functional \(byte(message, 1)), enabled \(byte(message, 2))")]
        default:
            return []
        }
    }

    private func moYuMoveEvents(from message: [UInt8]) -> [SmartCubeParsedEvent] {
        let moveCount = readBitWord(bytes: message, startBit: 88, bitLength: 8)
        guard let previousMoveCount = moYuPreviousMoveCount else {
            moYuPreviousMoveCount = moveCount
            return []
        }
        guard moveCount != previousMoveCount else { return [] }

        let moveDiff = min((moveCount - previousMoveCount) & 0xFF, 5)
        moYuPreviousMoveCount = moveCount
        guard moveDiff > 0 else { return [] }

        var moves: [String] = []
        for index in 0..<5 {
            let moveValue = readBitWord(bytes: message, startBit: 96 + index * 5, bitLength: 5)
            guard let moveName = Self.moYuMoveName(moveValue) else { return [] }
            moves.append(moveName)
        }

        let now = Date()
        return stride(from: moveDiff - 1, through: 0, by: -1).map { index in
            .move(SmartCubeMoveEvent(
                move: moves[index],
                serial: moveCount,
                face: nil,
                direction: nil,
                localTimestamp: now,
                cubeTimestampMilliseconds: nil
            ))
        }
    }

    private func handleGen4(_ message: [UInt8]) -> [SmartCubeParsedEvent] {
        let view = BitWordReader(message)
        let eventType = view.word(0, 8)
        let dataLength = view.word(8, 8)

        switch eventType {
        case 0x01:
            let cubeTimestamp = view.word(16, 32, littleEndian: true)
            let serial = view.word(48, 16, littleEndian: true)
            let direction = view.word(64, 2)
            let face = [2, 32, 8, 1, 16, 4].firstIndex(of: view.word(66, 6))
            guard let face else { return [] }
            let move = moveString(face: face, direction: direction)
            let event = SmartCubeMoveEvent(
                move: move,
                serial: serial,
                face: face,
                direction: direction,
                localTimestamp: Date(),
                cubeTimestampMilliseconds: cubeTimestamp
            )
            return [.debug("GAN Gen4 0x01", "count \(serial & 0xFF), move \(move), ts \(cubeTimestamp)")]
                + enqueueGANMove(event, count: serial, requestLostMoves: true)
        case 0xED:
            if ganPreviousMoveCount != nil {
                let stateMoveCount = view.word(16, 16, littleEndian: true)
                return handleGANStateCounter(stateMoveCount, label: "GAN Gen4 0xED")
            }
            return faceletsEvent(view: view, serialBit: 16, cornerStart: 32, cornerOrientationStart: 53, edgeStart: 69, edgeOrientationStart: 113)
        case 0xD1:
            return handleGen4MoveHistory(view: view, dataLength: dataLength)
        case 0xEF:
            return [.battery(min(view.word(8 + dataLength * 8, 8), 100))]
        case 0xEC:
            let qw = signedQuaternionComponent(view.word(16, 16))
            let qx = signedQuaternionComponent(view.word(32, 16))
            let qy = signedQuaternionComponent(view.word(48, 16))
            let qz = signedQuaternionComponent(view.word(64, 16))
            return [.gyro(String(format: "x %.2f y %.2f z %.2f w %.2f", qx, qy, qz, qw))]
        case 0xFA...0xFE:
            if let event = updateGen4Hardware(view: view, eventType: eventType, dataLength: dataLength) {
                return [event]
            }
            return []
        default:
            return []
        }
    }

    private func handleGen2(_ message: [UInt8]) -> [SmartCubeParsedEvent] {
        let view = BitWordReader(message)
        let eventType = view.word(0, 4)

        switch eventType {
        case 0x02:
            guard lastSerial != nil else { return [] }
            let serial = view.word(4, 8)
            let face = view.word(12, 4)
            let direction = view.word(16, 1)
            guard face >= 0, face < 6 else { return [] }
            let elapsed = view.word(47, 16)
            let event = SmartCubeMoveEvent(
                move: moveString(face: face, direction: direction),
                serial: serial,
                face: face,
                direction: direction,
                localTimestamp: Date(),
                cubeTimestampMilliseconds: elapsed
            )
            lastSerial = serial
            return [.move(event)]
        case 0x04:
            return faceletsEvent(view: view, serialBit: 4, cornerStart: 12, cornerOrientationStart: 33, edgeStart: 47, edgeOrientationStart: 91)
        case 0x05:
            var name = ""
            for index in 0..<8 {
                let scalar = view.word(index * 8 + 40, 8)
                if scalar > 0 { name.append(Character(UnicodeScalar(scalar) ?? "?")) }
            }
            let hardware = "\(name) HW \(view.word(8, 8)).\(view.word(16, 8)) SW \(view.word(24, 8)).\(view.word(32, 8))"
            return [.hardware(hardware)]
        case 0x09:
            return [.battery(min(view.word(8, 8), 100))]
        default:
            return []
        }
    }

    private func handleGen3(_ message: [UInt8]) -> [SmartCubeParsedEvent] {
        let view = BitWordReader(message)
        let magic = view.word(0, 8)
        let eventType = view.word(8, 8)
        guard magic == 0x55 else { return [] }

        switch eventType {
        case 0x01:
            let cubeTimestamp = view.word(24, 32, littleEndian: true)
            let serial = view.word(56, 16, littleEndian: true)
            let direction = view.word(72, 2)
            let face = [2, 32, 8, 1, 16, 4].firstIndex(of: view.word(74, 6))
            guard let face else { return [] }
            let event = SmartCubeMoveEvent(move: moveString(face: face, direction: direction), serial: serial, face: face, direction: direction, localTimestamp: Date(), cubeTimestampMilliseconds: cubeTimestamp)
            return [.debug("GAN Gen3 0x01", "count \(serial & 0xFF), move \(event.move), ts \(cubeTimestamp)")]
                + enqueueGANMove(event, count: serial, requestLostMoves: true)
        case 0x02:
            if ganPreviousMoveCount != nil {
                let stateMoveCount = view.word(24, 16, littleEndian: true)
                return handleGANStateCounter(stateMoveCount, label: "GAN Gen3 0x02")
            }
            return faceletsEvent(view: view, serialBit: 24, cornerStart: 40, cornerOrientationStart: 61, edgeStart: 77, edgeOrientationStart: 121)
        case 0x06:
            return handleGen3MoveHistory(view: view, dataLength: view.word(16, 8))
        case 0x10:
            return [.battery(min(view.word(24, 8), 100))]
        default:
            return []
        }
    }

    private func faceletsEvent(
        view: BitWordReader,
        serialBit: Int,
        cornerStart: Int,
        cornerOrientationStart: Int,
        edgeStart: Int,
        edgeOrientationStart: Int
    ) -> [SmartCubeParsedEvent] {
        let serial = view.word(serialBit, kind == .ganGen2 ? 8 : 16, littleEndian: kind != .ganGen2)
        lastSerial = serial
        if (kind == .ganGen3 || kind == .ganGen4), ganPreviousMoveCount == nil {
            ganPreviousMoveCount = serial
        }

        var cp: [Int] = []
        var co: [Int] = []
        var ep: [Int] = []
        var eo: [Int] = []

        for index in 0..<7 {
            cp.append(view.word(cornerStart + index * 3, 3))
            co.append(view.word(cornerOrientationStart + index * 2, 2))
        }
        cp.append(28 - cp.reduce(0, +))
        co.append((3 - (co.reduce(0, +) % 3)) % 3)

        for index in 0..<11 {
            ep.append(view.word(edgeStart + index * 4, 4))
            eo.append(view.word(edgeOrientationStart + index, 1))
        }
        ep.append(66 - ep.reduce(0, +))
        eo.append((2 - (eo.reduce(0, +) % 2)) % 2)

        return [.facelets(Self.toKociembaFacelets(cp: cp, co: co, ep: ep, eo: eo), serial: serial)]
    }

    private func updateGen4Hardware(view: BitWordReader, eventType: Int, dataLength: Int) -> SmartCubeParsedEvent? {
        switch eventType {
        case 0xFA:
            hardwareInfo[eventType] = String(format: "%04d-%02d-%02d", view.word(24, 16, littleEndian: true), view.word(40, 8), view.word(48, 8))
        case 0xFC:
            var name = ""
            for index in 0..<max(0, dataLength - 1) {
                let scalar = view.word(index * 8 + 24, 8)
                if scalar > 0 { name.append(Character(UnicodeScalar(scalar) ?? "?")) }
            }
            hardwareInfo[eventType] = name
        case 0xFD:
            hardwareInfo[eventType] = "\(view.word(24, 4)).\(view.word(28, 4))"
        case 0xFE:
            hardwareInfo[eventType] = "\(view.word(24, 4)).\(view.word(28, 4))"
        default:
            break
        }

        guard hardwareInfo.keys.count >= 4 else { return nil }
        let summary = "\(hardwareInfo[0xFC] ?? "GAN") HW \(hardwareInfo[0xFE] ?? "?") SW \(hardwareInfo[0xFD] ?? "?") \(hardwareInfo[0xFA] ?? "")"
        return .hardware(summary)
    }

    private func handleGen4MoveHistory(view: BitWordReader, dataLength: Int) -> [SmartCubeParsedEvent] {
        let startMoveCount = view.word(16, 8)
        let numberOfMoves = max(0, (dataLength - 1) * 2)
        var historyMoves: [String] = []
        var events: [SmartCubeParsedEvent] = [.debug("GAN Gen4 0xD1", "start \(startMoveCount), moves \(numberOfMoves)")]
        for index in 0..<numberOfMoves {
            let axis = view.word(24 + index * 4, 3)
            let direction = view.word(27 + index * 4, 1)
            guard axis < 6 else { continue }
            let face = Array("DUBFLR")[axis]
            let moveName = String(face) + (direction == 1 ? "'" : "")
            let count = (startMoveCount - index) & 0xFF
            historyMoves.append("\(count):\(moveName)")
            injectGANHistoryMove(
                SmartCubeMoveEvent(move: moveName, serial: count, face: nil, direction: direction, localTimestamp: Date(), cubeTimestampMilliseconds: nil),
                count: count,
                events: &events
            )
        }
        if !historyMoves.isEmpty {
            events.append(.debug("GAN history received", historyMoves.joined(separator: ", ")))
        }
        events.append(contentsOf: evictGANMoveBuffer(requestLostMoves: false))
        return events
    }

    private func handleGen3MoveHistory(view: BitWordReader, dataLength: Int) -> [SmartCubeParsedEvent] {
        let startMoveCount = view.word(24, 8)
        let numberOfMoves = max(0, (dataLength - 1) * 2)
        var historyMoves: [String] = []
        var events: [SmartCubeParsedEvent] = [.debug("GAN Gen3 0x06", "start \(startMoveCount), moves \(numberOfMoves)")]
        for index in 0..<numberOfMoves {
            let axis = view.word(32 + index * 4, 3)
            let direction = view.word(35 + index * 4, 1)
            guard axis < 6 else { continue }
            let face = Array("DUBFLR")[axis]
            let moveName = String(face) + (direction == 1 ? "'" : "")
            let count = (startMoveCount - index) & 0xFF
            historyMoves.append("\(count):\(moveName)")
            injectGANHistoryMove(
                SmartCubeMoveEvent(move: moveName, serial: count, face: nil, direction: direction, localTimestamp: Date(), cubeTimestampMilliseconds: nil),
                count: count,
                events: &events
            )
        }
        if !historyMoves.isEmpty {
            events.append(.debug("GAN history received", historyMoves.joined(separator: ", ")))
        }
        events.append(contentsOf: evictGANMoveBuffer(requestLostMoves: false))
        return events
    }

    private func enqueueGANMove(_ move: SmartCubeMoveEvent, count: Int, requestLostMoves: Bool) -> [SmartCubeParsedEvent] {
        let normalizedCount = count & 0xFF
        ganLatestMoveCount = normalizedCount
        if ganPreviousMoveCount == nil {
            ganPreviousMoveCount = (normalizedCount - 1) & 0xFF
        }
        injectGANMove(move, count: normalizedCount)
        return evictGANMoveBuffer(requestLostMoves: requestLostMoves)
    }

    private func handleGANStateCounter(_ count: Int, label: String) -> [SmartCubeParsedEvent] {
        guard let previousMoveCount = ganPreviousMoveCount else { return [] }
        let normalizedCount = count & 0xFF
        let diff = (normalizedCount - previousMoveCount) & 0xFF
        guard diff > 0 else {
            return [.debug(label, "count \(normalizedCount), prev \(previousMoveCount), no gap")]
        }
        guard normalizedCount != 0 else {
            return [.debug(label, "count 0 ignored around counter rollover")]
        }

        ganLatestMoveCount = normalizedCount
        let startMoveCount = ganMoveBuffer.first?.count ?? ((normalizedCount + 1) & 0xFF)
        return [
            .debug(label, "state ahead prev \(previousMoveCount), state \(normalizedCount), diff \(diff); requesting history"),
            .holdPendingMove(seconds: 0.65)
        ] + requestGANHistoryIfNeeded(startMoveCount: startMoveCount, numberOfMoves: diff + 1)
    }

    private func injectGANMove(_ move: SmartCubeMoveEvent, count: Int) {
        let normalizedCount = count & 0xFF
        guard !ganMoveBuffer.contains(where: { ($0.count & 0xFF) == normalizedCount }) else { return }
        ganMoveBuffer.append(GANBufferedMove(count: normalizedCount, move: move))
        sortGANMoveBuffer()
    }

    private func injectGANHistoryMove(_ move: SmartCubeMoveEvent, count: Int, events: inout [SmartCubeParsedEvent]) {
        guard let previousMoveCount = ganPreviousMoveCount else { return }
        let normalizedCount = count & 0xFF
        guard !ganMoveBuffer.contains(where: { ($0.count & 0xFF) == normalizedCount }) else { return }

        if let head = ganMoveBuffer.first {
            guard Self.isMoveCount(normalizedCount, inRangeAfter: previousMoveCount, before: head.count) else { return }
            guard normalizedCount == ((head.count - 1) & 0xFF) else { return }
            ganMoveBuffer.insert(GANBufferedMove(count: normalizedCount, move: move), at: 0)
            events.append(.debug("GAN lost move recovered", "\(normalizedCount):\(move.move)"))
        } else if let latestMoveCount = ganLatestMoveCount,
                  Self.isMoveCount(normalizedCount, inRangeAfter: previousMoveCount, through: latestMoveCount) {
            ganMoveBuffer.insert(GANBufferedMove(count: normalizedCount, move: move), at: 0)
            events.append(.debug("GAN lost move recovered", "\(normalizedCount):\(move.move)"))
        }
    }

    private func requestGANHistoryIfNeeded(startMoveCount: Int, numberOfMoves: Int) -> [SmartCubeParsedEvent] {
        let key = "\(startMoveCount & 0xFF)-\(numberOfMoves)"
        let now = Date()
        if let lastRequest = ganHistoryRequestDates[key],
           now.timeIntervalSince(lastRequest) < 0.22 {
            return [.debug("GAN request throttled", "start \(startMoveCount), moves \(numberOfMoves)")]
        }
        ganHistoryRequestDates[key] = now
        return [.requestMoveHistory(startMoveCount: startMoveCount, numberOfMoves: numberOfMoves)]
    }

    private func evictGANMoveBuffer(requestLostMoves: Bool) -> [SmartCubeParsedEvent] {
        guard let previousMoveCount = ganPreviousMoveCount else { return [] }
        var events: [SmartCubeParsedEvent] = []

        while let first = ganMoveBuffer.first {
            let diff = (first.count - (ganPreviousMoveCount ?? previousMoveCount)) & 0xFF
            if diff == 0 {
                ganMoveBuffer.removeFirst()
                continue
            }
            if diff > 1 {
                let previous = ganPreviousMoveCount ?? previousMoveCount
                events.append(.debug("GAN move gap waiting", "prev \(previous), next \(first.count), diff \(diff)"))
                if requestLostMoves {
                    events.append(.holdPendingMove(seconds: 0.65))
                    events.append(contentsOf: requestGANHistoryIfNeeded(startMoveCount: first.count, numberOfMoves: diff))
                }
                break
            }

            let buffered = ganMoveBuffer.removeFirst()
            ganPreviousMoveCount = buffered.count
            lastSerial = buffered.move.serial
            events.append(.debug("GAN emit", "count \(buffered.count), move \(buffered.move.move)"))
            events.append(.move(buffered.move))
        }

        if ganMoveBuffer.count > 16 {
            events.append(.debug("GAN buffer overflow", ganMoveBuffer.map { "\($0.count):\($0.move.move)" }.joined(separator: ", ")))
            ganMoveBuffer.removeAll()
        }

        return events
    }

    private func sortGANMoveBuffer() {
        guard let previousMoveCount = ganPreviousMoveCount else { return }
        ganMoveBuffer.sort {
            (($0.count - previousMoveCount) & 0xFF) < (($1.count - previousMoveCount) & 0xFF)
        }
        if ganMoveBuffer.count > 16 {
            ganMoveBuffer.removeFirst(ganMoveBuffer.count - 16)
        }
    }


    private func byte(_ bytes: [UInt8], _ offset: Int) -> Int {
        guard offset >= 0, offset < bytes.count else { return 0 }
        return Int(bytes[offset])
    }

    private func readUInt16BE(_ bytes: [UInt8], offset: Int) -> Int {
        guard offset + 1 < bytes.count else { return 0 }
        return (Int(bytes[offset]) << 8) | Int(bytes[offset + 1])
    }

    private func readBitWord(bytes: [UInt8], startBit: Int, bitLength: Int) -> Int {
        BitWordReader(bytes).word(startBit, bitLength)
    }

    private func readMoYuFaceletValues(from bytes: [UInt8]) -> [Int] {
        let bitReader = BitWordReader(bytes)
        return (0..<48).map { bitReader.word($0 * 3, 3) }
    }

    private func moveString(face: Int, direction: Int) -> String {
        let faces = Array("URFDLB")
        guard face >= 0, face < faces.count else { return "?" }
        return String(faces[face]) + (direction == 1 ? "'" : "")
    }

    private func signedQuaternionComponent(_ value: Int) -> Double {
        Double(1 - ((value >> 15) * 2)) * Double(value & 0x7FFF) / Double(0x7FFF)
    }


    private static func moYuMoveName(_ value: Int) -> String? {
        let moves = ["F", "F'", "B", "B'", "U", "U'", "D", "D'", "L", "L'", "R", "R'"]
        guard value >= 0, value < moves.count else { return nil }
        return moves[value]
    }

    private static func adjustedGANHistoryWindow(startMoveCount: Int, numberOfMoves: Int) -> (start: Int, count: Int) {
        var start = startMoveCount & 0xFF
        var count = max(0, numberOfMoves)
        if start % 2 == 0 {
            start = (start - 1) & 0xFF
        }
        if count % 2 == 1 {
            count += 1
        }
        count = min(count, start + 1)
        return (start, count)
    }

    private static func isMoveCount(_ count: Int, inRangeAfter start: Int, through end: Int) -> Bool {
        let total = (end - start) & 0xFF
        let offset = (count - start) & 0xFF
        return offset > 0 && offset <= total
    }

    private static func isMoveCount(_ count: Int, inRangeAfter start: Int, before end: Int) -> Bool {
        let total = (end - start) & 0xFF
        let offset = (count - start) & 0xFF
        return offset > 0 && offset < total
    }

    private static func moYuFaceletsToKociemba(_ values: [Int]) -> String {
        let colorToFace: [Character] = ["F", "B", "U", "D", "L", "R"]
        let faceOrder: [Character] = ["F", "B", "U", "D", "L", "R"]
        var blocks: [Character: [Character]] = [:]
        for faceIndex in 0..<min(6, values.count / 8) {
            let face = faceOrder[faceIndex]
            var stickers = values[(faceIndex * 8)..<(faceIndex * 8 + 8)].map { value in
                value >= 0 && value < colorToFace.count ? colorToFace[value] : "?"
            }
            stickers.insert(face, at: 4)
            blocks[face] = stickers
        }
        return String((blocks["U"] ?? Array("UUUUUUUUU"))
            + (blocks["R"] ?? Array("RRRRRRRRR"))
            + (blocks["F"] ?? Array("FFFFFFFFF"))
            + (blocks["D"] ?? Array("DDDDDDDDD"))
            + (blocks["L"] ?? Array("LLLLLLLLL"))
            + (blocks["B"] ?? Array("BBBBBBBBB")))
    }

    private static func toKociembaFacelets(cp: [Int], co: [Int], ep: [Int], eo: [Int]) -> String {
        let faces = Array("URFDLB")
        var facelets = (0..<54).map { faces[$0 / 9] }
        let cornerFaceletMap = [
            [8, 9, 20], [6, 18, 38], [0, 36, 47], [2, 45, 11],
            [29, 26, 15], [27, 44, 24], [33, 53, 42], [35, 17, 51]
        ]
        let edgeFaceletMap = [
            [5, 10], [7, 19], [3, 37], [1, 46], [32, 16], [28, 25],
            [30, 43], [34, 52], [23, 12], [21, 41], [50, 39], [48, 14]
        ]

        for index in 0..<min(8, cp.count, co.count) {
            guard cp[index] >= 0, cp[index] < cornerFaceletMap.count else { continue }
            for position in 0..<3 {
                facelets[cornerFaceletMap[index][(position + co[index]) % 3]] = faces[cornerFaceletMap[cp[index]][position] / 9]
            }
        }

        for index in 0..<min(12, ep.count, eo.count) {
            guard ep[index] >= 0, ep[index] < edgeFaceletMap.count else { continue }
            for position in 0..<2 {
                facelets[edgeFaceletMap[index][(position + eo[index]) % 2]] = faces[edgeFaceletMap[ep[index]][position] / 9]
            }
        }
        return String(facelets)
    }
}

private struct BitWordReader {
    private let bits: [Character]

    init(_ bytes: [UInt8]) {
        bits = bytes.flatMap { byte in
            Array(String(Int(byte) + 0x100, radix: 2).dropFirst())
        }
    }

    func word(_ startBit: Int, _ bitLength: Int, littleEndian: Bool = false) -> Int {
        guard startBit >= 0, bitLength > 0, startBit + bitLength <= bits.count else { return 0 }
        if bitLength <= 8 {
            return Int(String(bits[startBit..<(startBit + bitLength)]), radix: 2) ?? 0
        }
        if bitLength == 16 || bitLength == 32 {
            var bytes: [UInt8] = []
            for index in 0..<(bitLength / 8) {
                let byteStart = startBit + index * 8
                let value = UInt8(String(bits[byteStart..<(byteStart + 8)]), radix: 2) ?? 0
                bytes.append(value)
            }
            if littleEndian { bytes.reverse() }
            return bytes.reduce(0) { ($0 << 8) | Int($1) }
        }
        return Int(String(bits[startBit..<(startBit + bitLength)]), radix: 2) ?? 0
    }
}
#endif
