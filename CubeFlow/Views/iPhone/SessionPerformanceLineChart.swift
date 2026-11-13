#if os(iOS)
import Charts
import SwiftUI

nonisolated struct SessionPerformanceHistory: Sendable {
    struct Observation: Identifiable, Sendable {
        let id: Int
        let date: Date
        let time: Double?
        let penalty: SolveResult
        let ao5: Double?
        let ao12: Double?
        let record: Bool
        let segment: Int
        let ao12Segment: Int
    }
    struct Bucket: Identifiable, Sendable {
        let id: Int
        let lowest: Observation?
        let highest: Observation?
        let record: Observation?
        let trend: [Observation]
        let ao12Trend: [Observation]
    }
    let observations: [Observation]
    let buckets: [Bucket]
    let domain: ClosedRange<Double>
    let dnfCount: Int
    let plusTwoCount: Int
    let compressed: Bool

    init(_ samples: [SessionSolveSample], maximumBuckets: Int = 192) throws {
        let ordered = samples.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        var rows: [Observation] = []
        rows.reserveCapacity(ordered.count)
        var best = Double.infinity, slowest = 0.0, segment = 0, ao12Segment = 0, dnf = 0, plusTwo = 0
        for index in ordered.indices {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let sample = ordered[index]
            let penalty = SolveResult(rawValue: sample.resultRaw) ?? .solved
            let time = sample.adjustedTime.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            func average(_ count: Int) -> Double? {
                guard index + 1 >= count else { return nil }
                return SolveMetrics.averageValue(from: Array(ordered[(index + 1 - count)...index]), trimmingCount: 1)
            }
            let a5 = average(5), a12 = average(12)
            if a5?.isFinite != true { segment += 1 }
            if a12?.isFinite != true { ao12Segment += 1 }
            let record = time.map { $0 < best } ?? false
            if let time { best = min(best, time); slowest = max(slowest, time) }
            if penalty == .dnf { dnf += 1 }
            if penalty == .plusTwo { plusTwo += 1 }
            rows.append(.init(id: index + 1, date: sample.date, time: time, penalty: penalty,
                ao5: a5, ao12: a12, record: record, segment: segment, ao12Segment: ao12Segment))
        }
        let strideSize = max(1, (rows.count + max(1, maximumBuckets) - 1) / max(1, maximumBuckets))
        var grouped: [Bucket] = []
        for start in stride(from: 0, to: rows.count, by: strideSize) {
            let slice = rows[start..<min(start + strideSize, rows.count)]
            let valid = slice.filter { $0.time != nil }
            func trend(_ metric: KeyPath<Observation, Double?>) -> [Observation] {
                let points = slice.filter { $0[keyPath: metric]?.isFinite == true }
                let anchors = [points.first, points.min(by: { $0[keyPath: metric]! < $1[keyPath: metric]! }),
                    points.max(by: { $0[keyPath: metric]! < $1[keyPath: metric]! }), points.last]
                    .compactMap { $0 }.sorted { $0.id < $1.id }
                var seen: Set<Int> = []
                return anchors.filter { seen.insert($0.id).inserted }
            }
            grouped.append(.init(id: start + 1, lowest: valid.min(by: { $0.time! < $1.time! }),
                highest: valid.max(by: { $0.time! < $1.time! }), record: valid.last(where: \.record),
                trend: trend(\.ao5), ao12Trend: trend(\.ao12)))
        }
        let lower = best.isFinite ? best : 0
        let padding = max(0.5, (slowest - lower) * 0.08)
        observations = rows; buckets = grouped
        domain = max(0, lower - padding)...max(lower + padding, slowest + padding)
        dnfCount = dnf; plusTwoCount = plusTwo; compressed = strideSize > 1
    }

    func observation(at ordinal: Int) -> Observation? {
        guard ordinal > 0, ordinal <= observations.count else { return nil }
        return observations[ordinal - 1]
    }
}

