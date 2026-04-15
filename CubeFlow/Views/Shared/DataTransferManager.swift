import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum DataTransferExportFormat: String, CaseIterable, Identifiable, Sendable {
    case cubeFlow
    case csTimer

    var id: String { rawValue }
}

enum DataTransferImportSource: String, Sendable {
    case cubeFlow
    case csTimer
}

enum DataTransferSessionConflictResolution: String, Sendable {
    case merge
    case rename
}

struct DataTransferProgress: Sendable {
    enum Stage: Sendable {
        case preparing
        case importing
    }

    let stage: Stage
    let current: Int
    let total: Int
}

struct DataTransferSessionConflict: Identifiable, Sendable {
    let normalizedName: String
    let displayName: String
    let existingSessionCount: Int
    let importedSessionCount: Int

    var id: String { normalizedName }
}

struct DataTransferExistingSessionReference: Sendable {
    let id: UUID
    let name: String
    let createdAt: Date
}

struct DataTransferImportPreview: Sendable {
    let source: DataTransferImportSource
    let sessionCount: Int
    let solveCount: Int
    let sessionConflicts: [DataTransferSessionConflict]

    nonisolated var hasSessionConflicts: Bool {
        !sessionConflicts.isEmpty
    }
}

enum DataTransferImportPlan: Sendable {
    case cubeFlow(CubeFlowImportPlan)
    case csTimer(CSTimerImportPlan)

    nonisolated var source: DataTransferImportSource {
        switch self {
        case .cubeFlow:
            return .cubeFlow
        case .csTimer:
            return .csTimer
        }
    }

    nonisolated var sessionCount: Int {
        switch self {
        case .cubeFlow(let plan):
            return plan.payload.sessions.count
        case .csTimer(let plan):
            return plan.sessions.count
        }
    }

    nonisolated var solveCount: Int {
        switch self {
        case .cubeFlow(let plan):
            return plan.payload.solves.count
        case .csTimer(let plan):
            return plan.sessions.reduce(0) { $0 + $1.solves.count }
        }
    }
}

struct DataTransferPreparedImport: Sendable {
    let preview: DataTransferImportPreview
    let plan: DataTransferImportPlan
}

struct DataTransferExportPackage {
    let document: DataTransferDocument
    let contentType: UTType
    let defaultFilename: String
}

struct DataTransferDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .plainText] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum DataTransferError: Error, Equatable {
    case unsupportedImportFile
    case importSessionResolutionFailed
}

enum DataTransferManager {
    @MainActor
    static func prepareExport(
        format: DataTransferExportFormat,
        sessions: [Session],
        solves: [Solve]
    ) throws -> DataTransferExportPackage {
        switch format {
        case .cubeFlow:
            return try prepareCubeFlowExport(sessions: sessions, solves: solves)
        case .csTimer:
            return try prepareCSTimerExport(sessions: sessions, solves: solves)
        }
    }

    @MainActor
    static func prepareImport(
        _ data: Data,
        existingSessions: [Session]
    ) throws -> DataTransferPreparedImport {
        try prepareImport(
            data,
            existingSessions: existingSessions.map {
                DataTransferExistingSessionReference(
                    id: $0.id,
                    name: $0.name,
                    createdAt: $0.createdAt
                )
            }
        )
    }

    nonisolated static func prepareImport(
        _ data: Data,
        existingSessions: [DataTransferExistingSessionReference]
    ) throws -> DataTransferPreparedImport {
        if let payload = try? JSONDecoder.cubeFlowBackup.decode(CubeFlowBackupPayload.self, from: data) {
            let plan = DataTransferImportPlan.cubeFlow(CubeFlowImportPlan(payload: payload))
            return DataTransferPreparedImport(
                preview: buildImportPreview(for: plan, existingSessions: existingSessions),
                plan: plan
            )
        }

        if let plan = try parseCSTimerImportPlan(data) {
            let wrappedPlan = DataTransferImportPlan.csTimer(plan)
            return DataTransferPreparedImport(
                preview: buildImportPreview(for: wrappedPlan, existingSessions: existingSessions),
                plan: wrappedPlan
            )
        }

        throw DataTransferError.unsupportedImportFile
    }

