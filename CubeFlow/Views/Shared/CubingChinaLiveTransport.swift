import Foundation

nonisolated struct CubingChinaSSEFrame: Equatable, Sendable {
    let event: String
    let id: String?
    let data: String
}

/// Line-oriented SSE decoding independent of URLSession's arbitrary byte/chunk boundaries.
nonisolated struct CubingChinaSSEParser {
    private var line: [UInt8] = []
    private var data: [String] = []
    private var event = ""
    private var id: String?
    private var skipsLF = false
    private var firstLine = true
    private var frameBytes = 0
    var limit = 512 * 1024

    mutating func append(_ bytes: some Sequence<UInt8>) throws -> [CubingChinaSSEFrame] {
        var frames: [CubingChinaSSEFrame] = []
        for byte in bytes {
            if skipsLF { skipsLF = false; if byte == 10 { continue } }
            if byte == 10 || byte == 13 {
                if let frame = try finishLine() { frames.append(frame) }
                skipsLF = byte == 13
            } else {
                line.append(byte)
                guard line.count <= limit else { throw CubingChinaLiveError.oversized }
            }
        }
        return frames
    }

    private mutating func finishLine() throws -> CubingChinaSSEFrame? {
        guard var text = String(bytes: line, encoding: .utf8) else { throw CubingChinaLiveError.invalidData }
        line.removeAll(keepingCapacity: true)
        if firstLine { firstLine = false; if text.hasPrefix("\u{FEFF}") { text.removeFirst() } }
        if text.isEmpty {
            let frame = data.isEmpty ? nil : CubingChinaSSEFrame(event: event.isEmpty ? "message" : event,
                id: id, data: data.joined(separator: "\n"))
            data.removeAll(keepingCapacity: true); event = ""; frameBytes = 0
            return frame
        }
        if text.hasPrefix(":") { return nil }
        let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        var value = parts.count == 2 ? String(parts[1]) : ""
        if value.hasPrefix(" ") { value.removeFirst() }
        frameBytes += text.utf8.count
        guard frameBytes <= limit else { throw CubingChinaLiveError.oversized }
        switch parts[0] {
        case "data": data.append(value)
        case "event": event = value
        case "id": if !value.contains("\0") { id = value }
        default: break
        }
        return nil
    }
}

nonisolated protocol CubingChinaLiveTransport: Sendable {
    func rounds(slug: String) async throws -> [CubingChinaLiveRound]
    func results(slug: String, key: CubingChinaLiveRoundKey) async throws -> CubingChinaLiveSnapshot
    func messages(slug: String) async throws -> [CubingChinaLiveMessage]
    func events(slug: String, viewerID: String) async throws -> CubingChinaLiveConnection
    func competitorResults(slug: String, number: Int) async throws -> [CubingChinaLiveResult]
}

nonisolated struct CubingChinaLiveConnection: Sendable {
    let frames: AsyncThrowingStream<CubingChinaSSEFrame, Error>
    let cancel: @Sendable () -> Void
}

nonisolated final class CubingChinaLiveHTTPClient: CubingChinaLiveTransport, CubingChinaLiveExtrasTransport, @unchecked Sendable {
    static let shared = CubingChinaLiveHTTPClient()
    private let session: URLSession
    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 20
            self.session = URLSession(configuration: configuration)
        }
    }

    func rounds(slug: String) async throws -> [CubingChinaLiveRound] { try await get(slug, path: "rounds") }
    func results(slug: String, key: CubingChinaLiveRoundKey) async throws -> CubingChinaLiveSnapshot {
        guard key.number > 0, key.eventID.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil else {
            throw CubingChinaLiveError.invalidData
        }
        return try await get(slug, path: "results/\(key.eventID)/\(key.number)")
    }
    func messages(slug: String) async throws -> [CubingChinaLiveMessage] {
        try await get(slug, path: "messages", query: [URLQueryItem(name: "limit", value: "50")])
    }
    func competitorResults(slug: String, number: Int) async throws -> [CubingChinaLiveResult] {
        guard number > 0 else { throw CubingChinaLiveError.invalidData }
        return try await get(slug, path: "competitors/\(number)/results")
    }

    func podiums(slug: String) async throws -> [CubingChinaLivePodium] {
        let value: CubingChinaLiveData<[CubingChinaLivePodium]> = try await get(slug, path: "podiums")
        return value.data
    }
    func records(slug: String) async throws -> [CubingChinaLiveResult] {
        let value: CubingChinaLiveData<[CubingChinaLiveResult]> = try await get(slug, path: "records")
        return value.data
    }
    func sumOfRanks(slug: String) async throws -> [CubingChinaLiveSumRank] {
        let value: CubingChinaLiveData<[CubingChinaLiveSumRank]> = try await get(slug, path: "statistics/sum-of-ranks")
        return value.data
    }

    private func request(_ slug: String, path: String, query: [URLQueryItem] = []) throws -> URLRequest {
        guard CubingChinaTicket.website(slug: slug) != nil,
              var url = URLComponents(string: "https://api.cubing.com") else {
            throw CubingChinaLiveError.invalidData
        }
        url.path = "/competitions/\(slug)/live/\(path)"
        url.queryItems = query.isEmpty ? nil : query
        guard let resolved = url.url else { throw CubingChinaLiveError.invalidData }
        var request = URLRequest(url: resolved, cachePolicy: .reloadIgnoringLocalCacheData)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func get<Value: Decodable>(_ slug: String, path: String, query: [URLQueryItem] = []) async throws -> Value {
        let (data, response) = try await session.data(for: request(slug, path: path, query: query))
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw CubingChinaLiveError.invalidData }
        guard response.statusCode == 200 else { throw CubingChinaLiveError.http(response.statusCode) }
        guard data.count <= 4 * 1024 * 1024,
              response.mimeType == "application/json" else { throw CubingChinaLiveError.unsupported }
        return try JSONDecoder().decode(Value.self, from: data)
    }

    func events(slug: String, viewerID: String) async throws -> CubingChinaLiveConnection {
        guard viewerID.range(of: #"^[A-Za-z0-9-]{8,64}$"#, options: .regularExpression) != nil else {
            throw CubingChinaLiveError.invalidData
        }
        var request = try request(slug, path: "stream", query: [URLQueryItem(name: "viewerId", value: viewerID)])
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 60
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else {
            bytes.task.cancel(); throw CubingChinaLiveError.invalidData
        }
        guard response.statusCode == 200 else {
            bytes.task.cancel(); throw CubingChinaLiveError.http(response.statusCode)
        }
        guard !Task.isCancelled, response.mimeType == "text/event-stream" else {
            bytes.task.cancel(); throw CubingChinaLiveError.unsupported
        }
        // Overflow ends the connection, forcing snapshot recovery rather than silently losing updates.
        let frames = AsyncThrowingStream<CubingChinaSSEFrame, Error>(bufferingPolicy: .bufferingOldest(128)) { continuation in
            let producer = Task {
                defer { bytes.task.cancel() }
                do {
                    var parser = CubingChinaSSEParser()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        for frame in try parser.append(CollectionOfOne(byte)) {
                            switch continuation.yield(frame) {
                            case .enqueued: break
                            case .dropped: throw CubingChinaLiveError.oversized
                            case .terminated: return
                            @unknown default: return
                            }
                        }
                    }
                    continuation.finish(throwing: CubingChinaLiveError.disconnected)
                } catch { continuation.finish(throwing: error) }
            }
            continuation.onTermination = { @Sendable _ in producer.cancel(); bytes.task.cancel() }
        }
        return CubingChinaLiveConnection(frames: frames, cancel: { bytes.task.cancel() })
    }
}
