#if os(iOS)
import Foundation
import CommonCrypto

struct QiYiPacketResult {
    let events: [SmartCubeParsedEvent]
    let acknowledgement: [UInt8]?
}

final class QiYiCubeProtocolParser {
    private static let key: [UInt8] = [
        0x57, 0xB1, 0xF9, 0xAB, 0xCD, 0x5A, 0xE8, 0xA7,
        0x9C, 0xB9, 0x8C, 0xE7, 0x57, 0x8C, 0x51, 0x08
    ]
    private let address: [UInt8]
    private var lastMoveTimestamp: UInt32?

    init?(macAddress: String) {
        let octets = macAddress.split(separator: ":").compactMap { UInt8($0, radix: 16) }
        guard octets.count == 6 else { return nil }
        address = octets
    }

    static func resolvedMAC(manufacturerDataHex: String?, deviceName: String?) -> String? {
        if let manufacturerDataHex {
            let hex = Array(manufacturerDataHex)
            let bytes = stride(from: 0, to: hex.count - hex.count % 2, by: 2).compactMap {
                UInt8(String(hex[$0...($0 + 1)]), radix: 16)
            }
            if bytes.count >= 8, bytes[0] == 0x04, bytes[1] == 0x05 {
                return bytes[2..<8].reversed()
                    .map { String(format: "%02X", $0) }.joined(separator: ":")
            }
        }
        guard let deviceName else { return nil }
        let parts = deviceName.uppercased().split(separator: "-")
        guard let suffix = parts.last, suffix.count == 4,
              UInt16(suffix, radix: 16) != nil else { return nil }
        let prefix: String
        if deviceName.uppercased().hasPrefix("QY-QYSC-A-") {
            prefix = "CC:A2:00:00"
        } else if deviceName.uppercased().hasPrefix("XMD-TORNADOV4-I-") {
            prefix = "CC:A6:00:00"
        } else {
            return nil
        }
        return "\(prefix):\(suffix.prefix(2)):\(suffix.suffix(2))"
    }

    func helloPacket() -> [UInt8]? {
        let payload: [UInt8] = [0x00, 0x6B, 0x01, 0x00, 0x00, 0x22, 0x06, 0x00, 0x02, 0x08, 0x00]
            + Array(address.reversed())
        return encode(payload)
    }