    static func importPreparedImport(
        _ preparedImport: DataTransferPreparedImport,
        conflictResolution: DataTransferSessionConflictResolution = .rename,
        modelContext: ModelContext,
        progress: @escaping @Sendable @MainActor (DataTransferProgress) -> Void
    ) async throws {
        let container = modelContext.container
        try await Task.detached(priority: .userInitiated) {
            let backgroundContext = ModelContext(container)
            let backgroundExistingSessions = try backgroundContext.fetch(
                FetchDescriptor<Session>(
                    sortBy: [SortDescriptor(\Session.createdAt, order: .forward)]
                )
            )

            switch preparedImport.plan {
            case .cubeFlow(let plan):
                try await importBackup(
                    plan,
                    conflictResolution: conflictResolution,
                    modelContext: backgroundContext,
                    existingSessions: backgroundExistingSessions,
                    progress: progress
                )
            case .csTimer(let plan):
                try await importCSTimer(
                    plan,
                    conflictResolution: conflictResolution,
                    modelContext: backgroundContext,
                    existingSessions: backgroundExistingSessions,
                    progress: progress
                )
            }
        }.value
    }

    @MainActor
    static func importDataFile(
        _ data: Data,
        modelContext: ModelContext,
        existingSessions: [Session],
        progress: @escaping @Sendable @MainActor (DataTransferProgress) -> Void
    ) async throws {
        progress(DataTransferProgress(stage: .preparing, current: 0, total: 1))
        let existingSessionReferences = existingSessions.map {
            DataTransferExistingSessionReference(
                id: $0.id,
                name: $0.name,
                createdAt: $0.createdAt
            )
        }
        let preparedImport = try prepareImport(data, existingSessions: existingSessionReferences)
        try await importPreparedImport(
            preparedImport,
            conflictResolution: .rename,
            modelContext: modelContext,
            progress: progress
        )
    }

    @MainActor
    private static func prepareCubeFlowExport(
        sessions: [Session],
        solves: [Solve]
    ) throws -> DataTransferExportPackage {
        let payload = CubeFlowBackupPayload(
            version: 1,
            exportedAt: .now,
            sessions: sessions.map {
                SessionBackupItem(id: $0.id, name: $0.name, createdAt: $0.createdAt)
            },
            solves: solves.map {
                SolveBackupItem(
                    id: $0.id,
                    time: $0.time,
                    date: $0.date,
                    scramble: $0.scramble,
                    event: $0.event,
                    resultRaw: $0.resultRaw,
                    sessionID: $0.session?.id
                )
            }
        )

        let data = try JSONEncoder.cubeFlowBackup.encode(payload)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "CubeFlowBackup_\(formatter.string(from: .now))"
        return DataTransferExportPackage(
            document: DataTransferDocument(data: data),
            contentType: .json,
            defaultFilename: filename
        )
    }

    @MainActor
    private static func prepareCSTimerExport(
        sessions: [Session],
        solves: [Solve]
    ) throws -> DataTransferExportPackage {
        let solvesBySessionID = Dictionary(grouping: solves) { $0.session?.id }
        let exportSessions = sessions
            .filter { !(solvesBySessionID[$0.id] ?? []).isEmpty }
            .sorted { $0.createdAt < $1.createdAt }

        var root: [String: Any] = [:]
        var sessionMetadata: [String: [String: Any]] = [:]

        for (index, session) in exportSessions.enumerated() {
            let sessionNumber = index + 1
            let sessionKey = "session\(sessionNumber)"
            let sessionSolves = (solvesBySessionID[session.id] ?? [])
                .sorted { $0.date < $1.date }

            root[sessionKey] = sessionSolves.map(csTimerSolveEntry(for:))
            sessionMetadata[String(sessionNumber)] = csTimerSessionMetadata(
                session: session,
                sessionNumber: sessionNumber,
                solves: sessionSolves
            )
        }

        let sessionData = try JSONSerialization.data(withJSONObject: sessionMetadata, options: [.sortedKeys])
        let sessionDataString = String(decoding: sessionData, as: UTF8.self)
        root["properties"] = [
            "sessionData": sessionDataString
        ]
        root["session"] = exportSessions.isEmpty ? 0 : 1
        root["sessionN"] = exportSessions.count

        let data = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let filename = "cstimer_\(formatter.string(from: .now))"

        return DataTransferExportPackage(
            document: DataTransferDocument(data: data),
            contentType: .plainText,
            defaultFilename: filename
        )
    }