@available(iOS 16.0, *)
struct SessionPerformanceLineChart: View {
    let history: SessionPerformanceHistory
    let language: String
    @Environment(\.solveTimeAccuracy) private var accuracy
    @State private var selected: Int?
    private var inspection: SessionPerformanceHistory.Observation? { selected.flatMap(history.observation) ?? history.observations.last }
    private var trend: Color { Color(uiColor: .systemTeal) }
    private var raw: Color { Color(uiColor: .secondaryLabel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let value = inspection { header(value) }
            plot
            VStack(alignment: .leading, spacing: 7) {
                Label(appLocalizedString(history.compressed ? "data.trend.solve_range" : "data.trend.raw_solves", languageCode: language), systemImage: "circle.fill")
                    .foregroundStyle(raw)
                Label("Ao5", systemImage: "waveform.path").foregroundStyle(trend)
                Label("Ao12", systemImage: "line.horizontal.3").foregroundStyle(raw)
                Label(appLocalizedString("data.trend.record", languageCode: language), systemImage: "diamond.fill").foregroundStyle(Color(uiColor: .systemOrange))
            }.font(.caption.weight(.medium))
            HStack(spacing: 12) {
                Text(verbatim: "DNF: \(history.dnfCount.formatted())")
                Text(verbatim: "+2: \(history.plusTwoCount.formatted())")
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if history.compressed {
                Text(appLocalizedString("data.trend.range_note", languageCode: language)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityAdjustableAction { direction in
            let position = selected ?? history.observations.count
            switch direction {
            case .increment: selected = min(history.observations.count, position + 1)
            case .decrement: selected = max(1, position - 1)
            @unknown default: break
            }
        }
    }

    private func header(_ value: SessionPerformanceHistory.Observation) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("#\(value.id)   \u{00B7}   \(SolveMetrics.displayDate(value.date, languageCode: language))")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(value.penalty == .dnf ? "DNF" : time(value.time)).font(.largeTitle.weight(.semibold)).monospacedDigit()
                if value.penalty == .plusTwo { Text("+2").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
            }
            Text("Ao5  \(time(value.ao5))     Ao12  \(time(value.ao12))")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }.accessibilityElement(children: .combine)
    }

    private func time(_ value: Double?) -> String {
        guard let value else { return "\u{2014}" }
        return value.isFinite ? SolveMetrics.formatTime(value, decimals: accuracy.decimals) : "DNF"
    }

    @ViewBuilder private var plot: some View {
        if #available(iOS 17.0, *) {
            chart.chartXSelection(value: $selected)
        } else {
            chart.chartOverlay { proxy in
                GeometryReader { geometry in
                    Color.clear.contentShape(Rectangle()).onTapGesture { point in
                        let offset = geometry[proxy.plotAreaFrame].minX
                        if let ordinal: Int = proxy.value(atX: point.x - offset) {
                            selected = min(max(1, ordinal), history.observations.count)
                        }
                    }
                }
            }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(history.buckets) { bucket in
                if let low = bucket.lowest, let high = bucket.highest, let minimum = low.time, let maximum = high.time {
                    if history.compressed && maximum > minimum {
                        RuleMark(x: .value("Solve", bucket.id), yStart: .value("Fastest", minimum), yEnd: .value("Slowest", maximum))
                            .lineStyle(.init(lineWidth: 1.1)).foregroundStyle(raw.opacity(0.35))
                    } else {
                        PointMark(x: .value("Solve", low.id), y: .value("Seconds", minimum))
                            .symbolSize(17).foregroundStyle(raw.opacity(0.45))
                    }
                }
                if let record = bucket.record, let time = record.time {
                    PointMark(x: .value("Solve", record.id), y: .value("Record", time))
                        .symbol(.diamond).symbolSize(24).foregroundStyle(Color(uiColor: .systemOrange))
                }
                ForEach(bucket.trend) { point in
                    if let value = point.ao5 {
                        LineMark(x: .value("Solve", point.id), y: .value("Ao5", value), series: .value("Run", "ao5-\(point.segment)"))
                            .lineStyle(.init(lineWidth: 2.4, lineCap: .round, lineJoin: .round)).foregroundStyle(trend)
                    }
                }
                ForEach(bucket.ao12Trend) { point in
                    if let value = point.ao12 {
                        LineMark(x: .value("Solve", point.id), y: .value("Ao12", value), series: .value("Run", "ao12-\(point.ao12Segment)"))
                            .lineStyle(.init(lineWidth: 1.4, dash: [4, 3])).foregroundStyle(raw)
                    }
                }
            }
            if let selected, let value = history.observation(at: selected) {
                RuleMark(x: .value("Selected", selected)).foregroundStyle(.secondary.opacity(0.6))
                if let time = value.time {
                    PointMark(x: .value("Solve", selected), y: .value("Seconds", time))
                        .symbolSize(64).foregroundStyle(trend)
                }
            }
        }
        .chartXScale(domain: 0...max(2, history.observations.count + 1))
        .chartYScale(domain: history.domain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel { if let index = value.as(Int.self), index > 0 { Text("#\(index)").font(.caption2.monospacedDigit()) } }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(raw.opacity(0.16))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) {
                        Text(SolveMetrics.formatTime(seconds, decimals: 1) + (seconds < 60 ? " s" : ""))
                            .font(.caption2.monospacedDigit())
                    }
                }
            }
        }
        .frame(height: 242)
        .accessibilityLabel(Text("data.trend.graph"))
    }
}
#endif
