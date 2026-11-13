#if os(iOS)
import SwiftUI

struct TimerPBBannerHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct TimerPBObstacleKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) { value += nextValue() }
}
extension View {
    func timerPBObstacle() -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: TimerPBObstacleKey.self,
                value: [proxy.frame(in: .named("TimerTabView.Layout"))])
        })
    }
}

enum TimerPBPlacement {
    static func center(container: CGRect, timer: CGRect, upperBottom: CGFloat,
                       obstacles: [CGRect], bannerHeight: CGFloat, aboveTimer: Bool) -> CGPoint? {
        guard !timer.isEmpty, bannerHeight > 0 else { return nil }
        let gap: CGFloat = 8
        var low = aboveTimer ? max(container.minY, upperBottom) + gap : timer.maxY + gap
        var high = aboveTimer ? timer.minY - gap : container.maxY - gap
        for obstacle in obstacles where !obstacle.isEmpty {
            if aboveTimer, obstacle.maxY <= timer.minY { low = max(low, obstacle.maxY + gap) }
            if !aboveTimer, obstacle.minY >= timer.maxY { high = min(high, obstacle.minY - gap) }
        }
        guard high - low >= bannerHeight else { return nil }
        return CGPoint(x: container.midX, y: (low + high) / 2)
    }
}
#endif