    nonisolated private static func buildImportPreview(
        for plan: DataTransferImportPlan,
        existingSessions: [DataTransferExistingSessionReference]
    ) -> DataTransferImportPreview {
        let descriptors = importedSessionDescriptors(for: plan, existingSessions: existingSessions)

        return DataTransferImportPreview(
            source: plan.source,
            sessionCount: plan.sessionCount,
            solveCount: plan.solveCount,
            sessionConflicts: detectSessionConflicts(
                importedDescriptors: descriptors,
                existingSessions: existingSessions
            )
        )
    }

    nonisolated private static func importedSessionDescriptors(
        for plan: DataTransferImportPlan,
        existingSessions: [DataTransferExistingSessionReference]
    ) -> [ImportedSessionDescriptor] {
        let existingSessionIDs = Set(existingSessions.map(\.id))

        switch plan {
        case .cubeFlow(let plan):
            return plan.payload.sessions.map { session in
                ImportedSessionDescriptor(
                    key: session.id.uuidString,
                    name: session.name,
                    createdAt: session.createdAt,
                    matchedExistingSessionID: existingSessionIDs.contains(session.id) ? session.id : nil
                )
            }
        case .csTimer(let plan):
            return plan.sessions.map { session in
                ImportedSessionDescriptor(
                    key: session.key,
                    name: session.name,
                    createdAt: session.createdAt,
                    matchedExistingSessionID: nil
                )
            }
        }
    }

