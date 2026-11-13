import Foundation

/// Value-owned by a chart presentation; fresh input creates a fresh snapshot.
/// Selection/hover changes read the arrays without sorting or rebuilding bins.
struct SessionSolveTrend {
    struct Point: Identifiable, Equatable {
        let id: UUID
        let date: Date
        let time: Double
    }
    struct Bin: Identifiable, Equatable {
        let lower: Double
        let upper: Double
        let count: Int
        var id: Double { lower }
    }
    let points: [Point]
    let bins: [Bin]

    init(solves: [SessionSolveSample]) {
        var validPoints: [Point] = []
        var ordered: [Double] = []
        validPoints.reserveCapacity(solves.count)
        ordered.reserveCapacity(solves.count)
        var checkedEvents: Set<String> = []
        var containsSquare1 = false
        for solve in solves {
            if !containsSquare1, checkedEvents.insert(solve.eventRawValue).inserted {
                containsSquare1 = PuzzleEvent.fromSolveEvent(solve.eventRawValue) == .square1
            }
            guard let time = SolveMetrics.adjustedTime(for: solve), time.isFinite, time >= 0 else { continue }
            validPoints.append(Point(id: solve.id, date: solve.date, time: time))
            ordered.append(time)
        }
        validPoints.sort { $0.date < $1.date }
        points = validPoints
        guard !ordered.isEmpty else { bins = []; return }
        ordered.sort()
        let minValue = ordered[0], maxValue = ordered[ordered.count - 1]
        let q1 = ordered[(ordered.count - 1) / 4], q3 = ordered[(ordered.count - 1) * 3 / 4]
        let preferred = [0.25, 0.5, 1.0, 2, 5, 10, 15, 30, 60]
        let minimumWidth = containsSquare1 ? 1.0 : 0.25
        // Sparse small samples need useful detail too; FD alone can yield just
        // two very wide bars. Outlier gaps still cannot widen a dense peak.
        let suggested = min(2 * (q3 - q1) / pow(Double(ordered.count), 1.0 / 3),
            max(minimumWidth, (maxValue - minValue) / 8))
        var width = preferred.first { $0 >= max(minimumWidth, suggested) } ?? max(60, ceil(suggested / 60) * 60)
        // Empty outlier gaps need no individual bars. This bounds chart density
        // without widening useful central bins to the full observed range.
        var counts: [Double: Int] = [:], lower = 0.0
        repeat {
            lower = floor(minValue / width) * width
            counts.removeAll(keepingCapacity: true)
            let finalIndex = max(0, ceil((maxValue - lower) / width) - 1)
            for value in ordered {
                let index = min(finalIndex, max(0, floor((value - lower) / width)))
                counts[index, default: 0] += 1
            }
            if counts.count <= 80 { break }
            width = preferred.first { $0 > width } ?? width * 2
        } while width.isFinite
        // Half-open bins, except the final closed edge. An integral maximum
        // belongs to the final bin once, not to a second trailing bin.
        bins = counts.keys.sorted().map { index in
            Bin(lower: lower + index * width, upper: lower + (index + 1) * width, count: counts[index]!)
        }
    }
}