    func consume(_ encrypted: [UInt8]) -> QiYiPacketResult {
        guard let message = crypt(encrypted, operation: CCOperation(kCCDecrypt)), message.count >= 16 else {
            return QiYiPacketResult(events: [], acknowledgement: nil)
        }
        if message[0] == 0xCC, message[1] == 0x10 {
            guard crc(Array(message.prefix(14))) == (UInt16(message[14]) | (UInt16(message[15]) << 8)) else {
                return QiYiPacketResult(events: [], acknowledgement: nil)
            }
            let component = { (offset: Int) -> Double in
                let bits = UInt16(message[offset]) << 8 | UInt16(message[offset + 1])
                return Double(Int16(bitPattern: bits)) / 1000
            }
            let x = component(6), y = component(8), z = component(10), w = component(12)
            let norm = (x * x + y * y + z * z + w * w).squareRoot()
            guard norm.isFinite, norm > 0 else { return QiYiPacketResult(events: [], acknowledgement: nil) }
            return QiYiPacketResult(
                events: [.gyro(SmartCubeGyroState(x: x / norm, y: -z / norm, z: y / norm, w: w / norm))],
                acknowledgement: nil
            )
        }
        guard message[0] == 0xFE,
              Int(message[1]) >= 4,
              Int(message[1]) <= message.count else {
            return QiYiPacketResult(events: [], acknowledgement: nil)
        }
        let packet = Array(message.prefix(Int(message[1])))
        guard crc(packet) == 0, packet.count >= 7 else {
            return QiYiPacketResult(events: [], acknowledgement: nil)
        }
        let timestamp = word(packet, at: 3)
        let acknowledgement = encode(Array(packet[2..<7]))
        switch packet[2] {
        case 0x02:
            guard packet.count >= 36, let facelets = Self.facelets(packet) else {
                return QiYiPacketResult(events: [], acknowledgement: acknowledgement)
            }
            lastMoveTimestamp = timestamp
            var events: [SmartCubeParsedEvent] = [.facelets(facelets, serial: Int(timestamp))]
            if packet[35] <= 100 { events.append(.battery(Int(packet[35]))) }
            return QiYiPacketResult(events: events, acknowledgement: acknowledgement)
        case 0x03:
            guard packet.count >= 36 else { return QiYiPacketResult(events: [], acknowledgement: nil) }
            var samples: [(UInt32, UInt8)] = [(timestamp, packet[34])]
            if packet.count >= 41 {
                for offset in stride(from: 36, through: min(packet.count - 5, 86), by: 5) {
                    let slot = Array(packet[offset..<(offset + 5)])
                    if slot.allSatisfy({ $0 == 0xFF }) { continue }
                    samples.append((word(packet, at: offset), packet[offset + 4]))
                }
            }
            samples.sort { $0.0 < $1.0 }
            var events: [SmartCubeParsedEvent] = []
            var seen = Set<UInt64>()
            for (moveTime, code) in samples {
                let identity = UInt64(moveTime) << 8 | UInt64(code)
                guard seen.insert(identity).inserted, (1...12).contains(code),
                      lastMoveTimestamp.map({ Int32(bitPattern: moveTime &- $0) > 0 }) == true else { continue }
                let face = [4, 1, 3, 0, 2, 5][Int((code - 1) / 2)]
                let inverse = code % 2 == 1
                let move = String(Array("URFDLB")[face]) + (inverse ? "'" : "")
                events.append(.move(SmartCubeMoveEvent(
                    move: move,
                    serial: nil,
                    face: face,
                    direction: inverse ? 1 : 0,
                    localTimestamp: Date(),
                    cubeTimestampMilliseconds: Int(Double(moveTime) / 1.6),
                    timestampSource: .deviceClock
                )))
                lastMoveTimestamp = moveTime
            }
            if packet[35] <= 100 { events.append(.battery(Int(packet[35]))) }
            let needsAcknowledgement = packet.count > 91 && packet[91] != 0
            return QiYiPacketResult(events: events, acknowledgement: needsAcknowledgement ? acknowledgement : nil)
        default:
            return QiYiPacketResult(events: [], acknowledgement: nil)
        }
    }

    private static func facelets(_ packet: [UInt8]) -> String? {
        let colors = Array("LRDUFB")
        var result = [Character]()
        for index in 0..<54 {
            let packed = packet[7 + index / 2]
            let colorIndex = Int((packed >> (index % 2 == 0 ? 0 : 4)) & 0x0F)
            guard colorIndex < colors.count else { return nil }
            result.append(colors[colorIndex])
        }
        guard Array("URFDLB").allSatisfy({ face in result.filter { $0 == face }.count == 9 }) else {
            return nil
        }
        return String(result)
    }

    private func encode(_ payload: [UInt8]) -> [UInt8]? {
        guard payload.count <= 250 else { return nil }
        var packet = [UInt8(0xFE), UInt8(payload.count + 4)] + payload
        let checksum = Self.crc(packet)
        packet += [UInt8(checksum & 0xFF), UInt8(checksum >> 8)]
        packet += [UInt8](repeating: 0, count: (16 - packet.count % 16) % 16)
        return crypt(packet, operation: CCOperation(kCCEncrypt))
    }

    private func crypt(_ bytes: [UInt8], operation: CCOperation) -> [UInt8]? {
        guard !bytes.isEmpty, bytes.count % 16 == 0 else { return nil }
        var output = [UInt8](repeating: 0, count: bytes.count)
        let outputCapacity = output.count
        var outputLength = 0
        let status = Self.key.withUnsafeBytes { key in
            bytes.withUnsafeBytes { input in
                output.withUnsafeMutableBytes { buffer in
                    CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionECBMode),
                            key.baseAddress, kCCKeySizeAES128, nil,
                            input.baseAddress, bytes.count, buffer.baseAddress, outputCapacity, &outputLength)
                }
            }
        }
        return status == kCCSuccess && outputLength == bytes.count ? output : nil
    }

    private static func crc(_ bytes: [UInt8]) -> UInt16 {
        var value: UInt16 = 0xFFFF
        for byte in bytes {
            value ^= UInt16(byte)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? (value >> 1) ^ 0xA001 : value >> 1
            }
        }
        return value
    }

    private func crc(_ bytes: [UInt8]) -> UInt16 { Self.crc(bytes) }

    private func word(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }
}
#endif