    nonisolated private static func detectSessionConflicts(
        importedDescriptors: [ImportedSessionDescriptor],
        existingSessions: [DataTransferExistingSessionReference]
    ) -> [DataTransferSessionConflict] {
        let relevantDescriptors = importedDescriptors.filter { $0.matchedExistingSessionID == nil }
        guard !relevantDescriptors.isEmpty else { return [] }

        let existingCountsByName = existingSessions.reduce(into: [String: Int]()) { result, session in
            result[normalizedSessionName(session.name), default: 0] += 1
        }

        var importedCountsByName: [String: Int] = [:]
        var displayNamesByName: [String: String] = [:]

        for descriptor in relevantDescriptors {
            let normalizedName = normalizedSessionName(descriptor.name)
            importedCountsByName[normalizedName, default: 0] += 1
            if displayNamesByName[normalizedName] == nil {
                displayNamesByName[normalizedName] = descriptor.name
            }
        }

        return importedCountsByName.keys
            .compactMap { normalizedName in
                let importedCount = importedCountsByName[normalizedName, default: 0]
                let existingCount = existingCountsByName[normalizedName, default: 0]
                guard importedCount > 1 || existingCount > 0 else {
                    return nil
                }

                return DataTransferSessionConflict(
                    normalizedName: normalizedName,
                    displayName: displayNamesByName[normalizedName] ?? normalizedName,
                    existingSessionCount: existingCount,
                    importedSessionCount: importedCount
                )
            }
            .sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private static func importBackup(
        _ plan: CubeFlowImportPlan,
        conflictResolution: DataTransferSessionConflictResolution,
        modelContext: ModelContext,
        existingSessions: [Session],
        progress: @escaping @Sendable @MainActor (DataTransferProgress) -> Void
    ) async throws {
        let payload = plan.payload
        let total = max(payload.sessions.count + payload.solves.count, 1)
        let progressStep = progressStride(for: total)
        let saveStride = 1_000
        await MainActor.run {
            progress(DataTransferProgress(stage: .importing, current: 0, total: total))
        }
        let existingSolves = try modelContext.fetch(FetchDescriptor<Solve>())

        var sessionResolver = SessionImportResolver(
            existingSessions: existingSessions,
            conflictResolution: conflictResolution
        )
        var importedSessionTargets: [UUID: Session] = [:]
        var solveByID = Dictionary(uniqueKeysWithValues: existingSolves.map { ($0.id, $0) })
        var existingSolveFingerprints = buildExistingSolveFingerprints(from: existingSolves)
        var processed = 0
        var unsavedChanges = 0

        for sessionItem in payload.sessions {
            let targetSession = sessionResolver.resolveBackupSession(
                importedSessionID: sessionItem.id,
                importedName: sessionItem.name,
                createdAt: sessionItem.createdAt,
                modelContext: modelContext
            )
            importedSessionTargets[sessionItem.id] = targetSession
            unsavedChanges += 1

            processed += 1
            if processed.isMultiple(of: progressStep) || processed == total {
                let currentProcessed = processed
                await MainActor.run {
                    progress(DataTransferProgress(stage: .importing, current: currentProcessed, total: total))
                }
                await Task.yield()
            }
            if unsavedChanges >= saveStride {
                try modelContext.save()
                unsavedChanges = 0
            }
        }

        for solveItem in payload.solves {
            let targetSession = solveItem.sessionID.flatMap { importedSessionTargets[$0] }
            let fingerprint = solveFingerprint(
                sessionID: targetSession?.id,
                time: solveItem.time,
                date: solveItem.date,
                scramble: solveItem.scramble,
                event: solveItem.event,
                resultRaw: solveItem.resultRaw
            )

            if let existing = solveByID[solveItem.id] {
                existing.time = solveItem.time
                existing.date = solveItem.date
                existing.scramble = solveItem.scramble
                existing.event = solveItem.event
                existing.resultRaw = solveItem.resultRaw
                existing.session = targetSession
                existingSolveFingerprints.insert(fingerprint)
                unsavedChanges += 1
            } else if !existingSolveFingerprints.contains(fingerprint) {
                let newSolve = Solve(
                    time: solveItem.time,
                    date: solveItem.date,
                    scramble: solveItem.scramble,
                    event: solveItem.event,
                    result: SolveResult(rawValue: solveItem.resultRaw) ?? .solved,
                    session: targetSession
                )
                newSolve.id = solveItem.id
                modelContext.insert(newSolve)
                solveByID[newSolve.id] = newSolve
                existingSolveFingerprints.insert(fingerprint)
                unsavedChanges += 1
            }

            processed += 1
            if processed.isMultiple(of: progressStep) || processed == total {
                let currentProcessed = processed
                await MainActor.run {
                    progress(DataTransferProgress(stage: .importing, current: currentProcessed, total: total))
                }
                await Task.yield()
            }
            if unsavedChanges >= saveStride {
                try modelContext.save()
                unsavedChanges = 0
            }
        }

        if unsavedChanges > 0 {
            try modelContext.save()
        }
    }

    private static func importCSTimer(
        _ plan: CSTimerImportPlan,
        conflictResolution: DataTransferSessionConflictResolution,
        modelContext: ModelContext,
        existingSessions: [Session],
        progress: @escaping @Sendable @MainActor (DataTransferProgress) -> Void
    ) async throws {
        let total = max(plan.sessions.count + plan.solveCount, 1)
        let progressStep = progressStride(for: total)
        let solveChunkSize = 250
        await MainActor.run {
            progress(DataTransferProgress(stage: .importing, current: 0, total: total))
        }

        var sessionResolver = SessionImportResolver(
            existingSessions: existingSessions,
            conflictResolution: conflictResolution
        )
        let existingSessionIDs = Set(existingSessions.map(\.id))
        var targetSessions: [(session: CSTimerImportSession, targetSessionID: UUID, targetPersistentID: PersistentIdentifier)] = []
        var processed = 0

        for session in plan.sessions {
            let targetSession = sessionResolver.resolveImportedSession(
                importedName: session.name,
                createdAt: session.createdAt,
                preferredID: nil,
                modelContext: modelContext
            )
            targetSessions.append((session, targetSession.id, targetSession.persistentModelID))

            processed += 1
            if processed.isMultiple(of: progressStep) || processed == total {
                let currentProcessed = processed
                await MainActor.run {
                    progress(DataTransferProgress(stage: .importing, current: currentProcessed, total: total))
                }
                await Task.yield()
            }
        }

        if !targetSessions.isEmpty {
            try modelContext.save()
        }

        for (session, targetSessionID, targetPersistentID) in targetSessions {
            let existingFingerprints: Set<SolveFingerprint>
            if existingSessionIDs.contains(targetSessionID) {
                let fingerprintContext = ModelContext(modelContext.container)
                existingFingerprints = try fetchSolveFingerprints(
                    forSessionID: targetSessionID,
                    modelContext: fingerprintContext
                )
            } else {
                existingFingerprints = []
            }

            var sessionFingerprints = existingFingerprints

            var chunkStart = 0
            while chunkStart < session.solves.count {
                let chunkEnd = min(chunkStart + solveChunkSize, session.solves.count)
                let chunkContext = ModelContext(modelContext.container)
                guard let targetSession = chunkContext.model(for: targetPersistentID) as? Session else {
                    throw DataTransferError.importSessionResolutionFailed
                }

                var insertedInChunk = 0

                for importedSolve in session.solves[chunkStart..<chunkEnd] {
                    let fingerprint = solveFingerprint(
                        sessionID: targetSession.id,
                        time: importedSolve.time,
                        date: importedSolve.date,
                        scramble: importedSolve.scramble,
                        event: importedSolve.event,
                        resultRaw: importedSolve.result.rawValue
                    )

                    if sessionFingerprints.insert(fingerprint).inserted {
                        let solve = Solve(
                            time: importedSolve.time,
                            date: importedSolve.date,
                            scramble: importedSolve.scramble,
                            event: importedSolve.event,
                            result: importedSolve.result,
                            session: targetSession
                        )
                        chunkContext.insert(solve)
                        insertedInChunk += 1
                    }

                    processed += 1
                    if processed.isMultiple(of: progressStep) || processed == total {
                        let currentProcessed = processed
                await MainActor.run {
                    progress(DataTransferProgress(stage: .importing, current: currentProcessed, total: total))
                }
                        await Task.yield()
                    }
                }

                if insertedInChunk > 0 {
                    try chunkContext.save()
                }

                chunkStart = chunkEnd
            }
        }
    }

    nonisolated private static func parseCSTimerImportPlan(_ data: Data) throws -> CSTimerImportPlan? {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { return nil }

        let sessionEntries = root.keys
            .compactMap { key -> (Int, String)? in
                guard key.hasPrefix("session"), let number = Int(key.dropFirst("session".count)) else {
                    return nil
                }
                return (number, key)
            }
            .sorted { $0.0 < $1.0 }

        guard !sessionEntries.isEmpty else { return nil }

        let sessionMetadata = parseCSTimerSessionMetadata(from: root)
        let sessions = sessionEntries.compactMap { sessionNumber, sessionKey -> CSTimerImportSession? in
            guard let rawSolves = root[sessionKey] as? [[Any]], !rawSolves.isEmpty else {
                return nil
            }

            let metadata = sessionMetadata[String(sessionNumber)] ?? [:]
            let trimmedSessionName = (metadata["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let sessionName = (trimmedSessionName?.isEmpty == false ? trimmedSessionName : nil)
                ?? "csTimer Session \(sessionNumber)"
            let createdAt = csTimerSessionCreatedAt(metadata: metadata, rawSolves: rawSolves)
            let event = cubeFlowEventString(
                scrType: ((metadata["opt"] as? [String: Any])?["scrType"] as? String),
                sessionName: sessionName
            )

            let solves = rawSolves.compactMap { rawSolve in
                parseCSTimerSolve(rawSolve, defaultEvent: event)
            }

            guard !solves.isEmpty else { return nil }

            return CSTimerImportSession(
                key: sessionKey,
                name: sessionName,
                createdAt: createdAt,
                solves: solves
            )
        }

        guard !sessions.isEmpty else { return nil }
        return CSTimerImportPlan(sessions: sessions)
    }

    nonisolated private static func parseCSTimerSessionMetadata(from root: [String: Any]) -> [String: [String: Any]] {
        guard
            let properties = root["properties"] as? [String: Any],
            let sessionDataString = properties["sessionData"] as? String,
            let sessionData = sessionDataString.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: sessionData) as? [String: Any]
        else {
            return [:]
        }

        return object.reduce(into: [:]) { result, pair in
            if let metadata = pair.value as? [String: Any] {
                result[pair.key] = metadata
            }
        }
    }

    nonisolated private static func csTimerSessionCreatedAt(metadata: [String: Any], rawSolves: [[Any]]) -> Date {
        if
            let dateRange = metadata["date"] as? [Any],
            let firstTimestamp = number(from: dateRange.first)
        {
            return Date(timeIntervalSince1970: firstTimestamp)
        }

        if
            let firstSolve = rawSolves.first,
            let timestamp = number(from: firstSolve[safe: 3])
        {
            return Date(timeIntervalSince1970: timestamp)
        }

        return .now
    }

    private static func buildExistingSolveFingerprints(from solves: [Solve]) -> Set<SolveFingerprint> {
        Set(
            solves.map {
                solveFingerprint(
                    sessionID: $0.session?.id,
                    time: $0.time,
                    date: $0.date,
                    scramble: $0.scramble,
                    event: $0.event,
                    resultRaw: $0.resultRaw
                )
            }
        )
    }

    private static func fetchSolveFingerprints(
        forSessionID sessionID: UUID,
        modelContext: ModelContext
    ) throws -> Set<SolveFingerprint> {
        let descriptor = FetchDescriptor<Solve>(
            predicate: #Predicate<Solve> { solve in
                solve.session?.id == sessionID
            }
        )
        let solves = try modelContext.fetch(descriptor)
        return buildExistingSolveFingerprints(from: solves)
    }

    nonisolated private static func parseCSTimerSolve(_ rawSolve: [Any], defaultEvent: String) -> CSTimerImportSolve? {
        guard
            let timing = rawSolve[safe: 0] as? [Any],
            let penalty = number(from: timing[safe: 0]),
            let timeMilliseconds = number(from: timing[safe: 1]),
            let timestamp = number(from: rawSolve[safe: 3])
        else {
            return nil
        }

        let scramble = rawSolve[safe: 1] as? String ?? ""
        let result: SolveResult
        if penalty == -1 {
            result = .dnf
        } else if penalty == 2000 {
            result = .plusTwo
        } else {
            result = .solved
        }

        return CSTimerImportSolve(
            time: timeMilliseconds / 1000,
            date: Date(timeIntervalSince1970: timestamp),
            scramble: scramble,
            event: defaultEvent,
            result: result
        )
    }

    @MainActor
    private static func csTimerSolveEntry(for solve: Solve) -> [Any] {
        let penalty: Int
        switch solve.result {
        case .solved:
            penalty = 0
        case .plusTwo:
            penalty = 2000
        case .dnf:
            penalty = -1
        }

        return [
            [penalty, Int((solve.time * 1000).rounded())],
            solve.scramble,
            "",
            Int(solve.date.timeIntervalSince1970)
        ]
    }

    @MainActor
    private static func csTimerSessionMetadata(
        session: Session,
        sessionNumber: Int,
        solves: [Solve]
    ) -> [String: Any] {
        let dominantEvent = mostCommonEvent(in: solves) ?? solves.first?.event ?? "3x3"
        let scrType = csTimerScrType(for: dominantEvent)
        let validTimes = solves.compactMap(SolveMetrics.adjustedTime(for:))
        let dnfCount = solves.filter { $0.result == .dnf }.count
        let averageMilliseconds = validTimes.isEmpty
            ? -1.0
            : (validTimes.reduce(0.0, +) / Double(validTimes.count)) * 1000
        let firstTimestamp = Int((solves.min(by: { $0.date < $1.date })?.date ?? session.createdAt).timeIntervalSince1970)
        let lastTimestamp = Int((solves.max(by: { $0.date < $1.date })?.date ?? session.createdAt).timeIntervalSince1970)

        return [
            "name": session.name,
            "opt": ["scrType": scrType],
            "rank": sessionNumber,
            "stat": [solves.count, dnfCount, averageMilliseconds],
            "date": [firstTimestamp, lastTimestamp]
        ]
    }

    @MainActor
    private static func mostCommonEvent(in solves: [Solve]) -> String? {
        Dictionary(grouping: solves, by: \.event)
            .max { $0.value.count < $1.value.count }?
            .key
    }

    nonisolated private static func csTimerScrType(for event: String) -> String {
        switch event.lowercased() {
        case "2x2":
            return "222so"
        case "3x3":
            return "333"
        case "4x4":
            return "444wca"
        case "5x5":
            return "555wca"
        case "6x6":
            return "666wca"
        case "7x7":
            return "777wca"
        case "megaminx":
            return "mgmp"
        case "pyraminx":
            return "pyrso"
        case "square-1":
            return "sqrs"
        case "clock":
            return "clkwca"
        case "skewb":
            return "skbso"
        case "3x3 oh":
            return "333oh"
        case "3x3 fm":
            return "333fm"
        case "3x3 bld":
            return "333bf"
        case "4x4 bld":
            return "444bf"
        case "5x5 bld":
            return "555bf"
        case "3x3 mbld":
            return "r3ni"
        default:
            return "333"
        }
    }

    nonisolated private static func cubeFlowEventString(scrType: String?, sessionName: String) -> String {
        let normalizedName = sessionName.lowercased()
        if normalizedName.contains("4x4 bld") { return "4x4 bld" }
        if normalizedName.contains("5x5 bld") { return "5x5 bld" }
        if normalizedName.contains("3x3 bld") || normalizedName.contains("3bld") { return "3x3 bld" }
        if normalizedName.contains("3x3 oh") || normalizedName.contains("oh") { return "3x3 oh" }
        if normalizedName.contains("fmc") || normalizedName.contains("fm") { return "3x3 fm" }
        if normalizedName.contains("mbld") || normalizedName.contains("多盲") { return "3x3 mbld" }

        switch scrType?.lowercased() {
        case "222so": return "2x2"
        case "333", "333ni", "333oh0": return "3x3"
        case "444wca": return "4x4"
        case "555wca": return "5x5"
        case "666wca": return "6x6"
        case "777wca": return "7x7"
        case "mgmp": return "Megaminx"
        case "pyrso": return "pyraminx"
        case "sqrs": return "square-1"
        case "clkwca": return "clock"
        case "skbso": return "skewb"
        case "333oh": return "3x3 oh"
        case "333fm": return "3x3 fm"
        case "333bf": return "3x3 bld"
        case "444bf": return "4x4 bld"
        case "555bf": return "5x5 bld"
        default:
            return "3x3"
        }
    }

    nonisolated private static func normalizedSessionName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated private static func solveFingerprint(
        sessionID: UUID?,
        time: Double,
        date: Date,
        scramble: String,
        event: String,
        resultRaw: String
    ) -> SolveFingerprint {
        SolveFingerprint(
            sessionID: sessionID,
            timeMilliseconds: Int((time * 1000).rounded()),
            timestamp: Int(date.timeIntervalSince1970),
            scramble: scramble,
            event: event,
            resultRaw: resultRaw
        )
    }

    nonisolated private static func progressStride(for total: Int) -> Int {
        min(max(total / 1_000, 10), 80)
    }

    nonisolated private static func number(from any: Any?) -> Double? {
        switch any {
        case let number as NSNumber:
            return number.doubleValue
        case let double as Double:
            return double
        case let int as Int:
            return Double(int)
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }
}

private struct SessionImportResolver {
    private let conflictResolution: DataTransferSessionConflictResolution
    private var sessionsByID: [UUID: Session]
    private var mergeTargetsByName: [String: Session]
    private var reservedNormalizedNames: Set<String>

    init(existingSessions: [Session], conflictResolution: DataTransferSessionConflictResolution) {
        self.conflictResolution = conflictResolution

        let sortedSessions = existingSessions.sorted { $0.createdAt < $1.createdAt }
        let normalize: (String) -> String = {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        self.sessionsByID = Dictionary(uniqueKeysWithValues: sortedSessions.map { ($0.id, $0) })
        self.mergeTargetsByName = [:]
        self.reservedNormalizedNames = Set(sortedSessions.map { normalize($0.name) })

        for session in sortedSessions where mergeTargetsByName[normalize(session.name)] == nil {
            mergeTargetsByName[normalize(session.name)] = session
        }
    }

    mutating func resolveBackupSession(
        importedSessionID: UUID,
        importedName: String,
        createdAt: Date,
        modelContext: ModelContext
    ) -> Session {
        if let existing = sessionsByID[importedSessionID] {
            existing.name = importedName
            existing.createdAt = createdAt
            register(session: existing)
            return existing
        }

        return resolveImportedSession(
            importedName: importedName,
            createdAt: createdAt,
            preferredID: importedSessionID,
            modelContext: modelContext
        )
    }

    mutating func resolveImportedSession(
        importedName: String,
        createdAt: Date,
        preferredID: UUID?,
        modelContext: ModelContext
    ) -> Session {
        let trimmedName = importedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmedName.isEmpty ? "Session" : trimmedName
        let normalizedName = normalizedSessionName(baseName)

        switch conflictResolution {
        case .merge:
            if let existing = mergeTargetsByName[normalizedName] {
                return existing
            }

            let newSession = Session(name: baseName, createdAt: createdAt)
            if let preferredID {
                newSession.id = preferredID
            }
            modelContext.insert(newSession)
            register(session: newSession)
            return newSession

        case .rename:
            let finalName = uniqueSessionName(for: baseName)
            let newSession = Session(name: finalName, createdAt: createdAt)
            if let preferredID {
                newSession.id = preferredID
            }
            modelContext.insert(newSession)
            register(session: newSession)
            return newSession
        }
    }

    private mutating func register(session: Session) {
        sessionsByID[session.id] = session
        let normalizedName = normalizedSessionName(session.name)
        if mergeTargetsByName[normalizedName] == nil {
            mergeTargetsByName[normalizedName] = session
        }
        reservedNormalizedNames.insert(normalizedName)
    }

    private mutating func uniqueSessionName(for baseName: String) -> String {
        let normalizedBaseName = normalizedSessionName(baseName)
        guard reservedNormalizedNames.contains(normalizedBaseName) else {
            return baseName
        }

        var suffix = 1
        while true {
            let candidate = "\(baseName) \(suffix)"
            if !reservedNormalizedNames.contains(normalizedSessionName(candidate)) {
                return candidate
            }
            suffix += 1
        }
    }

    private func normalizedSessionName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

private struct ImportedSessionDescriptor: Sendable {
    let key: String
    let name: String
    let createdAt: Date
    let matchedExistingSessionID: UUID?
}

private struct SolveFingerprint: Hashable {
    let sessionID: UUID?
    let timeMilliseconds: Int
    let timestamp: Int
    let scramble: String
    let event: String
    let resultRaw: String
}

struct CubeFlowImportPlan: Sendable {
    let payload: CubeFlowBackupPayload
}

struct CSTimerImportPlan: Sendable {
    let sessions: [CSTimerImportSession]

    nonisolated var solveCount: Int {
        sessions.reduce(0) { $0 + $1.solves.count }
    }
}

struct CSTimerImportSession: Sendable {
    let key: String
    let name: String
    let createdAt: Date
    let solves: [CSTimerImportSolve]
}

struct CSTimerImportSolve: Sendable {
    let time: Double
    let date: Date
    let scramble: String
    let event: String
    let result: SolveResult
}

private extension Array {
    nonisolated subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}

struct CubeFlowBackupPayload: Sendable, Codable {
    let version: Int
    let exportedAt: Date
    let sessions: [SessionBackupItem]
    let solves: [SolveBackupItem]

    enum CodingKeys: String, CodingKey {
        case version
        case exportedAt
        case sessions
        case solves
    }

    nonisolated init(version: Int, exportedAt: Date, sessions: [SessionBackupItem], solves: [SolveBackupItem]) {
        self.version = version
        self.exportedAt = exportedAt
        self.sessions = sessions
        self.solves = solves
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        exportedAt = try container.decode(Date.self, forKey: .exportedAt)
        sessions = try container.decode([SessionBackupItem].self, forKey: .sessions)
        solves = try container.decode([SolveBackupItem].self, forKey: .solves)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(sessions, forKey: .sessions)
        try container.encode(solves, forKey: .solves)
    }
}

struct SessionBackupItem: Sendable, Codable {
    let id: UUID
    let name: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
    }

    nonisolated init(id: UUID, name: String, createdAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct SolveBackupItem: Sendable, Codable {
    let id: UUID
    let time: Double
    let date: Date
    let scramble: String
    let event: String
    let resultRaw: String
    let sessionID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case time
        case date
        case scramble
        case event
        case resultRaw
        case sessionID
    }

    nonisolated init(
        id: UUID,
        time: Double,
        date: Date,
        scramble: String,
        event: String,
        resultRaw: String,
        sessionID: UUID?
    ) {
        self.id = id
        self.time = time
        self.date = date
        self.scramble = scramble
        self.event = event
        self.resultRaw = resultRaw
        self.sessionID = sessionID
    }

    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        time = try container.decode(Double.self, forKey: .time)
        date = try container.decode(Date.self, forKey: .date)
        scramble = try container.decode(String.self, forKey: .scramble)
        event = try container.decode(String.self, forKey: .event)
        resultRaw = try container.decode(String.self, forKey: .resultRaw)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(time, forKey: .time)
        try container.encode(date, forKey: .date)
        try container.encode(scramble, forKey: .scramble)
        try container.encode(event, forKey: .event)
        try container.encode(resultRaw, forKey: .resultRaw)
        try container.encodeIfPresent(sessionID, forKey: .sessionID)
    }
}

private extension JSONEncoder {
    nonisolated static var cubeFlowBackup: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var cubeFlowBackup: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
