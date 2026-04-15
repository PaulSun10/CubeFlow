import Foundation

enum SessionSolveCountPhase: Equatable {
    case normal
    case selected
    case deselecting
}

struct RecordStatItem: Identifiable, Sendable {
    let title: String
    let value: String

    nonisolated var id: String { title }
}

struct RecordSnapshot: Sendable {
    let sessionMeanText: String
    let sessionMeanSuffix: String?
    let bestTimeText: String
    let worstTimeText: String
    let currentStats: [RecordStatItem]
    let bestStats: [RecordStatItem]

    static let empty = RecordSnapshot(
        sessionMeanText: "",
        sessionMeanSuffix: nil,
        bestTimeText: "",
        worstTimeText: "",
        currentStats: [],
        bestStats: []
    )
}

struct SessionSolveSample: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let time: Double
    let resultRaw: String
    let scramble: String

    nonisolated init(id: UUID, date: Date, time: Double, resultRaw: String, scramble: String) {
        self.id = id
        self.date = date
        self.time = time
        self.resultRaw = resultRaw
        self.scramble = scramble
    }

    nonisolated var adjustedTime: Double? {
        switch SolveResult(rawValue: resultRaw) ?? .solved {
        case .solved:
            return time
        case .plusTwo:
            return time + 2
        case .dnf:
            return nil
        }
    }
}

struct SessionSnapshotKey: Equatable, Sendable {
    let sessionID: UUID
    let solveCount: Int
    let languageCode: String
}

struct RecordAverageMetric: Identifiable, Sendable {
    enum Kind: Sendable {
        case meanOfThree
        case trimmed(Int)
        case percentage(Double)
    }

    let title: String
    let solveCount: Int
    let kind: Kind

    nonisolated var id: String { title }

    nonisolated func localizedTitle(languageCode: String) -> String {
        switch title {
        case "mo3":
            return dataTabLocalizedString(for: "data.mo3", languageCode: languageCode)
        case "ao5":
            return dataTabLocalizedString(for: "data.ao5", languageCode: languageCode)
        case "ao12":
            return dataTabLocalizedString(for: "data.ao12", languageCode: languageCode)
        case "ao50":
            return dataTabLocalizedString(for: "data.ao50", languageCode: languageCode)
        case "ao100":
            return dataTabLocalizedString(for: "data.ao100", languageCode: languageCode)
        case "ao500":
            return dataTabLocalizedString(for: "data.ao500", languageCode: languageCode)
        case "ao1000":
            return dataTabLocalizedString(for: "data.ao1000", languageCode: languageCode)
        case "ao5000":
            return dataTabLocalizedString(for: "data.ao5000", languageCode: languageCode)
        case "ao10000":
            return dataTabLocalizedString(for: "data.ao10000", languageCode: languageCode)
        default:
            return title
        }
    }

    nonisolated var trimCount: Int {
        switch kind {
        case .meanOfThree:
            return 0
        case .trimmed(let count):
            return count
        case .percentage(let percentage):
            return Int(Double(solveCount) * percentage)
        }
    }

    nonisolated func averageValue(from solves: [SessionSolveSample]) -> Double? {
        switch kind {
        case .meanOfThree:
            return SolveMetrics.averageValue(from: solves, trimmingCount: 0)
        case .trimmed(let trimmingCount):
            return SolveMetrics.averageValue(from: solves, trimmingCount: trimmingCount)
        case .percentage(let percentage):
            return SolveMetrics.percentageTrimmedAverage(from: solves, percentage: percentage)
        }
    }

    nonisolated static let defaultMetrics: [RecordAverageMetric] = [
        RecordAverageMetric(title: "mo3", solveCount: 3, kind: .meanOfThree),
        RecordAverageMetric(title: "ao5", solveCount: 5, kind: .trimmed(1)),
        RecordAverageMetric(title: "ao12", solveCount: 12, kind: .trimmed(1)),
        RecordAverageMetric(title: "ao50", solveCount: 50, kind: .percentage(0.05)),
        RecordAverageMetric(title: "ao100", solveCount: 100, kind: .percentage(0.05)),
        RecordAverageMetric(title: "ao500", solveCount: 500, kind: .percentage(0.05)),
        RecordAverageMetric(title: "ao1000", solveCount: 1000, kind: .percentage(0.05)),
        RecordAverageMetric(title: "ao5000", solveCount: 5000, kind: .percentage(0.05)),
        RecordAverageMetric(title: "ao10000", solveCount: 10000, kind: .percentage(0.05))
    ]
}

enum DataSegment: Sendable {
    case time
    case average
    case record

    nonisolated var segmentIndex: Int {
        switch self {
        case .time: 0
        case .average: 1
        case .record: 2
        }
    }
}

enum AverageListType: String, CaseIterable, Identifiable, Sendable {
    case mo3
    case ao5
    case ao12
    case ao50
    case ao100

    nonisolated var id: String { rawValue }

    nonisolated func title(languageCode: String) -> String {
        switch self {
        case .mo3:
            return dataTabLocalizedString(for: "data.mo3", languageCode: languageCode)
        case .ao5:
            return dataTabLocalizedString(for: "data.ao5", languageCode: languageCode)
        case .ao12:
            return dataTabLocalizedString(for: "data.ao12", languageCode: languageCode)
        case .ao50:
            return dataTabLocalizedString(for: "data.ao50", languageCode: languageCode)
        case .ao100:
            return dataTabLocalizedString(for: "data.ao100", languageCode: languageCode)
        }
    }

    nonisolated var solveCount: Int {
        switch self {
        case .mo3: 3
        case .ao5: 5
        case .ao12: 12
        case .ao50: 50
        case .ao100: 100
        }
    }

    nonisolated var trimmingCount: Int {
        switch self {
        case .mo3: 0
        case .ao5, .ao12: 1
        case .ao50: 2
        case .ao100: 5
        }
    }

    nonisolated var recordMetricKind: RecordAverageMetric.Kind {
        switch self {
        case .mo3:
            return .meanOfThree
        case .ao5, .ao12:
            return .trimmed(1)
        case .ao50, .ao100:
            return .percentage(0.05)
        }
    }
}

struct AverageListEntry: Identifiable, Sendable {
    let position: Int
    let date: Date
    let value: Double?

    nonisolated var id: Int { position }
}

nonisolated func dataTabLocalizedString(for key: String, languageCode: String) -> String {
    appLocalizedString(key, languageCode: languageCode)
}

struct MetricEvaluation: Sendable {
    let currentValue: Double?
    let bestValue: Double?
    let windowValues: [Double?]
}

struct FenwickTree: Sendable {
    private var tree: [Double]

    nonisolated init(size: Int) {
        self.tree = Array(repeating: 0, count: max(0, size) + 1)
    }

    nonisolated mutating func add(index: Int, value: Double) {
        guard index >= 0 else { return }
        var treeIndex = index + 1
        while treeIndex < tree.count {
            tree[treeIndex] += value
            treeIndex += treeIndex & -treeIndex
        }
    }

    nonisolated func prefixSum(at treeIndex: Int) -> Double {
        guard !tree.isEmpty else { return 0 }
        if treeIndex <= 0 { return 0 }

        var index = min(treeIndex, tree.count - 1)
        var sum = 0.0
        while index > 0 {
            sum += tree[index]
            index -= index & -index
        }
        return sum
    }

    nonisolated func lowerBound(prefixSumAtLeast target: Double) -> Int {
        guard target > 0, tree.count > 1 else { return 1 }

        var index = 0
        var bit = 1
        while bit < tree.count {
            bit <<= 1
        }

        var remaining = target
        while bit > 0 {
            let next = index + bit
            if next < tree.count, tree[next] < remaining {
                index = next
                remaining -= tree[next]
            }
            bit >>= 1
        }

        return min(index + 1, tree.count - 1)
    }
}

enum DataTabComputation {
    nonisolated static func buildAverageEntriesSnapshot(
        from solves: [SessionSolveSample],
        averageType: AverageListType
    ) -> [AverageListEntry] {
        guard solves.count >= averageType.solveCount else { return [] }
        let metric = RecordAverageMetric(
            title: averageType.rawValue,
            solveCount: averageType.solveCount,
            kind: averageType.recordMetricKind
        )
        let evaluation = evaluateRecordMetric(metric: metric, solves: solves, includeWindowValues: true)
        let values = evaluation.windowValues
        let totalWindows = values.count

        return values.enumerated().map { index, value in
            AverageListEntry(
                position: totalWindows - index,
                date: solves[index].date,
                value: value
            )
        }
    }

    nonisolated static func buildRecordSnapshotData(
        from solves: [SessionSolveSample],
        notAvailable: String,
        languageCode: String
    ) -> RecordSnapshot {
        let availableMetrics = RecordAverageMetric.defaultMetrics.filter { solves.count >= $0.solveCount }
        let validTimes = solves.compactMap { $0.adjustedTime }
        let validCount = validTimes.count

        let evaluations = availableMetrics.map { metric in
            (metric, evaluateRecordMetric(metric: metric, solves: solves, includeWindowValues: false))
        }

        let currentStats = evaluations.compactMap { metric, evaluation -> RecordStatItem? in
            guard let value = evaluation.currentValue else { return nil }
            return RecordStatItem(
                title: metric.localizedTitle(languageCode: languageCode),
                value: SolveMetrics.formatAverage(value)
            )
        }

        let bestStats = evaluations.compactMap { metric, evaluation -> RecordStatItem? in
            guard let bestValue = evaluation.bestValue else { return nil }
            return RecordStatItem(
                title: metric.localizedTitle(languageCode: languageCode),
                value: SolveMetrics.formatAverage(bestValue)
            )
        }

        return RecordSnapshot(
            sessionMeanText: validTimes.isEmpty
                ? notAvailable
                : SolveMetrics.formatTime(validTimes.reduce(0, +) / Double(validTimes.count), decimals: 3),
            sessionMeanSuffix: validCount < solves.count ? "(\(validCount)/\(solves.count))" : nil,
            bestTimeText: validTimes.min().map { SolveMetrics.formatTime($0, decimals: 3) } ?? notAvailable,
            worstTimeText: validTimes.max().map { SolveMetrics.formatTime($0, decimals: 3) } ?? notAvailable,
            currentStats: currentStats,
            bestStats: bestStats
        )
    }

    nonisolated static func evaluateRecordMetric(
        metric: RecordAverageMetric,
        solves: [SessionSolveSample],
        includeWindowValues: Bool
    ) -> MetricEvaluation {
    guard solves.count >= metric.solveCount else {
        return MetricEvaluation(currentValue: nil, bestValue: nil, windowValues: [])
    }

    let trimCount = metric.trimCount
    guard trimCount * 2 < metric.solveCount else {
        return MetricEvaluation(currentValue: nil, bestValue: nil, windowValues: [])
    }

    let distinctValues = Array(Set(solves.compactMap { $0.adjustedTime })).sorted()
    let valueToIndex = Dictionary(uniqueKeysWithValues: distinctValues.enumerated().map { ($1, $0) })
    var countsTree = FenwickTree(size: distinctValues.count)
    var sumsTree = FenwickTree(size: distinctValues.count)
    var finiteCount = 0
    var finiteSum = 0.0
    var dnfCount = 0

    func add(_ solve: SessionSolveSample) {
        guard let adjusted = solve.adjustedTime, let index = valueToIndex[adjusted] else {
            dnfCount += 1
            return
        }
        countsTree.add(index: index, value: 1)
        sumsTree.add(index: index, value: adjusted)
        finiteCount += 1
        finiteSum += adjusted
    }

    func remove(_ solve: SessionSolveSample) {
        guard let adjusted = solve.adjustedTime, let index = valueToIndex[adjusted] else {
            dnfCount -= 1
            return
        }
        countsTree.add(index: index, value: -1)
        sumsTree.add(index: index, value: -adjusted)
        finiteCount -= 1
        finiteSum -= adjusted
    }

    func sumOfSmallest(_ count: Int) -> Double {
        guard count > 0 else { return 0 }
        let searchOrder = Double(count)
        let treeIndex = countsTree.lowerBound(prefixSumAtLeast: searchOrder)
        let prefixCountBefore = countsTree.prefixSum(at: treeIndex - 1)
        let prefixSumBefore = sumsTree.prefixSum(at: treeIndex - 1)
        let remaining = searchOrder - prefixCountBefore
        let valueAtIndex = distinctValues[treeIndex - 1]
        return prefixSumBefore + remaining * valueAtIndex
    }

    func currentWindowValue() -> Double? {
        if dnfCount > trimCount {
            return Double.nan
        }

        let smallestTrimSum = sumOfSmallest(trimCount)
        let largestFiniteTrimCount = max(0, trimCount - dnfCount)
        let largestTrimSum: Double
        if largestFiniteTrimCount > 0 {
            largestTrimSum = finiteSum - sumOfSmallest(finiteCount - largestFiniteTrimCount)
        } else {
            largestTrimSum = 0
        }

        let trimmedCount = metric.solveCount - (trimCount * 2)
        guard trimmedCount > 0 else { return nil }
        return (finiteSum - smallestTrimSum - largestTrimSum) / Double(trimmedCount)
    }

    for solve in solves.prefix(metric.solveCount) {
        add(solve)
    }

    var windowValues: [Double?] = []
    let firstValue = currentWindowValue()
    if includeWindowValues {
        windowValues.append(firstValue)
    }

    var bestValue = firstValue
    if let current = firstValue, let currentBest = bestValue {
        if current.isNaN {
            bestValue = currentBest
        } else if currentBest.isNaN || current < currentBest {
            bestValue = current
        }
    }

    if solves.count > metric.solveCount {
        for startIndex in 1...(solves.count - metric.solveCount) {
            remove(solves[startIndex - 1])
            add(solves[startIndex + metric.solveCount - 1])

            let value = currentWindowValue()
            if includeWindowValues {
                windowValues.append(value)
            }

            switch (bestValue, value) {
            case (nil, let newValue):
                bestValue = newValue
            case (let existing?, let newValue?):
                if existing.isNaN {
                    bestValue = newValue
                } else if !newValue.isNaN, newValue < existing {
                    bestValue = newValue
                }
            default:
                break
            }
        }
    }

    let currentValue = includeWindowValues ? windowValues.first ?? firstValue : firstValue
    return MetricEvaluation(
        currentValue: currentValue,
        bestValue: bestValue,
        windowValues: includeWindowValues ? windowValues : []
    )
    }
}
